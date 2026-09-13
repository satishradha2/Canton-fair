import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

import 'cloud_sync_service.dart';
import 'team_workspace_service.dart';

const _backgroundSyncUniqueName = 'canton-fair-cloud-sync';
const _backgroundSyncTask = 'sync-team-workspace';

@pragma('vm:entry-point')
void cantonFairBackgroundDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != _backgroundSyncTask) return true;
    const url = String.fromEnvironment('SUPABASE_URL');
    const key = String.fromEnvironment('SUPABASE_ANON_KEY');
    if (url.isEmpty || key.isEmpty) return false;
    try {
      WidgetsFlutterBinding.ensureInitialized();
      await Supabase.initialize(url: url, publishableKey: key);
      if (Supabase.instance.client.auth.currentUser == null) return true;
      if (await TeamWorkspaceService().load() == null) return true;
      await CloudSyncService().syncTeamWorkspace();
      return true;
    } catch (_) {
      return false;
    }
  });
}

class BackgroundSyncService {
  static Future<void> initialize({required bool enabled}) async {
    await Workmanager().initialize(cantonFairBackgroundDispatcher);
    await setEnabled(enabled);
  }

  static Future<void> setEnabled(bool enabled) async {
    if (!enabled) {
      await Workmanager().cancelByUniqueName(_backgroundSyncUniqueName);
      return;
    }
    await Workmanager().registerPeriodicTask(
      _backgroundSyncUniqueName,
      _backgroundSyncTask,
      frequency: const Duration(minutes: 30),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 15),
    );
  }
}
