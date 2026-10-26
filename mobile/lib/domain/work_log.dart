import 'estimate.dart';

enum ChargeType { included, additional }

class TimeEntry {
  TimeEntry({
    required this.id,
    required this.jobId,
    required this.person,
    required this.startedAt,
    required this.endedAt,
    required this.hourlyRateOre,
    required this.note,
    this.chargeType = ChargeType.included,
    this.approved = false,
    this.invoiceId,
  }) {
    if (!endedAt.isAfter(startedAt) ||
        hourlyRateOre < 0 ||
        note.trim().isEmpty) {
      throw ArgumentError('Ange giltig tid, timpris och beskrivning.');
    }
  }
  final String id, jobId, person, note;
  final DateTime startedAt, endedAt;
  final int hourlyRateOre;
  final ChargeType chargeType;
  final bool approved;
  final String? invoiceId;
  int get minutes =>
      (endedAt.difference(startedAt).inMilliseconds / 60000).ceil();
  int get netOre => roundRatio(hourlyRateOre * minutes, 60);
  bool overlaps(TimeEntry other) =>
      id != other.id &&
      person == other.person &&
      startedAt.isBefore(other.endedAt) &&
      endedAt.isAfter(other.startedAt);
  EstimateLine get invoiceLine => EstimateLine(
    description:
        '$note · $minutes min à ${(hourlyRateOre / 100).toStringAsFixed(2)} kr/tim',
    unitPriceOre: netOre,
    quantityMilli: 1000,
    kind: LineKind.labour,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'jobId': jobId,
    'person': person,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'endedAt': endedAt.toUtc().toIso8601String(),
    'hourlyRateOre': hourlyRateOre,
    'note': note,
    'chargeType': chargeType.name,
    'approved': approved,
    'invoiceId': invoiceId,
  };
  factory TimeEntry.fromJson(Map<String, dynamic> j) => TimeEntry(
    id: j['id'] as String,
    jobId: j['jobId'] as String,
    person: j['person'] as String,
    startedAt: DateTime.parse(j['startedAt'] as String),
    endedAt: DateTime.parse(j['endedAt'] as String),
    hourlyRateOre: j['hourlyRateOre'] as int,
    note: j['note'] as String,
    chargeType: ChargeType.values.byName(j['chargeType'] as String),
    approved: j['approved'] as bool,
    invoiceId: j['invoiceId'] as String?,
  );
}

class MaterialEntry {
  MaterialEntry({
    required this.id,
    required this.jobId,
    required this.description,
    required this.quantityMilli,
    required this.purchasePriceOre,
    required this.sellingPriceOre,
    this.unit = 'st',
    this.chargeType = ChargeType.included,
    this.approved = false,
    this.invoiceId,
  }) {
    if (description.trim().isEmpty ||
        quantityMilli <= 0 ||
        purchasePriceOre < 0 ||
        sellingPriceOre < 0 ||
        unit.trim().isEmpty) {
      throw ArgumentError('Ange giltigt material, antal och priser.');
    }
  }
  final String id, jobId, description, unit;
  final int quantityMilli, purchasePriceOre, sellingPriceOre;
  final ChargeType chargeType;
  final bool approved;
  final String? invoiceId;
  int get costOre => roundRatio(quantityMilli * purchasePriceOre, 1000);
  int get netOre => invoiceLine.netOre;
  EstimateLine get invoiceLine => EstimateLine(
    description: '$description ($unit)',
    unitPriceOre: sellingPriceOre,
    quantityMilli: quantityMilli,
    kind: LineKind.material,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'jobId': jobId,
    'description': description,
    'quantityMilli': quantityMilli,
    'purchasePriceOre': purchasePriceOre,
    'sellingPriceOre': sellingPriceOre,
    'unit': unit,
    'chargeType': chargeType.name,
    'approved': approved,
    'invoiceId': invoiceId,
  };
  factory MaterialEntry.fromJson(Map<String, dynamic> j) => MaterialEntry(
    id: j['id'] as String,
    jobId: j['jobId'] as String,
    description: j['description'] as String,
    quantityMilli: j['quantityMilli'] as int,
    purchasePriceOre: j['purchasePriceOre'] as int,
    sellingPriceOre: j['sellingPriceOre'] as int,
    unit: j['unit'] as String,
    chargeType: ChargeType.values.byName(j['chargeType'] as String),
    approved: j['approved'] as bool,
    invoiceId: j['invoiceId'] as String?,
  );
}

class JobBillingPreview {
  JobBillingPreview({
    required List<TimeEntry> time,
    required List<MaterialEntry> materials,
    Quote? quote,
  }) {
    final chargeTime = time
        .where(
          (e) => e.chargeType == ChargeType.additional && e.invoiceId == null,
        )
        .toList();
    final chargeMaterials = materials
        .where(
          (e) => e.chargeType == ChargeType.additional && e.invoiceId == null,
        )
        .toList();
    pendingApproval =
        chargeTime.where((e) => !e.approved).length +
        chargeMaterials.where((e) => !e.approved).length;
    timeIds = chargeTime.where((e) => e.approved).map((e) => e.id).toList();
    materialIds = chargeMaterials
        .where((e) => e.approved)
        .map((e) => e.id)
        .toList();
    lines = List.unmodifiable([
      if (quote != null) ...quote.lines,
      ...chargeTime.where((e) => e.approved).map((e) => e.invoiceLine),
      ...chargeMaterials.where((e) => e.approved).map((e) => e.invoiceLine),
    ]);
    deduction = quote?.deduction ?? Deduction.none;
  }
  late final int pendingApproval;
  late final List<String> timeIds, materialIds;
  late final List<EstimateLine> lines;
  late final Deduction deduction;
  EstimateTotals? get totals =>
      lines.isEmpty ? null : EstimateTotals(lines, deduction);
}
