/// All monetary values are integer öre. Quantity uses thousandths.
/// Tax and deductions are estimates, never eligibility decisions.
enum LineKind { labour, material, other }
enum Deduction { none, rot, rut }
enum QuoteStatus { draft, sent, accepted, declined }

int roundRatio(int numerator, int denominator) {
  if (denominator <= 0 || numerator < 0) {
    throw ArgumentError('Expected nonnegative numerator and positive denominator');
  }
  return (numerator + denominator ~/ 2) ~/ denominator;
}

class EstimateLine {
  EstimateLine({required this.description, required this.unitPriceOre,
    required this.quantityMilli, required this.kind}) {
    if (description.trim().isEmpty || unitPriceOre < 0 || quantityMilli <= 0) {
      throw ArgumentError('Invalid estimate line');
    }
  }
  final String description;
  final int unitPriceOre;
  final int quantityMilli;
  final LineKind kind;
  int get netOre => roundRatio(unitPriceOre * quantityMilli, 1000);
  int get vatOre => roundRatio(netOre * 25, 100);
  Map<String, Object> toJson() => {'description': description,
    'unitPriceOre': unitPriceOre, 'quantityMilli': quantityMilli, 'kind': kind.name};
  factory EstimateLine.fromJson(Map<String, dynamic> json) => EstimateLine(
    description: json['description'] as String,
    unitPriceOre: json['unitPriceOre'] as int,
    quantityMilli: json['quantityMilli'] as int,
    kind: LineKind.values.byName(json['kind'] as String));
}

class EstimateTotals {
  EstimateTotals(List<EstimateLine> lines, Deduction deduction) {
    if (lines.isEmpty) throw ArgumentError('At least one line is required');
    netOre = lines.fold(0, (sum, line) => sum + line.netOre);
    vatOre = lines.fold(0, (sum, line) => sum + line.vatOre);
    final labourGross = lines.where((line) => line.kind == LineKind.labour)
      .fold(0, (sum, line) => sum + line.netOre + line.vatOre);
    final percent = switch (deduction) {
      Deduction.none => 0, Deduction.rot => 30, Deduction.rut => 50,
    };
    deductionOre = roundRatio(labourGross * percent, 100);
  }
  late final int netOre;
  late final int vatOre;
  late final int deductionOre;
  int get grossOre => netOre + vatOre;
  int get customerPaysOre => grossOre - deductionOre;
}

class Quote {
  Quote({required this.id, required this.customerId, required this.title,
    required this.lines, this.status = QuoteStatus.draft,
    this.deduction = Deduction.none, this.revision = 1});
  final String id;
  final String customerId;
  final String title;
  final List<EstimateLine> lines;
  final QuoteStatus status;
  final Deduction deduction;
  final int revision;
  EstimateTotals get totals => EstimateTotals(lines, deduction);

  Quote transition(QuoteStatus next) {
    final allowed = switch (status) {
      QuoteStatus.draft => next == QuoteStatus.sent,
      QuoteStatus.sent => next == QuoteStatus.accepted || next == QuoteStatus.declined,
      QuoteStatus.accepted || QuoteStatus.declined => false,
    };
    if (!allowed) throw StateError('Invalid quote transition: $status → $next');
    return Quote(id: id, customerId: customerId, title: title,
      lines: List.unmodifiable(lines), deduction: deduction, status: next,
      revision: revision + 1);
  }
  Map<String, Object> toJson() => {'id': id, 'customerId': customerId,
    'title': title, 'lines': lines.map((line) => line.toJson()).toList(),
    'status': status.name, 'deduction': deduction.name, 'revision': revision};
  factory Quote.fromJson(Map<String, dynamic> json) => Quote(
    id: json['id'] as String, customerId: json['customerId'] as String,
    title: json['title'] as String,
    lines: (json['lines'] as List).map((line) =>
      EstimateLine.fromJson(Map<String, dynamic>.from(line as Map))).toList(),
    status: QuoteStatus.values.byName(json['status'] as String),
    deduction: Deduction.values.byName(json['deduction'] as String),
    revision: json['revision'] as int);
}
