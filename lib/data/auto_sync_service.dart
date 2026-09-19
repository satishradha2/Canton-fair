import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'cloud_sync_service.dart';
import 'reminder_service.dart';
import 'team_workspace_service.dart';
import 'background_sync_service.dart';

class AutoSyncService with WidgetsBindingObserver {
  AutoSyncService._();

  static final AutoSyncService instance = AutoSyncService._();
  static final changes = ValueNotifier<int>(0);

  static const _enabledKey = 'automatic_sync_enabled';
  final _storage = const FlutterSecureStorage();
  final _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  RealtimeChannel? _teamChannel;
  Timer? _timer;
  bool _started = false;
  bool _syncing = false;
  DateTime? lastAttemptAt;
  String? lastError;

  Future<bool> get enabled async =>
      (await _storage.read(key: _enabledKey)) != 'false';

  Future<void> setEnabled(bool value) async {
    await _storage.write(key: _enabledKey, value: value.toString());
    await BackgroundSyncService.setEnabled(value);
    changes.value++;
    if (value) unawaited(syncIfPossible());
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    TeamWorkspaceService.changes.addListener(_workspaceChanged);
    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen((results) {
      if (!results.contains(ConnectivityResult.none)) {
        unawaited(syncIfPossible());
      }
    });
    _timer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => unawaited(syncIfPossible()),
    );
    unawaited(_subscribeToTeam());
    unawaited(syncIfPossible());
  }

  Future<void> stop() async {
    WidgetsBinding.instance.removeObserver(this);
    TeamWorkspaceService.changes.removeListener(_workspaceChanged);
    await _connectivitySubscription?.cancel();
    if (_teamChannel != null) {
      await Supabase.instance.client.removeChannel(_teamChannel!);
      _teamChannel = null;
    }
    _timer?.cancel();
    _started = false;
  }

  void _workspaceChanged() => unawaited(_subscribeToTeam());

  Future<void> _subscribeToTeam() async {
    final user = Supabase.instance.client.auth.currentUser;
    final team = user == null ? null : await TeamWorkspaceService().load();
    if (user == null || team == null) return;
    if (_teamChannel != null) {
      await Supabase.instance.client.removeChannel(_teamChannel!);
    }
    _teamChannel = Supabase.instance.client
        .channel('team-updates-${team.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'team_records',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'team_id',
            value: team.id,
          ),
          callback: (payload) {
            final changedBy = payload.newRecord['updated_by']?.toString();
            if (changedBy == user.id) return;
            unawaited(_handleTeamChange());
          },
        )
        .subscribe();
  }

  Future<void> _handleTeamChange() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    await syncIfPossible();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(syncIfPossible());
  }

  Future<void> syncIfPossible() async {
    if (_syncing ||
        TeamWorkspaceService.isOperationInProgress ||
        !await enabled) {
      return;
    }
    if (Supabase.instance.client.auth.currentUser == null) return;
    if (await TeamWorkspaceService().load() == null) return;
    final connectivity = await _connectivity.checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) return;

    _syncing = true;
    lastAttemptAt = DateTime.now();
    lastError = null;
    changes.value++;
    try {
      final result =
          await CloudSyncService().syncTeamWorkspace(showBusy: false);
      if (result.downloaded > 0) {
        await ReminderService.showTeamUpdate(
          title: 'Team workspace updated',
          body: '${result.downloaded} new or changed records downloaded.',
        );
      }
    } catch (error) {
      lastError = error.toString();
    } finally {
      _syncing = false;
      changes.value++;
    }
  }
}
