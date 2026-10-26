import 'package:flutter_test/flutter_test.dart';
import 'package:falt/domain/estimate.dart';

void main() {
  EstimateLine line(int price, LineKind kind, {int quantity = 1000}) =>
      EstimateLine(
        description: 'Test',
        unitPriceOre: price,
        quantityMilli: quantity,
        kind: kind,
      );
  test('ROT applies only to labour gross and does not reduce invoice VAT', () {
    final totals = EstimateTotals([
      line(100000, LineKind.labour),
      line(20000, LineKind.material),
    ], Deduction.rot);
    expect(totals.netOre, 120000);
    expect(totals.vatOre, 30000);
    expect(totals.deductionOre, 37500);
    expect(totals.customerPaysOre, 112500);
  });
  test('RUT excludes material and other charges', () {
    final totals = EstimateTotals([
      line(100000, LineKind.labour),
      line(20000, LineKind.other),
    ], Deduction.rut);
    expect(totals.deductionOre, 62500);
    expect(totals.customerPaysOre, 87500);
  });
  test('fractional quantities and half öre round deterministically', () {
    final row = line(101, LineKind.material, quantity: 1500);
    expect(row.netOre, 152);
    expect(row.vatOre, 38);
  });
  test('invalid lines and empty quotes are rejected', () {
    expect(() => line(-1, LineKind.labour), throwsArgumentError);
    expect(() => line(100, LineKind.labour, quantity: 0), throwsArgumentError);
    expect(() => EstimateTotals([], Deduction.none), throwsArgumentError);
  });
  test('terminal quote states cannot be reopened or overwritten', () {
    final draft = Quote(
      id: 'q',
      customerId: 'c',
      title: 'Test',
      lines: [line(100, LineKind.labour)],
    );
    expect(() => draft.transition(QuoteStatus.accepted), throwsStateError);
    final sent = draft.transition(QuoteStatus.sent);
    final accepted = sent.transition(QuoteStatus.accepted);
    expect(accepted.revision, 3);
    expect(() => accepted.transition(QuoteStatus.declined), throwsStateError);
    expect(Quote.fromJson(accepted.toJson()).status, QuoteStatus.accepted);
  });
}
