import 'dart:async';

import '../data/local_store.dart';
import 'sync_models.dart';
import 'sync_transport.dart';

class SyncRunResult {
  SyncRunResult({
    required this.pushed,
    required this.pulled,
    required this.conflictCount,
    required this.retryCount,
    required this.failedCount,
    required this.finalCursor,
    Iterable<SyncTransportException> errors = const [],
  }) : errors = List<SyncTransportException>.unmodifiable(errors);

  final int pushed;
  final int pulled;
  final int conflictCount;
  final int retryCount;
  final int failedCount;
  final int finalCursor;
  final List<SyncTransportException> errors;

  int get pushedCount => pushed;
  int get pulledCount => pulled;
  int get protocolErrorCount =>
      errors.whereType<SyncProtocolException>().length;
}

class SyncEngine {
  SyncEngine({required LocalStore store, required SyncTransport transport})
      : _store = store,
        _transport = transport;

  static const _maxPushAttempts = 50;

  static const _retryDelays = <Duration>[
    Duration(seconds: 5),
    Duration(seconds: 30),
    Duration(minutes: 5),
    Duration(minutes: 30),
    Duration(hours: 2),
  ];

  // LocalStore has no public failed-status mutation, so this date makes a
  // retained operation ineligible while leaving its error visible for a UI.
  static final _ineligibleAtUtc = DateTime.utc(9999, 12, 31, 23, 59, 59);

  final LocalStore _store;
  final SyncTransport _transport;

  Future<SyncRunResult> runOnce() async {
    var pushed = 0;
    var pulled = 0;
    var conflictCount = 0;
    var retryCount = 0;
    var failedCount = 0;
    var pushBlocked = false;
    var pushAttempts = 0;
    final attemptedOperationIds = <String>{};
    final errors = <SyncTransportException>[];

    while (pushAttempts < _maxPushAttempts) {
      // Re-read the current outbox after every result. Acknowledgement can
      // rebase later operations for the same entity, so a preloaded batch
      // could contain stale expected versions.
      final pending = await _store.pendingOperations(limit: _maxPushAttempts);
      SyncOperation? selected;
      for (final candidate in pending) {
        if (!attemptedOperationIds.contains(candidate.operationId)) {
          selected = candidate;
          break;
        }
      }
      if (selected == null) break;

      final operation = selected;
      attemptedOperationIds.add(operation.operationId);
      pushAttempts++;
      SyncPushResult result;
      try {
        result = await _transport.push(operation);
      } on SyncTransientException catch (error) {
        errors.add(error);
        pushBlocked = true;
        if (operation.attemptCount >= _retryDelays.length) {
          await _makeIneligible(operation, error.message);
          failedCount++;
        } else {
          await _store.scheduleRetry(
            operation.operationId,
            nextAttemptAtUtc: DateTime.now().toUtc().add(
              _retryDelays[operation.attemptCount],
            ),
            error: error.message,
          );
          retryCount++;
        }
        continue;
      } on TimeoutException catch (error) {
        final transient = SyncTransientException(error.message ?? 'timeout');
        errors.add(transient);
        pushBlocked = true;
        if (operation.attemptCount >= _retryDelays.length) {
          await _makeIneligible(operation, transient.message);
          failedCount++;
        } else {
          await _store.scheduleRetry(
            operation.operationId,
            nextAttemptAtUtc: DateTime.now().toUtc().add(
              _retryDelays[operation.attemptCount],
            ),
            error: transient.message,
          );
          retryCount++;
        }
        continue;
      } on SyncValidationException catch (error) {
        errors.add(error);
        pushBlocked = true;
        await _makeIneligible(operation, error.message);
        failedCount++;
        continue;
      } on SyncAuthorizationException catch (error) {
        errors.add(error);
        pushBlocked = true;
        await _makeIneligible(operation, error.message);
        failedCount++;
        continue;
      } on SyncProtocolException catch (error) {
        errors.add(error);
        pushBlocked = true;
        continue;
      } catch (error) {
        final transient = SyncTransientException(error.toString());
        errors.add(transient);
        pushBlocked = true;
        if (operation.attemptCount >= _retryDelays.length) {
          await _makeIneligible(operation, transient.message);
          failedCount++;
        } else {
          await _store.scheduleRetry(
            operation.operationId,
            nextAttemptAtUtc: DateTime.now().toUtc().add(
              _retryDelays[operation.attemptCount],
            ),
            error: transient.message,
          );
          retryCount++;
        }
        continue;
      }

      pushed++;
      try {
        switch (result.status) {
          case SyncPushStatus.accepted:
            await _acknowledge(operation, result);
            break;
          case SyncPushStatus.duplicate:
            await _acknowledge(operation, result);
            break;
          case SyncPushStatus.conflict:
            final version = result.version;
            if (version == null) {
              const protocolError = SyncProtocolException(
                'Push conflict result omitted server version.',
              );
              errors.add(protocolError);
              pushBlocked = true;
              await _makeIneligible(operation, protocolError.message);
              failedCount++;
              break;
            }
            await _store.recordConflict(
              SyncConflict(
                operation: operation,
                serverVersion: version,
                serverPayload: result.current,
                detectedAtUtc: DateTime.now().toUtc(),
              ),
            );
            conflictCount++;
            break;
          case SyncPushStatus.rejected:
            final error = SyncValidationException(
              'The server rejected operation ${operation.operationId}.',
            );
            errors.add(error);
            pushBlocked = true;
            await _makeIneligible(operation, error.message);
            failedCount++;
            break;
        }
      } on SyncProtocolException catch (error) {
        errors.add(error);
        pushBlocked = true;
      }
    }

    var cursor = await _store.syncCursor();
    if (!pushBlocked) {
      try {
        final page = await _transport.pull(afterCursor: cursor, limit: 100);
        // An empty page at the current cursor is a legitimate no-op. In
        // particular, never invent a cursor advance for it.
        if (page.changes.isNotEmpty || page.nextCursor > cursor) {
          await _store.applyPullPage(page);
          pulled = page.changes.length;
          cursor = await _store.syncCursor();
        }
      } on SyncTransportException catch (error) {
        errors.add(error);
      } on TimeoutException catch (error) {
        errors.add(SyncTransientException(error.message ?? 'timeout'));
      }
    }

    return SyncRunResult(
      pushed: pushed,
      pulled: pulled,
      conflictCount: conflictCount,
      retryCount: retryCount,
      failedCount: failedCount,
      finalCursor: cursor,
      errors: errors,
    );
  }

  Future<void> _makeIneligible(
    SyncOperation operation,
    String error,
  ) =>
      _store.scheduleRetry(
        operation.operationId,
        nextAttemptAtUtc: _ineligibleAtUtc,
        error: 'User action required: $error',
      );

  Future<void> _acknowledge(
    SyncOperation operation,
    SyncPushResult result,
  ) async {
    final version = result.version;
    if (version == null) {
      throw SyncProtocolException(
        'Push ${result.status.name} result omitted version.',
      );
    }
    try {
      await _store.acknowledgeOperation(
        operation.operationId,
        acceptedVersion: version,
      );
    } on ArgumentError catch (error) {
      throw SyncProtocolException(error.message.toString());
    }
  }
}
