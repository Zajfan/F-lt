import 'package:flutter_test/flutter_test.dart';
import 'package:falt/sync/sync_models.dart';

void main() {
  const operationId = '11111111-1111-4111-8111-111111111111';
  const companyId = '22222222-2222-4222-8222-222222222222';
  const deviceId = '33333333-3333-4333-8333-333333333333';
  const entityId = '44444444-4444-4444-8444-444444444444';

  test('round trips an upsert operation with a typed payload', () {
    final original = SyncOperation(
      operationId: operationId,
      companyId: companyId,
      deviceId: deviceId,
      entityKind: SyncEntityKind.customer,
      entityId: entityId,
      expectedVersion: 0,
      operationKind: SyncOperationKind.upsert,
      payload: {'name': 'Anna Svensson'},
    );
    expect(SyncOperation.fromJson(original.toJson()), original);
  });

  test('equivalent nested maps have equal values and hash codes', () {
    final first = SyncOperation(
      operationId: operationId,
      companyId: companyId,
      deviceId: deviceId,
      entityKind: SyncEntityKind.customer,
      entityId: entityId,
      expectedVersion: 0,
      operationKind: SyncOperationKind.upsert,
      payload: {
        'profile': {'first': 'Anna', 'last': 'Svensson'},
        'tags': ['customer', 'priority'],
      },
    );
    final second = SyncOperation(
      operationId: operationId,
      companyId: companyId,
      deviceId: deviceId,
      entityKind: SyncEntityKind.customer,
      entityId: entityId,
      expectedVersion: 0,
      operationKind: SyncOperationKind.upsert,
      payload: {
        'tags': ['customer', 'priority'],
        'profile': {'last': 'Svensson', 'first': 'Anna'},
      },
    );

    expect(first, second);
    expect(first.hashCode, second.hashCode);
  });

  test('decodes a tombstone without inventing payload data', () {
    final change = SyncChange.fromJson({
      'cursor': 7,
      'entity_kind': 'job',
      'entity_id': entityId,
      'version': 3,
      'deleted_at': '2026-10-26T10:00:00Z',
      'payload': null,
      'operation_id': '55555555-5555-4555-8555-555555555555',
    });
    expect(change.payload, isNull);
    expect(change.cursor, 7);
  });

  test('round trips every push outcome', () {
    for (final status in SyncPushStatus.values) {
      final result = SyncPushResult.fromJson({
        'status': status.name,
        'version': 2,
        'cursor': 9,
        'deleted_at': null,
        'current': {'name': 'Anna'},
      });
      expect(result.status, status);
      expect(SyncPushResult.fromJson(result.toJson()), result);
    }
  });

  test('decodes a nested live conflict from the SQL response shape', () {
    final result = SyncPushResult.fromJson({
      'status': 'conflict',
      'current': {
        'version': 2,
        'deleted_at': null,
        'payload': {'name': 'Anna'},
      },
    });

    expect(result.status, SyncPushStatus.conflict);
    expect(result.version, 2);
    expect(result.deletedAtUtc, isNull);
    expect(result.current, {'name': 'Anna'});
    expect(
      result.toJson(),
      {
        'status': 'conflict',
        'version': 2,
        'cursor': null,
        'deleted_at': null,
        'current': {'name': 'Anna'},
      },
    );
  });

  test('decodes a nested tombstone conflict with a null payload', () {
    final result = SyncPushResult.fromJson({
      'status': 'conflict',
      'current': {
        'version': 3,
        'deleted_at': '2026-10-26T10:00:00Z',
        'payload': null,
      },
    });

    expect(result.version, 3);
    expect(result.deletedAtUtc, DateTime.utc(2026, 10, 26, 10));
    expect(result.current, isNull);
  });

  test('decodes a conflict whose SQL current record is null', () {
    final result = SyncPushResult.fromJson({
      'status': 'conflict',
      'current': null,
    });

    expect(result.status, SyncPushStatus.conflict);
    expect(result.version, isNull);
    expect(result.deletedAtUtc, isNull);
    expect(result.current, isNull);
  });

  test('rejects a negative nested conflict version as malformed wire data', () {
    expect(
      () => SyncPushResult.fromJson({
        'status': 'conflict',
        'current': {
          'version': -1,
          'deleted_at': null,
          'payload': {'name': 'Anna'},
        },
      }),
      throwsFormatException,
    );
  });

  test('enforces the SQL conflict deletion and payload invariant', () {
    final invalid = <Map<String, dynamic>>[
      {
        'status': 'conflict',
        'current': {
          'version': 2,
          'deleted_at': '2026-10-26T10:00:00Z',
          'payload': {'name': 'Anna'},
        },
      },
      {
        'status': 'conflict',
        'current': {
          'version': 2,
          'deleted_at': null,
          'payload': null,
        },
      },
    ];

    for (final json in invalid) {
      expect(
        () => SyncPushResult.fromJson(json),
        throwsFormatException,
      );
    }
  });

  test('rejects malformed nested conflict fields', () {
    final malformed = <Map<String, dynamic>>[
      {'status': 'conflict'},
      {'status': 'conflict', 'current': 'not an object'},
      {
        'status': 'conflict',
        'current': {'deleted_at': null, 'payload': null},
      },
      {
        'status': 'conflict',
        'current': {'version': '2', 'deleted_at': null, 'payload': null},
      },
      {
        'status': 'conflict',
        'current': {'version': 2, 'deleted_at': 3, 'payload': null},
      },
      {
        'status': 'conflict',
        'version': 2,
        'current': {'name': 'Anna'},
      },
      {
        'status': 'conflict',
        'current': {'version': 2, 'deleted_at': null, 'payload': 'not an object'},
      },
    ];

    for (final json in malformed) {
      expect(
        () => SyncPushResult.fromJson(json),
        throwsFormatException,
      );
    }
  });

  test('missing required fields throw FormatException', () {
    expect(() => SyncChange.fromJson({}), throwsFormatException);
    expect(
      () => SyncChange.fromJson({
        'cursor': 7,
        'entity_kind': 'job',
        'entity_id': entityId,
        'version': 3,
        'deleted_at': null,
        'operation_id': '55555555-5555-4555-8555-555555555555',
      }),
      throwsFormatException,
    );
  });

  test('rejects negative operation versions and pull cursors', () {
    expect(
      () => SyncOperation(
        operationId: operationId,
        companyId: companyId,
        deviceId: deviceId,
        entityKind: SyncEntityKind.customer,
        entityId: entityId,
        expectedVersion: -1,
        operationKind: SyncOperationKind.upsert,
        payload: const {},
      ),
      throwsArgumentError,
    );
    expect(() => SyncPullPage(changes: const [], nextCursor: -1),
        throwsArgumentError);
  });

  test('requires stable UUID identifiers', () {
    expect(
      () => SyncOperation(
        operationId: 'unstable',
        companyId: companyId,
        deviceId: deviceId,
        entityKind: SyncEntityKind.customer,
        entityId: entityId,
        expectedVersion: 0,
        operationKind: SyncOperationKind.upsert,
        payload: const {},
      ),
      throwsArgumentError,
    );
  });
}
