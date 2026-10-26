import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:falt/data/local_store.dart';
import 'package:falt/domain/estimate.dart';
import 'package:falt/domain/job.dart';
import 'package:falt/domain/work_log.dart';

void main() {
  sqfliteFfiInit();
  late LocalStore store;
  final start = DateTime.utc(2026, 1, 10, 8);
  Future<Job> addJob({String id = 'j', String? quoteId}) async {
    final job = Job(
      id: id,
      title: 'Spotlights',
      customerId: 'c',
      address: 'Testgatan 1',
      assignee: 'Erik',
      startsAt: start,
      endsAt: start.add(const Duration(hours: 2)),
      quoteId: quoteId,
    );
    await store.saveJob(job);
    return job;
  }

  Future<Job> complete(Job job) async {
    final started = job.withStatus(JobStatus.inProgress);
    await store.saveJob(started);
    final done = started.withStatus(JobStatus.completed);
    await store.saveJob(done);
    return done;
  }

  TimeEntry entry({
    String id = 't',
    String jobId = 'j',
    bool approved = true,
    ChargeType charge = ChargeType.additional,
  }) => TimeEntry(
    id: id,
    jobId: jobId,
    person: 'Erik',
    startedAt: start,
    endedAt: start.add(const Duration(hours: 1)),
    hourlyRateOre: 65000,
    note: 'Montering',
    chargeType: charge,
    approved: approved,
  );
  setUp(() async {
    store = await LocalStore.open(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
  });
  tearDown(() async {
    await store.close();
  });
  test('timer survives a database close and restart', () async {
    final dir = await Directory.systemTemp.createTemp('falt-test-');
    final path = '${dir.path}/restart.db';
    var disk = await LocalStore.open(
      factory: databaseFactoryFfi,
      databasePath: path,
    );
    try {
      final job = Job(
        id: 'restart',
        title: 'Test',
        customerId: 'c',
        address: 'Test',
        assignee: 'Erik',
        startsAt: start,
        endsAt: start.add(const Duration(hours: 2)),
      );
      await disk.saveJob(job);
      await disk.saveJob(job.withStatus(JobStatus.inProgress));
      await disk.startTimer('restart', at: start);
      await disk.close();
      disk = await LocalStore.open(
        factory: databaseFactoryFfi,
        databasePath: path,
      );
      expect(
        (await disk.get('timer', 'active'))!['startedAt'],
        start.toIso8601String(),
      );
      await disk.stopTimer(
        expectedJobId: 'restart',
        note: 'Arbete',
        hourlyRateOre: 65000,
        chargeType: ChargeType.additional,
        approved: true,
        at: start.add(const Duration(minutes: 30)),
      );
      expect(await disk.get('timer', 'active'), isNull);
      expect(
        TimeEntry.fromJson(
          (await disk.forJob('time', 'restart')).single,
        ).minutes,
        30,
      );
    } finally {
      await disk.close();
      await dir.delete(recursive: true);
    }
  });
  test(
    'overlapping time write rolls back record and outbox together',
    () async {
      await addJob();
      await store.saveTime(entry());
      final before = await store.pendingCount;
      await expectLater(store.saveTime(entry(id: 'overlap')), throwsStateError);
      expect((await store.list('time')).length, 1);
      expect(await store.pendingCount, before);
    },
  );
  test(
    'failed timer stop preserves active timer and does not add time',
    () async {
      final job = await addJob();
      await store.saveJob(job.withStatus(JobStatus.inProgress));
      await store.startTimer('j', at: start);
      final before = await store.pendingCount;
      await expectLater(
        store.stopTimer(
          expectedJobId: 'j',
          note: 'Arbete',
          hourlyRateOre: 65000,
          chargeType: ChargeType.additional,
          approved: true,
          at: start.subtract(const Duration(minutes: 1)),
        ),
        throwsArgumentError,
      );
      expect(await store.get('timer', 'active'), isNotNull);
      expect(await store.list('time'), isEmpty);
      expect(await store.pendingCount, before);
    },
  );
  test('one timer across jobs and completion guard', () async {
    final job = await addJob();
    final started = job.withStatus(JobStatus.inProgress);
    await store.saveJob(started);
    await store.startTimer('j', at: start);
    await expectLater(store.startTimer('j', at: start), throwsStateError);
    await expectLater(
      store.saveJob(started.withStatus(JobStatus.completed)),
      throwsStateError,
    );
  });
  test('required checklist blocks completion', () async {
    final job = await addJob();
    await store.ensureWorkspace('j');
    final started = job.withStatus(JobStatus.inProgress);
    await store.saveJob(started);
    await expectLater(
      store.saveJob(started.withStatus(JobStatus.completed)),
      throwsStateError,
    );
    for (final c in await store.forJob('check', 'j')) {
      await store.addJobRecord('check', {...c, 'checked': true});
    }
    await store.saveJob(started.withStatus(JobStatus.completed));
    expect((await store.get('job', 'j'))!['status'], 'completed');
  });
  test(
    'pending extras block invoice; approval creates one immutable snapshot',
    () async {
      final job = await addJob();
      await store.saveTime(entry(approved: false));
      await complete(job);
      final before = await store.pendingCount;
      await expectLater(store.createJobInvoice('j'), throwsStateError);
      expect(await store.list('invoice'), isEmpty);
      expect(await store.pendingCount, before);
      await store.approveCharge('time', 't');
      final id = await store.createJobInvoice('j');
      final snapshot = await store.get('invoice', id);
      final writes = await store.pendingCount;
      expect(await store.createJobInvoice('j'), id);
      expect(await store.pendingCount, writes);
      expect(await store.get('invoice', id), snapshot);
      expect((await store.get('time', 't'))!['invoiceId'], id);
      final q = Quote.fromJson(
        Map<String, dynamic>.from(snapshot!['quoteSnapshot'] as Map),
      );
      expect(q.totals.netOre, 65000);
      await expectLater(store.saveTime(entry(id: 'late')), throwsStateError);
    },
  );
  test('fixed quote does not charge included actual work twice', () async {
    final quote = Quote(
      id: 'q',
      customerId: 'c',
      title: 'Test',
      status: QuoteStatus.accepted,
      lines: [
        EstimateLine(
          description: 'Fast pris',
          unitPriceOre: 100000,
          quantityMilli: 1000,
          kind: LineKind.labour,
        ),
      ],
    );
    await store.put('quote', quote.toJson());
    final job = await addJob(quoteId: 'q');
    await store.saveTime(entry(charge: ChargeType.included));
    await store.saveMaterial(
      MaterialEntry(
        id: 'm',
        jobId: 'j',
        description: 'Extra uttag',
        quantityMilli: 2000,
        purchasePriceOre: 10000,
        sellingPriceOre: 18500,
        chargeType: ChargeType.additional,
        approved: true,
      ),
    );
    await expectLater(store.createInvoice(quote), throwsStateError);
    await complete(job);
    final id = await store.createJobInvoice('j');
    final invoice = (await store.get('invoice', id))!;
    final snapshot = Quote.fromJson(
      Map<String, dynamic>.from(invoice['quoteSnapshot'] as Map),
    );
    expect(snapshot.lines.length, 2);
    expect(snapshot.totals.netOre, 137000);
    expect((await store.get('time', 't'))!['invoiceId'], isNull);
  });
  test('stale job save cannot overwrite a newer revision', () async {
    final job = await addJob();
    await store.saveJob(job.copyWith(instructions: 'Ny instruktion'));
    await expectLater(
      store.saveJob(job.copyWith(instructions: 'Gammal instruktion')),
      throwsStateError,
    );
    expect((await store.get('job', 'j'))!['instructions'], 'Ny instruktion');
  });
  test(
    'one job per quote prevents accidental partial invoice collisions',
    () async {
      await addJob(quoteId: 'q');
      await expectLater(addJob(id: 'second', quoteId: 'q'), throwsStateError);
    },
  );
}
