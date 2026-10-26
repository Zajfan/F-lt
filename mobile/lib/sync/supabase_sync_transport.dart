import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'sync_models.dart';
import 'sync_transport.dart';

typedef SyncRpcGateway = Future<Object?> Function(
  String functionName, {
  required Map<String, dynamic> rpcParams,
});

typedef SyncSessionProvider = Object? Function();

/// Test seam for external no-response transport wrappers.
abstract interface class SyncNoResponseTransportFailure {}

class SupabaseSyncTransport implements SyncTransport {
  factory SupabaseSyncTransport({
    required SupabaseClient client,
    required String companyId,
  }) {
    return SupabaseSyncTransport._(
      companyId: companyId,
      rpcGateway: (functionName, {required rpcParams}) async {
        return await client.rpc(functionName, params: rpcParams);
      },
      sessionProvider: () => client.auth.currentSession,
    );
  }

  SupabaseSyncTransport.forTesting({
    required String companyId,
    required SyncRpcGateway rpcGateway,
    required SyncSessionProvider sessionProvider,
  }) : this._(
          companyId: companyId,
          rpcGateway: rpcGateway,
          sessionProvider: sessionProvider,
        );

  const SupabaseSyncTransport._({
    required this.companyId,
    required SyncRpcGateway rpcGateway,
    required SyncSessionProvider sessionProvider,
  })  : _rpcGateway = rpcGateway,
        _sessionProvider = sessionProvider;

  final String companyId;
  final SyncRpcGateway _rpcGateway;
  final SyncSessionProvider _sessionProvider;

  @override
  Future<SyncPushResult> push(SyncOperation operation) async {
    _requireSession();
    try {
      final response = await _rpcGateway(
        'sync_push',
        rpcParams: {
          'p_operation_id': operation.operationId,
          'p_company_id': operation.companyId,
          'p_entity_kind': operation.entityKind.name,
          'p_entity_id': operation.entityId,
          'p_device_id': operation.deviceId,
          'p_expected_version': operation.expectedVersion,
          'p_operation_kind': operation.operationKind.name,
          'p_payload': operation.payload,
        },
      );
      return SyncPushResult.fromJson(_asMap(response));
    } on SyncTransportException {
      rethrow;
    } catch (error) {
      throw _classify(error);
    }
  }

  @override
  Future<SyncPullPage> pull({required int afterCursor, int limit = 100}) async {
    _requireSession();
    try {
      final response = await _rpcGateway(
        'sync_pull',
        rpcParams: {
          'p_company_id': companyId,
          'p_after_cursor': afterCursor,
          'p_limit': limit,
        },
      );
      final rows = _asList(response);
      final changes = rows
          .map((row) => SyncChange.fromJson(_asMap(row)))
          .toList(growable: false);
      final nextCursor = changes.isEmpty ? afterCursor : changes.last.cursor;
      return SyncPullPage(changes: changes, nextCursor: nextCursor);
    } on SyncTransportException {
      rethrow;
    } catch (error) {
      throw _classify(error);
    }
  }

  void _requireSession() {
    if (_sessionProvider() == null) {
      throw const SyncAuthorizationException('Sign in required to sync.');
    }
  }

  static Map<String, dynamic> _asMap(Object? value) {
    if (value is! Map) {
      throw const SyncProtocolException('Sync response was not an object.');
    }
    try {
      return Map<String, dynamic>.from(value);
    } on TypeError {
      throw const SyncProtocolException('Sync response had invalid fields.');
    }
  }

  static List<Object?> _asList(Object? value) {
    if (value is! List) {
      throw const SyncProtocolException('Sync response was not a row list.');
    }
    return List<Object?>.from(value);
  }

  static SyncTransportException _classify(Object error) {
    if (error is SyncTransportException) return error;
    if (error is SyncNoResponseTransportFailure ||
        _isNoResponseTransportType(error)) {
      return const SyncTransientException('Sync service is temporarily unavailable.');
    }
    if (error is FormatException || error is ArgumentError || error is TypeError) {
      return const SyncProtocolException('Sync response was invalid.');
    }

    final code = _errorField(error, 'code')?.toString().toUpperCase();
    final status = _statusCode(error);
    if (error is TimeoutException || error is SocketException || _isTransient(code, status)) {
      return const SyncTransientException('Sync service is temporarily unavailable.');
    }
    if (_isAuthorization(code, status)) {
      return const SyncAuthorizationException('Sync authorization was rejected.');
    }
    if (_isValidation(code, status)) {
      return const SyncValidationException('Sync request was rejected.');
    }
    return const SyncProtocolException('Sync service returned an unusable response.');
  }

  static Object? _errorField(Object error, String name) {
    if (error is Map) return error[name];
    final dynamic dynamicError = error;
    try {
      switch (name) {
        case 'code':
          return dynamicError.code;
        case 'status':
          return dynamicError.status;
        case 'statusCode':
          return dynamicError.statusCode;
        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }

  static int? _statusCode(Object error) {
    final value = _errorField(error, 'status') ?? _errorField(error, 'statusCode');
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  static bool _isNoResponseTransportType(Object error) {
    switch (error.runtimeType.toString()) {
      case 'ClientException':
      case 'AuthRetryableFetchException':
      case 'AuthRetryableException':
      case 'FunctionsFetchException':
      case 'PostgrestTransportException':
      case 'StorageTransportException':
      case 'RealtimeTransportException':
      case 'SupabaseTransportException':
      case 'IcebergNetworkException':
        return true;
      default:
        return false;
    }
  }

  static bool _isTransient(String? code, int? status) {
    if (status == 0 ||
        status == 408 ||
        status == 425 ||
        status == 429 ||
        (status != null && status >= 500)) {
      return true;
    }
    return code == 'PGRST003' ||
        code == '08000' ||
        code == '08003' ||
        code == '08006' ||
        code == '57P01' ||
        code == '57014';
  }

  static bool _isAuthorization(String? code, int? status) {
    if (status == 401 || status == 403) return true;
    return code == '42501' ||
        code == 'PGRST301' ||
        code == 'AUTHENTICATION_REQUIRED' ||
        code == 'UNAUTHENTICATED' ||
        code == 'FORBIDDEN';
  }

  static bool _isValidation(String? code, int? status) {
    if (status == 400 || status == 409 || status == 422) return true;
    if (code == null) return false;
    return code == 'P0001' ||
        code == '23503' ||
        code == '23505' ||
        code == '23514' ||
        code.startsWith('22');
  }
}
