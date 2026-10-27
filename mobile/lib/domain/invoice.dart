import 'estimate.dart';

/// Immutable, display-ready data for the invoice recipient view.
///
/// Invoice records created before snapshots existed are still supported by
/// using the current customer/company values as a migration fallback.
class InvoiceDocument {
  const InvoiceDocument({
    required this.invoiceId,
    required this.title,
    required this.quote,
    required this.companyName,
    required this.companyOrganisation,
    required this.companyAddress,
    required this.companyEmail,
    required this.companyPhone,
    required this.customerName,
    required this.customerAddress,
    required this.customerEmail,
    required this.customerPhone,
    required this.issuedAt,
    required this.dueAt,
    required this.status,
  });

  final String invoiceId;
  final String title;
  final Quote quote;
  final String companyName;
  final String companyOrganisation;
  final String companyAddress;
  final String companyEmail;
  final String companyPhone;
  final String customerName;
  final String customerAddress;
  final String customerEmail;
  final String customerPhone;
  final DateTime issuedAt;
  final DateTime dueAt;
  final String status;

  EstimateTotals get totals => quote.totals;
  bool get isDraft => status == 'draft' || status == 'unpaid';

  factory InvoiceDocument.fromRecord(
    Map<String, dynamic> record, {
    Map<String, dynamic>? customerFallback,
    Map<String, dynamic>? companyFallback,
  }) {
    final rawQuote = record['quoteSnapshot'];
    if (rawQuote is! Map) {
      throw const FormatException('Invoice quote snapshot is missing.');
    }
    final customer = _merged(
      customerFallback,
      record['customerSnapshot'],
    );
    final company = _merged(
      companyFallback,
      record['companySnapshot'],
    );
    final issuedAt = _date(record['createdAt']) ?? DateTime.now().toUtc();
    return InvoiceDocument(
      invoiceId: _text(record['id']) ?? 'invoice-preview',
      title: _text(record['title']) ?? 'Faktura',
      quote: Quote.fromJson(Map<String, dynamic>.from(rawQuote)),
      companyName: _text(company['name']) ?? 'Ditt företag',
      companyOrganisation: _text(company['organisation']) ?? '',
      companyAddress: _text(company['address']) ?? '',
      companyEmail: _text(company['email']) ?? '',
      companyPhone: _text(company['phone']) ?? '',
      customerName: _text(customer['name']) ?? 'Okänd kund',
      customerAddress: _text(customer['address']) ?? '',
      customerEmail: _text(customer['email']) ?? '',
      customerPhone: _text(customer['phone']) ?? '',
      issuedAt: issuedAt,
      dueAt: _date(record['dueAt']) ?? issuedAt.add(const Duration(days: 30)),
      status: _text(record['status']) ?? 'draft',
    );
  }

  factory InvoiceDocument.draft({
    required String invoiceId,
    required String title,
    required Quote quote,
    Map<String, dynamic>? customer,
    Map<String, dynamic>? company,
    DateTime? issuedAt,
  }) {
    final issued = (issuedAt ?? DateTime.now()).toUtc();
    final customerData = customer ?? const <String, dynamic>{};
    final companyData = company ?? const <String, dynamic>{};
    return InvoiceDocument(
      invoiceId: invoiceId,
      title: title,
      quote: quote,
      companyName: _text(companyData['name']) ?? 'Ditt företag',
      companyOrganisation: _text(companyData['organisation']) ?? '',
      companyAddress: _text(companyData['address']) ?? '',
      companyEmail: _text(companyData['email']) ?? '',
      companyPhone: _text(companyData['phone']) ?? '',
      customerName: _text(customerData['name']) ?? 'Okänd kund',
      customerAddress: _text(customerData['address']) ?? '',
      customerEmail: _text(customerData['email']) ?? '',
      customerPhone: _text(customerData['phone']) ?? '',
      issuedAt: issued,
      dueAt: issued.add(const Duration(days: 30)),
      status: 'draft',
    );
  }

  static Map<String, dynamic> _merged(
    Map<String, dynamic>? fallback,
    Object? snapshot,
  ) {
    final result = <String, dynamic>{...?fallback};
    if (snapshot is Map) {
      result.addAll(Map<String, dynamic>.from(snapshot));
    }
    return result;
  }

  static String? _text(Object? value) => value is String && value.isNotEmpty
      ? value
      : null;

  static DateTime? _date(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value)?.toLocal();
  }
}
