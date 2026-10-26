enum JobStatus { scheduled, inProgress, completed }

class Job {
  const Job({
    required this.id,
    required this.title,
    required this.customerId,
    required this.address,
    required this.assignee,
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
  final DateTime startsAt;
  final DateTime endsAt;
  final JobStatus status;
  final String instructions;
  final String? quoteId;
  final int revision;
  bool overlaps(Job other) =>
      assignee == other.assignee &&
      id != other.id &&
      startsAt.isBefore(other.endsAt) &&
      endsAt.isAfter(other.startsAt);
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
    'startsAt': startsAt.toIso8601String(),
    'endsAt': endsAt.toIso8601String(),
    'status': status.name,
    'instructions': instructions,
    'quoteId': quoteId,
    'revision': revision,
  };
  factory Job.fromJson(Map<String, dynamic> json) => Job(
    id: json['id'] as String,
    title: json['title'] as String,
    customerId: json['customerId'] as String,
    address: json['address'] as String,
    assignee: json['assignee'] as String,
    startsAt: DateTime.parse(json['startsAt'] as String),
    endsAt: DateTime.parse(json['endsAt'] as String),
    status: JobStatus.values.byName(json['status'] as String),
    instructions: json['instructions'] as String? ?? '',
    quoteId: json['quoteId'] as String?,
    revision: json['revision'] as int? ?? 1,
  );
}
