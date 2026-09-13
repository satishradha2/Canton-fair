import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class ReminderService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static final ValueNotifier<String?> selectedPayload = ValueNotifier(null);
  static bool _ready = false;

  static Future<void> initialize() async {
    if (_ready) return;
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.UTC);

    const AndroidInitializationSettings android =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const InitializationSettings settings =
        InitializationSettings(android: android, iOS: ios);

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        selectedPayload.value = response.payload;
      },
    );

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'followup_channel',
      'Follow-up reminders',
      description: 'Alerts for supplier follow-up meetings',
      importance: Importance.high,
      playSound: true,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      selectedPayload.value = launch?.notificationResponse?.payload;
    }
    _ready = true;
  }

  static Future<bool> requestPermissions() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final notifications = await android?.requestNotificationsPermission();
    if (await android?.canScheduleExactNotifications() == false) {
      await android?.requestExactAlarmsPermission();
    }
    return notifications ?? true;
  }

  static Future<void> scheduleFollowUp({
    required int id,
    required String title,
    required String body,
    required DateTime at,
    String? payload,
  }) async {
    if (at.isBefore(DateTime.now())) return;
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    final canScheduleExactly =
        await android?.canScheduleExactNotifications() ?? true;
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(at.toUtc(), tz.UTC),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'followup_channel',
          'Follow-up reminders',
          channelDescription: 'Alerts for supplier follow-up meetings',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(presentSound: true, presentAlert: true),
      ),
      androidScheduleMode: canScheduleExactly
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: null,
      payload: payload ?? 'followup:$id',
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  static Future<void> cancel(int id) async {
    await _plugin.cancel(id);
  }

  static Future<void> showTeamUpdate({
    required String title,
    required String body,
  }) async {
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(2147483647),
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'followup_channel',
          'Follow-up reminders',
          channelDescription: 'Supplier tasks and team workspace updates',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(presentSound: true, presentAlert: true),
      ),
    );
  }
}
