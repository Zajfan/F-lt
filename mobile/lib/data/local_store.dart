import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../domain/estimate.dart';
import '../domain/job.dart';
import '../domain/work_log.dart';

/// Single-device evaluation store. Not a multi-user sync implementation.
/// Business writes and their outbox records commit atomically.
class LocalStore {
  LocalStore._(this._db);
  final Database _db;
  static Future<LocalStore> open({
    DatabaseFactory? factory,
    String? databasePath,
  }) async {
    final selectedFactory = factory ?? databaseFactory;
    final db = await selectedFactory.openDatabase(
      databasePath ??
          path.join(await selectedFactory.getDatabasesPath(), 'falt.db'),
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE records (kind TEXT NOT NULL, id TEXT NOT NULL, payload TEXT NOT NULL, PRIMARY KEY(kind,id))',
          );
          await db.execute(
            'CREATE TABLE outbox (id TEXT PRIMARY KEY, kind TEXT NOT NULL, entity_id TEXT NOT NULL, payload TEXT NOT NULL, created_at TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
        },
      ),
    );
    return LocalStore._(db);
  }

  Future<List<Map<String, dynamic>>> list(String kind) async =>
      (await _db.query('records', where: 'kind = ?', whereArgs: [kind]))
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
    await txn.insert('records', {
      'kind': kind,
      'id': value['id'],
      'payload': payload,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await txn.insert('outbox', {
      'id': const Uuid().v4(),
      'kind': kind,
      'entity_id': value['id'],
      'payload': payload,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> put(String kind, Map<String, dynamic> value) =>
      _db.transaction((txn) => _write(txn, kind, value));
  Future<int> get pendingCount async =>
      Sqflite.firstIntValue(
        await _db.rawQuery('SELECT COUNT(*) FROM outbox'),
      ) ??
      0;

  Future<void> saveJob(Job job) async {
    if (!job.endsAt.isAfter(job.startsAt)) {
      throw ArgumentError('Invalid duration');
    }
    await _db.transaction((txn) async {
      final current = await _get(txn, 'job', job.id);
      if (current != null &&
          (current['revision'] as int? ?? 1) != job.revision - 1) {
        throw StateError('Jobbet har ändrats. Öppna det igen.');
      }
      if (current != null && current['status'] == JobStatus.completed.name) {
        throw StateError('Avslutade jobb är låsta.');
      }
      if (job.status == JobStatus.completed) {
        final timer = await _get(txn, 'timer', 'active');
        if (timer?['jobId'] == job.id) {
          throw StateError('Stoppa timern innan du avslutar jobbet.');
        }
        final checks = await _jobRecords(txn, 'check', job.id);
        if (checks.any((c) => c['required'] == true && c['checked'] != true)) {
          throw StateError('Slutför obligatoriska checklistpunkter först.');
        }
      }
      final existing = await txn.query(
        'records',
        where: 'kind = ?',
        whereArgs: ['job'],
      );
      if (job.quoteId != null) {
        if (await _get(txn, 'invoice', 'invoice-${job.quoteId}') != null) {
          throw StateError('Offerten har redan ett fakturautkast.');
        }
        if (existing.any((r) {
          final other = jsonDecode(r['payload'] as String) as Map;
          return other['id'] != job.id && other['quoteId'] == job.quoteId;
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
        if (job.overlaps(other)) {
          throw StateError('Personen är redan bokad vid den tiden.');
        }
      }
      await _write(txn, 'job', job.toJson());
    });
  }

  Future<void> transitionQuote(Quote expected, QuoteStatus next) async {
    await _db.transaction((txn) async {
      final rows = await txn.query(
        'records',
        where: 'kind = ? AND id = ?',
        whereArgs: ['quote', expected.id],
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
        where: 'kind = ? AND id = ?',
        whereArgs: ['quote', expected.id],
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
        where: 'kind = ?',
        whereArgs: ['job'],
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
        where: 'kind = ? AND id = ?',
        whereArgs: ['invoice', id],
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
        whereArgs: ['seeded'],
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
      await txn.insert('meta', {'key': 'seeded', 'value': 'true'});
    });
  }

  Future<Map<String, dynamic>?> _get(
    DatabaseExecutor db,
    String kind,
    String id,
  ) async {
    final rows = await db.query(
      'records',
      where: 'kind = ? AND id = ?',
      whereArgs: [kind, id],
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
      where: 'kind = ?',
      whereArgs: [kind],
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
      where: 'kind = ?',
      whereArgs: ['time'],
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
        where: 'kind = ? AND id = ?',
        whereArgs: ['timer', 'active'],
      );
      await _checkTime(txn, entry);
      await _write(txn, 'time', entry.toJson());
      await _write(txn, 'timer', {'id': 'active', 'deleted': true});
      await txn.delete(
        'records',
        where: 'kind = ? AND id = ?',
        whereArgs: ['timer', 'active'],
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
        whereArgs: ['catalog-v1'],
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
      await txn.insert('meta', {'key': 'catalog-v1', 'value': 'true'});
    });
  }

  Future<void> ensureWorkspace(String jobId) async {
    await _db.transaction((txn) async {
      final key = 'workspace-$jobId';
      if ((await txn.query(
        'meta',
        where: 'key = ?',
        whereArgs: [key],
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
      await txn.insert('meta', {'key': key, 'value': 'true'});
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
