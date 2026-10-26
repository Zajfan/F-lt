import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

abstract interface class DeviceIdentityStorage {
  Future<String?> read();
  Future<void> write(String value);
}

class MemoryDeviceIdentityStorage implements DeviceIdentityStorage {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    this.value = value;
  }
}

class DeviceIdentity {
  DeviceIdentity({required DeviceIdentityStorage storage}) : _storage = storage;

  factory DeviceIdentity.production() => DeviceIdentity(
        storage: _FileDeviceIdentityStorage(),
      );

  final DeviceIdentityStorage _storage;

  Future<String> load() async {
    final stored = await _storage.read();
    if (stored != null && _uuidPattern.hasMatch(stored)) return stored;
    final generated = const Uuid().v4();
    await _storage.write(generated);
    return generated;
  }
}

class _FileDeviceIdentityStorage implements DeviceIdentityStorage {
  static const _fileName = '.falt-device-id';

  Future<File> _file() async {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    return File('${directory.path}/$_fileName');
  }

  @override
  Future<String?> read() async {
    final file = await _file();
    if (!await file.exists()) return null;
    final value = (await file.readAsString()).trim();
    return value.isEmpty ? null : value;
  }

  @override
  Future<void> write(String value) async {
    await (await _file()).writeAsString(value);
  }
}

final _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
);
