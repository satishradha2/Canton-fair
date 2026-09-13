import 'package:supabase_flutter/supabase_flutter.dart';

class CloudHealthCheck {
  const CloudHealthCheck(this.name, this.ok, this.detail);

  final String name;
  final bool ok;
  final String detail;
}

class CloudHealthService {
  SupabaseClient get _client => Supabase.instance.client;

  Future<List<CloudHealthCheck>> run() async {
    final checks = <CloudHealthCheck>[];
    checks.add(CloudHealthCheck(
      'Authentication',
      _client.auth.currentSession != null,
      _client.auth.currentSession == null
          ? 'Sign in again before using cloud features.'
          : 'Signed-in session is available.',
    ));

    await _check(checks, 'Database schema', () async {
      final value = await _client.rpc('canton_fair_health');
      final data = Map<String, dynamic>.from(value as Map);
      final version = data['schema_version'] as int? ?? 0;
      if (version < 17) {
        throw StateError('Schema $version; version 17 required.');
      }
      return 'Schema version $version is ready.';
    });
    await _check(checks, 'Team access', () async {
      await _client.from('team_members').select('team_id').limit(1);
      await _client.from('team_records').select('record_id').limit(1);
      return 'Team membership and record tables are reachable.';
    });
    await _check(checks, 'Attachment storage', () async {
      await _client.storage
          .from('team-attachments')
          .list(searchOptions: const SearchOptions(limit: 1));
      return 'Private attachment bucket is reachable.';
    });
    for (final function in const ['card-ai', 'meeting-ai', 'external-share']) {
      await _check(checks, 'Function: $function', () async {
        final response = await _client.functions.invoke(
          function,
          body: const {'action': 'health'},
        );
        final data = response.data;
        if (data is! Map || data['ok'] != true) {
          throw StateError('Unexpected health response.');
        }
        return 'Deployed and responding.';
      });
    }
    return checks;
  }

  Future<void> _check(
    List<CloudHealthCheck> checks,
    String name,
    Future<String> Function() operation,
  ) async {
    try {
      checks.add(CloudHealthCheck(name, true, await operation()));
    } catch (error) {
      checks.add(CloudHealthCheck(name, false, _friendly(error)));
    }
  }

  String _friendly(Object error) {
    final value = error.toString();
    if (value.contains('canton_fair_health')) {
      return 'Apply SQL migration 017_cloud_health.sql.';
    }
    if (value.contains('FunctionException') || value.contains('404')) {
      return 'Deploy this Edge Function from the repository.';
    }
    return value.replaceFirst(RegExp(r'^(Exception|StateError):\s*'), '');
  }
}
