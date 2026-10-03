import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'cloud_sync_service.dart';
import 'reminder_service.dart';
import 'team_workspace_service.dart';
import 'background_sync_service.dart';
import 'phone_cleanup_service.dart';
import 'database.dart';

class AutoSyncService with WidgetsBindingObserver {
  AutoSyncService._();

  static final AutoSyncService instance = AutoSyncService._();
  static final changes = ValueNotifier<int>(0);

  static const _enabledKey = 'automatic_sync_enabled';
  final _storage = const FlutterSecureStorage();
  final _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  StreamSubscription<AuthState>? _authSubscription;
  RealtimeChannel? _teamChannel;
  Timer? _timer;
  bool _started = false;
  bool _syncing = false;
  bool _checking = false;
  String? _revisionScope;
  int _syncedRevision = -1;
  int _failures = 0;
  DateTime? _retryAt;
  DateTime? lastAttemptAt;
  String? lastError;

  Future<bool> get enabled async =>
      (await _storage.read(key: _enabledKey)) != 'false';

  Future<void> setEnabled(bool value) async {
    await _storage.write(key: _enabledKey, value: value.toString());
    await BackgroundSyncService.setEnabled(value);
    changes.value++;
    if (value) unawaited(syncIfPossible(force: true));
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    TeamWorkspaceService.changes.addListener(_workspaceChanged);
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      _workspaceChanged();
    });
    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen((results) {
      if (!results.contains(ConnectivityResult.none)) {
        unawaited(syncIfPossible(force: true));
      }
    });
    _timer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(syncIfPossible()),
    );
    unawaited(_subscribeToTeam());
    unawaited(syncIfPossible());
  }

  Future<void> stop() async {
    WidgetsBinding.instance.removeObserver(this);
    TeamWorkspaceService.changes.removeListener(_workspaceChanged);
    await _connectivitySubscription?.cancel();
    await _authSubscription?.cancel();
    if (_teamChannel != null) {
      await Supabase.instance.client.removeChannel(_teamChannel!);
      _teamChannel = null;
    }
    _timer?.cancel();
    _started = false;
  }

  void _workspaceChanged() {
    _revisionScope = null;
    _syncedRevision = -1;
    _retryAt = null;
    unawaited(_subscribeToTeam());
    unawaited(syncIfPossible(force: true));
  }

  Future<void> _subscribeToTeam() async {
    final user = Supabase.instance.client.auth.currentUser;
    final team = user == null ? null : await TeamWorkspaceService().load();
    if (_teamChannel != null) {
      await Supabase.instance.client.removeChannel(_teamChannel!);
      _teamChannel = null;
    }
    if (user == null || team == null) return;
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
    await syncIfPossible(force: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(syncIfPossible(force: true));
    }
  }

  Future<void> syncIfPossible({bool force = false}) async {
    if (_syncing || _checking || TeamWorkspaceService.isOperationInProgress) {
      return;
    }
    _checking = true;
    try {
      if (!await enabled || Supabase.instance.client.auth.currentUser == null) return;
      final workspace = TeamWorkspaceService();
      if (await workspace.load() == null) return;
      final scope = await workspace.scopeKey();
      if (await PhoneCleanupService.paused(scope)) return;
      if (!force && _retryAt != null && DateTime.now().isBefore(_retryAt!)) return;
      final connectivity = await _connectivity.checkConnectivity();
      if (connectivity.contains(ConnectivityResult.none)) return;
      final revision = await TradeDatabase.instance.localChangeRevision();
      if (_revisionScope != scope) {
        _revisionScope = scope;
        _syncedRevision = -1;
      }
      if (!force && revision == _syncedRevision) return;
      if (TeamWorkspaceService.isOperationInProgress || scope != await workspace.scopeKey()) return;
      _syncing = true;
      lastAttemptAt = DateTime.now();
      lastError = null;
      changes.value++;
      final result =
          await CloudSyncService().syncTeamWorkspace(showBusy: false);
      // Capture the revision BEFORE sync: a concurrent save must get another pass.
      if (scope == await workspace.scopeKey()) _syncedRevision = revision;
      _failures = 0;
      _retryAt = null;
      if (result.downloaded > 0) {
        await ReminderService.showTeamUpdate(
          title: 'Team workspace updated',
          body: '${result.downloaded} new or changed records downloaded.',
        );
      }
    } catch (error) {
      lastError = error.toString();
      _failures = (_failures + 1).clamp(1, 5).toInt();
      _retryAt = DateTime.now().add(Duration(seconds: 5 * (1 << _failures)));
    } finally {
      _checking = false;
      final attempted = _syncing;
      _syncing = false;
      if (attempted) changes.value++;
    }
  }
}
