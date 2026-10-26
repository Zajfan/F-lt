import 'dart:collection';

enum SyncEntityKind { customer, job }
enum SyncOperationKind { upsert, delete }
enum SyncOperationStatus { pending, acknowledged, retry, conflict, failed }
enum SyncPushStatus { accepted, duplicate, conflict, rejected }

final _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
);

void _requireUuid(String field, String value) {
  if (!_uuidPattern.hasMatch(value)) {
    throw ArgumentError.value(value, field, 'Must be a stable UUID string');
  }
}

void _requireNonNegative(String field, int value) {
  if (value < 0) throw ArgumentError.value(value, field, 'Must be non-negative');
}

Map<String, dynamic> _immutableMap(Map<String, dynamic> source) =>
    UnmodifiableMapView({
      for (final entry in source.entries)
        entry.key: _freeze(entry.value),
    });

dynamic _freeze(dynamic value) {
  if (value is Map) {
    return UnmodifiableMapView({
      for (final entry in value.entries) entry.key as String: _freeze(entry.value),
    });
  }
  if (value is List) return List<dynamic>.unmodifiable(value.map(_freeze));
  return value;
}

dynamic _jsonValue(dynamic value) {
  if (value is Map) {
    return {for (final entry in value.entries) entry.key: _jsonValue(entry.value)};
  }
  if (value is List) return value.map(_jsonValue).toList();
  return value;
}

bool _deepEquals(dynamic a, dynamic b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length || !a.keys.toSet().containsAll(b.keys)) return false;
    return a.keys.every((key) => _deepEquals(a[key], b[key]));
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

int _deepHash(dynamic value) {
  if (value is Map) {
    return Object.hash(
      value.length,
      Object.hashAllUnordered(
        value.entries.map((e) => Object.hash(e.key, _deepHash(e.value))),
      ),
    );
  }
  if (value is Iterable) return Object.hashAll(value.map(_deepHash));
  return value.hashCode;
}

T _enumValue<T extends Enum>(List<T> values, dynamic value, String field) {
  for (final item in values) {
    if (item.name == value) return item;
  }
  throw FormatException('Invalid $field: $value');
}

dynamic _required(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key) || json[key] == null) {
    throw FormatException('Missing required field: $key');
  }
  return json[key];
}

int _intField(Map<String, dynamic> json, String key) {
  final value = _required(json, key);
  if (value is! int) throw FormatException('$key must be an integer');
  return value;
}

String _stringField(Map<String, dynamic> json, String key) {
  final value = _required(json, key);
  if (value is! String) throw FormatException('$key must be a string');
  return value;
}

DateTime? _optionalDate(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) throw FormatException('$key must be a date string');
  try {
    return DateTime.parse(value).toUtc();
  } on FormatException {
    throw FormatException('Invalid date for $key');
  }
}

Map<String, dynamic>? _optionalPayload(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! Map) throw FormatException('$key must be an object or null');
  try {
    return Map<String, dynamic>.from(value);
  } on TypeError {
    throw FormatException('$key must have string keys');
  }
}

class SyncOperation {
  SyncOperation({
    required this.operationId,
    required this.companyId,
    required this.deviceId,
    required this.entityKind,
    required this.entityId,
    required this.expectedVersion,
    required this.operationKind,
    required Map<String, dynamic> payload,
    this.createdAtUtc,
    this.attemptCount = 0,
    this.nextAttemptAtUtc,
    this.lastError,
    this.status = SyncOperationStatus.pending,
  }) : payload = _immutableMap(payload) {
    _requireUuid('operationId', operationId);
    _requireUuid('companyId', companyId);
    _requireUuid('deviceId', deviceId);
    _requireUuid('entityId', entityId);
    _requireNonNegative('expectedVersion', expectedVersion);
    _requireNonNegative('attemptCount', attemptCount);
  }

  final String operationId;
  final String companyId;
  final String deviceId;
  final SyncEntityKind entityKind;
  final String entityId;
  final int expectedVersion;
  final SyncOperationKind operationKind;
  final Map<String, dynamic> payload;
  final DateTime? createdAtUtc;
  final int attemptCount;
  final DateTime? nextAttemptAtUtc;
  final String? lastError;
  final SyncOperationStatus status;

  Map<String, dynamic> toJson() => {
    'operation_id': operationId,
    'company_id': companyId,
    'device_id': deviceId,
    'entity_kind': entityKind.name,
    'entity_id': entityId,
    'expected_version': expectedVersion,
    'operation_kind': operationKind.name,
    'payload': _jsonValue(payload),
    if (createdAtUtc != null) 'created_at_utc': createdAtUtc!.toUtc().toIso8601String(),
    if (attemptCount != 0) 'attempt_count': attemptCount,
    if (nextAttemptAtUtc != null) 'next_attempt_at_utc': nextAttemptAtUtc!.toUtc().toIso8601String(),
    if (lastError != null) 'last_error': lastError,
    if (status != SyncOperationStatus.pending) 'status': status.name,
  };

  factory SyncOperation.fromJson(Map<String, dynamic> json) {
    final payload = _optionalPayload(json, 'payload');
    if (payload == null) throw const FormatException('Missing required field: payload');
    final attemptCount = json['attempt_count'] ?? 0;
    if (attemptCount is! int) throw const FormatException('attempt_count must be an integer');
    final lastError = json['last_error'];
    if (lastError != null && lastError is! String) throw const FormatException('last_error must be a string');
    return SyncOperation(
      operationId: _stringField(json, 'operation_id'),
      companyId: _stringField(json, 'company_id'),
      deviceId: _stringField(json, 'device_id'),
      entityKind: _enumValue(SyncEntityKind.values, _stringField(json, 'entity_kind'), 'entity_kind'),
      entityId: _stringField(json, 'entity_id'),
      expectedVersion: _intField(json, 'expected_version'),
      operationKind: _enumValue(SyncOperationKind.values, _stringField(json, 'operation_kind'), 'operation_kind'),
      payload: payload,
      createdAtUtc: _optionalDate(json, 'created_at_utc'),
      attemptCount: attemptCount,
      nextAttemptAtUtc: _optionalDate(json, 'next_attempt_at_utc'),
      lastError: lastError as String?,
      status: json.containsKey('status')
          ? _enumValue(SyncOperationStatus.values, _stringField(json, 'status'), 'status')
          : SyncOperationStatus.pending,
    );
  }

  @override
  bool operator ==(Object other) => other is SyncOperation &&
      operationId == other.operationId && companyId == other.companyId && deviceId == other.deviceId &&
      entityKind == other.entityKind && entityId == other.entityId && expectedVersion == other.expectedVersion &&
      operationKind == other.operationKind && _deepEquals(payload, other.payload) &&
      createdAtUtc == other.createdAtUtc && attemptCount == other.attemptCount &&
      nextAttemptAtUtc == other.nextAttemptAtUtc && lastError == other.lastError && status == other.status;

  @override
  int get hashCode => Object.hash(operationId, companyId, deviceId, entityKind, entityId,
      expectedVersion, operationKind, _deepHash(payload), createdAtUtc, attemptCount,
      nextAttemptAtUtc, lastError, status);
}

class SyncChange {
  SyncChange({
    required this.cursor,
    required this.entityKind,
    required this.entityId,
    required this.version,
    required this.deletedAtUtc,
    required Map<String, dynamic>? payload,
    required this.operationId,
  }) : payload = payload == null ? null : _immutableMap(payload) {
    _requireNonNegative('cursor', cursor);
    _requireNonNegative('version', version);
    _requireUuid('entityId', entityId);
    _requireUuid('operationId', operationId);
    if (deletedAtUtc != null && payload != null) {
      throw ArgumentError('A tombstone must have a null payload');
    }
  }
  final int cursor;
  final SyncEntityKind entityKind;
  final String entityId;
  final int version;
  final DateTime? deletedAtUtc;
  final Map<String, dynamic>? payload;
  final String operationId;

  factory SyncChange.fromJson(Map<String, dynamic> json) {
    if (!json.containsKey('deleted_at')) {
      throw const FormatException('Missing required field: deleted_at');
    }
    if (!json.containsKey('payload')) {
      throw const FormatException('Missing required field: payload');
    }
    return SyncChange(
      cursor: _intField(json, 'cursor'),
      entityKind: _enumValue(SyncEntityKind.values, _stringField(json, 'entity_kind'), 'entity_kind'),
      entityId: _stringField(json, 'entity_id'),
      version: _intField(json, 'version'),
      deletedAtUtc: _optionalDate(json, 'deleted_at'),
      payload: _optionalPayload(json, 'payload'),
      operationId: _stringField(json, 'operation_id'),
    );
  }

  Map<String, dynamic> toJson() => {
    'cursor': cursor,
    'entity_kind': entityKind.name,
    'entity_id': entityId,
    'version': version,
    'deleted_at': deletedAtUtc?.toUtc().toIso8601String(),
    'payload': payload == null ? null : _jsonValue(payload),
    'operation_id': operationId,
  };

  @override
  bool operator ==(Object other) => other is SyncChange && cursor == other.cursor && entityKind == other.entityKind &&
      entityId == other.entityId && version == other.version && deletedAtUtc == other.deletedAtUtc &&
      _deepEquals(payload, other.payload) && operationId == other.operationId;
  @override
  int get hashCode => Object.hash(cursor, entityKind, entityId, version, deletedAtUtc, _deepHash(payload), operationId);
}

class SyncConflict {
  SyncConflict({required this.operation, required this.serverVersion, required Map<String, dynamic>? serverPayload,
      required this.detectedAtUtc}) : serverPayload = serverPayload == null ? null : _immutableMap(serverPayload) {
    _requireNonNegative('serverVersion', serverVersion);
  }
  final SyncOperation operation;
  final int serverVersion;
  final Map<String, dynamic>? serverPayload;
  final DateTime detectedAtUtc;

  @override
  bool operator ==(Object other) => other is SyncConflict && operation == other.operation &&
      serverVersion == other.serverVersion && _deepEquals(serverPayload, other.serverPayload) && detectedAtUtc == other.detectedAtUtc;
  @override
  int get hashCode => Object.hash(operation, serverVersion, _deepHash(serverPayload), detectedAtUtc);
}

class SyncPushResult {
  SyncPushResult({required this.status, required this.version, required this.cursor,
      required this.deletedAtUtc, required Map<String, dynamic>? current})
      : current = current == null ? null : _immutableMap(current) {
    if (version != null) _requireNonNegative('version', version!);
    if (cursor != null) _requireNonNegative('cursor', cursor!);
  }
  final SyncPushStatus status;
  final int? version;
  final int? cursor;
  final DateTime? deletedAtUtc;
  final Map<String, dynamic>? current;

  factory SyncPushResult.fromJson(Map<String, dynamic> json) {
    final status = _enumValue(SyncPushStatus.values, _stringField(json, 'status'), 'status');
    final versionValue = json['version'];
    final cursor = json['cursor'];
    if (versionValue != null && versionValue is! int) {
      throw const FormatException('version must be an integer');
    }
    if (cursor != null && cursor is! int) throw const FormatException('cursor must be an integer');
    var version = versionValue as int?;
    var deletedAtUtc = _optionalDate(json, 'deleted_at');
    var current = _optionalPayload(json, 'current');

    if (status == SyncPushStatus.conflict) {
      if (!json.containsKey('current')) {
        throw const FormatException('Missing required field: current');
      }
      if (current == null) {
        version = null;
        deletedAtUtc = null;
      } else {
        // Keep the pre-existing flat fixture shape round-trippable while
        // requiring every field when a response has the nested SQL shape.
        final hasLegacyFlatFields =
            json.containsKey('cursor') || json.containsKey('deleted_at');
        final looksNested = current.containsKey('version') ||
            current.containsKey('deleted_at') ||
            current.containsKey('payload') ||
            version == null ||
            !hasLegacyFlatFields;
        if (looksNested) {
          if (!current.containsKey('version')) {
            throw const FormatException('Missing required field: current.version');
          }
          if (!current.containsKey('deleted_at')) {
            throw const FormatException('Missing required field: current.deleted_at');
          }
          if (!current.containsKey('payload')) {
            throw const FormatException('Missing required field: current.payload');
          }
          final nestedVersion = _intField(current, 'version');
          if (nestedVersion < 0) {
            throw const FormatException(
              'current.version must be non-negative',
            );
          }
          final nestedDeletedAtUtc = _optionalDate(current, 'deleted_at');
          final nestedPayload = _optionalPayload(current, 'payload');
          if ((nestedDeletedAtUtc != null && nestedPayload != null) ||
              (nestedDeletedAtUtc == null && nestedPayload == null)) {
            throw const FormatException(
              'current.deleted_at and current.payload must describe a live record or tombstone',
            );
          }
          version = nestedVersion;
          deletedAtUtc = nestedDeletedAtUtc;
          current = nestedPayload;
        }
      }
    }

    return SyncPushResult(
      status: status,
      version: version,
      cursor: cursor as int?,
      deletedAtUtc: deletedAtUtc,
      current: current,
    );
  }

  Map<String, dynamic> toJson() => {
    'status': status.name, 'version': version, 'cursor': cursor,
    'deleted_at': deletedAtUtc?.toUtc().toIso8601String(),
    'current': current == null ? null : _jsonValue(current),
  };
  @override
  bool operator ==(Object other) => other is SyncPushResult && status == other.status && version == other.version &&
      cursor == other.cursor && deletedAtUtc == other.deletedAtUtc && _deepEquals(current, other.current);
  @override
  int get hashCode => Object.hash(status, version, cursor, deletedAtUtc, _deepHash(current));
}

class SyncPullPage {
  SyncPullPage({required List<SyncChange> changes, required this.nextCursor})
      : changes = List<SyncChange>.unmodifiable(changes) {
    _requireNonNegative('nextCursor', nextCursor);
  }
  final List<SyncChange> changes;
  final int nextCursor;

  @override
  bool operator ==(Object other) => other is SyncPullPage && nextCursor == other.nextCursor && _deepEquals(changes, other.changes);
  @override
  int get hashCode => Object.hash(_deepHash(changes), nextCursor);
}
