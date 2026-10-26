import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'database_key.dart';
import '../domain/estimate.dart';
import '../domain/job.dart';
import '../domain/work_log.dart';
import '../sync/sync_context.dart';
import '../sync/sync_models.dart';

/// Business writes and their outbox records commit atomically.
class LocalStore {
  LocalStore._(this._db, this._syncContext);
  final Database _db;
  final SyncContext? _syncContext;
  String get _accountId => _syncContext?.accountId ?? 'demo';
  String get _companyId => _syncContext?.companyId ?? 'demo';
  String get _deviceId => _syncContext?.deviceId ?? 'demo';
  List<Object?> get _scopeArgs => [_accountId, _companyId];
  static const _scopeWhere = 'account_id = ? AND company_id = ?';

  SyncContext _requireSyncContext() {
    final context = _syncContext;
    if (context == null) {
      throw StateError('An authenticated sync context is required.');
    }
    context.validate();
    return context;
  }

  String _metaKey(String key) => '$_accountId:$_companyId:$key';

  static Future<LocalStore> open({
    DatabaseFactory? factory,
    String? databasePath,
    SyncContext? syncContext,
    DatabaseKeyProvider? keyProvider,
    String? databasePassword,
  }) async {
    syncContext?.validate();
    final selectedFactory = factory ?? databaseFactory;
    final password = databasePassword ??
        (factory == null
            ? await (keyProvider ?? DatabaseKeyProvider.production())
                .loadOrCreate()
            : null);
    final db = await selectedFactory.openDatabase(
      databasePath ??
          path.join(await selectedFactory.getDatabasesPath(), 'falt.db'),
      options: SqlCipherOpenDatabaseOptions(
        version: 3,
        password: password,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) => _createV2(db),
        onUpgrade: (db, oldVersion, newVersion) async {
          var migratedVersion = oldVersion;
          if (migratedVersion < 2) {
            await db.execute('ALTER TABLE records RENAME TO records_v1');
            await db.execute('ALTER TABLE outbox RENAME TO outbox_v1');
            await _createRecords(db);
            await _createOutbox(db);
            await db.execute(
              "INSERT INTO records (account_id, company_id, kind, id, payload) SELECT 'demo', 'demo', kind, id, payload FROM records_v1",
            );
            await db.execute(
              "INSERT INTO outbox (id, account_id, company_id, device_id, kind, entity_id, payload, created_at) SELECT id, 'demo', 'demo', 'demo', kind, entity_id, payload, created_at FROM outbox_v1",
            );
            await db.execute('DROP TABLE records_v1');
            await db.execute('DROP TABLE outbox_v1');
            await _createSyncTables(db);
            // v1 metadata belongs to the evaluation partition.
            await db.execute("UPDATE meta SET key = 'demo:demo:' || key");
            migratedVersion = 2;
          }
          if (migratedVersion < 3) {
            await _normalizeLegacyJobRecords(db);
            migratedVersion = 3;
          }
          if (newVersion > 3) {
            throw StateError('Unsupported store version: $newVersion');
          }
        },
      ),
    );
    return LocalStore._(db, syncContext);
  }

  static Future<void> _createV2(Database db) async {
    await _createRecords(db);
    await _createOutbox(db);
    await db.execute('CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
    await _createSyncTables(db);
  }

  static Future<void> _createRecords(Database db) => db.execute(
    'CREATE TABLE records (account_id TEXT NOT NULL, company_id TEXT NOT NULL, kind TEXT NOT NULL, id TEXT NOT NULL, payload TEXT NOT NULL, server_version INTEGER NOT NULL DEFAULT 0, deleted_at TEXT, PRIMARY KEY(account_id, company_id, kind, id))',
  );

  static Future<void> _createOutbox(Database db) => db.execute(
    "CREATE TABLE outbox (id TEXT PRIMARY KEY, account_id TEXT NOT NULL, company_id TEXT NOT NULL, device_id TEXT NOT NULL, kind TEXT NOT NULL, entity_id TEXT NOT NULL, payload TEXT NOT NULL, created_at TEXT NOT NULL, expected_version INTEGER NOT NULL DEFAULT 0, operation_kind TEXT NOT NULL DEFAULT 'upsert', status TEXT NOT NULL DEFAULT 'pending', attempt_count INTEGER NOT NULL DEFAULT 0, next_attempt_at TEXT, last_error TEXT)",
  );

  static Future<void> _createSyncTables(Database db) async {
    await db.execute(
      'CREATE TABLE sync_conflicts (account_id TEXT NOT NULL, company_id TEXT NOT NULL, operation_id TEXT NOT NULL, server_version INTEGER NOT NULL, server_payload TEXT, detected_at TEXT NOT NULL, PRIMARY KEY(account_id, company_id, operation_id))',
    );
    await db.execute(
      'CREATE TABLE sync_cursors (account_id TEXT NOT NULL, company_id TEXT NOT NULL, cursor INTEGER NOT NULL, PRIMARY KEY(account_id, company_id))',
    );
  }

  static Future<void> _normalizeLegacyJobRecords(Database db) async {
    final rows = await db.query(
      'records',
      columns: ['account_id', 'company_id', 'kind', 'id', 'payload'],
      where: "kind = 'job'",
    );
    for (final row in rows) {
      final payload = jsonDecode(row['payload'] as String) as Map<String, dynamic>;
      final isSqlJob = payload.containsKey('version') &&
          (payload.containsKey('customer_id') ||
              payload.containsKey('assignee_id') ||
              payload.containsKey('starts_at') ||
              payload.containsKey('ends_at'));
      if (!isSqlJob) continue;
      final job = Job.fromJson(payload);
      final normalized = <String, Object?>{
        ...job.toJson(),
        'revision': payload['version'] as int? ?? job.revision,
      };
      await db.update(
        'records',
        {'payload': jsonEncode(normalized)},
        where: 'account_id = ? AND company_id = ? AND kind = ? AND id = ?',
        whereArgs: [row['account_id'], row['company_id'], row['kind'], row['id']],
      );
    }
  }

  Future<List<Map<String, dynamic>>> list(String kind) async =>
      (await _db.query('records', where: '$_scopeWhere AND kind = ? AND deleted_at IS NULL',
          whereArgs: [..._scopeArgs, kind]))
          .map(
            (row) =>
                jsonDecode(row['payload'] as String) as Map<String, dynamic>,
          )
          .toList();
  Future<void> _write(
    Transaction txn,
    String kind,
    Map<String, dynamic> value,
  ) async {
    final payload = jsonEncode(value);
    final outboxPayload = jsonEncode(_outboxPayload(kind, value));
    final id = value['id'] as String;
    if (_syncContext != null && (kind == 'customer' || kind == 'job')) {
      SyncContext.requireStableUuid('entityId', id);
    }
    final previous = await txn.query('records', columns: ['server_version'],
      where: '$_scopeWhere AND kind = ? AND id = ?',
      whereArgs: [..._scopeArgs, kind, id]);
    final expectedVersion = previous.isEmpty ? 0 : previous.single['server_version'] as int;
    final isDelete = value['deleted'] == true;
    await txn.insert('records', {
      'account_id': _accountId,
      'company_id': _companyId,
      'kind': kind,
      'id': id,
      'payload': payload,
      'server_version': expectedVersion,
      'deleted_at': isDelete ? DateTime.now().toUtc().toIso8601String() : null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    final operationId = const Uuid().v4();
    SyncContext.requireStableUuid('operationId', operationId);
    await txn.insert('outbox', {
      'id': operationId,
      'account_id': _accountId,
      'company_id': _companyId,
      'device_id': _deviceId,
      'kind': kind,
      'entity_id': id,
      'payload': outboxPayload,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'expected_version': expectedVersion,
      'operation_kind': isDelete ? SyncOperationKind.delete.name : SyncOperationKind.upsert.name,
    });
  }

  Map<String, dynamic> _outboxPayload(
    String kind,
    Map<String, dynamic> value,
  ) {
    if (_syncContext == null || kind != 'job') return value;
    if (value['deleted'] == true) return <String, dynamic>{};

    final payload = <String, dynamic>{};
    void copy(String wireKey, Iterable<String> localKeys) {
      for (final key in localKeys) {
        if (value.containsKey(key) && value[key] != null) {
          payload[wireKey] = value[key];
          return;
        }
      }
    }

    copy('customer_id', ['customerId', 'customer_id']);
    copy('title', ['title']);
    copy('address', ['address']);
    copy('instructions', ['instructions']);
    copy('quote_id', ['quoteId', 'quote_id']);
    copy('starts_at', ['startsAt', 'starts_at']);
    copy('ends_at', ['endsAt', 'ends_at']);

    final assigneeId = value['assigneeId'] ??
        value['assignee_id'] ??
        _syncContext!.accountId;
    SyncContext.requireStableUuid('assignee_id', assigneeId as String);
    payload['assignee_id'] = assigneeId;

    final status = value['status'];
    if (status is String) {
      payload['status'] = status == 'inProgress' ? 'in_progress' : status;
    }
    return payload;
  }

  Future<void> put(String kind, Map<String, dynamic> value) =>
      _db.transaction((txn) => _write(txn, kind, value));
  Future<int> get pendingCount async =>
      Sqflite.firstIntValue(
        await _db.rawQuery('SELECT COUNT(*) FROM outbox WHERE $_scopeWhere', _scopeArgs),
      ) ??
      0;

  Future<List<SyncOperation>> pendingOperations({int limit = 50}) async {
    _requireSyncContext();
    if (limit <= 0) return [];
    return _db.transaction((txn) async {
      final rows = await txn.query('outbox',
        where: "$_scopeWhere AND kind IN ('customer', 'job') AND status IN ('pending', 'retry') AND (next_attempt_at IS NULL OR next_attempt_at <= ?)",
        whereArgs: [..._scopeArgs, DateTime.now().toUtc().toIso8601String()],
        orderBy: 'created_at ASC, rowid ASC', limit: limit);
      final operations = <SyncOperation>[];
      for (final row in rows) {
        var payload = Map<String, dynamic>.from(
          jsonDecode(row['payload'] as String) as Map,
        );
        if (row['kind'] == 'job') {
          final normalized = _outboxPayload('job', payload);
          final encoded = jsonEncode(normalized);
          if (encoded != row['payload']) {
            await txn.update(
              'outbox',
              {'payload': encoded},
              where: '$_scopeWhere AND id = ?',
              whereArgs: [..._scopeArgs, row['id']],
            );
            payload = normalized;
          }
        }
        operations.add(SyncOperation.fromJson({
          'operation_id': row['id'],
          'company_id': row['company_id'],
          'device_id': row['device_id'],
          'entity_kind': row['kind'],
          'entity_id': row['entity_id'],
          'expected_version': row['expected_version'],
          'operation_kind': row['operation_kind'],
          'payload': payload,
          'created_at_utc': row['created_at'],
          'attempt_count': row['attempt_count'],
          'next_attempt_at_utc': row['next_attempt_at'],
          'last_error': row['last_error'],
          'status': row['status'],
        }));
      }
      return operations;
    });
  }

  Future<void> acknowledgeOperation(String operationId, {
    required int acceptedVersion,
  }) async {
    _requireSyncContext();
    SyncContext.requireStableUuid('operationId', operationId);
    if (acceptedVersion < 0) {
      throw ArgumentError.value(acceptedVersion, 'acceptedVersion');
    }
    await _db.transaction((txn) async {
      final rows = await txn.rawQuery(
        'SELECT rowid, kind, entity_id, expected_version FROM outbox WHERE $_scopeWhere AND id = ?',
        [..._scopeArgs, operationId]);
      if (rows.isEmpty) return;
      final operation = rows.single;
      final kind = operation['kind'] as String;
      final entityId = operation['entity_id'] as String;
      if (kind == 'customer' || kind == 'job') {
        if (acceptedVersion <= (operation['expected_version'] as int)) {
          throw ArgumentError.value(acceptedVersion, 'acceptedVersion',
            'Must advance the operation expected version');
        }
        final records = await txn.query('records', columns: ['server_version'],
          where: '$_scopeWhere AND kind = ? AND id = ?',
          whereArgs: [..._scopeArgs, kind, entityId]);
        if (records.isEmpty ||
            (records.single['server_version'] as int) > acceptedVersion) {
          throw StateError('The acknowledged record version is inconsistent.');
        }
        await txn.update('records', {'server_version': acceptedVersion},
          where: '$_scopeWhere AND kind = ? AND id = ?',
          whereArgs: [..._scopeArgs, kind, entityId]);
        await txn.rawUpdate(
          "UPDATE outbox SET expected_version = ? WHERE $_scopeWhere AND kind = ? AND entity_id = ? AND rowid > ? AND status IN ('pending', 'retry')",
          [acceptedVersion, ..._scopeArgs, kind, entityId, operation['rowid']]);
      }
      await txn.delete('outbox', where: '$_scopeWhere AND id = ?',
        whereArgs: [..._scopeArgs, operationId]);
    });
  }

  Future<void> scheduleRetry(String operationId, {
    required DateTime nextAttemptAtUtc,
    required String error,
  }) async {
    _requireSyncContext();
    SyncContext.requireStableUuid('operationId', operationId);
    await _db.rawUpdate(
      "UPDATE outbox SET attempt_count = attempt_count + 1, last_error = ?, next_attempt_at = ?, status = 'retry' WHERE $_scopeWhere AND id = ? AND status IN ('pending', 'retry')",
      [error, nextAttemptAtUtc.toUtc().toIso8601String(), ..._scopeArgs, operationId]);
  }

  Future<void> recordConflict(SyncConflict conflict) async {
    _requireSyncContext();
    await _db.transaction((txn) async {
      final rows = await txn.query('outbox', columns: ['id'],
        where: '$_scopeWhere AND id = ? AND company_id = ? AND device_id = ?',
        whereArgs: [..._scopeArgs, conflict.operation.operationId,
          conflict.operation.companyId, conflict.operation.deviceId]);
      if (rows.isEmpty) throw StateError('Operation is not in the active context.');
      await txn.insert('sync_conflicts', {
        'account_id': _accountId,
        'company_id': _companyId,
        'operation_id': conflict.operation.operationId,
        'server_version': conflict.serverVersion,
        'server_payload': conflict.serverPayload == null ? null : jsonEncode(conflict.serverPayload),
        'detected_at': conflict.detectedAtUtc.toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.update('outbox', {'status': SyncOperationStatus.conflict.name},
        where: '$_scopeWhere AND id = ?',
        whereArgs: [..._scopeArgs, conflict.operation.operationId]);
    });
  }

  Future<int> syncCursor() async {
    _requireSyncContext();
    return _readCursor(_db);
  }

  Future<int> _readCursor(DatabaseExecutor db) async {
    final rows = await db.query('sync_cursors', columns: ['cursor'],
      where: _scopeWhere, whereArgs: _scopeArgs);
    return rows.isEmpty ? 0 : rows.single['cursor'] as int;
  }

  Future<void> applyPullPage(SyncPullPage page) async {
    _requireSyncContext();
    await _db.transaction((txn) async {
      final storedCursor = await _readCursor(txn);
      if (page.nextCursor <= storedCursor) {
        throw StateError('Pull cursor must advance.');
      }
      var lastCursor = storedCursor;
      for (final change in page.changes) {
        if (change.cursor <= lastCursor || change.cursor > page.nextCursor) {
          throw ArgumentError('Pull changes must have increasing cursors within the page.');
        }
        lastCursor = change.cursor;
        if (change.deletedAtUtc == null &&
            (change.payload == null || change.payload!['id'] != change.entityId)) {
          throw ArgumentError('Pull payload must contain the matching entity ID.');
        }
        final kind = change.entityKind.name;
        final existing = await txn.query('records', columns: ['server_version'],
          where: '$_scopeWhere AND kind = ? AND id = ?',
          whereArgs: [..._scopeArgs, kind, change.entityId]);
        if (existing.isNotEmpty &&
            (existing.single['server_version'] as int) >= change.version) {
          continue;
        }
        final unresolved = await txn.query('outbox', columns: ['id'],
          where: "$_scopeWhere AND kind = ? AND entity_id = ? AND status != 'acknowledged'",
          whereArgs: [..._scopeArgs, kind, change.entityId]);
        if (unresolved.isNotEmpty) {
          for (final operation in unresolved) {
            final operationId = operation['id'] as String;
            final recorded = await txn.query('sync_conflicts',
              columns: ['server_version'],
              where: '$_scopeWhere AND operation_id = ?',
              whereArgs: [..._scopeArgs, operationId]);
            if (recorded.isNotEmpty &&
                (recorded.single['server_version'] as int) >= change.version) {
              continue;
            }
            await txn.insert('sync_conflicts', {
              'account_id': _accountId,
              'company_id': _companyId,
              'operation_id': operationId,
              'server_version': change.version,
              'server_payload': change.payload == null ? null : jsonEncode(change.payload),
              'detected_at': DateTime.now().toUtc().toIso8601String(),
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          }
          continue;
        }
        await txn.insert('records', {
          'account_id': _accountId,
          'company_id': _companyId,
          'kind': kind,
          'id': change.entityId,
          'payload': jsonEncode(_localRecordPayload(change)),
          'server_version': change.version,
          'deleted_at': change.deletedAtUtc?.toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await txn.insert('sync_cursors', {
        'account_id': _accountId, 'company_id': _companyId, 'cursor': page.nextCursor,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Map<String, dynamic> _localRecordPayload(SyncChange change) {
    final payload = change.payload;
    if (payload == null || change.entityKind != SyncEntityKind.job) {
      return payload ?? <String, dynamic>{};
    }
    final job = Job.fromJson(payload);
    return {
      ...Map<String, dynamic>.from(job.toJson()),
      'revision': change.version,
    };
  }

  Future<void> saveJob(Job job) async {
    final localJob = _syncContext == null || job.assigneeId != null
        ? job
        : Job(
            id: job.id,
            title: job.title,
            customerId: job.customerId,
            address: job.address,
            assignee: job.assignee,
            assigneeId: _syncContext!.accountId,
            startsAt: job.startsAt,
            endsAt: job.endsAt,
            status: job.status,
            instructions: job.instructions,
            quoteId: job.quoteId,
            revision: job.revision,
          );
    if (!localJob.endsAt.isAfter(localJob.startsAt)) {
      throw ArgumentError('Invalid duration');
    }
    await _db.transaction((txn) async {
      final current = await _get(txn, 'job', localJob.id);
      if (current != null &&
          (current['revision'] as int? ?? 1) != localJob.revision - 1) {
        throw StateError('Jobbet har ändrats. Öppna det igen.');
      }
      if (current != null && current['status'] == JobStatus.completed.name) {
        throw StateError('Avslutade jobb är låsta.');
      }
      if (localJob.status == JobStatus.completed) {
        final timer = await _get(txn, 'timer', 'active');
        if (timer?['jobId'] == localJob.id) {
          throw StateError('Stoppa timern innan du avslutar jobbet.');
        }
        final checks = await _jobRecords(txn, 'check', job.id);
        if (checks.any((c) => c['required'] == true && c['checked'] != true)) {
          throw StateError('Slutför obligatoriska checklistpunkter först.');
        }
      }
      final existing = await txn.query(
        'records',
        where: '$_scopeWhere AND kind = ? AND deleted_at IS NULL',
        whereArgs: [..._scopeArgs, 'job'],
      );
      if (localJob.quoteId != null) {
        if (await _get(txn, 'invoice', 'invoice-${localJob.quoteId}') != null) {
          throw StateError('Offerten har redan ett fakturautkast.');
        }
        if (existing.any((r) {
          final other = jsonDecode(r['payload'] as String) as Map;
          return other['id'] != localJob.id && other['quoteId'] == localJob.quoteId;
        })) {
          throw StateError(
            'Offerten är redan kopplad till ett jobb. Öppna det befintliga jobbet.',
          );
        }
      }
      for (final row in existing) {
        final other = Job.fromJson(
          jsonDecode(row['payload'] as String) as Map<String, dynamic>,
        );
        if (localJob.overlaps(other)) {
          throw StateError('Personen är redan bokad vid den tiden.');
        }
      }
      await _write(txn, 'job', localJob.toJson());
    });
  }

  Future<void> transitionQuote(Quote expected, QuoteStatus next) async {
    await _db.transaction((txn) async {
      final rows = await txn.query(
        'records',
        where: '$_scopeWhere AND kind = ? AND id = ? AND deleted_at IS NULL',
        whereArgs: [..._scopeArgs, 'quote', expected.id],
      );
      if (rows.length != 1) throw StateError('Offerten saknas.');
      final current = Quote.fromJson(
        jsonDecode(rows.single['payload'] as String) as Map<String, dynamic>,
      );
      if (current.revision != expected.revision) {
        throw StateError('Offerten har ändrats. Öppna den igen.');
      }
      await _write(txn, 'quote', current.transition(next).toJson());
    });
  }

  Future<void> createInvoice(Quote expected) async {
    await _db.transaction((txn) async {
      final rows = await txn.query(
        'records',
        where: '$_scopeWhere AND kind = ? AND id = ? AND deleted_at IS NULL',
        whereArgs: [..._scopeArgs, 'quote', expected.id],
      );
      if (rows.isEmpty) throw StateError('Offerten saknas.');
      final quote = Quote.fromJson(
        jsonDecode(rows.single['payload'] as String) as Map<String, dynamic>,
      );
      if (quote.status != QuoteStatus.accepted &&
          quote.status != QuoteStatus.sent) {
        throw StateError('Offerten måste vara skickad eller godkänd.');
      }
      final linkedJobs = await txn.query(
        'records',
        where: '$_scopeWhere AND kind = ? AND deleted_at IS NULL',
        whereArgs: [..._scopeArgs, 'job'],
      );
      if (linkedJobs.any(
        (r) =>
            (jsonDecode(r['payload'] as String) as Map)['quoteId'] == quote.id,
      )) {
        throw StateError(
          'Offerten är kopplad till ett jobb. Skapa underlaget från jobbet för att få med tid och material.',
        );
      }
      // Stable ID makes repeated taps idempotent, including after app restarts.
      final id = 'invoice-${quote.id}';
      final existing = await txn.query(
        'records',
        where: '$_scopeWhere AND kind = ? AND id = ? AND deleted_at IS NULL',
        whereArgs: [..._scopeArgs, 'invoice', id],
      );
      if (existing.isNotEmpty) return;
      await _write(txn, 'invoice', {
        'id': id,
        'quoteId': quote.id,
        'title': quote.title,
        'customerId': quote.customerId,
        'quoteSnapshot': quote.toJson(),
        'status': 'unpaid',
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'dueAt': DateTime.now()
            .add(const Duration(days: 30))
            .toUtc()
            .toIso8601String(),
      });
    });
  }

  Future<void> seedDemo({DateTime? at}) async {
    await _db.transaction((txn) async {
      if ((await txn.query(
        'meta',
        where: 'key = ?',
        whereArgs: [_metaKey('seeded')],
      )).isNotEmpty) {
        return;
      }
      final now = at??DateTime.now();
      for (final c in [
        {
          'id': 'anna',
          'name': 'Anna Svensson',
          'address': 'Linnégatan 24, Göteborg',
          'phone': '070-123 45 67',
          'email': 'anna@example.com',
        },
        {
          'id': 'johan',
          'name': 'Johan Berg',
          'address': 'Vasagatan 8, Göteborg',
          'phone': '070-234 56 78',
          'email': 'johan@example.com',
        },
      ]) {
        await _write(txn, 'customer', c);
      }
      for (final job in [
        Job(
          id: 'job-1',
          title: 'Byte av elcentral',
          customerId: 'anna',
          address: 'Linnégatan 24, Göteborg',
          assignee: 'Erik',
          startsAt: DateTime(now.year, now.month, now.day, 8),
          endsAt: DateTime(now.year, now.month, now.day, 11),
        ),
        Job(
          id: 'job-2',
          title: 'Felsökning och nya uttag',
          customerId: 'johan',
          address: 'Vasagatan 8, Göteborg',
          assignee: 'Nora',
          startsAt: DateTime(now.year, now.month, now.day, 13),
          endsAt: DateTime(now.year, now.month, now.day, 15),
        ),
      ]) {
        await _write(txn, 'job', job.toJson());
      }
      final quote = Quote(
        id: 'spots',
        customerId: 'anna',
        title: 'Spotlights kök',
        status: QuoteStatus.sent,
        deduction: Deduction.rot,
        lines: [
          EstimateLine(
            description: 'Elektriker, arbete',
            unitPriceOre: 65000,
            quantityMilli: 6000,
            kind: LineKind.labour,
          ),
          EstimateLine(
            description: 'LED-spotlight',
            unitPriceOre: 39500,
            quantityMilli: 6000,
            kind: LineKind.material,
          ),
        ],
      );
      await _write(txn, 'quote', quote.toJson());
      await txn.insert('meta', {'key': _metaKey('seeded'), 'value': 'true'});
    });
  }

  Future<Map<String, dynamic>?> _get(
    DatabaseExecutor db,
    String kind,
    String id,
  ) async {
    final rows = await db.query(
      'records',
      where: '$_scopeWhere AND kind = ? AND id = ? AND deleted_at IS NULL',
      whereArgs: [..._scopeArgs, kind, id],
    );
    return rows.isEmpty
        ? null
        : jsonDecode(rows.single['payload'] as String) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>?> get(String kind, String id) =>
      _get(_db, kind, id);
  Future<List<Map<String, dynamic>>> _jobRecords(
    DatabaseExecutor db,
    String kind,
    String jobId,
  ) async {
    final rows = await db.query(
      'records',
      where: '$_scopeWhere AND kind = ? AND deleted_at IS NULL',
      whereArgs: [..._scopeArgs, kind],
    );
    return rows
        .map((r) => jsonDecode(r['payload'] as String) as Map<String, dynamic>)
        .where((r) => r['jobId'] == jobId)
        .toList();
  }

  Future<List<Map<String, dynamic>>> forJob(String kind, String jobId) =>
      _jobRecords(_db, kind, jobId);
  Future<void> _requireOpenJob(Transaction txn, String id) async {
    final job = await _get(txn, 'job', id);
    if (job == null) throw StateError('Jobbet saknas.');
    if (job['status'] == JobStatus.completed.name) {
      throw StateError('Avslutade jobb är låsta.');
    }
  }

  Future<void> addJobRecord(String kind, Map<String, dynamic> value) async {
    if (!['note', 'photo', 'check'].contains(kind)) {
      throw ArgumentError('Invalid job record type');
    }
    await _db.transaction((txn) async {
      await _requireOpenJob(txn, value['jobId'] as String);
      await _write(txn, kind, value);
    });
  }

  Future<void> startTimer(String jobId, {DateTime? at}) async {
    await _db.transaction((txn) async {
      await _requireOpenJob(txn, jobId);
      if (await _get(txn, 'timer', 'active') != null) {
        throw StateError('En timer kör redan. Stoppa den först.');
      }
      final job = Job.fromJson((await _get(txn, 'job', jobId))!);
      if (job.status != JobStatus.inProgress) {
        throw StateError('Starta jobbet innan du startar timern.');
      }
      await _write(txn, 'timer', {
        'id': 'active',
        'jobId': jobId,
        'person': job.assignee,
        'startedAt': (at ?? DateTime.now()).toUtc().toIso8601String(),
      });
    });
  }

  Future<void> _checkTime(Transaction txn, TimeEntry entry) async {
    for (final r in await txn.query(
      'records',
      where: '$_scopeWhere AND kind = ? AND deleted_at IS NULL',
      whereArgs: [..._scopeArgs, 'time'],
    )) {
      final other = TimeEntry.fromJson(
        jsonDecode(r['payload'] as String) as Map<String, dynamic>,
      );
      if (entry.overlaps(other)) {
        throw StateError(
          'Tiden överlappar en annan tidrapport för samma person.',
        );
      }
    }
    final active = await _get(txn, 'timer', 'active');
    if (active != null &&
        active['person'] == entry.person &&
        entry.endedAt.isAfter(DateTime.parse(active['startedAt'] as String))) {
      throw StateError('Tiden överlappar en aktiv timer.');
    }
  }

  Future<void> saveTime(TimeEntry entry) async {
    await _db.transaction((txn) async {
      await _requireOpenJob(txn, entry.jobId);
      if (await _get(txn, 'time', entry.id) != null) {
        throw StateError('Tidrapporten finns redan.');
      }
      if (entry.endedAt.isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
        throw StateError('Tidrapporten får inte sluta i framtiden.');
      }
      await _checkTime(txn, entry);
      await _write(txn, 'time', entry.toJson());
    });
  }

  Future<void> stopTimer({
    required String expectedJobId,
    required String note,
    required int hourlyRateOre,
    required ChargeType chargeType,
    required bool approved,
    DateTime? at,
  }) async {
    await _db.transaction((txn) async {
      final timer = await _get(txn, 'timer', 'active');
      if (timer == null || timer['jobId'] != expectedJobId) {
        throw StateError('Timern har ändrats. Öppna jobbet igen.');
      }
      await _requireOpenJob(txn, expectedJobId);
      final entry = TimeEntry(
        id: const Uuid().v4(),
        jobId: expectedJobId,
        person: timer['person'] as String,
        startedAt: DateTime.parse(timer['startedAt'] as String),
        endedAt: at ?? DateTime.now(),
        hourlyRateOre: hourlyRateOre,
        note: note,
        chargeType: chargeType,
        approved: approved,
      );
      // Timer deletion and the resulting time entry are one indivisible write.
      await txn.delete(
        'records',
        where: '$_scopeWhere AND kind = ? AND id = ?',
        whereArgs: [..._scopeArgs, 'timer', 'active'],
      );
      await _checkTime(txn, entry);
      await _write(txn, 'time', entry.toJson());
      await _write(txn, 'timer', {'id': 'active', 'deleted': true});
      await txn.delete(
        'records',
        where: '$_scopeWhere AND kind = ? AND id = ?',
        whereArgs: [..._scopeArgs, 'timer', 'active'],
      );
    });
  }

  Future<void> saveMaterial(MaterialEntry entry) async {
    await _db.transaction((txn) async {
      await _requireOpenJob(txn, entry.jobId);
      if (await _get(txn, 'material', entry.id) != null) {
        throw StateError('Materialraden finns redan.');
      }
      await _write(txn, 'material', entry.toJson());
    });
  }

  Future<void> approveCharge(String kind, String id) async {
    if (!['time', 'material'].contains(kind)) {
      throw ArgumentError('Invalid charge type');
    }
    await _db.transaction((txn) async {
      final record = await _get(txn, kind, id);
      if (record == null || record['invoiceId'] != null) {
        throw StateError('Raden saknas eller är redan fakturerad.');
      }
      await _write(txn, kind, {
        ...record,
        'approved': true,
        'approvedAt': DateTime.now().toUtc().toIso8601String(),
        'approvalMethod': 'manual_internal_record',
      });
    });
  }

  Future<void> ensureCatalog() async {
    await _db.transaction((txn) async {
      if ((await txn.query(
        'meta',
        where: 'key = ?',
        whereArgs: [_metaKey('catalog-v1')],
      )).isNotEmpty) {
        return;
      }
      for (final p in [
        {
          'id': 'led',
          'name': 'LED-spotlight, dimbar',
          'unit': 'st',
          'purchasePriceOre': 24500,
          'sellingPriceOre': 39500,
        },
        {
          'id': 'dimmer',
          'name': 'Dimmer, infälld',
          'unit': 'st',
          'purchasePriceOre': 38500,
          'sellingPriceOre': 59500,
        },
        {
          'id': 'outlet',
          'name': 'Vägguttag, jordat',
          'unit': 'st',
          'purchasePriceOre': 11000,
          'sellingPriceOre': 18500,
        },
        {
          'id': 'cable',
          'name': 'Installationskabel',
          'unit': 'm',
          'purchasePriceOre': 1800,
          'sellingPriceOre': 3200,
        },
      ]) {
        await _write(txn, 'price', p);
      }
      await txn.insert('meta', {'key': _metaKey('catalog-v1'), 'value': 'true'});
    });
  }

  Future<void> ensureWorkspace(String jobId) async {
    await _db.transaction((txn) async {
      final key = 'workspace-$jobId';
      if ((await txn.query(
        'meta',
        where: 'key = ?',
        whereArgs: [_metaKey(key)],
      )).isNotEmpty) {
        return;
      }
      if (await _get(txn, 'job', jobId) == null) {
        throw StateError('Jobbet saknas.');
      }
      for (final label in [
        'Stäm av uppdrag och omfattning med kunden',
        'Dokumentera utfört arbete',
        'Informera kunden och städa arbetsplatsen',
      ]) {
        await _write(txn, 'check', {
          'id': const Uuid().v4(),
          'jobId': jobId,
          'label': label,
          'required': true,
          'checked': false,
        });
      }
      await txn.insert('meta', {'key': _metaKey(key), 'value': 'true'});
    });
  }

  Future<JobBillingPreview> billingPreview(String jobId) async {
    final data = await get('job', jobId);
    if (data == null) throw StateError('Jobbet saknas.');
    final job = Job.fromJson(data);
    final quote = job.quoteId == null ? null : await get('quote', job.quoteId!);
    return JobBillingPreview(
      time: (await forJob('time', jobId)).map(TimeEntry.fromJson).toList(),
      materials: (await forJob(
        'material',
        jobId,
      )).map(MaterialEntry.fromJson).toList(),
      quote: quote == null ? null : Quote.fromJson(quote),
    );
  }

  Future<String> createJobInvoice(String jobId) async {
    return _db.transaction((txn) async {
      final data = await _get(txn, 'job', jobId);
      if (data == null) throw StateError('Jobbet saknas.');
      final job = Job.fromJson(data);
      if (job.status != JobStatus.completed) {
        throw StateError('Avsluta jobbet innan du skapar fakturautkastet.');
      }
      final id = job.quoteId == null
          ? 'invoice-job-$jobId'
          : 'invoice-${job.quoteId}';
      if (await _get(txn, 'invoice', id) != null) return id;
      final q = job.quoteId == null
          ? null
          : await _get(txn, 'quote', job.quoteId!);
      final quote = q == null ? null : Quote.fromJson(q);
      if (job.quoteId != null &&
          (quote == null ||
              !['sent', 'accepted'].contains(quote.status.name))) {
        throw StateError(
          'Den kopplade offerten måste vara skickad eller godkänd.',
        );
      }
      final preview = JobBillingPreview(
        time: (await _jobRecords(
          txn,
          'time',
          jobId,
        )).map(TimeEntry.fromJson).toList(),
        materials: (await _jobRecords(
          txn,
          'material',
          jobId,
        )).map(MaterialEntry.fromJson).toList(),
        quote: quote,
      );
      if (preview.pendingApproval > 0) {
        throw StateError(
          'Registrera godkännande av tilläggen före fakturering.',
        );
      }
      if (preview.lines.isEmpty) {
        throw StateError('Det finns inget att fakturera.');
      }
      final snapshot = Quote(
        id: 'job-$jobId',
        customerId: job.customerId,
        title: job.title,
        lines: preview.lines,
        deduction: preview.deduction,
      );
      await _write(txn, 'invoice', {
        'id': id,
        'jobId': jobId,
        'quoteId': job.quoteId,
        'title': job.title,
        'customerId': job.customerId,
        'quoteSnapshot': snapshot.toJson(),
        'sourceQuoteSnapshot': quote?.toJson(),
        'sourceTimeIds': preview.timeIds,
        'sourceMaterialIds': preview.materialIds,
        'status': 'unpaid',
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'dueAt': DateTime.now()
            .add(const Duration(days: 30))
            .toUtc()
            .toIso8601String(),
      });
      for (final kind in ['time', 'material']) {
        final ids = kind == 'time' ? preview.timeIds : preview.materialIds;
        for (final entryId in ids) {
          final entry = (await _get(txn, kind, entryId))!;
          await _write(txn, kind, {...entry, 'invoiceId': id});
        }
      }
      return id;
    });
  }

  Future<void> close() => _db.close();
}
