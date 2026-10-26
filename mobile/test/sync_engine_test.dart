import 'dart:convert';
import 'dart:io';

import 'package:falt/data/local_store.dart';
import 'package:falt/sync/sync_context.dart';
import 'package:falt/sync/sync_engine.dart';
import 'package:falt/sync/sync_models.dart';
import 'package:falt/sync/sync_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const accountId = '11111111-1111-4111-8111-111111111111';
const companyId = '22222222-2222-4222-8222-222222222222';
const deviceId = '33333333-3333-4333-8333-333333333333';
const customerId = '55555555-5555-4555-8555-555555555555';
const jobId = '66666666-6666-4666-8666-666666666666';
const changeOperationId = '77777777-7777-4777-8777-777777777777';

const syncContext = SyncContext(
  accountId: accountId,
  companyId: companyId,
  deviceId: deviceId,
);

SyncPushResult pushResult(
  SyncPushStatus status, {
  int? version,
  Map<String, dynamic>? current,
}) => SyncPushResult(
  status: status,
  version: version,
  cursor: null,
  deletedAtUtc: null,
  current: current,
);

SyncChange pulledChange({
  required int cursor,
  required String entityId,
  SyncEntityKind entityKind = SyncEntityKind.customer,
  int version = 1,
  Map<String, dynamic>? payload,
}) => SyncChange(
  cursor: cursor,
  entityKind: entityKind,
  entityId: entityId,
  version: version,
  deletedAtUtc: null,
  payload: payload ?? {'id': entityId, 'name': 'Remote'},
  operationId: changeOperationId,
);

class FakeTransport implements SyncTransport {
  final pushed = <SyncOperation>[];
  final pullCursors = <int>[];
  final pullLimits = <int>[];
  Future<SyncPushResult> Function(SyncOperation operation)? onPush;
  Future<SyncPullPage> Function(int afterCursor, int limit)? onPull;

  @override
  Future<SyncPushResult> push(SyncOperation operation) async {
    pushed.add(operation);
    return onPush?.call(operation) ??
        pushResult(SyncPushStatus.accepted, version: 1);
  }

  @override
  Future<SyncPullPage> pull({required int afterCursor, int limit = 100}) async {
    pullCursors.add(afterCursor);
    pullLimits.add(limit);
    return onPull?.call(afterCursor, limit) ??
        SyncPullPage(changes: const [], nextCursor: afterCursor);
  }
}

void main() {
  sqfliteFfiInit();
  late LocalStore store;
  late Directory testDirectory;
  late String databasePath;

  setUp(() async {
    testDirectory = await Directory.systemTemp.createTemp('falt-engine-test-');
    databasePath = '${testDirectory.path}/store.db';
    store = await LocalStore.open(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
      syncContext: syncContext,
    );
  });

  tearDown(() async {
    await store.close();
    await testDirectory.delete(recursive: true);
  });

  test('acknowledges accepted and duplicate operations with server versions', () async {
    await store.put('customer', {'id': customerId, 'name': 'Anna'});
    await store.put('job', {'id': jobId, 'title': 'Visit'});
    final transport = FakeTransport();
    transport.onPush = (operation) async => pushResult(
          operation.entityKind == SyncEntityKind.customer
              ? SyncPushStatus.accepted
              : SyncPushStatus.duplicate,
          version: 1,
        );

    final result = await SyncEngine(store: store, transport: transport).runOnce();

    expect(result.pushed, 2);
    expect(result.pushedCount, 2);
    expect(await store.pendingOperations(), isEmpty);
    expect(transport.pullLimits, [100]);
  });

  test('refreshes later same-entity operations after acknowledgement rebases them', () async {
    await store.put('customer', {'id': customerId, 'name': 'First'});
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await store.put('customer', {'id': customerId, 'name': 'Second'});
    final expectedVersions = <int>[];
    final transport = FakeTransport()
      ..onPush = (operation) async {
        expectedVersions.add(operation.expectedVersion);
        return pushResult(
          SyncPushStatus.accepted,
          version: expectedVersions.length,
        );
      };

    await SyncEngine(store: store, transport: transport).runOnce();

    expect(expectedVersions, [0, 1]);
    expect(await store.pendingOperations(), isEmpty);
  });

  test('missing accepted or duplicate version preserves operations and reports protocol failures', () async {
    await store.put('customer', {'id': customerId, 'name': 'Anna'});
    await store.put('job', {'id': jobId, 'title': 'Visit'});
    final transport = FakeTransport()
      ..onPush = (operation) async => pushResult(
            operation.entityKind == SyncEntityKind.customer
                ? SyncPushStatus.accepted
                : SyncPushStatus.duplicate,
          );

    final result = await SyncEngine(store: store, transport: transport).runOnce();

    expect(result.protocolErrorCount, 2);
    expect(result.errors, everyElement(isA<SyncProtocolException>()));
    expect((await store.pendingOperations()).map((operation) => operation.entityId),
        [customerId, jobId]);
  });

  test('transient failure schedules bounded retry and does not advance the cursor', () async {
    await store.put('customer', {'id': customerId, 'name': 'Anna'});
    final transport = FakeTransport()
      ..onPush = (_) async => throw const SyncTransientException('timeout');

    final result = await SyncEngine(store: store, transport: transport).runOnce();

    expect(result.retryCount, 1);
    expect(result.finalCursor, 0);
    expect(transport.pullCursors, isEmpty);
    expect(await store.syncCursor(), 0);
    expect(await store.pendingOperations(), isEmpty);
    final db = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    try {
      final nextAttempt = DateTime.parse(
        (await db.query('outbox')).single['next_attempt_at'] as String,
      );
      final now = DateTime.now().toUtc();
      expect(nextAttempt.isAfter(now.add(const Duration(seconds: 4))), isTrue);
      expect(nextAttempt.isBefore(now.add(const Duration(seconds: 6))), isTrue);
    } finally {
      await db.close();
    }
  });

  test('transient pull failures remain retryable for background scheduling', () async {
    final transport = FakeTransport()
      ..onPull = (_, _) async => throw const SyncTransientException('offline');

    final result = await SyncEngine(store: store, transport: transport).runOnce();

    expect(result.errors.single, isA<SyncTransientException>());
    expect(result.errors.single.isRetryable, isTrue);
  });

  test('validation and authorization failures are ineligible without retry scheduling', () async {
    await store.put('customer', {'id': customerId, 'name': 'Anna'});
    final transport = FakeTransport()
      ..onPush = (_) async => throw const SyncValidationException('invalid payload');

    final result = await SyncEngine(store: store, transport: transport).runOnce();

    expect(result.retryCount, 0);
    expect(result.failedCount, 1);
    expect(result.errors.single, isA<SyncValidationException>());
    expect(await store.pendingOperations(), isEmpty);
    expect(await store.pendingCount, 1);
  });

  test('authorization failures are ineligible without retry scheduling', () async {
    await store.put('customer', {'id': customerId, 'name': 'Anna'});
    final transport = FakeTransport()
      ..onPush = (_) async =>
          throw const SyncAuthorizationException('not allowed');

    final result = await SyncEngine(store: store, transport: transport).runOnce();

    expect(result.retryCount, 0);
    expect(result.failedCount, 1);
    expect(result.errors.single, isA<SyncAuthorizationException>());
    expect(await store.pendingOperations(), isEmpty);
    expect(await store.pendingCount, 1);
  });

  test('stops retrying after five scheduled attempts', () async {
    await store.put('customer', {'id': customerId, 'name': 'Anna'});
    final operationId = (await store.pendingOperations()).single.operationId;
    for (var attempt = 0; attempt < 5; attempt++) {
      await store.scheduleRetry(
        operationId,
        nextAttemptAtUtc: DateTime.now().toUtc().subtract(const Duration(seconds: 1)),
        error: 'timeout $attempt',
      );
    }
    final transport = FakeTransport()
      ..onPush = (_) async => throw const SyncTransientException('timeout again');

    final result = await SyncEngine(store: store, transport: transport).runOnce();

    expect(result.retryCount, 0);
    expect(result.failedCount, 1);
    expect(transport.pushed, hasLength(1));
    expect(await store.pendingOperations(), isEmpty);
    expect(await store.pendingCount, 1);
  });

  test('uses every bounded retry delay before terminal ineligibility', () async {
    await store.put('customer', {'id': customerId, 'name': 'Anna'});
    final retryDelays = [
      const Duration(seconds: 5),
      const Duration(seconds: 30),
      const Duration(minutes: 5),
      const Duration(minutes: 30),
      const Duration(hours: 2),
    ];
    final transport = FakeTransport()
      ..onPush = (_) async => throw const SyncTransientException('timeout');
    final engine = SyncEngine(store: store, transport: transport);

    for (var index = 0; index < retryDelays.length; index++) {
      final before = DateTime.now().toUtc();
      final result = await engine.runOnce();
      final after = DateTime.now().toUtc();
      expect(result.retryCount, 1);
      expect(result.failedCount, 0);

      final db = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      try {
        final row = (await db.query('outbox')).single;
        expect(row['attempt_count'], index + 1);
        final nextAttempt = DateTime.parse(row['next_attempt_at'] as String);
        expect(
          nextAttempt.isAfter(
            before.add(retryDelays[index] - const Duration(seconds: 1)),
          ),
          isTrue,
        );
        expect(
          nextAttempt.isBefore(
            after.add(retryDelays[index] + const Duration(seconds: 1)),
          ),
          isTrue,
        );
        await db.update(
          'outbox',
          {'next_attempt_at': DateTime.now().toUtc().subtract(const Duration(seconds: 1)).toIso8601String()},
        );
      } finally {
        await db.close();
      }
    }

    final terminal = await engine.runOnce();
    expect(terminal.retryCount, 0);
    expect(terminal.failedCount, 1);
    expect(await store.pendingOperations(), isEmpty);
    expect(await store.pendingCount, 1);
  });

  test('records conflicts without deleting the outbox operation', () async {
    await store.put('customer', {'id': customerId, 'name': 'Local'});
    final transport = FakeTransport()
      ..onPush = (_) async => pushResult(
            SyncPushStatus.conflict,
            version: 4,
            current: {'id': customerId, 'name': 'Server'},
          );

    final result = await SyncEngine(store: store, transport: transport).runOnce();

    expect(result.conflictCount, 1);
    expect(await store.pendingCount, 1);
    expect(await store.pendingOperations(), isEmpty);

    await store.close();
    store = await LocalStore.open(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
      syncContext: syncContext,
    );
    final db = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    try {
      final conflict = (await db.query('sync_conflicts')).single;
      expect(conflict['server_version'], 4);
      expect(jsonDecode(conflict['server_payload'] as String), {
        'id': customerId,
        'name': 'Server',
      });
    } finally {
      await db.close();
    }
  });

  test('makes a versionless conflict ineligible while retaining its outbox row', () async {
    await store.put('customer', {'id': customerId, 'name': 'Local'});
    final transport = FakeTransport()
      ..onPush = (_) async => pushResult(SyncPushStatus.conflict);

    final result = await SyncEngine(store: store, transport: transport).runOnce();

    expect(result.conflictCount, 0);
    expect(result.failedCount, 1);
    expect(result.protocolErrorCount, 1);
    expect(result.errors.single, isA<SyncProtocolException>());
    expect(transport.pullCursors, isEmpty);
    expect(await store.pendingOperations(), isEmpty);
    expect(await store.pendingCount, 1);

    final db = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    try {
      final row = (await db.query('outbox')).single;
      expect(row['status'], 'retry');
      expect(row['next_attempt_at'], startsWith('9999-12-31'));
      expect(
        row['last_error'],
        'User action required: Push conflict result omitted server version.',
      );
    } finally {
      await db.close();
    }
  });

  test('applies a pull page before reporting its cursor', () async {
    final transport = FakeTransport()
      ..onPull = (afterCursor, limit) async => SyncPullPage(
            changes: [pulledChange(cursor: 1, entityId: customerId)],
            nextCursor: 1,
          );

    final result = await SyncEngine(store: store, transport: transport).runOnce();

    expect(result.pulled, 1);
    expect(result.finalCursor, 1);
    expect(await store.syncCursor(), 1);
    expect((await store.get('customer', customerId))?['name'], 'Remote');
  });

  test('pull application failure leaves the previous cursor and records unchanged', () async {
    final transport = FakeTransport()
      ..onPull = (afterCursor, limit) async => SyncPullPage(
            changes: [
              pulledChange(cursor: 1, entityId: customerId),
              pulledChange(cursor: 2, entityId: jobId, entityKind: SyncEntityKind.job,
                  payload: {'id': customerId, 'title': 'Wrong ID'}),
            ],
            nextCursor: 2,
          );

    await expectLater(
      SyncEngine(store: store, transport: transport).runOnce(),
      throwsArgumentError,
    );
    expect(await store.syncCursor(), 0);
    expect(await store.get('customer', customerId), isNull);
    expect(await store.get('job', jobId), isNull);
  });

  test('enforces 50 push and 100 pull limits', () async {
    for (var i = 0; i < 60; i++) {
      await store.put('customer', {
        'id': 'aaaaaaaa-aaaa-4aaa-8aaa-${i.toString().padLeft(12, '0')}',
        'name': 'Customer $i',
      });
    }
    final transport = FakeTransport()
      ..onPull = (afterCursor, limit) async => SyncPullPage(
            changes: [
              for (var i = 1; i <= limit; i++)
                pulledChange(
                  cursor: i,
                  entityId: 'bbbbbbbb-bbbb-4bbb-8bbb-${i.toString().padLeft(12, '0')}',
                ),
            ],
            nextCursor: limit,
          );

    final result = await SyncEngine(store: store, transport: transport).runOnce();

    expect(transport.pushed, hasLength(50));
    expect(transport.pullLimits, [100]);
    expect(result.pulled, 100);
    expect(await store.syncCursor(), 100);
  });

  test('a second successful run with no work is a no-op', () async {
    final transport = FakeTransport();
    final engine = SyncEngine(store: store, transport: transport);

    final first = await engine.runOnce();
    final second = await engine.runOnce();

    expect(first.pushed, 0);
    expect(first.pulled, 0);
    expect(second.pushed, 0);
    expect(second.pulled, 0);
    expect(second.conflictCount, 0);
    expect(second.retryCount, 0);
    expect(second.finalCursor, 0);
  });
}
