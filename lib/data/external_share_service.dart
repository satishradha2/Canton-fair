import 'package:supabase_flutter/supabase_flutter.dart';

import 'team_workspace_service.dart';

class ExternalShareService {
  const ExternalShareService();

  Future<Uri> create({
    required String mode,
    required String title,
    required Map<String, Object?> payload,
    required Duration validity,
  }) async {
    final team = await TeamWorkspaceService().load();
    if (team == null) {
      throw StateError('Choose a cloud team before creating an external link.');
    }
    final response = await Supabase.instance.client.functions.invoke(
      'external-share',
      body: {
        'action': 'create',
        'team_id': team.id,
        'mode': mode,
        'title': title,
        'payload': payload,
        'expires_in_hours': validity.inHours,
      },
    );
    final data = Map<String, dynamic>.from(response.data as Map);
    final value = data['url']?.toString();
    if (response.status != 200 || value == null) {
      throw StateError(data['error']?.toString() ??
          'Secure sharing is not deployed for this workspace.');
    }
    return Uri.parse(value);
  }

  Future<List<Map<String, dynamic>>> responses() async {
    final team = await TeamWorkspaceService().load();
    if (team == null) {
      throw StateError('Choose a cloud team before checking responses.');
    }
    final response = await Supabase.instance.client.functions.invoke(
      'external-share',
      body: {'action': 'responses', 'team_id': team.id},
    );
    final data = Map<String, dynamic>.from(response.data as Map);
    if (response.status != 200) {
      throw StateError(
          data['error']?.toString() ?? 'Could not load responses.');
    }
    return (data['responses'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }
}
