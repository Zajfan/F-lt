import 'package:flutter_test/flutter_test.dart';
import 'package:falt/domain/work_log.dart';
import 'package:falt/shared/format.dart';

void main() {
  test('minute billing rounds once and keeps exact öre for invoice line', () {
    final start = DateTime.utc(2026, 1, 1, 8);
    final entry = TimeEntry(
      id: 't',
      jobId: 'j',
      person: 'Erik',
      startedAt: start,
      endedAt: start.add(const Duration(minutes: 1, seconds: 1)),
      hourlyRateOre: 65000,
      note: 'Arbete',
    );
    expect(entry.minutes, 2);
    expect(entry.netOre, 2167);
    expect(entry.invoiceLine.netOre, 2167);
  });
  test('Swedish decimal input rejects negative, excess precision and junk', () {
    expect(parseFixed('650,50', 2), 65050);
    expect(parseFixed('1,125', 3), 1125);
    expect(parseFixed('-1', 2), isNull);
    expect(parseFixed('1.234', 2), isNull);
    expect(parseFixed('1e3', 2), isNull);
    expect(parseFixed('NaN', 2), isNull);
  });
  test(
    'material quantity snapshots purchase and sale amounts independently',
    () {
      final m = MaterialEntry(
        id: 'm',
        jobId: 'j',
        description: 'Kabel',
        quantityMilli: 12500,
        purchasePriceOre: 1800,
        sellingPriceOre: 3200,
        unit: 'm',
      );
      expect(m.costOre, 22500);
      expect(m.netOre, 40000);
      expect(MaterialEntry.fromJson(m.toJson()).quantityMilli, 12500);
    },
  );
}
