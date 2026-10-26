import 'package:flutter_test/flutter_test.dart';
import 'package:falt/domain/job.dart';

void main() {
  Job job(String id, int from, int to, {
    String person = 'Erik',
    String? personId,
  }) => Job(
    id: id,
    title: 'Test',
    customerId: 'c',
    address: 'Test',
    assignee: person,
    assigneeId: personId,
    startsAt: DateTime(2026, 10, 26, from),
    endsAt: DateTime(2026, 10, 26, to),
  );
  test('adjacent jobs allowed; same worker overlaps rejected', () {
    expect(job('a', 8, 10).overlaps(job('b', 10, 12)), false);
    expect(job('a', 8, 11).overlaps(job('b', 10, 12)), true);
    expect(job('a', 8, 11).overlaps(job('b', 10, 12, person: 'Nora')), false);
  });

  test('job overlap prefers matching assignee IDs over display names', () {
    expect(
      job('a', 8, 11, person: 'Erik', personId: 'worker-a').overlaps(
        job('b', 10, 12, person: 'Nora', personId: 'worker-b'),
      ),
      false,
    );
    expect(
      job('a', 8, 11, person: 'Erik', personId: 'worker-a').overlaps(
        job('b', 10, 12, person: 'Nora', personId: 'worker-a'),
      ),
      true,
    );
    expect(
      job('a', 8, 11, person: 'Erik').overlaps(
        job('b', 10, 12, person: 'Erik'),
      ),
      true,
    );
  });
  test('job must start before completion', () {
    final scheduled = job('a', 8, 10);
    expect(() => scheduled.withStatus(JobStatus.completed), throwsStateError);
    final completed = scheduled
        .withStatus(JobStatus.inProgress)
        .withStatus(JobStatus.completed);
    expect(Job.fromJson(completed.toJson()).status, JobStatus.completed);
    expect(() => completed.withStatus(JobStatus.inProgress), throwsStateError);
  });

  test('parses the SQL job shape and keeps optional local fields safe', () {
    final job = Job.fromJson({
      'id': 'job-1',
      'title': 'Service visit',
      'customer_id': 'customer-1',
      'assignee_id': '11111111-1111-4111-8111-111111111111',
      'starts_at': '2026-10-26T08:00:00Z',
      'ends_at': '2026-10-26T10:00:00Z',
      'status': 'in_progress',
    });

    expect(job.customerId, 'customer-1');
    expect(job.assigneeId, '11111111-1111-4111-8111-111111111111');
    expect(job.assignee, 'Ansvarig');
    expect(job.address, isEmpty);
    expect(job.instructions, isEmpty);
    expect(job.status, JobStatus.inProgress);
  });

  test('preserves an assignee UUID in local camelCase JSON', () {
    final original = Job(
      id: 'job-1',
      title: 'Service visit',
      customerId: 'customer-1',
      address: '',
      assignee: 'Ansvarig',
      assigneeId: '11111111-1111-4111-8111-111111111111',
      startsAt: DateTime.utc(2026, 10, 26, 8),
      endsAt: DateTime.utc(2026, 10, 26, 10),
    );

    final json = original.toJson();
    expect(json['customerId'], 'customer-1');
    expect(json['assigneeId'], original.assigneeId);
    expect(json.containsKey('customer_id'), isFalse);
    expect(Job.fromJson(json).assigneeId, original.assigneeId);
  });
}
