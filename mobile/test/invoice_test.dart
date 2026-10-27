import 'package:flutter_test/flutter_test.dart';
import 'package:falt/domain/estimate.dart';
import 'package:falt/domain/invoice.dart';

void main() {
  test('invoice document renders frozen recipient and company details', () {
    final quote = Quote(
      id: 'quote-1',
      customerId: 'customer-1',
      title: 'Målning av fasad',
      status: QuoteStatus.sent,
      lines: [
        EstimateLine(
          description: 'Målningsarbete',
          unitPriceOre: 65000,
          quantityMilli: 1500,
          kind: LineKind.labour,
        ),
      ],
    );

    final document = InvoiceDocument.fromRecord({
      'id': 'invoice-quote-1',
      'title': quote.title,
      'customerId': quote.customerId,
      'quoteSnapshot': quote.toJson(),
      'customerSnapshot': {
        'name': 'Anna Svensson',
        'address': 'Linnégatan 24, Göteborg',
        'email': 'anna@example.com',
      },
      'companySnapshot': {
        'name': 'Målarna Väst AB',
        'organisation': '559000-1234',
        'address': 'Industrigatan 4, Göteborg',
      },
      'createdAt': '2026-10-27T08:00:00.000Z',
      'dueAt': '2026-11-26T08:00:00.000Z',
      'status': 'unpaid',
    });

    expect(document.invoiceId, 'invoice-quote-1');
    expect(document.companyName, 'Målarna Väst AB');
    expect(document.customerName, 'Anna Svensson');
    expect(document.customerAddress, 'Linnégatan 24, Göteborg');
    expect(document.quote.title, 'Målning av fasad');
    expect(document.totals.netOre, 97500);
    expect(document.totals.vatOre, 24375);
    expect(document.totals.customerPaysOre, 121875);
  });

  test('legacy invoice document falls back to current contact details', () {
    final quote = Quote(
      id: 'quote-legacy',
      customerId: 'customer-legacy',
      title: 'Service',
      status: QuoteStatus.sent,
      lines: [
        EstimateLine(
          description: 'Servicebesök',
          unitPriceOre: 10000,
          quantityMilli: 1000,
          kind: LineKind.labour,
        ),
      ],
    );

    final document = InvoiceDocument.fromRecord(
      {
        'id': 'invoice-legacy',
        'title': quote.title,
        'customerId': quote.customerId,
        'quoteSnapshot': quote.toJson(),
        'createdAt': '2026-10-27T08:00:00.000Z',
        'dueAt': '2026-11-26T08:00:00.000Z',
        'status': 'unpaid',
      },
      customerFallback: {
        'name': 'Johan Berg',
        'address': 'Vasagatan 8, Göteborg',
      },
      companyFallback: {'name': 'Ditt företag'},
    );

    expect(document.customerName, 'Johan Berg');
    expect(document.customerAddress, 'Vasagatan 8, Göteborg');
    expect(document.companyName, 'Ditt företag');
  });
}
