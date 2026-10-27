import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:falt/domain/estimate.dart';
import 'package:falt/domain/invoice.dart';
import 'package:falt/features/invoices/invoice_preview_page.dart';

void main() {
  testWidgets('invoice preview shows the recipient-facing document', (
    tester,
  ) async {
    final quote = Quote(
      id: 'preview-quote',
      customerId: 'preview-customer',
      title: 'Takmålning',
      lines: [
        EstimateLine(
          description: 'Målningsarbete',
          unitPriceOre: 65000,
          quantityMilli: 2000,
          kind: LineKind.labour,
        ),
      ],
    );
    final document = InvoiceDocument.draft(
      invoiceId: 'invoice-preview-quote',
      title: quote.title,
      quote: quote,
      customer: {
        'name': 'Johan Berg',
        'address': 'Vasagatan 8, Göteborg',
      },
      company: {'name': 'Tak & Måleri AB'},
      issuedAt: DateTime.utc(2026, 10, 27),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('sv'),
        home: InvoicePreviewPage(document: document),
      ),
    );

    expect(find.text('Förhandsvisning'), findsOneWidget);
    expect(find.text('FAKTURA'), findsOneWidget);
    expect(find.text('Tak & Måleri AB'), findsOneWidget);
    expect(find.text('Johan Berg'), findsOneWidget);
    expect(find.text('Målningsarbete'), findsOneWidget);

    await tester.ensureVisible(find.text('Att betala'));
    await tester.pumpAndSettle();
    expect(find.text('Att betala'), findsOneWidget);
    expect(
      find.text(
        'Förhandsvisning – skickas inte. Detta är hur fakturan är tänkt att se ut för mottagaren.',
      ),
      findsOneWidget,
    );
  });
}
