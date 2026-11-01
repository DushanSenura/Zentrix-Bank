import 'package:flutter/material.dart';
import '../../../shared/models/models.dart';
import '../../../shared/models/payment_models.dart';

enum SearchKind { feature, setting, beneficiary, transaction }

class SearchHit {
  const SearchHit({required this.kind, required this.title, required this.subtitle, required this.route, required this.icon, this.extra});
  final SearchKind kind;
  final String title, subtitle, route;
  final IconData icon;

  /// Passed to the route (e.g. the beneficiary or transaction being opened).
  final Object? extra;
}

class SearchSection {
  const SearchSection(this.title, this.hits);
  final String title;
  final List<SearchHit> hits;
}

typedef _Target = (String label, String keywords, String route, IconData icon);

const _features = <_Target>[
  ('Send money', 'transfer send pay someone', '/transfer', Icons.swap_horiz_rounded),
  ('Pay bills', 'bill electricity water internet tv insurance utilities', '/bills', Icons.receipt_long_rounded),
  ('Card management', 'card freeze block unblock limit pin lost stolen virtual debit', '/cards/manage', Icons.credit_card_rounded),
  ('Scan to pay', 'qr scan merchant', '/qr', Icons.qr_code_scanner_rounded),
  ('My QR', 'qr receive code', '/qr?mine=1', Icons.qr_code_2_rounded),
  ('Beneficiaries', 'payee recipient saved contacts', '/beneficiaries', Icons.group_rounded),
  ('Transactions', 'history activity spending', '/transactions', Icons.history_rounded),
  ('Savings goals', 'save goal target', '/savings', Icons.savings_rounded),
  ('Loans', 'loan borrow credit', '/loans', Icons.account_balance_rounded),
  ('Loan calculator', 'loan emi instalment estimate', '/loans/calculator', Icons.calculate_rounded),
  ('Statements', 'statement csv export pdf', '/statements', Icons.description_rounded),
  ('Notifications', 'alerts inbox messages', '/notifications', Icons.notifications_rounded),
  ('Help & support', 'help support faq chat contact branch atm', '/support', Icons.support_agent_rounded),
];

const _settings = <_Target>[
  ('Change password', 'password security credentials', '/security/password', Icons.password_rounded),
  ('Change transaction PIN', 'pin passcode security', '/security/pin', Icons.pin_rounded),
  ('Trusted devices & sessions', 'devices sessions logout sign out security', '/security/devices', Icons.devices_rounded),
  ('Transaction limits', 'limit daily maximum security', '/security/limits', Icons.speed_rounded),
  ('Login history', 'login history sign in security', '/security/history', Icons.history_toggle_off_rounded),
  ('Security center', 'security biometric fingerprint face two-factor 2fa', '/security', Icons.shield_rounded),
  ('Appearance', 'theme dark light mode appearance', '/settings', Icons.palette_rounded),
  ('App lock', 'lock timeout inactivity privacy', '/settings', Icons.lock_clock_rounded),
  ('Accessibility', 'reduce motion accessibility', '/settings', Icons.accessibility_new_rounded),
  ('Language', 'language english sinhala tamil', '/settings', Icons.translate_rounded),
];

bool _matches(String haystack, String query) => query.split(RegExp(r'\s+')).every((w) => haystack.toLowerCase().contains(w));

/// Searches features, settings, beneficiaries and transactions. Empty sections are omitted.
List<SearchSection> searchAll(String query, {required List<Transaction> transactions, required List<Beneficiary> beneficiaries, int perSection = 6}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  List<SearchHit> targets(List<_Target> list, SearchKind kind, String subtitle) => [
    for (final (label, keywords, route, icon) in list)
      if (_matches('$label $keywords', q)) SearchHit(kind: kind, title: label, subtitle: subtitle, route: route, icon: icon),
  ];
  final sections = [
    SearchSection('Features', targets(_features, SearchKind.feature, 'Feature')),
    SearchSection('Settings', targets(_settings, SearchKind.setting, 'Setting')),
    SearchSection('Beneficiaries', [
      for (final b in beneficiaries)
        if (_matches('${b.name} ${b.nickname} ${b.bank}', q))
          SearchHit(kind: SearchKind.beneficiary, title: b.displayName, subtitle: '${b.bank} ${b.masked}', route: '/transfer', icon: Icons.person_rounded, extra: b),
    ]),
    SearchSection('Transactions', [
      for (final t in transactions)
        if (_matches('${t.merchant} ${t.id} ${t.reference}', q))
          SearchHit(kind: SearchKind.transaction, title: t.merchant, subtitle: t.id, route: '/transactions/${t.id}', icon: Icons.receipt_rounded, extra: t),
    ]),
  ];
  return [
    for (final s in sections)
      if (s.hits.isNotEmpty) SearchSection(s.title, s.hits.take(perSection).toList()),
  ];
}
