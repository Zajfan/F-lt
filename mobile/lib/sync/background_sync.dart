import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

import '../config/app_config.dart';
import '../data/local_store.dart';
import 'supabase_sync_transport.dart';
import 'sync_context.dart';
import 'sync_engine.dart';

const faltBackgroundSyncTask = 'falt.background.sync';

bool shouldRetryBackgroundSync(SyncRunResult result) =>
    result.errors.any((error) => error.isRetryable);

@pragma('vm:entry-point')
void faltBackgroundTaskDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != faltBackgroundSyncTask) return true;

    try {
      WidgetsFlutterBinding.ensureInitialized();
      DartPluginRegistrant.ensureInitialized();
      final config = AppConfig.fromEnvironment();
      if (!config.isLive) return true;

      await Supabase.initialize(
        url: config.supabaseUrl,
        publishableKey: config.publishableKey,
      );
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      final companyId = inputData?['company_id'];
      final deviceId = inputData?['device_id'];
      if (user == null || companyId is! String || deviceId is! String) {
        return true;
      }

      final store = await LocalStore.open(
        syncContext: SyncContext(
          accountId: user.id,
          companyId: companyId,
          deviceId: deviceId,
        ),
      );
      try {
        final result = await SyncEngine(
          store: store,
          transport: SupabaseSyncTransport(
            client: client,
            companyId: companyId,
          ),
        ).runOnce();
        return !shouldRetryBackgroundSync(result);
      } finally {
        await store.close();
      }
    } catch (_) {
      // Returning false lets WorkManager retry with its platform backoff.
      return false;
    }
  });
}

class BackgroundSyncScheduler {
  BackgroundSyncScheduler({Workmanager? workmanager})
      : _workmanager = workmanager ?? Workmanager();

  static const frequency = Duration(minutes: 15);
  static const _uniquePrefix = 'falt-company-sync-';

  final Workmanager _workmanager;
  Future<void>? _initialized;

  Future<void> initialize() {
    return _initialized ??= _workmanager.initialize(
          faltBackgroundTaskDispatcher,
        );
  }

  Future<void> schedule({
    required String accountId,
    required String companyId,
    required String deviceId,
  }) async {
    await initialize();
    await _workmanager.registerPeriodicTask(
      uniqueName(companyId),
      faltBackgroundSyncTask,
      frequency: frequency,
      constraints: Constraints(networkType: NetworkType.connected),
      inputData: <String, dynamic>{
        'account_id': accountId,
        'company_id': companyId,
        'device_id': deviceId,
      },
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 5),
    );
  }

  Future<void> cancel(String companyId) async {
    await initialize();
    await _workmanager.cancelByUniqueName(uniqueName(companyId));
  }

  static String uniqueName(String companyId) => '$_uniquePrefix$companyId';
}
