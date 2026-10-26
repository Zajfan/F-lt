import 'sync_models.dart';

abstract interface class SyncTransport {
  Future<SyncPushResult> push(SyncOperation operation);

  Future<SyncPullPage> pull({required int afterCursor, int limit = 100});
}

abstract class SyncTransportException implements Exception {
  const SyncTransportException(this.message);

  final String message;

  bool get isRetryable => false;

  @override
  String toString() => '$runtimeType: $message';
}

final class SyncTransientException extends SyncTransportException {
  const SyncTransientException(super.message);

  @override
  bool get isRetryable => true;
}

final class SyncValidationException extends SyncTransportException {
  const SyncValidationException(super.message);
}

final class SyncAuthorizationException extends SyncTransportException {
  const SyncAuthorizationException(super.message);
}

final class SyncProtocolException extends SyncTransportException {
  const SyncProtocolException(super.message);
}
