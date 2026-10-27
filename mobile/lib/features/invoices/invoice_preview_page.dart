import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../domain/estimate.dart';
import '../../domain/invoice.dart';
import '../../shared/format.dart';

class InvoicePreviewPage extends StatelessWidget {
  const InvoicePreviewPage({super.key, required this.document});

  final InvoiceDocument document;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Förhandsvisning')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.secondaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.visibility_outlined),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Förhandsvisning – skickas inte. Detta är hur fakturan är tänkt att se ut för mottagaren.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            color: Colors.white,
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(context),
                  const Divider(height: 32),
                  _recipient(context),
                  const SizedBox(height: 24),
                  _invoiceMeta(context),
                  const SizedBox(height: 24),
                  _lines(context),
                  const SizedBox(height: 22),
                  _totals(context),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 12),
                  Text(
                    'Tack för ditt förtroende.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (document.companyEmail.isNotEmpty ||
                      document.companyPhone.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        [
                          document.companyEmail,
                          document.companyPhone,
                        ].where((value) => value.isNotEmpty).join(' · '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              document.companyName,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            if (document.companyOrganisation.isNotEmpty)
              Text(document.companyOrganisation),
            if (document.companyAddress.isNotEmpty)
              Text(document.companyAddress),
          ],
        ),
      ),
      const SizedBox(width: 16),
      Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            'FAKTURA',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          Text(
            'UTKAST',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ],
  );

  Widget _recipient(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'FAKTURERAS TILL',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: .8,
        ),
      ),
      const SizedBox(height: 5),
      Text(
        document.customerName,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      if (document.customerAddress.isNotEmpty)
        Text(document.customerAddress),
      if (document.customerEmail.isNotEmpty ||
          document.customerPhone.isNotEmpty)
        Text(
          [document.customerEmail, document.customerPhone]
              .where((value) => value.isNotEmpty)
              .join(' · '),
        ),
    ],
  );

  Widget _invoiceMeta(BuildContext context) => Wrap(
    spacing: 24,
    runSpacing: 14,
    children: [
      _meta(
        context,
        'Fakturadatum',
        DateFormat('d MMM yyyy', 'sv').format(document.issuedAt),
      ),
      _meta(
        context,
        'Förfallodatum',
        DateFormat('d MMM yyyy', 'sv').format(document.dueAt),
      ),
      _meta(context, 'Referens', _reference),
    ],
  );

  Widget _meta(BuildContext context, String label, String value) => SizedBox(
    width: 125,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 3),
        Text(value, style: Theme.of(context).textTheme.bodyMedium),
      ],
    ),
  );

  Widget _lines(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        padding: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: const Text(
          'FAKTURARADER',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
      for (final line in document.quote.lines) _line(context, line),
    ],
  );

  Widget _line(BuildContext context, EstimateLine line) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                line.description,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 3),
              Text(
                '${_quantity(line.quantityMilli)} × ${money(line.unitPriceOre)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          money(line.netOre),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );

  Widget _totals(BuildContext context) {
    final totals = document.totals;
    final deductionLabel = switch (document.quote.deduction) {
      Deduction.rot => 'ROT-avdrag, preliminärt',
      Deduction.rut => 'RUT-avdrag, preliminärt',
      Deduction.none => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _totalRow(context, 'Summa exkl. moms', money(totals.netOre)),
        _totalRow(context, 'Moms 25 %', money(totals.vatOre)),
        if (deductionLabel != null)
          _totalRow(
            context,
            deductionLabel,
            '−${money(totals.deductionOre)}',
          ),
        const Divider(height: 24),
        _totalRow(
          context,
          'Att betala',
          money(totals.customerPaysOre),
          prominent: true,
        ),
      ],
    );
  }

  Widget _totalRow(
    BuildContext context,
    String label,
    String value, {
    bool prominent = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: prominent
                ? Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  )
                : null,
          ),
        ),
        Text(
          value,
          style: prominent
              ? Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                )
              : null,
        ),
      ],
    ),
  );

  String get _reference {
    final id = document.invoiceId;
    return id.startsWith('invoice-') ? id.substring('invoice-'.length) : id;
  }

  String _quantity(int quantityMilli) {
    final whole = quantityMilli ~/ 1000;
    final remainder = quantityMilli % 1000;
    if (remainder == 0) return '$whole';
    return '${quantityMilli / 1000}'.replaceAll(RegExp(r'\.0+$'), '');
  }
}
