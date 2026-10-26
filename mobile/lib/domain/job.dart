enum JobStatus { scheduled, inProgress, completed }

class Job {
  const Job({
    required this.id,
    required this.title,
    required this.customerId,
    required this.address,
    required this.assignee,
    this.assigneeId,
    required this.startsAt,
    required this.endsAt,
    this.status = JobStatus.scheduled,
    this.instructions = '',
    this.quoteId,
    this.revision = 1,
  });
  final String id;
  final String title;
  final String customerId;
  final String address;
  final String assignee;
  final String? assigneeId;
  final DateTime startsAt;
  final DateTime endsAt;
  final JobStatus status;
  final String instructions;
  final String? quoteId;
  final int revision;
  bool overlaps(Job other) {
    final sameAssignee = assigneeId != null && other.assigneeId != null
        ? assigneeId == other.assigneeId
        : assignee == other.assignee;
    return sameAssignee &&
        id != other.id &&
        startsAt.isBefore(other.endsAt) &&
        endsAt.isAfter(other.startsAt);
  }
  Job withStatus(JobStatus next) {
    final valid =
        (status == JobStatus.scheduled && next == JobStatus.inProgress) ||
        (status == JobStatus.inProgress && next == JobStatus.completed);
    if (!valid) throw StateError('Ogiltig ändring av jobbstatus.');
    return copyWith(status: next);
  }

  Job copyWith({JobStatus? status, String? instructions}) => Job(
    id: id,
    title: title,
    customerId: customerId,
    address: address,
    assignee: assignee,
    assigneeId: assigneeId,
    startsAt: startsAt,
    endsAt: endsAt,
    status: status ?? this.status,
    instructions: instructions ?? this.instructions,
    quoteId: quoteId,
    revision: revision + 1,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'customerId': customerId,
    'address': address,
    'assignee': assignee,
    if (assigneeId != null) 'assigneeId': assigneeId,
    'startsAt': startsAt.toIso8601String(),
    'endsAt': endsAt.toIso8601String(),
    'status': status.name,
    'instructions': instructions,
    'quoteId': quoteId,
    'revision': revision,
  };
  factory Job.fromJson(Map<String, dynamic> json) {
    final assigneeId = _optionalString(json, 'assigneeId') ??
        _optionalString(json, 'assignee_id');
    final assignee = _optionalString(json, 'assignee') ?? 'Ansvarig';
    final status = json['status'] as String?;
    return Job(
      id: json['id'] as String,
      title: json['title'] as String,
      customerId: (json['customerId'] ?? json['customer_id']) as String,
      address: _optionalString(json, 'address') ?? '',
      assignee: assignee,
      assigneeId: assigneeId,
      startsAt: DateTime.parse(
        (json['startsAt'] ?? json['starts_at']) as String,
      ),
      endsAt: DateTime.parse(
        (json['endsAt'] ?? json['ends_at']) as String,
      ),
      status: _parseStatus(status),
      instructions: _optionalString(json, 'instructions') ?? '',
      quoteId: _optionalString(json, 'quoteId') ??
          _optionalString(json, 'quote_id'),
      revision: json['revision'] as int? ?? json['version'] as int? ?? 1,
    );
  }

  static String? _optionalString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is! String) throw FormatException('$key must be a string.');
    return value;
  }

  static JobStatus _parseStatus(String? value) {
    return switch (value) {
      'in_progress' || 'inProgress' => JobStatus.inProgress,
      'scheduled' => JobStatus.scheduled,
      'completed' => JobStatus.completed,
      _ => throw FormatException('Invalid job status: $value'),
    };
  }
}
