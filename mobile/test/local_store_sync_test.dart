import 'dart:convert';
import 'dart:io';

import 'package:falt/data/local_store.dart';
import 'package:falt/domain/job.dart';
import 'package:falt/sync/sync_context.dart';
import 'package:falt/sync/sync_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const accountA = '11111111-1111-4111-8111-111111111111';
const accountB = '99999999-9999-4999-8999-999999999999';
const companyA = '22222222-2222-4222-8222-222222222222';
const companyB = '33333333-3333-4333-8333-333333333333';
const deviceA = '44444444-4444-4444-8444-444444444444';
const customerId = '55555555-5555-4555-8555-555555555555';
const jobId = '66666666-6666-4666-8666-666666666666';
const contextA = SyncContext(accountId: accountA, companyId: companyA, deviceId: deviceA);
const contextB = SyncContext(accountId: accountB, companyId: companyB, deviceId: deviceA);

SyncChange change({
  required int cursor,
  required SyncEntityKind kind,
  required String id,
  required int version,
  Map<String, dynamic>? payload,
  DateTime? deletedAt,
}) => SyncChange(
  cursor: cursor,
  entityKind: kind,
  entityId: id,
  version: version,
  deletedAtUtc: deletedAt,
  payload: payload,
  operationId: '77777777-7777-4777-8777-777777777777',
);

void main() {
  sqfliteFfiInit();
  late LocalStore store;
  late Directory testDir;
  late String databasePath;

  setUp(() async {
    testDir = await Directory.systemTemp.createTemp('falt-sync-test-');
    databasePath = '${testDir.path}/store.db';
    store = await LocalStore.open(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
      syncContext: contextA,
    );
  });
  tearDown(() async {
    await store.close();
    await testDir.delete(recursive: true);
  });

  test('local write and outbox carry the active account, company and device', () async {
    await store.put('customer', {'id': customerId, 'name': 'Anna'});
    final operation = (await store.pendingOperations()).single;
    expect(operation.companyId, companyA);
    expect(operation.deviceId, deviceA);
    expect(operation.entityKind, SyncEntityKind.customer);
    expect(operation.operationKind, SyncOperationKind.upsert);
    expect(operation.expectedVersion, 0);
    expect(operation.payload['name'], 'Anna');
    final db = await databaseFactoryFfi.openDatabase(databasePath,
      options: OpenDatabaseOptions(singleInstance: false));
    try {
      expect((await db.query('outbox')).single['account_id'], accountA);
    } finally {
      await db.close();
    }
  });

  test('live job records stay local-shaped while outbox uses SQL job fields', () async {
    await store.put('job', {
      'id': jobId,
      'title': 'Service visit',
      'customerId': customerId,
      'address': 'Main street 1',
      'assignee': 'Ansvarig',
      'startsAt': '2026-10-26T08:00:00.000Z',
      'endsAt': '2026-10-26T10:00:00.000Z',
      'status': 'inProgress',
      'instructions': 'Call first',
    });

    final local = await store.get('job', jobId);
    final operation = (await store.pendingOperations()).single;
    expect(local, containsPair('customerId', customerId));
    expect(local, containsPair('startsAt', '2026-10-26T08:00:00.000Z'));
    expect(local!.containsKey('customer_id'), isFalse);
    expect(operation.payload, {
      'customer_id': customerId,
      'title': 'Service visit',
      'assignee_id': accountA,
      'address': 'Main street 1',
      'instructions': 'Call first',
      'starts_at': '2026-10-26T08:00:00.000Z',
      'ends_at': '2026-10-26T10:00:00.000Z',
      'status': 'in_progress',
    });
  });

  test('live save assigns the authenticated account UUID to the local job', () async {
    await store.saveJob(Job(
      id: jobId,
      title: 'Service visit',
      customerId: customerId,
      address: 'Main street 1',
      assignee: 'Ansvarig',
      startsAt: DateTime.utc(2026, 10, 26, 8),
      endsAt: DateTime.utc(2026, 10, 26, 10),
    ));

    final local = await store.get('job', jobId);
    expect(local?['assigneeId'], accountA);
    expect((await store.pendingOperations()).single.payload['assignee_id'], accountA);
  });

  test('normalizes a pulled job version before a local status update', () async {
    await store.applyPullPage(SyncPullPage(changes: [
      change(
        cursor: 1,
        kind: SyncEntityKind.job,
        id: jobId,
        version: 5,
        payload: {
          'id': jobId,
          'title': 'Service visit',
          'customer_id': customerId,
          'assignee_id': accountA,
          'starts_at': '2026-10-26T08:00:00.000Z',
          'ends_at': '2026-10-26T10:00:00.000Z',
          'status': 'scheduled',
          'address': 'Main street 1',
          'instructions': 'Call first',
          'quote_id': 'quote-1',
          'version': 5,
        },
      ),
    ], nextCursor: 1));

    final pulled = await store.get('job', jobId);
    expect(pulled, containsPair('revision', 5));
    expect(pulled, containsPair('customerId', customerId));
    expect(pulled, containsPair('quoteId', 'quote-1'));

    final updated = Job.fromJson(pulled!).withStatus(JobStatus.inProgress);
    await store.saveJob(updated);
    final operation = (await store.pendingOperations()).single;
    expect(operation.expectedVersion, 5);
    expect(operation.payload['status'], 'in_progress');
    expect((await store.get('job', jobId))?['revision'], 6);
  });

  test('normalizes legacy camelCase job outbox payloads transactionally', () async {
    final db = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    try {
      await db.insert('outbox', {
        'id': '88888888-8888-4888-8888-888888888888',
        'account_id': accountA,
        'company_id': companyA,
        'device_id': deviceA,
        'kind': 'job',
        'entity_id': jobId,
        'payload': jsonEncode({
          'id': jobId,
          'title': 'Legacy visit',
          'customerId': customerId,
          'assignee': 'Ansvarig',
          'startsAt': '2026-10-26T08:00:00.000Z',
          'endsAt': '2026-10-26T10:00:00.000Z',
          'status': 'inProgress',
          'address': 'Main street 1',
          'instructions': 'Call first',
          'quoteId': 'quote-1',
        }),
        'created_at': '2026-10-26T10:00:00.000Z',
      });
    } finally {
      await db.close();
    }

    final operation = (await store.pendingOperations()).single;
    expect(operation.payload, {
      'customer_id': customerId,
      'title': 'Legacy visit',
      'assignee_id': accountA,
      'starts_at': '2026-10-26T08:00:00.000Z',
      'ends_at': '2026-10-26T10:00:00.000Z',
      'status': 'in_progress',
      'address': 'Main street 1',
      'instructions': 'Call first',
      'quote_id': 'quote-1',
    });
  });

  test('UUID context values are persisted on each outbox row', () async {
    final literal = await LocalStore.open(factory: databaseFactoryFfi,
      databasePath: databasePath,
      syncContext: SyncContext(accountId: accountB,
        companyId: companyB, deviceId: deviceA));
    await literal.put('customer', {'id': customerId, 'name': 'Anna'});
    await literal.put('job', {'id': jobId, 'title': 'Visit'});
    final db = await databaseFactoryFfi.openDatabase(databasePath,
      options: OpenDatabaseOptions(singleInstance: false));
    try {
      final rows = await db.query('outbox',
        where: 'company_id = ?', whereArgs: [companyB]);
      expect(rows, hasLength(2));
      for (final row in rows) {
        expect(row['account_id'], accountB);
        expect(row['company_id'], companyB);
        expect(row['device_id'], deviceA);
      }
    } finally {
      await db.close();
    }
  });

  test('pending operations are ordered, due, limited and omit acknowledged rows', () async {
    await store.put('customer', {'id': customerId, 'name': 'First'});
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await store.put('job', {'id': jobId, 'title': 'Second'});
    final first = (await store.pendingOperations()).first;
    expect((await store.pendingOperations(limit: 1)).single.operationId, first.operationId);
    await store.scheduleRetry(first.operationId,
      nextAttemptAtUtc: DateTime.now().toUtc().add(const Duration(days: 1)), error: 'offline');
    expect((await store.pendingOperations()).map((o) => o.entityId), [jobId]);
    await store.acknowledgeOperation((await store.pendingOperations()).single.operationId,
      acceptedVersion: 1);
    expect(await store.pendingOperations(), isEmpty);
    expect(await store.pendingCount, 1);
  });

  test('acknowledgement deletes only the selected operation', () async {
    await store.put('customer', {'id': customerId, 'name': 'First'});
    await store.put('job', {'id': jobId, 'title': 'Second'});
    final operations = await store.pendingOperations();
    await store.acknowledgeOperation(operations.first.operationId, acceptedVersion: 1);
    expect((await store.pendingOperations()).single.operationId, operations.last.operationId);
  });

  test('acknowledgement advances the record version for the next write', () async {
    await store.applyPullPage(SyncPullPage(changes: [
      change(cursor: 1, kind: SyncEntityKind.customer, id: customerId,
        version: 4, payload: {'id': customerId, 'name': 'Server'}),
    ], nextCursor: 1));
    await store.put('customer', {'id': customerId, 'name': 'Local one'});
    final first = (await store.pendingOperations()).single;
    expect(first.expectedVersion, 4);
    await store.acknowledgeOperation(first.operationId, acceptedVersion: 5);
    expect(await store.pendingOperations(), isEmpty);
    expect((await store.get('customer', customerId))?['name'], 'Local one');
    await store.close();
    store = await LocalStore.open(factory: databaseFactoryFfi,
      databasePath: databasePath, syncContext: contextA);
    await store.put('customer', {'id': customerId, 'name': 'Local two'});
    expect((await store.pendingOperations()).single.expectedVersion, 5);
  });

  test('acknowledgement rebases later writes to the same entity', () async {
    await store.put('customer', {'id': customerId, 'name': 'First'});
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await store.put('customer', {'id': customerId, 'name': 'Second'});
    final operations = await store.pendingOperations();
    await store.acknowledgeOperation(operations.first.operationId,
      acceptedVersion: 1);
    final second = (await store.pendingOperations()).single;
    expect(second.operationId, operations.last.operationId);
    expect(second.expectedVersion, 1);
    expect((await store.get('customer', customerId))?['name'], 'Second');
    await store.acknowledgeOperation(second.operationId, acceptedVersion: 2);
    await store.put('customer', {'id': customerId, 'name': 'Third'});
    expect((await store.pendingOperations()).single.expectedVersion, 2);
  });

  test('rejects invalid authenticated context at the LocalStore boundary', () async {
    const invalidAccount = SyncContext(accountId: 'account-a',
      companyId: companyA, deviceId: deviceA);
    const invalidCompany = SyncContext(accountId: accountA,
      companyId: 'company-a', deviceId: deviceA);
    const invalidDevice = SyncContext(accountId: accountA,
      companyId: companyA, deviceId: 'device-a');
    await expectLater(LocalStore.open(factory: databaseFactoryFfi,
      databasePath: databasePath, syncContext: invalidAccount), throwsArgumentError);
    await expectLater(LocalStore.open(factory: databaseFactoryFfi,
      databasePath: databasePath, syncContext: invalidCompany), throwsArgumentError);
    await expectLater(LocalStore.open(factory: databaseFactoryFfi,
      databasePath: databasePath, syncContext: invalidDevice), throwsArgumentError);
    await expectLater(store.put('customer', {'id': 'customer-a', 'name': 'Bad'}),
      throwsArgumentError);
    await expectLater(store.acknowledgeOperation('operation-a', acceptedVersion: 1),
      throwsArgumentError);
    await expectLater(store.scheduleRetry('operation-a',
      nextAttemptAtUtc: DateTime.utc(2026, 10, 26), error: 'bad'),
      throwsArgumentError);
    expect(await store.pendingCount, 0);
  });

  test('local changes use the pulled server version and a deletion kind', () async {
    await store.applyPullPage(SyncPullPage(changes: [
      change(cursor: 1, kind: SyncEntityKind.customer, id: customerId,
        version: 7, payload: {'id': customerId, 'name': 'Server'}),
    ], nextCursor: 1));
    await store.put('customer', {'id': customerId, 'deleted': true});
    final operation = (await store.pendingOperations()).single;
    expect(operation.expectedVersion, 7);
    expect(operation.operationKind, SyncOperationKind.delete);
    expect(await store.get('customer', customerId), isNull);
  });

  test('retry persists attempts and error and becomes due at requested time', () async {
    await store.put('customer', {'id': customerId, 'name': 'Anna'});
    final id = (await store.pendingOperations()).single.operationId;
    final later = DateTime.now().toUtc().add(const Duration(days: 1));
    await store.scheduleRetry(id, nextAttemptAtUtc: later, error: 'timeout');
    expect(await store.pendingOperations(), isEmpty);
    final due = DateTime.now().toUtc().subtract(const Duration(seconds: 1));
    await store.scheduleRetry(id, nextAttemptAtUtc: due, error: 'timeout again');
    final operation = (await store.pendingOperations()).single;
    expect(operation.attemptCount, 2);
    expect(operation.lastError, 'timeout again');
    expect(operation.status, SyncOperationStatus.retry);
    expect(operation.nextAttemptAtUtc, due);
  });

  test('pull applies customer and job with cursor, and rolls back invalid page', () async {
    await store.applyPullPage(SyncPullPage(changes: [
      change(cursor: 1, kind: SyncEntityKind.customer, id: customerId,
        version: 1, payload: {'id': customerId, 'name': 'Anna'}),
      change(cursor: 2, kind: SyncEntityKind.job, id: jobId,
        version: 1, payload: {'id': jobId, 'title': 'Visit'}),
    ], nextCursor: 2));
    expect((await store.get('customer', customerId))?['name'], 'Anna');
    expect((await store.get('job', jobId))?['title'], 'Visit');
    expect(await store.syncCursor(), 2);
    await expectLater(store.applyPullPage(SyncPullPage(changes: [
      change(cursor: 3, kind: SyncEntityKind.customer, id: customerId,
        version: 2, payload: {'id': customerId, 'name': 'Changed'}),
      change(cursor: 4, kind: SyncEntityKind.job, id: jobId,
        version: 2, payload: {'id': customerId, 'title': 'Wrong ID'}),
    ], nextCursor: 4)), throwsArgumentError);
    expect((await store.get('customer', customerId))?['name'], 'Anna');
    expect(await store.syncCursor(), 2);
    await expectLater(store.applyPullPage(SyncPullPage(changes: const [], nextCursor: 2)), throwsStateError);
  });

  test('pull keeps an unsent local edit and records newer remote state', () async {
    await store.put('customer', {'id': customerId, 'name': 'Local'});
    final pending = (await store.pendingOperations()).single;
    await store.applyPullPage(SyncPullPage(changes: [
      change(cursor: 1, kind: SyncEntityKind.customer, id: customerId,
        version: 1, payload: {'id': customerId, 'name': 'Remote'}),
    ], nextCursor: 1));
    expect((await store.get('customer', customerId))?['name'], 'Local');
    expect((await store.pendingOperations()).single.operationId, pending.operationId);
    expect(await store.syncCursor(), 1);
    await store.applyPullPage(SyncPullPage(changes: [
      change(cursor: 2, kind: SyncEntityKind.customer, id: customerId,
        version: 2, deletedAt: DateTime.utc(2026, 10, 26)),
    ], nextCursor: 2));
    expect((await store.get('customer', customerId))?['name'], 'Local');
    await store.close();
    store = await LocalStore.open(factory: databaseFactoryFfi,
      databasePath: databasePath, syncContext: contextA);
    expect((await store.get('customer', customerId))?['name'], 'Local');
    expect((await store.pendingOperations()).single.operationId, pending.operationId);
    expect(await store.syncCursor(), 2);
    final db = await databaseFactoryFfi.openDatabase(databasePath,
      options: OpenDatabaseOptions(singleInstance: false));
    try {
      final conflict = (await db.query('sync_conflicts')).single;
      expect(conflict['operation_id'], pending.operationId);
      expect(conflict['server_version'], 2);
      expect(conflict['server_payload'], isNull);
      expect((await db.query('outbox')).single['status'], 'pending');
    } finally {
      await db.close();
    }
  });

  test('pull keeps an unsent local deletion and records remote payload', () async {
    await store.put('customer', {'id': customerId, 'deleted': true});
    final pending = (await store.pendingOperations()).single;
    await store.applyPullPage(SyncPullPage(changes: [
      change(cursor: 1, kind: SyncEntityKind.customer, id: customerId,
        version: 2, payload: {'id': customerId, 'name': 'Remote'}),
    ], nextCursor: 1));
    expect(await store.get('customer', customerId), isNull);
    expect((await store.pendingOperations()).single.operationId, pending.operationId);
    final db = await databaseFactoryFfi.openDatabase(databasePath,
      options: OpenDatabaseOptions(singleInstance: false));
    try {
      final conflict = (await db.query('sync_conflicts')).single;
      expect(conflict['server_version'], 2);
      expect(conflict['server_payload'], contains('Remote'));
      expect((await db.query('records')).single['deleted_at'], isNotNull);
    } finally {
      await db.close();
    }
  });

  test('tombstone hides a record and blocks an older version on a later page', () async {
    await store.applyPullPage(SyncPullPage(changes: [
      change(cursor: 1, kind: SyncEntityKind.customer, id: customerId,
        version: 3, payload: {'id': customerId, 'name': 'Anna'}),
    ], nextCursor: 1));
    await store.applyPullPage(SyncPullPage(changes: [
      change(cursor: 2, kind: SyncEntityKind.customer, id: customerId,
        version: 4, deletedAt: DateTime.utc(2026, 10, 26)),
    ], nextCursor: 2));
    expect(await store.get('customer', customerId), isNull);
    expect(await store.list('customer'), isEmpty);
    await store.applyPullPage(SyncPullPage(changes: [
      change(cursor: 3, kind: SyncEntityKind.customer, id: customerId,
        version: 3, payload: {'id': customerId, 'name': 'Old'}),
    ], nextCursor: 3));
    expect(await store.get('customer', customerId), isNull);
    final db = await databaseFactoryFfi.openDatabase(databasePath,
      options: OpenDatabaseOptions(singleInstance: false));
    try {
      expect((await db.query('records', columns: ['server_version', 'deleted_at'])).single,
        containsPair('server_version', 4));
    } finally {
      await db.close();
    }
  });

  test('different context cannot see or mutate records, operations or cursor', () async {
    await store.put('customer', {'id': customerId, 'name': 'Private'});
    final operation = (await store.pendingOperations()).single;
    await store.applyPullPage(SyncPullPage(changes: const [], nextCursor: 1));
    final other = await LocalStore.open(factory: databaseFactoryFfi,
      databasePath: databasePath, syncContext: contextB);
    expect(await other.list('customer'), isEmpty);
    expect(await other.get('customer', customerId), isNull);
    expect(await other.pendingOperations(), isEmpty);
    expect(await other.syncCursor(), 0);
    await other.acknowledgeOperation(operation.operationId, acceptedVersion: 1);
    await other.scheduleRetry(operation.operationId,
      nextAttemptAtUtc: DateTime.now().toUtc(), error: 'wrong account');
    await expectLater(other.recordConflict(SyncConflict(operation: operation,
      serverVersion: 1, serverPayload: null,
      detectedAtUtc: DateTime.utc(2026, 10, 26))), throwsStateError);
    expect((await store.pendingOperations()).single.attemptCount, 0);
    await other.put('customer', {'id': customerId, 'name': 'Other'});
    expect((await store.get('customer', customerId))?['name'], 'Private');
    expect((await other.get('customer', customerId))?['name'], 'Other');
  });

  for (final isolationCase in [
    ('account only', SyncContext(accountId: accountB,
      companyId: companyA, deviceId: deviceA)),
    ('company only', SyncContext(accountId: accountA,
      companyId: companyB, deviceId: deviceA)),
  ]) {
    test('${isolationCase.$1} change keeps records, outbox and cursor isolated', () async {
      await store.put('customer', {'id': customerId, 'name': 'Owner'});
      final ownerOperation = (await store.pendingOperations()).single;
      await store.applyPullPage(SyncPullPage(changes: const [], nextCursor: 3));
      final other = await LocalStore.open(factory: databaseFactoryFfi,
        databasePath: databasePath, syncContext: isolationCase.$2);
      expect(await other.get('customer', customerId), isNull);
      expect(await other.list('customer'), isEmpty);
      expect(await other.pendingOperations(), isEmpty);
      expect(await other.syncCursor(), 0);
      await other.acknowledgeOperation(ownerOperation.operationId,
        acceptedVersion: 1);
      await other.scheduleRetry(ownerOperation.operationId,
        nextAttemptAtUtc: DateTime.now().toUtc(), error: 'foreign');
      await other.put('customer', {'id': customerId, 'name': 'Other'});
      await other.applyPullPage(SyncPullPage(changes: const [], nextCursor: 4));
      expect((await store.get('customer', customerId))?['name'], 'Owner');
      expect((await store.pendingOperations()).single.operationId,
        ownerOperation.operationId);
      expect(await store.syncCursor(), 3);
      expect((await other.get('customer', customerId))?['name'], 'Other');
      expect(await other.syncCursor(), 4);
    });
  }

  test('records, pending operations, conflicts and cursor survive restart', () async {
    final dir = await Directory.systemTemp.createTemp('falt-sync-');
    final file = '${dir.path}/store.db';
    var disk = await LocalStore.open(factory: databaseFactoryFfi,
      databasePath: file, syncContext: contextA);
    try {
      await disk.put('customer', {'id': customerId, 'name': 'Anna'});
      final operation = (await disk.pendingOperations()).single;
      await disk.recordConflict(SyncConflict(operation: operation, serverVersion: 2,
        serverPayload: {'id': customerId, 'name': 'Server'}, detectedAtUtc: DateTime.utc(2026, 10, 26)));
      await disk.put('job', {'id': jobId, 'title': 'Pending'});
      final pending = (await disk.pendingOperations()).single;
      expect(pending.entityId, jobId);
      await disk.scheduleRetry(pending.operationId,
        nextAttemptAtUtc: DateTime.utc(2026, 1, 1), error: 'network');
      await disk.applyPullPage(SyncPullPage(changes: const [], nextCursor: 5));
      await disk.close();
      disk = await LocalStore.open(factory: databaseFactoryFfi,
        databasePath: file, syncContext: contextA);
      expect((await disk.get('customer', customerId))?['name'], 'Anna');
      final resumed = (await disk.pendingOperations()).single;
      expect(resumed.operationId, pending.operationId);
      expect(resumed.attemptCount, 1);
      expect(resumed.lastError, 'network');
      expect(await disk.syncCursor(), 5);
      final db = await databaseFactoryFfi.openDatabase(file,
        options: OpenDatabaseOptions(singleInstance: false));
      try {
        final conflict = (await db.query('sync_conflicts')).single;
        expect(conflict['operation_id'], operation.operationId);
        expect(conflict['server_version'], 2);
        expect(conflict['server_payload'], contains('Server'));
        expect(conflict['detected_at'], DateTime.utc(2026, 10, 26).toIso8601String());
      } finally {
        await db.close();
      }
    } finally {
      await disk.close();
      await dir.delete(recursive: true);
    }
  });

  test('v1 evaluation rows migrate into demo without becoming sync operations', () async {
    final dir = await Directory.systemTemp.createTemp('falt-v1-');
    final file = '${dir.path}/store.db';
    final legacy = await databaseFactoryFfi.openDatabase(file,
      options: OpenDatabaseOptions(version: 1, onCreate: (db, version) async {
        await db.execute('CREATE TABLE records (kind TEXT NOT NULL, id TEXT NOT NULL, payload TEXT NOT NULL, PRIMARY KEY(kind,id))');
        await db.execute('CREATE TABLE outbox (id TEXT PRIMARY KEY, kind TEXT NOT NULL, entity_id TEXT NOT NULL, payload TEXT NOT NULL, created_at TEXT NOT NULL)');
        await db.execute('CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
      }));
    try {
      await legacy.insert('records', {'kind': 'customer', 'id': customerId,
        'payload': '{"id":"$customerId","name":"Legacy"}'});
      await legacy.insert('outbox', {'id': '88888888-8888-4888-8888-888888888888',
        'kind': 'customer', 'entity_id': customerId,
        'payload': '{"id":"$customerId","name":"Legacy"}',
        'created_at': '2026-10-26T10:00:00.000Z'});
      await legacy.insert('meta', {'key': 'seeded', 'value': 'true'});
    } finally {
      await legacy.close();
    }
    final demo = await LocalStore.open(factory: databaseFactoryFfi, databasePath: file);
    final authenticated = await LocalStore.open(factory: databaseFactoryFfi,
      databasePath: file, syncContext: contextA);
    try {
      expect((await demo.get('customer', customerId))?['name'], 'Legacy');
      expect(await demo.pendingCount, 1);
      await demo.seedDemo();
      expect(await demo.pendingCount, 1);
      expect(await authenticated.get('customer', customerId), isNull);
      expect(await authenticated.pendingOperations(), isEmpty);
      await expectLater(demo.pendingOperations(), throwsStateError);
      await expectLater(demo.syncCursor(), throwsStateError);
      await expectLater(demo.applyPullPage(SyncPullPage(changes: const [],
        nextCursor: 1)), throwsStateError);
    } finally {
      await demo.close();
      await dir.delete(recursive: true);
    }
  });

  test('v2 SQL-shaped job rows normalize to local fields during upgrade', () async {
    final dir = await Directory.systemTemp.createTemp('falt-v2-');
    final file = '${dir.path}/store.db';
    final legacy = await databaseFactoryFfi.openDatabase(file,
      options: OpenDatabaseOptions(version: 2, onCreate: (db, version) async {
        await db.execute('CREATE TABLE records (account_id TEXT NOT NULL, company_id TEXT NOT NULL, kind TEXT NOT NULL, id TEXT NOT NULL, payload TEXT NOT NULL, server_version INTEGER NOT NULL DEFAULT 0, deleted_at TEXT, PRIMARY KEY(account_id, company_id, kind, id))');
        await db.execute("CREATE TABLE outbox (id TEXT PRIMARY KEY, account_id TEXT NOT NULL, company_id TEXT NOT NULL, device_id TEXT NOT NULL, kind TEXT NOT NULL, entity_id TEXT NOT NULL, payload TEXT NOT NULL, created_at TEXT NOT NULL, expected_version INTEGER NOT NULL DEFAULT 0, operation_kind TEXT NOT NULL DEFAULT 'upsert', status TEXT NOT NULL DEFAULT 'pending', attempt_count INTEGER NOT NULL DEFAULT 0, next_attempt_at TEXT, last_error TEXT)");
        await db.execute('CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
        await db.execute('CREATE TABLE sync_conflicts (account_id TEXT NOT NULL, company_id TEXT NOT NULL, operation_id TEXT NOT NULL, server_version INTEGER NOT NULL, server_payload TEXT, detected_at TEXT NOT NULL, PRIMARY KEY(account_id, company_id, operation_id))');
        await db.execute('CREATE TABLE sync_cursors (account_id TEXT NOT NULL, company_id TEXT NOT NULL, cursor INTEGER NOT NULL, PRIMARY KEY(account_id, company_id))');
      }));
    try {
      await legacy.insert('records', {
        'account_id': accountA,
        'company_id': companyA,
        'kind': 'job',
        'id': jobId,
        'payload': jsonEncode({
          'id': jobId,
          'title': 'Historical visit',
          'customer_id': customerId,
          'assignee_id': accountA,
          'starts_at': '2026-10-26T08:00:00.000Z',
          'ends_at': '2026-10-26T10:00:00.000Z',
          'status': 'scheduled',
          'version': 5,
        }),
        'server_version': 5,
      });
    } finally {
      await legacy.close();
    }

    final upgraded = await LocalStore.open(
      factory: databaseFactoryFfi,
      databasePath: file,
      syncContext: contextA,
    );
    try {
      final local = await upgraded.get('job', jobId);
      expect(local?['customerId'], customerId);
      expect(local?['assigneeId'], accountA);
      expect(local?['revision'], 5);
      expect(local?.containsKey('customer_id'), isFalse);
    } finally {
      await upgraded.close();
      await dir.delete(recursive: true);
    }
  });
}
