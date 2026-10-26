import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../domain/estimate.dart';
import '../domain/job.dart';

/// Single-device evaluation store. Not a multi-user sync implementation.
/// Business writes and their outbox records commit atomically.
class LocalStore {
  LocalStore._(this._db);
  final Database _db;
  static Future<LocalStore> open() async {
    final db = await openDatabase(path.join(await getDatabasesPath(), 'falt.db'),
      version: 1, onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      }, onCreate: (db, version) async {
        await db.execute('CREATE TABLE records (kind TEXT NOT NULL, id TEXT NOT NULL, payload TEXT NOT NULL, PRIMARY KEY(kind,id))');
        await db.execute('CREATE TABLE outbox (id TEXT PRIMARY KEY, kind TEXT NOT NULL, entity_id TEXT NOT NULL, payload TEXT NOT NULL, created_at TEXT NOT NULL)');
        await db.execute('CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
      });
    return LocalStore._(db);
  }
  Future<List<Map<String, dynamic>>> list(String kind) async =>
    (await _db.query('records', where: 'kind = ?', whereArgs: [kind]))
      .map((row) => jsonDecode(row['payload'] as String) as Map<String, dynamic>).toList();
  Future<void> _write(Transaction txn, String kind, Map<String, dynamic> value) async {
    final payload = jsonEncode(value);
    await txn.insert('records', {'kind': kind, 'id': value['id'], 'payload': payload},
      conflictAlgorithm: ConflictAlgorithm.replace);
    await txn.insert('outbox', {'id': const Uuid().v4(), 'kind': kind,
      'entity_id': value['id'], 'payload': payload,
      'created_at': DateTime.now().toUtc().toIso8601String()});
  }
  Future<void> put(String kind, Map<String, dynamic> value) =>
    _db.transaction((txn) => _write(txn, kind, value));
  Future<int> get pendingCount async => Sqflite.firstIntValue(
    await _db.rawQuery('SELECT COUNT(*) FROM outbox')) ?? 0;

  Future<void> saveJob(Job job) async {
    if (!job.endsAt.isAfter(job.startsAt)) throw ArgumentError('Invalid duration');
    await _db.transaction((txn) async {
      final existing = await txn.query('records', where: 'kind = ?', whereArgs: ['job']);
      for (final row in existing) {
        final other = Job.fromJson(jsonDecode(row['payload'] as String) as Map<String, dynamic>);
        if (job.overlaps(other)) throw StateError('Personen är redan bokad vid den tiden.');
      }
      await _write(txn, 'job', job.toJson());
    });
  }
  Future<void> transitionQuote(Quote expected, QuoteStatus next) async {
    await _db.transaction((txn) async {
      final rows = await txn.query('records', where: 'kind = ? AND id = ?',
        whereArgs: ['quote', expected.id]);
      if (rows.length != 1) throw StateError('Offerten saknas.');
      final current = Quote.fromJson(jsonDecode(rows.single['payload'] as String) as Map<String, dynamic>);
      if (current.revision != expected.revision) throw StateError('Offerten har ändrats. Öppna den igen.');
      await _write(txn, 'quote', current.transition(next).toJson());
    });
  }
  Future<void> createInvoice(Quote expected) async {
    await _db.transaction((txn) async {
      final rows = await txn.query('records', where: 'kind = ? AND id = ?',
        whereArgs: ['quote', expected.id]);
      if (rows.isEmpty) throw StateError('Offerten saknas.');
      final quote = Quote.fromJson(jsonDecode(rows.single['payload'] as String) as Map<String, dynamic>);
      if (quote.status != QuoteStatus.accepted && quote.status != QuoteStatus.sent) {
        throw StateError('Offerten måste vara skickad eller godkänd.');
      }
      // Stable ID makes repeated taps idempotent, including after app restarts.
      final id = 'invoice-${quote.id}';
      final existing = await txn.query('records', where: 'kind = ? AND id = ?',
        whereArgs: ['invoice', id]);
      if (existing.isNotEmpty) return;
      await _write(txn, 'invoice', {'id': id, 'quoteId': quote.id,
        'title': quote.title, 'customerId': quote.customerId,
        'quoteSnapshot': quote.toJson(), 'status': 'unpaid',
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'dueAt': DateTime.now().add(const Duration(days: 30)).toUtc().toIso8601String()});
    });
  }
  Future<void> seedDemo() async {
    await _db.transaction((txn) async {
      if ((await txn.query('meta', where: 'key = ?', whereArgs: ['seeded'])).isNotEmpty) return;
      final now = DateTime.now();
      for (final c in [
        {'id':'anna','name':'Anna Svensson','address':'Linnégatan 24, Göteborg','phone':'070-123 45 67','email':'anna@example.com'},
        {'id':'johan','name':'Johan Berg','address':'Vasagatan 8, Göteborg','phone':'070-234 56 78','email':'johan@example.com'},
      ]) { await _write(txn, 'customer', c); }
      for (final job in [
        Job(id:'job-1',title:'Byte av elcentral',customerId:'anna',address:'Linnégatan 24, Göteborg',assignee:'Erik',startsAt:DateTime(now.year,now.month,now.day,8),endsAt:DateTime(now.year,now.month,now.day,11)),
        Job(id:'job-2',title:'Felsökning och nya uttag',customerId:'johan',address:'Vasagatan 8, Göteborg',assignee:'Nora',startsAt:DateTime(now.year,now.month,now.day,13),endsAt:DateTime(now.year,now.month,now.day,15)),
      ]) { await _write(txn, 'job', job.toJson()); }
      final quote = Quote(id:'spots',customerId:'anna',title:'Spotlights kök',
        status:QuoteStatus.sent,deduction:Deduction.rot,lines:[
          EstimateLine(description:'Elektriker, arbete',unitPriceOre:65000,quantityMilli:6000,kind:LineKind.labour),
          EstimateLine(description:'LED-spotlight',unitPriceOre:39500,quantityMilli:6000,kind:LineKind.material),
        ]);
      await _write(txn, 'quote', quote.toJson());
      await txn.insert('meta', {'key':'seeded','value':'true'});
    });
  }
  Future<void> close() => _db.close();
}
