# Zentrix Bank — REST contract the app expects

This is what `lib/features/**/data/api_*.dart` calls. It is a **contract for a server that does not exist yet**;
nothing here was verified against a real bank. Build the server to this, or change the mappers in
`lib/core/network/mappers.dart` to match yours.

## Conventions

* Base URL from `--dart-define=API_BASE_URL=https://…` (HTTPS only; `http://` is accepted solely for
  `localhost`, `127.0.0.1` and `10.0.2.2` in debug builds).
* JSON in, JSON out. Collections are always wrapped: `{ "items": [ … ] }`.
* **Money is an integer in minor units** (`amountMinor: 250050` = LKR 2,500.50). Field names end in `Minor`.
* Dates are ISO-8601 UTC.
* Every request carries `X-Request-Id` (32 hex chars). Echo it back in error bodies/logs so support can trace a call.
* Authenticated calls carry `Authorization: Bearer <accessToken>`.
* `POST /v1/payments` carries `Idempotency-Key`. The same key with the same body must return the **original** result
  and must never move money twice.
* Errors: non-2xx with `{ "code": "snake_case_reason", "message": "Customer-safe text", "fields": { "field": "text" } }`.
  * `401` → the access token is missing/expired. The app refreshes once and replays, otherwise signs the customer out.
  * `503` with `code: "maintenance"` (or an `X-Maintenance` header) and optional `Retry-After` seconds → the app shows its maintenance screen.
  * Other `4xx` → a business refusal; `message` is shown to the customer, so keep it free of internals.
  * `5xx` → shown as a generic "something went wrong on our side".
* Safe reads (`GET`) are retried twice on connection errors and 502/503/504. Writes are never retried automatically.

## Authentication

| Call | Body | Success |
| --- | --- | --- |
| `POST /v1/auth/login` | `{ identifier, password }` | `{ accessToken, refreshToken, user }` |
| `POST /v1/auth/register` | `{ fullName, username, password, initialDepositMinor, profile:{…} }` | same as login |
| `POST /v1/auth/refresh` | `{ refreshToken }` | `{ accessToken, refreshToken }` — the refresh token **rotates**; the old one must stop working |
| `POST /v1/auth/device-token` | — (authenticated) | `{ refreshToken }` — long-lived, device-bound token for "remember me" |
| `GET /v1/me` | — | `{ user }` |
| `POST /v1/auth/logout` | — | `204` — revokes the refresh token |
| `PUT /v1/me/contact` | `{ email, phone }` → `{ user }`; an email used by another customer → `4xx`. Treat as sensitive: re-authenticate, notify the customer on every previously known contact |
| `POST /v1/auth/password` | `{ current, next }` | `204`; wrong `current` → `401`/`4xx` |
| `POST /v1/auth/password-reset/request` | `{ identifier }` | always `202` (never reveal whether the account exists) |
| `POST /v1/auth/password-reset/confirm` | `{ identifier, code, newPassword }` | `204`; bad/expired code → `4xx` |

`user` = `{ id, fullName, firstName, customerNumber, email, phone }`.
Failed logins must return the same response for "unknown user" and "wrong password".

## Banking

| Call | Success |
| --- | --- |
| `GET /v1/accounts` | `items: [{ id, type, name, maskedNumber, balanceMinor, currency, active, interestRate?, maturityDate? }]` — `type` ∈ `savings`, `current`, `fixed_deposit`, `foreign_currency` |
| `POST /v1/accounts` | `{ type: "savings"|"current", name, fromAccountId, amountMinor }` with `Idempotency-Key` → the new account. The server owns minimums and the account-count limit; refusals use the payment codes (`insufficient_funds`, …). Fixed deposits are opened with `/v1/fixed-deposits`, not here |
| `GET /v1/fixed-deposits` | `items: [{ id, name, maskedNumber, principalMinor, rate, termMonths, startDate, maturityDate, renewal, fundingAccountId, status, renewals, paidOutMinor }]` — `id` is also the deposit's account id, so it appears in `GET /v1/accounts` too; `renewal` ∈ `renewWithInterest`, `renewPrincipalOnly` (shown to the customer as "Renew without interest"), `payOut` (the app never sets it, but displays it if a deposit was arranged that way); `status` ∈ `active`, `matured` |
| `POST /v1/fixed-deposits` | `{ fromAccountId, amountMinor, termMonths, renewal }` with `Idempotency-Key` → the deposit. `termMonths` is 3, 6 or 12, or a multiple of 12 from 24 to 120. The **server** sets the rate, and pays or renews at maturity: interest is simple interest for the term; `renewWithInterest` rolls principal + interest into a new term at the then-current rate; `renewPrincipalOnly` rolls the principal and pays the interest to `fundingAccountId`; `payOut` (not offered in the app) pays both there and closes the deposit |
There is deliberately **no endpoint to edit or cancel a deposit**: term, amount and `renewal` are fixed when it is opened. Early closure, if ever offered, is a branch matter.
| `GET /v1/cards` | `items: [{ id, kind, network, holder, last4, expiry, frozen, blocked, issuance, readyOn?, collectionBranch? }]` — `kind` ∈ `debit`, `credit`, `virtual`; `network` ∈ `visa`, `mastercard`; `issuance` ∈ `active`, `pendingApproval`, `preparing`, `readyToCollect` (the **server** decides which; the app never works it out from its own clock). **Never** send full card numbers or CVVs. |
| `PUT /v1/cards/{id}/freeze` body `{ frozen: bool }` | `204`; a permanently blocked card → `4xx` |
| `GET /v1/cards/{id}/controls` | `{ dailyLimitMinor, maxDailyLimitMinor, onlineEnabled, internationalEnabled }` |
| `PUT /v1/cards/{id}/controls` body `{ dailyLimitMinor, onlineEnabled, internationalEnabled }` | `204`; above `maxDailyLimitMinor` → `4xx` with a customer-safe `message` |
| `PUT /v1/cards/{id}/pin` body `{ currentPin, newPin }` | `204`; wrong `currentPin` → `4xx`. The **issuer** verifies and stores card PINs (HSM); the app never stores or logs them and the contract expects the server to rate-limit attempts |
| `POST /v1/cards` | `{ kind: "virtual"|"debit", accountId, collectionBranch? }` (with `Idempotency-Key`) → the new card. A **virtual** card returns `issuance: pendingApproval` and stays unusable until bank staff activate it in the bank's own system (there is no customer endpoint for that). A **debit** card requires `collectionBranch` and returns `issuance: preparing` with `readyOn` (about 5 days later); the server moves it to `readyToCollect` on that day and should send the customer a notification to collect it from that branch with ID. Credit cards are refused (`4xx`) |
| `POST /v1/cards/{id}/activate` | `204` — only for a debit card whose `issuance` is `readyToCollect` (the customer has it in hand). `4xx` for a virtual card, a card still being prepared, or one already active |
| `POST /v1/cards/{id}/report-lost` | `204` — blocks the card permanently and orders a replacement; cards then report `blocked: true` |
| `GET /v1/transactions?limit=500` | `items: [{ id, merchant, category, amountMinor, date, status, accountId, reference, method, internal }]` — negative `amountMinor` = money out; `category` ∈ the app's `TxCategory` names; `status` ∈ `completed`, `pending`, `failed` |
| `GET /v1/beneficiaries` | `items: [{ id, bank, accountNumber, name, nickname, favorite }]` |
| `POST /v1/beneficiaries` | body as above without `id` → `201`; duplicate → `409 duplicate` |
| `PUT /v1/beneficiaries/{id}` / `DELETE …` | `204` |
| `GET /v1/loans` | `items: [{ id, type, principalMinor, outstandingMinor, annualRate, monthlyPaymentMinor, nextPaymentDate, remainingMonths, totalMonths, history:[{ date, amountMinor }] }]` — `type` ∈ `personal`, `vehicle`, `home`, `education` |
| `GET /v1/loan-applications` | `items: [{ id, type, amountMinor, termMonths, monthlyIncomeMinor, employment, purpose, createdAt, indicativeMonthlyMinor }]` — status is derived from `createdAt` in the prototype; a real server should return its own |
| `POST /v1/loan-applications` | `{ type, amountMinor, termMonths, monthlyIncomeMinor, employment, purpose }` with `Idempotency-Key` → the application. Never an approval: decisions are the bank's, made later |
| `GET /v1/disputes` | `items: [{ id, transactionId, merchant, amountMinor, reason, details, createdAt }]` — `reason` ∈ `notMine`, `wrongAmount`, `duplicate`, `notReceived`, `other` |
| `POST /v1/disputes` | `{ transactionId, reason, details }` with `Idempotency-Key` → the dispute. One open dispute per transaction; the server decides what is disputable. Raising a dispute does not move money |
| `GET /v1/health` | `200` when serving (used by "Try again" on the maintenance screen) |

## Payments

`POST /v1/payments` (with `Idempotency-Key`)

```json
{ "kind": "transfer|bill|qr|loan", "fromAccountId": "…", "toAccountId": null, "loanId": null,
  "payee": "…", "payeeDetail": "…", "amountMinor": 100000, "reference": "",
  "category": "transfer", "scheduledFor": null, "recurrence": "once|weekly|monthly",
  "details": [ { "label": "Bank", "value": "BOC" } ] }
```

There is deliberately **no fee, balance or limit** in the request: the server prices the payment, checks funds and
limits, and returns the authoritative result:

```json
{ "id": "…", "kind": "transfer", "status": "completed", "payee": "…", "amountMinor": 100000, "feeMinor": 2500,
  "fromName": "Savings", "fromMasked": "•••• 1234", "reference": "", "date": "…", "scheduled": false,
  "details": [ { "label": "Bank", "value": "BOC" } ] }
```

For `kind: "loan"` set `loanId`; the server applies interest first and the rest to principal, advances the schedule when
at least the instalment is paid, and refuses amounts above the payoff figure or on a closed loan. Loan payments cannot be scheduled.

Mobile top-up is no longer a payment kind in the app. If a server still reports `topUp` / `top_up` on a receipt or scheduled payment, the app reads it as a `bill`.

A payment with `scheduledFor` in the future is **not executed now**: the server stores it and runs it on the day (checking funds and limits then,
not at scheduling time). `recurrence` repeats it; monthly runs keep the originally chosen day, clamped to short months. A run that cannot be paid is
recorded as failed and a repeating payment carries on.

| Call | Notes |
| --- | --- |
| `GET /v1/scheduled-payments` | `items: [{ id, kind, fromAccountId, payee, payeeDetail, amountMinor, feeMinor, reference, nextRun, recurrence, status, runCount, lastMessage }]` — `status` ∈ `active`, `completed`, `cancelled`, `failed` |
| `DELETE /v1/scheduled-payments/{id}` | `204`; already finished → `4xx` |

Refusals use `422` with `code` ∈ `insufficient_funds`, `invalid_recipient`, `limit_exceeded` (anything else is shown as
"unavailable"). The app authorises with a local PIN today; a real deployment must add **server-verified step-up
authentication** (PIN/OTP/biometric-bound signature) before this call is accepted.

## Savings, notifications, security, limits, support

| Call | Notes |
| --- | --- |
| `GET /v1/savings/goals` | `items: [{ id, name, targetMinor, savedMinor, targetDate, autoMonthlyMinor? }]` |
| `POST /v1/savings/goals` | `{ name, targetMinor, targetDate, autoMonthlyMinor }` |
| `POST /v1/savings/goals/{id}/transfer` | `{ accountId, amountMinor }` (positive = deposit, negative = withdraw), with `Idempotency-Key`; refusals use the payment codes |
| `GET /v1/notifications` | `items: [{ id, category, title, body, date, read, severity }]` — `category` ∈ `transactions`, `security`, `payments`, `offers`, `bank_notices`; `severity` ∈ `info`, `warning`, `critical` |
| `POST /v1/notifications` | Events the app observed itself (e.g. card frozen). A server that records its own may answer `204` and ignore the body |
| `POST /v1/notifications/{id}/read`, `POST /v1/notifications/read-all` | `204` |
| `GET /v1/security/sessions` | `items: [{ id, name, platform, lastActive, approxLocation, current }]` |
| `DELETE /v1/security/sessions/{id}`, `POST /v1/security/sessions/revoke-others` | `204` |
| `GET /v1/security/login-history` | `items: [{ date, device, success, approxLocation }]` — the server records attempts itself |
| `GET /v1/security/two-factor`, `PUT …` `{ enabled }` | `{ enabled }` |
| `GET /v1/limits/transfer`, `PUT …` `{ dailyMinor }` | `{ bankMaximumMinor, dailyMinor }`; above the maximum → `4xx` |
| `GET /v1/support/branches` | `items: [{ name, address, distanceKm, isAtm, latitude?, longitude? }]` — with coordinates the app offers directions and, if the customer shares their location, re-sorts by distance on the device. The app never sends the customer's position to the server |
| `GET /v1/budgets` | `items: [{ category, monthlyLimitMinor }]` — `category` ∈ the spending categories (`food`, `shopping`, `transport`, `bills`, `entertainment`, `health`, `education`, `other`) |
| `PUT /v1/budgets/{category}` | `{ monthlyLimitMinor }` → `204` (creates or replaces). `DELETE` removes it. Budgets are the customer's own targets: nothing is blocked when one is passed |

## Still local, even with `API_BASE_URL` set

The support FAQs and rule-based chat, and the identity-verification step of registration (a mock — nothing is verified).
