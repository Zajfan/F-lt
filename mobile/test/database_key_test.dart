import 'package:falt/data/database_key.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('database key is generated once and reused', () async {
    final storage = MemoryDatabaseKeyStorage();
    final provider = DatabaseKeyProvider(storage: storage);

    final first = await provider.loadOrCreate();
    final second = await provider.loadOrCreate();

    expect(first, second);
    expect(first.length, greaterThanOrEqualTo(40));
    expect(storage.value, first);
  });
}
