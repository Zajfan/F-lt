import 'package:intl/intl.dart';

String money(int ore) =>
    NumberFormat.currency(locale: 'sv_SE', symbol: 'kr').format(ore / 100);

/// Parse locale-style decimal input without binary floating point money conversion.
int? parseFixed(String value, int decimals) {
  if (decimals < 0 || decimals > 3) {
    throw ArgumentError('Unsupported precision');
  }
  final text = value.trim().replaceAll(',', '.');
  final pattern = decimals == 0 ? r'^\d+$' : '^\\d+(?:\\.\\d{1,$decimals})?\$';
  if (!RegExp(pattern).hasMatch(text)) return null;
  final parts = text.split('.');
  final scale = [1, 10, 100, 1000][decimals];
  final whole = int.tryParse(parts.first);
  if (whole == null || whole > 100000000) return null;
  return whole * scale +
      (parts.length == 2 ? int.parse(parts[1].padRight(decimals, '0')) : 0);
}
