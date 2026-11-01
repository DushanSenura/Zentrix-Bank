# Zentrix Bank (prototype)

Flutter banking app with a liquid-glass design system. **Everything runs on mock repositories — no real bank is connected.**

## Run

```
flutter pub get
flutter run            # Android or iOS device/emulator
flutter analyze && flutter test
```

Mock sign-in: `dushan` / `Dushan@123` (also accepts `dushan@example.com` or `NC10293847`).
Accounts created through registration live in memory only. A new account starts empty: one account holding the opening deposit,
a single "Opening deposit" transaction, a welcome notification, and no cards, beneficiaries, goals, loans or past sign-ins. Only the
demo customer has sample data, and each customer's changes stay separate (`features/payments/data/mock_bank.dart`).

## Demo account Details
username - demo
password - demo1234

## Architecture

```
lib/
  app/        app.dart, router.dart (go_router + auth redirect), transitions.dart, providers.dart (Riverpod)
  core/       theme/ (tokens), widgets/ (design-system components), utils/ (formatters, validators), l10n/
  features/   splash, onboarding, authentication, dashboard, cards, profile, navigation
  shared/     models/
```

* **State:** `flutter_riverpod` (`Notifier` / `AsyncNotifier` / `FutureProvider`).
* **Routing:** `go_router`. Signed-out users are redirected to `/login`; signed-in users away from public routes. Tabs use `StatefulShellRoute.indexedStack`, so each tab keeps its state.
* **Theme:** colours are a `ThemeExtension` (`context.colors`) with light and dark palettes; spacing, radius, shadows, typography (Manrope) and animation durations are in `core/theme/`.
* **Motion:** all durations/curves come from `AppAnimations`; `AppAnimations.scaled(context, d)` collapses them when the OS asks for reduced motion. Route transitions are named in `PageMotion`.
* **Strings:** `core/l10n/app_strings.dart` — swap for generated localisation when Sinhala/Tamil are added.

## Connecting a real backend

With no configuration the app runs on in-memory mocks. Point it at a server and the core repositories switch to HTTP:

```
flutter run --dart-define=API_BASE_URL=https://api.example-bank.test
# optional certificate pinning (lower-case SHA-256 of the server certificate, DER; include a backup pin)
flutter build apk --dart-define=API_BASE_URL=https://… --dart-define=API_PINS=<hex>,<backup-hex>
```

* **Contract:** [`docs/api_contract.md`](docs/api_contract.md) lists every endpoint the app calls. No such server exists in this repo,
  and the contract has never been run against one — only against a fake HTTP adapter in `test/network_test.dart`.
* **Covered by the API:** auth, accounts, cards (list, freeze, limits, PIN, lost/stolen), transactions, beneficiaries, payments
  (including loan instalments), loans, savings goals, notifications, security centre, transfer limits, branch list.
  **Still local:** support FAQs/chat and the registration identity check.
* **`core/network/`:** `ApiClient` (Dio) adds a bearer token and `X-Request-Id`; on `401` it refreshes once (shared by concurrent
  requests, refresh token rotates and is stored in secure storage, access token is memory-only) and replays; retries `GET`s on
  connection errors/502–504 but **never retries a write**; maps everything to `ApiException` subclasses so no URL, header or
  server text can leak into the UI.
* **Payments** send an `Idempotency-Key` that is reused when the same draft is resent, send **no fee or balance** (the server
  prices and decides), and treat a dropped connection as *unknown outcome* ("check your recent transactions"), never as a clean failure.
* **Logging** is off in release builds; in debug, `LogSanitizer` redacts passwords, PINs, tokens, headers, OTPs, personal fields
  and masks long digit runs. Only query-string *keys* are logged.
* **HTTPS only**, except `http://localhost|127.0.0.1|10.0.2.2` in debug (`ApiConfig`). Android release builds forbid cleartext.
* To replace one piece instead, implement the interface and override its provider in `ProviderScope`.
* Money is `double` in the UI models and **integer minor units on the wire**; conversion happens only in `mappers.dart`.

## Resilience

* **Offline:** `onlineProvider` (connectivity_plus behind `ConnectivityService`) shows a banner, pauses payment confirmation, and
  refetches accounts/cards/transactions on reconnect. Interface-up is not proof the bank is reachable; real failures still arrive as `NetworkException`.
* **Maintenance:** a `503 maintenance` response shows a full-screen notice over the app (navigation underneath is preserved) with a
  health-check "Try again".
* **Session expiry:** if the token can't be refreshed the customer is signed out without another server call and sees why on the sign-in screen.
* **Load failures:** `ErrorView` words the problem by cause (offline / server / expired session), offers Retry, and shows the request id for support.
* **Crashes:** `installErrorHandling` routes framework and async errors to a `CrashReporter` (debug-print only here — plug in a real service)
  and replaces Flutter's error widget in release so no exception text is shown.

## Accessibility

* `test/accessibility_test.dart` runs Flutter's tap-target (48 dp / 44 pt) and labelled-control guidelines on **every screen in light and dark**.
* `test/contrast_test.dart` checks WCAG AA (4.5:1) for every text token against the page, surfaces and glass over each gradient stop —
  computed from the tokens because screenshot sampling over blur is unreliable. The audit found and fixed: light-theme accent, success and warning text,
  dark-theme error text and white-on-primary buttons were below 4.5:1; the "Remember me" checkbox had no label; notification filter chips were 40 dp tall.
* Large-text layouts are covered by earlier overflow tests (text scale up to 2×). **Not done:** a real TalkBack/VoiceOver walkthrough.

## Authentication & device security

* **Sign in:** username/email/customer ID + password. "Remember me" stores a refresh token (never the password) in `flutter_secure_storage` and sends the user to PIN setup.
* **PIN:** 4 or 6 digits (chosen when it is created; the length is stored beside the hash so every screen shows the right number of dots), weak PINs rejected, stored only as a salted PBKDF2-HMAC-SHA256 hash (`core/security/pin_hasher.dart`). It unlocks the app on this device; real payment authorisation must be verified by the server. Five wrong PINs wipe the stored session.
* **Biometrics:** `local_auth` behind `BiometricService`; an optional shortcut to the same stored session. No biometric data is read or stored. Android uses `FlutterFragmentActivity` and the `USE_BIOMETRIC` permission; iOS has `NSFaceIDUsageDescription`.
* **Returning users:** splash checks for a stored session + PIN and goes to `/unlock` (shorter splash).
* **Registration:** 5 steps (personal, contact, banking, identity, review). Identity capture is a mock `IdentityVerificationService`; nothing is verified. Passwords are never held in Riverpod state.
* **Forgot password:** requests never reveal whether an account exists. Prototype reset code: `123456`.
* **Logout** clears the refresh token, PIN hash, biometric flag and all in-memory user data.

## Payments

Every payment type (transfer, bill, QR, loan instalment) is reduced to a `PaymentDraft` and goes through one pipeline:
**review → PIN/biometric authorisation → processing → receipt** (`features/payments/`).

* **Transfers:** own accounts, saved beneficiary, new beneficiary (optionally saved after paying), other bank (LKR 25 fee), scheduled date. International is shown as unavailable.
* **Beneficiaries:** search, favourites first, nickname edit, remove with confirmation.
* **Bills / QR:** 10 bill categories with providers; a camera QR scanner (with sample codes) plus a "My QR" code that holds identity only. Foreign QR codes are refused. *Mobile top-up was removed from the app.*
* **Authorisation:** `authorize_sheet.dart` verifies the PIN locally (or creates one the first time); three wrong PINs cancel the payment. This is a simulated layer — a real backend must authorise server-side.
* **Server-side rules (mock):** `MockLedger` owns balances and enforces funds, fee, daily limit (LKR 500,000), recipient validity and payable accounts. The UI checks are only for convenience.
* **Receipts:** share via the OS sheet, save a text copy to app storage (`ReceiptService`; swap in a PDF generator later).
* Test hooks: an account number ending `0000` is rejected as unverifiable.

## Money management

* **Transactions** (`/transactions`): grouped history, search, filters (date, type, category, amount, account), details with receipt/share, repeat (only for payments made in this app) and report (acknowledged locally).
* **Analytics**: income, expenses, savings, cash flow; donut, bars and net line (`fl_chart`); insights are plain month-to-date comparisons, not advice.
* **Savings goals**, **loans** with an estimate-only calculator, and **statements** with real CSV export (PDF not included).
* Demo data is generated relative to today, so the current month always has activity.

## Engagement & security

* **Notifications** (`/notifications`): five categories, unread badge on the dashboard bell, mark one/all read. Payments, card freezes, new beneficiaries, large transfers, PIN/password/limit changes and device sign-outs create entries; muting a category in Settings stops its entries, except Security.
* **Search** (`/search`): features, settings, beneficiaries and transactions in one box; recent searches last for the session (`features/search/domain/search.dart` is the pure matcher).
* **Security center** (`/security`): change password and PIN (current one confirmed first), biometric toggle, two-factor switch (prototype — no codes), trusted devices and sessions, daily transfer limit (lowering/raising needs the PIN; the ledger enforces it), login history, recent alerts.
* **App lock** (`app/app_lock_gate.dart`): after the idle/background timeout (Settings: 1/2/5/15 min) the app asks for the PIN or biometrics and returns you to where you were; five wrong PINs sign you out. After 30 minutes away the session ends. A privacy cover hides content in the app switcher. Without a PIN there is nothing to unlock with, so the lock never engages.
* **Settings**: theme, language (English only), notification categories, show balances, lock timeout, reduce motion (also honours the OS setting), default payment account.
* **Support**: FAQs, rule-based chat that says it is automated (not a model, not a person), call/email/maps via `LinkLauncher`, sample branch and ATM list.

## Security & performance review

Reviewed and fixed in this pass:

* Android release builds had **no INTERNET permission** (would have broken any backend); added with `ACCESS_NETWORK_STATE`.
* Auto-backup was on; now `allowBackup=false`, cleartext off (debug-only exception for local servers).
* `FLAG_SECURE` on non-debuggable builds blocks screenshots, screen recording and the recents thumbnail.
* A payment that throws anything other than `PaymentException` used to leave the screen on "Processing"; it now fails with "check your recent transactions".
* Freezing a card is now sent to the repository and rolled back on failure (previously a local-only toggle).

Known and **not** fixed — do these before any real release:

* `applicationId` is still `com.example.bank_app` and release builds are signed with the **debug key** (`android/app/build.gradle.kts`).
* The PIN gate is client-side only; server-verified step-up authentication is required for payments (see the contract).
* No root/jailbreak or tamper detection, no screenshot blocking on iOS (the privacy cover only hides the app switcher), no certificate-pin rotation tooling.
* Build with `--obfuscate --split-debug-info=<dir>`.
* Performance has **not been profiled on a device**. Known cost: each `GlassCard`/nav bar/sheet uses its own `BackdropFilter`; lists wrap rows in one card to keep the count low. Profile in `--profile` mode before adding more blurred surfaces.

## Cards, loans, statements and settings

* **Card controls** (`features/cards/`): daily limit (never above the bank's maximum), online and international switches, 4-digit card PIN change,
  and "report lost or stolen" which blocks the card permanently. Raising a limit or switching a capability on needs the app PIN; tightening does not.
  A card PIN is sent straight to the bank and is never stored, logged or put in a notification. In the prototype the limits are stored but nothing
  makes card purchases, so they are not enforced anywhere.
* **Loan instalments** (`features/loans/`): pay the instalment, any other amount, or settle in full, through the normal review → PIN → receipt flow.
  The mock bank applies interest first, then principal; paying at least the instalment advances the schedule; more than the payoff figure or a closed
  loan is refused. Loan payments can't be scheduled.
* **PDF statements** (`features/statements/domain/statement_pdf.dart`): a real multi-page A4 PDF built with the `pdf` package, shared or saved from the Statements screen.
  It uses the built-in Latin-1 fonts, so characters outside that range (for example Sinhala merchant names) print as `?`; embedding a font is needed first for those.
  The footer says it is a prototype statement, not an official record.
* **Saved settings** (`core/storage/preferences_store.dart`): theme, reduce motion and lock timeout persist per device; default account and muted
  notification categories persist but are cleared on sign-out because they belong to the customer. Stored in secure storage; nothing sensitive.

## Card management

**Payments → Card management** (also the *My cards* shortcut on Home, and *Manage all cards* on the Cards tab) is the one place to look after every card.

* **The list** shows each card (kind, last four digits, network, expiry) with its status as text and an icon: *Active*, *Frozen*, *Blocked*, *Awaiting bank approval*, *Being prepared* or *Ready to collect*, plus a summary such as "3 cards · 1 needs attention".
* **Open a card** to see its details and do everything with it: freeze or unfreeze it, set the daily limit and online/international use, change its 4-digit card PIN, report it lost or stolen (permanent), or activate a debit card you have collected.
  A blocked card can't be changed, and a card that isn't active yet can't be frozen, limited or have its PIN changed.
* **Request a new card** is on the list (see "How new cards are issued" below). The same actions are on the Cards tab; the management screens reuse them, so behaviour is identical.
* Searching for *freeze*, *limit*, *PIN* or *lost* finds Card management.

## How new cards are issued

Neither kind of new card works at once, and the app never decides when a card becomes usable: the bank does.

* **Debit card:** you choose the **branch you'll collect it from** and confirm with your PIN. The bank prepares it for **5 days** (status *Being prepared*, with the day it will be ready).
  After 5 days you get a notification to **collect it from that branch with your ID** and the status becomes *Ready to collect*. Only then can you activate it in the app (PIN), after you have it in your hand.
  One debit card can be on its way at a time.
* **Virtual card:** the request goes to the bank and the card shows *Awaiting bank approval*. **Only the bank can activate it**, from its own system; the customer has no Activate button and time alone
  never approves it. When the bank approves it you get a notification and the card becomes active. Up to 3 virtual cards (waiting ones count).
* Until a card is active it can't be frozen, limited, have its PIN changed or be reported lost.
* **Prototype tools (Settings → Prototype tools):** there is no bank back-office in this prototype, so a clearly labelled section stands in for it: *Bank: approve waiting virtual cards* and *Time: skip 5 days*.
  It appears only while the app runs on its built-in mock bank; with a real server (`API_BASE_URL`) it is not shown, and the bank's staff do these things in their own systems.
* The "ready to collect" and "approved" notices are **in-app notifications**. Phone push notifications still need a Firebase/APNs setup.

## Accounts, scheduled payments, profile and card requests

* **Account detail** (`/accounts/:id`): balance (respecting the hide-balances switch), this month's money in/out, recent activity for that account only, and
  shortcuts to send from it, get its statement, or see its full history. Fixed deposits say money can't be sent from them.
* **Scheduled and repeating payments** (`/scheduled`, Payments → Scheduled): schedule a transfer for a date and repeat it weekly or monthly. A scheduled payment
  is stored and **actually runs on its day** (the mock bank runs due payments whenever you open accounts, history or this list, as an overnight batch would). Funds
  and limits are checked on the day; a failed run is recorded and shown, and a repeating payment carries on. You can see what's queued and cancel it.
* **Personal details** (`/profile/edit`): change email and mobile number (name and customer number are fixed). It needs your PIN and leaves a security notification.
* **Request a card** (Cards tab or Card management): see *How new cards are issued* below. Credit cards are refused ("visit a branch"). No fees are charged in the prototype.

## Disputes, new accounts and loan applications

* **Disputes** (`/disputes`, `/disputes/new?tx=…`): from a payment's details choose **Report**, pick what went wrong and send it. You get a reference, a
  notification, and a list under Help & support → My disputes. Only settled payments you made can be disputed (income, pending, failed and own-account moves
  say why not); one dispute per payment. It does not refund or reverse anything: the bank decides. "I don't recognise this" also points to protecting your cards.
* **Open an account** (Home → Accounts → Open new, or Payments → Open account): another savings or current account, funded from an existing account with your PIN. The minimum is LKR 1,000 and
  there is a ceiling of 6 accounts (deposits count). Fixed deposits have their own section (below).
* **Apply for a loan** (Loans → Apply for a loan): type, amount, term, income, employment and consent. It shows an estimated monthly payment and a plain affordability hint
  (instalment as a share of income), clearly labelled as a guide. The application is recorded with a reference as *received / under review*. **The app can never approve a loan**:
  there is no approved state, no loan is created and no money moves.

## Fixed deposits

Payments → **Fixed deposits** lists every deposit you've opened; **Open a fixed deposit** creates one (also reachable from Open an account).

* **Pay from:** you choose which savings or current account the money comes from. The minimum is LKR 10,000.
* **Term:** 3, 6 or 12 months, or **More than 12 months**, where you type the number of months. Only whole years are accepted (24, 36, 48 … up to 120), and the box
  says exactly what's wrong if you type something else (for example 34).
* **When it matures:** two choices, *Renew with interest* (principal and interest start a new term together, so interest earns interest) or *Renew without interest* (only the original amount
  renews; the interest is paid to your account). "With interest" is selected by default.
* **Nothing can be changed after opening.** The amount, the term and the maturity choice are fixed once the deposit is open: the screen says so before you confirm and again in the PIN prompt,
  the list has no edit controls, and the API has no endpoint to edit one. (A deposit arranged some other way, for example at a branch, that pays out at maturity is still shown correctly as *Paid out at maturity*.)
* **The list** shows what's locked away and the interest still to come, and for each deposit: amount, term, rate, progress through the term, days left, interest and total at maturity,
  where it was funded from, how many times it has renewed, and what happens at maturity. It also appears in your accounts and total balance.
* **Maturity** is processed by the mock bank when you open accounts, history or the deposits list (like an overnight run): it renews as instructed, dates the entries on the maturity
  day, and records interest as income and your own money coming back as an own-account move (not income). Interest is **simple interest** for the term.
* **Sample figures:** the rates (7.5% for 3 months up to 11% for 6+ years) are made-up examples, not a rate card, and the screen says the bank confirms the real rate. A fixed deposit can't send money, and taking money
  out early needs a branch visit; early closure isn't built.

## QR scanning, branches and budgets

* **Scan to pay** uses the **camera** (`mobile_scanner`) to read a Zentrix payment QR code; only Zentrix codes are accepted and a foreign one is refused. Reading is
  one-at-a-time (the camera repeats a code; the amount sheet opens once). If camera access is off you get a plain message and the sample codes remain. No image is stored.
* **Branches & ATMs** open real turn-by-turn directions (a maps link). *Sort by distance from me* asks for **approximate** location only when you tap it, sorts nearest first
  using straight-line distance, and uses the position on that screen only: it is not stored or sent. Without it, distances are from a fixed reference point (sample data).
* **Budgets** (`/budgets`, Payments → Budgets): a monthly limit per spending category, with month-to-date progress (settled spending only, same rules as Analytics), a suggested
  limit from your last three months, and a notification when a payment takes you past 80% or 100% of a limit (once per threshold). Nothing is ever blocked: they're your own targets.
* Platform declarations: Android `CAMERA` (camera optional) and `ACCESS_COARSE_LOCATION`; iOS camera and location-when-in-use descriptions. The app asks for **no contacts access** (it was only ever needed for top-up, which is gone), and a test checks that stays true.
* **Not tested here:** the live camera and GPS need a real device. Tests replace them with fakes, so the code around them is covered but the plugins themselves are not.

## Brand assets

Your two source images live in `assets/icon/` (`app icon.png`, `bank logo.png`) and are never modified. Everything the app uses is derived from them:

```
python tool/prepare_brand_assets.py     # writes assets/brand/*
dart run flutter_launcher_icons         # writes the Android and iOS launcher icons
```

* `assets/brand/app_icon.png`: full-bleed, fully opaque 1024 px square (iOS rounds corners itself and rejects transparency, so the rounded artwork's corners are cropped away).
* `assets/brand/app_icon_foreground.png`: the Android adaptive foreground, sized to sit inside the launcher's circle/squircle mask; the background layer is the artwork's own deep blue (`#012372`).
* `assets/brand/bank_logo.png`: the logo with the stray glow specks around it removed. `BankMark` in `core/widgets/bank_logo.dart` shows it on the splash screen, sign-in and other logo spots, and as a single-colour silhouette on card faces.

## Project status by phase

| Phase | Scope | Status |
| --- | --- | --- |
| 1–2 | Design system, splash, onboarding, sign-in, registration, PIN/biometrics, dashboard, cards | Done (on mocks) |
| 3 | Navigation shell, profile, shared widgets, routing guards | Done |
| 4 | Payments: transfers, beneficiaries, bills, QR (camera), receipts, loan instalments, scheduled and repeating payments | Done (on mocks, plus API repositories) |
| 5 | Money management: history, analytics, budgets, savings, loans and loan applications, accounts and fixed deposits, CSV and PDF statements, disputes | Done |
| 6 | Engagement & security: notifications, search, security centre, app lock, settings (persisted), support and branch finder, card controls and card requests, edit profile | Done (mock services) |
| 7 | Quality: offline, maintenance, session expiry, error states, accessibility audit, crash handling, security review | Done, with the open items below |
| 8 | Backend groundwork: Dio client, API repositories for every data feature, contract, log redaction, pinning hook | Done; no server exists |

**"Done" means built, analysed (`flutter analyze` clean) and covered by 332 passing tests, plus a successful Android debug build.
It does not mean production-ready.** Nothing has been run on a physical device, and no real bank, SMS, KYC or card service is connected.

### Open items

* **Sinhala and Tamil: not started, and bigger than it looks.** There are about **1,260 sentence-length strings in 86 files**, and only 29 of them are in `AppStrings`; the rest are written inline in the screens. Real localisation means moving all of them into ARB files (rewriting every call site), bundling Sinhala and Tamil fonts (the Manrope font has neither script), translating them, and having native speakers review the financial wording. Machine-translated money terms in a banking app are a real risk, so this was deliberately left rather than done half-way. The Language setting honestly says English only.
* **Push notifications.** Needs a Firebase/APNs project and server-side sending; the in-app notification centre is separate and works.
* **Verification against a real server.** The API contract has only run against a fake HTTP adapter.
* A real crash-reporting service; server-verified step-up authentication for payments.
* Release hardening: real `applicationId` and signing key, obfuscation, iOS screenshot protection, root/jailbreak checks.
* Device testing: TalkBack/VoiceOver walkthrough, performance profiling of the blur effects, release-build checks, a PDF viewed in a real reader.
