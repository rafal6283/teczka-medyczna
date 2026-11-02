import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'db.dart';
import 'meds.dart';

/// Codzienne przypomnienia o dawkach leków (o godzinach z listy leków).
class MedNotify {
  static final _p = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static const _base = 5000;
  static const _details = NotificationDetails(
    android: AndroidNotificationDetails('leki', 'Leki', channelDescription: 'Przypomnienia o dawkach leków', importance: Importance.high),
    iOS: DarwinNotificationDetails(),
  );

  static Future<void> init() async {
    if (_ready) return;
    try {
      tzdata.initializeTimeZones();
      var name = 'Europe/Warsaw';
      try {
        name = await FlutterTimezone.getLocalTimezone();
      } catch (_) {}
      try {
        tz.setLocalLocation(tz.getLocation(name));
      } catch (_) {
        tz.setLocalLocation(tz.getLocation('Europe/Warsaw'));
      }
      await _p.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
      ));
      _ready = true;
    } catch (e) {
      debugPrint('Powiadomienia: $e');
    }
  }

  static Future<bool> requestPermission() async {
    await init();
    final a = _p.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (a != null) return await a.requestNotificationsPermission() ?? false;
    final i = _p.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (i != null) return await i.requestPermissions(alert: true, sound: true) ?? false;
    return false;
  }

  /// Przelicza przypomnienia od nowa: jedno powiadomienie dziennie na godzinę dawki (leki z tej godziny razem).
  static Future<void> reschedule() async {
    await init();
    if (!_ready) return;
    try {
      for (var i = 0; i < 64; i++) {
        await _p.cancel(_base + i);
      }
      final profiles = {for (final p in await AppDb.I.getProfiles()) p.id: p.name};
      final byTime = <String, List<String>>{};
      for (final m in await AppDb.I.allActiveMeds()) {
        if (!m.remind) continue;
        for (final t in m.times) {
          final who = profiles.length > 1 ? ' (${profiles[m.profileId] ?? ''})' : '';
          (byTime[t] ??= []).add('${m.name}${m.dose.isEmpty ? '' : ' ${m.dose}'}$who');
        }
      }
      var id = _base;
      final now = tz.TZDateTime.now(tz.local);
      for (final e in (byTime.entries.toList()..sort((a, b) => a.key.compareTo(b.key))).take(60)) {
        final hm = e.key.split(':');
        var when = tz.TZDateTime(tz.local, now.year, now.month, now.day, int.parse(hm[0]), int.parse(hm[1]));
        if (when.isBefore(now)) when = when.add(const Duration(days: 1));
        await _p.zonedSchedule(id++, 'Leki – ${e.key}', e.value.join(', '), when, _details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle, matchDateTimeComponents: DateTimeComponents.time);
      }
    } catch (e) {
      debugPrint('Przypomnienia o lekach: $e');
    }
  }
}
