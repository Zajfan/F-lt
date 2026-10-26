import 'package:falt/sync/background_sync.dart';
import 'package:falt/sync/sync_engine.dart';
import 'package:falt/sync/sync_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final clean = SyncRunResult(
    pushed: 0,
    pulled: 0,
    conflictCount: 0,
    retryCount: 0,
    failedCount: 0,
    finalCursor: 0,
  );

  SyncRunResult result(SyncTransportException error) => SyncRunResult(
    pushed: 0,
    pulled: 0,
    conflictCount: 0,
    retryCount: 0,
    failedCount: 1,
    finalCursor: 0,
    errors: [error],
  );

  test('background work retries only transient sync errors', () {
    expect(shouldRetryBackgroundSync(clean), isFalse);
    expect(shouldRetryBackgroundSync(result(const SyncTransientException('offline'))), isTrue);
    expect(shouldRetryBackgroundSync(result(const SyncValidationException('manual action'))), isFalse);
    expect(shouldRetryBackgroundSync(result(const SyncAuthorizationException('manual action'))), isFalse);
    expect(shouldRetryBackgroundSync(result(const SyncProtocolException('invalid response'))), isFalse);
  });
}
