import 'package:flutter_test/flutter_test.dart';
import 'package:falt/domain/job.dart';

void main() {
  Job job(String id, int from, int to, {String person = 'Erik'}) => Job(
    id: id,
    title: 'Test',
    customerId: 'c',
    address: 'Test',
    assignee: person,
    startsAt: DateTime(2026, 10, 26, from),
    endsAt: DateTime(2026, 10, 26, to),
  );
  test('adjacent jobs allowed; same worker overlaps rejected', () {
    expect(job('a', 8, 10).overlaps(job('b', 10, 12)), false);
    expect(job('a', 8, 11).overlaps(job('b', 10, 12)), true);
    expect(job('a', 8, 11).overlaps(job('b', 10, 12, person: 'Nora')), false);
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
}
