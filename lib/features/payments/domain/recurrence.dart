import '../../../shared/models/payment_models.dart';

int _daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// The run after [from]. Monthly runs keep to [anchorDay] (the day the customer originally chose), clamped to
/// the length of the month, so 31 Jan → 28 Feb → 31 Mar rather than drifting to the 28th for good.
/// The time of day is kept. [Recurrence.once] has no next run and returns [from].
DateTime nextOccurrence(DateTime from, Recurrence recurrence, {int? anchorDay}) {
  switch (recurrence) {
    case Recurrence.once:
      return from;
    case Recurrence.weekly:
      return DateTime(from.year, from.month, from.day + 7, from.hour, from.minute);
    case Recurrence.monthly:
      final y = from.month == 12 ? from.year + 1 : from.year;
      final m = from.month == 12 ? 1 : from.month + 1;
      final day = (anchorDay ?? from.day).clamp(1, _daysInMonth(y, m));
      return DateTime(y, m, day, from.hour, from.minute);
  }
}

String recurrenceLabel(Recurrence r) => switch (r) {
  Recurrence.once => 'One time',
  Recurrence.weekly => 'Every week',
  Recurrence.monthly => 'Every month',
};
