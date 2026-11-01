import '../../../shared/models/models.dart';

class QrMerchant {
  const QrMerchant({required this.id, required this.name, required this.category});
  final String id, name;
  final TxCategory category;
}

/// Parses `zentrixpay://pay?m=<id>&n=<name>&c=<category>`. Returns null for anything else,
/// so a random QR code can never start a payment.
QrMerchant? parseMerchantQr(String payload) {
  final uri = Uri.tryParse(payload.trim());
  if (uri == null || uri.scheme != 'zentrixpay' || uri.host != 'pay') return null;
  final id = uri.queryParameters['m'];
  final name = uri.queryParameters['n'];
  if (id == null || id.isEmpty || name == null || name.trim().isEmpty) return null;
  final category = TxCategory.values.firstWhere(
    (c) => c.name == uri.queryParameters['c'],
    orElse: () => TxCategory.shopping,
  );
  return QrMerchant(id: id, name: name.trim(), category: category);
}

String merchantQr(String id, String name, TxCategory category) =>
    Uri(scheme: 'zentrixpay', host: 'pay', queryParameters: {'m': id, 'n': name, 'c': category.name}).toString();

/// What the "My QR" screen encodes: enough for a payer to identify the customer, no balances or card data.
String receiveQr(String customerNumber, String name) =>
    Uri(scheme: 'zentrixpay', host: 'receive', queryParameters: {'c': customerNumber.replaceAll(' ', ''), 'n': name}).toString();

/// Simulated scan targets for the prototype scanner.
final sampleScans = <(String, String)>[
  ('Keells Supermarket', merchantQr('KEELLS-114', 'Keells Supermarket', TxCategory.food)),
  ('Odel', merchantQr('ODEL-021', 'Odel', TxCategory.shopping)),
  ('PickMe ride', merchantQr('PICKME-770', 'PickMe', TxCategory.transport)),
  ('Not a Zentrix code', 'https://example.com/not-a-payment'),
];
