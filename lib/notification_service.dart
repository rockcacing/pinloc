import 'package:flutter/cupertino.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  Future<void> init({onSelect}) async {
    notification = FlutterLocalNotificationsPlugin();

    await notification.initialize(
        InitializationSettings(
          android: AndroidInitializationSettings('app_icon'),
          iOS: IOSInitializationSettings(),
        ), onSelectNotification: (value) {
      print('NOTIFICATION: $value');
      onSelect(value!.split(','));
    });
  }

  late FlutterLocalNotificationsPlugin notification;

  static const CHANNEL_ID = 'PINLOC';
  static const CHANNEL_NAME = 'PINLOC';
  static const androidSpec = AndroidNotificationDetails(
    CHANNEL_ID,
    CHANNEL_NAME,
    importance: Importance.high,
    priority: Priority.high,
  );
  static const iOSSpec = IOSNotificationDetails();
  static const plateformSpec = NotificationDetails(
    android: androidSpec,
    iOS: iOSSpec,
  );

  Future show(id, title, body, payload) async {
    return notification.show(
      id,
      title,
      body,
      plateformSpec,
      payload: payload,
    );
  }

  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() {
    return _instance;
  }

  NotificationService._internal();
}
