import 'package:supabase_flutter/supabase_flutter.dart';

class MeetingAiService {
  static Future<String> createMinutes({
    required String supplier,
    required String notes,
  }) async {
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'meeting-ai',
        body: {'supplier': supplier, 'notes': notes},
      ).timeout(const Duration(seconds: 70));
      final data = Map<String, dynamic>.from(response.data as Map);
      if (response.status != 200 || data['minutes'] is! String) {
        throw StateError('Meeting AI is unavailable.');
      }
      return data['minutes'] as String;
    } on FunctionException catch (error) {
      final details = error.details;
      throw StateError(details is Map && details['error'] is String
          ? details['error'] as String
          : 'Meeting AI is not deployed.');
    }
  }
}
