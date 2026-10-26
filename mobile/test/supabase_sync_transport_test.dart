import 'package:flutter_test/flutter_test.dart';

import 'package:falt/sync/supabase_sync_transport.dart';
import 'package:falt/sync/sync_models.dart';
import 'package:falt/sync/sync_transport.dart';

const _operationId = '11111111-1111-4111-8111-111111111111';
const _companyId = '22222222-2222-4222-8222-222222222222';
const _deviceId = '33333333-3333-4333-8333-333333333333';
const _entityId = '44444444-4444-4444-8444-444444444444';
const _otherOperationId = '55555555-5555-4555-8555-555555555555';

SyncOperation _operation() => SyncOperation(
      operationId: _operationId,
      companyId: _companyId,
      deviceId: _deviceId,
      entityKind: SyncEntityKind.customer,
      entityId: _entityId,
      expectedVersion: 2,
      operationKind: SyncOperationKind.upsert,
      payload: const {'name': 'Anna Svensson'},
    );

class FakeRpcFailure implements Exception {
  FakeRpcFailure({this.code, this.status, this.message = 'raw response detail'});

  final String? code;
  final int? status;
  final String message;
}

class FakeHttpClientException implements Exception, SyncNoResponseTransportFailure {
  FakeHttpClientException(this.message);

  final String message;
}

class FakeAuthRefreshException implements Exception, SyncNoResponseTransportFailure {
  FakeAuthRefreshException(this.message);

  final String message;
}

void main() {
  test('push sends the exact RPC map and decodes an accepted result', () async {
    String? functionName;
    Map<String, dynamic>? params;
    final transport = SupabaseSyncTransport.forTesting(
      companyId: _companyId,
      sessionProvider: () => Object(),
      rpcGateway: (name, {required rpcParams}) async {
        functionName = name;
        params = rpcParams;
        return const {
          'status': 'accepted',
          'version': 3,
          'cursor': 18,
          'deleted_at': null,
          'current': {'name': 'Anna Svensson'},
        };
      },
    );

    final result = await transport.push(_operation());

    expect(functionName, 'sync_push');
    expect(params, {
      'p_operation_id': _operationId,
      'p_company_id': _companyId,
      'p_entity_kind': 'customer',
      'p_entity_id': _entityId,
      'p_device_id': _deviceId,
      'p_expected_version': 2,
      'p_operation_kind': 'upsert',
      'p_payload': {'name': 'Anna Svensson'},
    });
    expect(result.status, SyncPushStatus.accepted);
    expect(result.version, 3);
    expect(result.cursor, 18);
    expect(result.current, {'name': 'Anna Svensson'});
  });

  test('pull sends exact parameters, decodes tombstones, and uses last cursor', () async {
    String? functionName;
    Map<String, dynamic>? params;
    final transport = SupabaseSyncTransport.forTesting(
      companyId: _companyId,
      sessionProvider: () => Object(),
      rpcGateway: (name, {required rpcParams}) async {
        functionName = name;
        params = rpcParams;
        return [
          {
            'cursor': 9,
            'entity_kind': 'customer',
            'entity_id': _entityId,
            'version': 3,
            'deleted_at': null,
            'payload': {'name': 'Anna Svensson'},
            'operation_id': _operationId,
          },
          {
            'cursor': 10,
            'entity_kind': 'job',
            'entity_id': _entityId,
            'version': 4,
            'deleted_at': '2026-10-26T10:00:00Z',
            'payload': null,
            'operation_id': _otherOperationId,
          },
        ];
      },
    );

    final page = await transport.pull(afterCursor: 8, limit: 25);

    expect(functionName, 'sync_pull');
    expect(params, {
      'p_company_id': _companyId,
      'p_after_cursor': 8,
      'p_limit': 25,
    });
    expect(page.nextCursor, 10);
    expect(page.changes, hasLength(2));
    expect(page.changes.last.payload, isNull);
    expect(page.changes.last.deletedAtUtc, DateTime.utc(2026, 10, 26, 10));
  });

  test('pull preserves the requested cursor for an empty page', () async {
    final transport = SupabaseSyncTransport.forTesting(
      companyId: _companyId,
      sessionProvider: () => Object(),
      rpcGateway: (name, {required rpcParams}) async => const <Object?>[],
    );

    final page = await transport.pull(afterCursor: 41);

    expect(page.changes, isEmpty);
    expect(page.nextCursor, 41);
  });

  test('requires a current session before invoking the RPC gateway', () async {
    var calls = 0;
    final transport = SupabaseSyncTransport.forTesting(
      companyId: _companyId,
      sessionProvider: () => null,
      rpcGateway: (name, {required rpcParams}) async {
        calls++;
        return const {};
      },
    );

    await expectLater(
      transport.push(_operation()),
      throwsA(isA<SyncAuthorizationException>()),
    );
    await expectLater(
      transport.pull(afterCursor: 0),
      throwsA(isA<SyncAuthorizationException>()),
    );
    expect(calls, 0);
  });

  test('classifies transient failures without exposing raw details', () async {
    final transport = _failingTransport(
      FakeRpcFailure(code: 'PGRST003', status: 503, message: 'secret response body'),
    );

    final error = await _captureError(() => transport.push(_operation()));

    expect(error, isA<SyncTransientException>());
    expect(error.message, isNot(contains('secret response body')));
  });

  test('classifies marked client no-response failures as transient', () async {
    final transport = _failingTransport(
      FakeHttpClientException('http client raw detail'),
    );

    final error = await _captureError(() => transport.push(_operation()));

    expect(error, isA<SyncTransientException>());
    expect(error.message, isNot(contains('http client raw detail')));
  });

  test('classifies marked auth refresh no-response failures as transient', () async {
    final transport = _failingTransport(
      FakeAuthRefreshException('refresh token raw detail'),
    );

    final error = await _captureError(() => transport.pull(afterCursor: 0));

    expect(error, isA<SyncTransientException>());
    expect(error.message, isNot(contains('refresh token raw detail')));
  });

  test('classifies a stable no-response status as transient', () async {
    final transport = _failingTransport(
      FakeRpcFailure(status: 0, message: 'no response raw detail'),
    );

    final error = await _captureError(() => transport.pull(afterCursor: 0));

    expect(error, isA<SyncTransientException>());
    expect(error.message, isNot(contains('no response raw detail')));
  });

  test('classifies authorization failures without exposing raw details', () async {
    final transport = _failingTransport(
      FakeRpcFailure(code: '42501', status: 403, message: 'membership and token details'),
    );

    final error = await _captureError(() => transport.push(_operation()));

    expect(error, isA<SyncAuthorizationException>());
    expect(error.message, isNot(contains('membership and token details')));
  });

  test('classifies validation failures without exposing raw details', () async {
    final transport = _failingTransport(
      FakeRpcFailure(code: '23505', status: 409, message: 'constraint and tenant details'),
    );

    final error = await _captureError(() => transport.push(_operation()));

    expect(error, isA<SyncValidationException>());
    expect(error.message, isNot(contains('constraint and tenant details')));
  });

  test('classifies unknown failures as protocol errors without raw response details', () async {
    final transport = _failingTransport(
      FakeRpcFailure(code: 'UNRECOGNIZED', status: 499, message: 'sensitive raw body'),
    );

    final error = await _captureError(() => transport.pull(afterCursor: 0));

    expect(error, isA<SyncProtocolException>());
    expect(error.message, isNot(contains('sensitive raw body')));
  });

  test('malformed pull responses are protocol errors', () async {
    final transport = SupabaseSyncTransport.forTesting(
      companyId: _companyId,
      sessionProvider: () => Object(),
      rpcGateway: (name, {required rpcParams}) async => const [
        {'cursor': 'not-an-integer'},
      ],
    );

    await expectLater(
      transport.pull(afterCursor: 0),
      throwsA(isA<SyncProtocolException>()),
    );
  });
}

SupabaseSyncTransport _failingTransport(Object failure) =>
    SupabaseSyncTransport.forTesting(
      companyId: _companyId,
      sessionProvider: () => Object(),
      rpcGateway: (name, {required rpcParams}) async => throw failure,
    );

Future<SyncTransportException> _captureError(
  Future<Object?> Function() operation,
) async {
  try {
    await operation();
  } on SyncTransportException catch (error) {
    return error;
  }
  fail('Expected a SyncTransportException');
}
