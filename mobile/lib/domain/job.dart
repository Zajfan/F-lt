enum JobStatus { scheduled, inProgress, completed }

class Job {
  const Job({required this.id, required this.title, required this.customerId,
    required this.address, required this.assignee, required this.startsAt,
    required this.endsAt, this.status = JobStatus.scheduled});
  final String id;
  final String title;
  final String customerId;
  final String address;
  final String assignee;
  final DateTime startsAt;
  final DateTime endsAt;
  final JobStatus status;
  bool overlaps(Job other) => assignee == other.assignee && id != other.id &&
    startsAt.isBefore(other.endsAt) && endsAt.isAfter(other.startsAt);
  Job withStatus(JobStatus next) {
    final valid = (status == JobStatus.scheduled && next == JobStatus.inProgress) ||
      (status == JobStatus.inProgress && next == JobStatus.completed);
    if (!valid) throw StateError('Invalid job transition');
    return Job(id: id, title: title, customerId: customerId, address: address,
      assignee: assignee, startsAt: startsAt, endsAt: endsAt, status: next);
  }
  Map<String, Object> toJson() => {'id': id, 'title': title,
    'customerId': customerId, 'address': address, 'assignee': assignee,
    'startsAt': startsAt.toIso8601String(), 'endsAt': endsAt.toIso8601String(),
    'status': status.name};
  factory Job.fromJson(Map<String, dynamic> json) => Job(
    id: json['id'] as String, title: json['title'] as String,
    customerId: json['customerId'] as String, address: json['address'] as String,
    assignee: json['assignee'] as String,
    startsAt: DateTime.parse(json['startsAt'] as String),
    endsAt: DateTime.parse(json['endsAt'] as String),
    status: JobStatus.values.byName(json['status'] as String));
}
