import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class DatabaseKeyStorage {
  Future<String?> read();
  Future<void> write(String value);
}

class MemoryDatabaseKeyStorage implements DatabaseKeyStorage {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    this.value = value;
  }
}

class SecureDatabaseKeyStorage implements DatabaseKeyStorage {
  SecureDatabaseKeyStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'falt.database.key.v1';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);
}

class DatabaseKeyProvider {
  DatabaseKeyProvider({required DatabaseKeyStorage storage}) : _storage = storage;

  factory DatabaseKeyProvider.production() => DatabaseKeyProvider(
        storage: SecureDatabaseKeyStorage(),
      );

  final DatabaseKeyStorage _storage;

  Future<String> loadOrCreate() async {
    final existing = await _storage.read();
    if (existing != null && existing.length >= 40) return existing;

    final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    final generated = base64Url.encode(bytes).replaceAll('=', '');
    await _storage.write(generated);
    return generated;
  }
}
