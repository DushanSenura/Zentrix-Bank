import 'package:intl/intl.dart';

final _amount = NumberFormat('#,##0.00', 'en_US');
final _whole = NumberFormat('#,##0', 'en_US');

/// `LKR 428,750.00`; with [signed], positive values get a leading `+`.
String formatMoney(double value, {String currency = 'LKR', bool signed = false}) {
  final sign = value < 0 ? '-' : (signed ? '+' : '');
  return '$sign$currency ${_amount.format(value.abs())}';
}

String formatWhole(double value) => _whole.format(value);

String formatShortDate(DateTime d) => DateFormat('d MMM').format(d);

String formatGroupDate(DateTime d, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return DateFormat('d MMM yyyy').format(d);
}

String greetingFor(DateTime now) {
  final h = now.hour;
  if (h < 12) return 'Good morning';
  if (h < 17) return 'Good afternoon';
  return 'Good evening';
}

/// `Just now`, `5 min ago`, `3 h ago`, `Yesterday`, or a date.
String timeAgo(DateTime d, DateTime now) {
  final diff = now.difference(d);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  if (diff.inDays == 1) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays} days ago';
  return DateFormat('d MMM yyyy').format(d);
}
