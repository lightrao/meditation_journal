import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter/foundation.dart'; // For kIsWeb

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const int dailyReminderId = 0; // Unique ID for the daily reminder

  Future<void> init() async {
    if (kIsWeb) {
      // Notifications not supported on web
      return;
    }

    // Initialize timezone database
    tz.initializeTimeZones();
    // TODO: Set the local location. This might need adjustment based on how
    // you want to handle timezones across the app. For now, using local.
    // tz.setLocalLocation(tz.getLocation('America/Detroit')); // Example

    // Android Initialization Settings
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher'); // Use default app icon

    // iOS Initialization Settings
    final DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestAlertPermission: false, // Request permissions separately
      requestBadgePermission: false,
      requestSoundPermission: false,
      onDidReceiveLocalNotification: onDidReceiveLocalNotification,
    );

    // Linux Initialization Settings (Optional, add if needed)
    // final LinuxInitializationSettings initializationSettingsLinux =
    //     LinuxInitializationSettings(
    //         defaultActionName: 'Open notification');

    final InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
      // linux: initializationSettingsLinux,
    );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: onDidReceiveNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
  }

  // Callback for when a notification is received while the app is in the foreground (iOS only)
  void onDidReceiveLocalNotification(
      int id, String? title, String? body, String? payload) async {
    // display a dialog with the notification details, tap ok to go to another page
    // This is typically less relevant now with onDidReceiveNotificationResponse
    print('Foreground notification received (iOS): id=$id, title=$title, body=$body, payload=$payload');
  }

  // Callback for when a user taps a notification (foreground or background)
  void onDidReceiveNotificationResponse(NotificationResponse notificationResponse) async {
    final String? payload = notificationResponse.payload;
    if (notificationResponse.payload != null) {
      debugPrint('notification payload: $payload');
    }
    // Handle notification tap action here, e.g., navigate to a specific screen
    // For now, just print
    print('Notification tapped: id=${notificationResponse.id}, payload=$payload');
    // Example: await Navigator.push(context, MaterialPageRoute<void>(builder: (context) => SecondScreen(payload)));
  }

  // Callback for when a user taps a notification that launches the app from terminated state
  static void notificationTapBackground(NotificationResponse notificationResponse) {
    // handle action
    print('Notification tapped (background): id=${notificationResponse.id}, payload=${notificationResponse.payload}');
  }

  Future<bool> requestPermissions() async {
    if (kIsWeb) return false;

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final bool? result = await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
      return result ?? false;
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
          flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      final bool? result = await androidImplementation?.requestNotificationsPermission();
      return result ?? false;
    }
    // Add other platforms if needed (macOS, Linux)
    return false; // Default to false if platform not handled
  }


  Future<void> scheduleDailyReminder(TimeOfDay time) async {
     if (kIsWeb) return;
    await cancelDailyReminder(); // Cancel previous before scheduling new

    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'daily_reminder_channel', // id
      'Daily Reminders', // title
      channelDescription: 'Channel for daily meditation reminders', // description
      importance: Importance.max,
      priority: Priority.high,
      showWhen: false, // Don't show timestamp
      // sound: RawResourceAndroidNotificationSound('notification_sound'), // Optional custom sound
      // styleInformation: BigTextStyleInformation(''), // Optional expanded text
    );
    const DarwinNotificationDetails iOSPlatformChannelSpecifics =
        DarwinNotificationDetails(
            // presentAlert: true, // Present an alert when the notification is triggered while the app is in the foreground.
            // presentBadge: true, // Present the badge number when the notification is triggered while the app is in the foreground.
            // presentSound: true, // Play a sound when the notification is triggered while the app is in the foreground.
            // sound: 'notification_sound.aiff', // Optional custom sound
            // badgeNumber: 1, // Optional badge number
            // attachments: <DarwinNotificationAttachment>[], // Optional attachments
            );
    // const LinuxNotificationDetails linuxPlatformChannelSpecifics =
    //     LinuxNotificationDetails(); // Optional Linux specifics

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: iOSPlatformChannelSpecifics,
      // linux: linuxPlatformChannelSpecifics,
    );

    final tz.TZDateTime scheduledTime = _nextInstanceOfTime(time);

    print('Scheduling daily reminder for: $scheduledTime');

    await flutterLocalNotificationsPlugin.zonedSchedule(
      dailyReminderId, // Use the constant ID
      'Meditation Reminder',
      'Time for your daily meditation session!',
      scheduledTime,
      platformChannelSpecifics,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time, // Match only time daily
      payload: 'daily_reminder', // Optional payload
    );
     print('Daily reminder scheduled successfully.');
  }

  Future<void> cancelDailyReminder() async {
     if (kIsWeb) return;
    await flutterLocalNotificationsPlugin.cancel(dailyReminderId);
    print('Cancelled daily reminder (if any).');
  }

  tz.TZDateTime _nextInstanceOfTime(TimeOfDay time) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate = tz.TZDateTime(
        tz.local, now.year, now.month, now.day, time.hour, time.minute);
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }

}