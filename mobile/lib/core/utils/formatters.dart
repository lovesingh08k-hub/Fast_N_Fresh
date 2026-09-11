import 'package:intl/intl.dart';

class Formatters {
  Formatters._();

  static final NumberFormat _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
  static final NumberFormat _currencyDecimal = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

  static String currency(num amount) {
    if (amount == amount.roundToDouble()) return _currency.format(amount);
    return _currencyDecimal.format(amount);
  }

  static String currencyPlain(num amount) => _currencyDecimal.format(amount).replaceAll('₹', '₹');

  static final DateFormat _date = DateFormat('dd MMM yyyy');
  static final DateFormat _dateTime = DateFormat('dd MMM yyyy, hh:mm a');
  static final DateFormat _time = DateFormat('hh:mm a');
  static final DateFormat _shortDate = DateFormat('dd MMM');

  static String date(DateTime dt) => _date.format(dt.toLocal());
  static String dateTime(DateTime dt) => _dateTime.format(dt.toLocal());
  static String time(DateTime dt) => _time.format(dt.toLocal());
  static String shortDate(DateTime dt) => _shortDate.format(dt.toLocal());

  static String relative(DateTime dt) {
    final diff = DateTime.now().difference(dt.toLocal());
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    if (diff.inDays < 7) return '${diff.inDays} day${diff.inDays > 1 ? 's' : ''} ago';
    return date(dt);
  }
}
