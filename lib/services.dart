import 'dart:math';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'store.dart';

/// Notificaciones (temporizador y recordatorios) y sonido de alarma.
class Services {
  static final _np = FlutterLocalNotificationsPlugin();
  static AudioPlayer? _player;
  static Uint8List? _wavBytes;
  static bool ready = false;

  static Future<void> init() async {
    try {
      tzdata.initializeTimeZones();
      await _np.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
      final a = _np.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await a?.requestNotificationsPermission();
      ready = true;
    } catch (_) {
      ready = false;
    }
  }

  /// Sonido de alarma generado por código (3 pitidos). No requiere archivos de audio.
  static Uint8List _wav() {
    const sr = 22050;
    final samples = <int>[];
    const beepLen = (sr * 0.22) ~/ 1;
    const gapLen = (sr * 0.12) ~/ 1;
    for (var b = 0; b < 3; b++) {
      for (var i = 0; i < beepLen; i++) {
        final t = i / sr;
        final env = i < 200 ? i / 200 : (i > beepLen - 400 ? (beepLen - i) / 400 : 1.0);
        samples.add((sin(2 * pi * 988 * t) * env * 0.85 * 32767).round());
      }
      for (var i = 0; i < gapLen; i++) {
        samples.add(0);
      }
    }
    final data = ByteData(44 + samples.length * 2);
    void str(int o, String s) {
      for (var i = 0; i < s.length; i++) {
        data.setUint8(o + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    data.setUint32(4, 36 + samples.length * 2, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, sr, Endian.little);
    data.setUint32(28, sr * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    str(36, 'data');
    data.setUint32(40, samples.length * 2, Endian.little);
    for (var i = 0; i < samples.length; i++) {
      data.setInt16(44 + i * 2, samples[i], Endian.little);
    }
    return data.buffer.asUint8List();
  }

  /// Suena la alarma con la app abierta (y vibra).
  static Future<void> beep() async {
    try {
      HapticFeedback.vibrate();
      _wavBytes ??= _wav();
      _player ??= AudioPlayer();
      await _player!.stop();
      await _player!.play(BytesSource(_wavBytes!));
    } catch (_) {}
  }

  static NotificationDetails _details(String channel, String name, {bool alarm = false}) => NotificationDetails(
        android: AndroidNotificationDetails(channel, name,
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            category: alarm ? AndroidNotificationCategory.alarm : AndroidNotificationCategory.reminder,
            audioAttributesUsage: alarm ? AudioAttributesUsage.alarm : AudioAttributesUsage.notification),
      );

  /// Notificación programada para cuando termine el descanso (funciona con la pantalla apagada).
  static Future<void> scheduleRest(DateTime at) async {
    if (!ready) return;
    final when = tz.TZDateTime.from(at.add(const Duration(seconds: 1)), tz.UTC);
    try {
      await _np.zonedSchedule(1, 'GYMSHERONSO', '¡Descanso terminado! Hora de la siguiente serie 💪', when,
          _details('rest_v1', 'Temporizador de descanso', alarm: true),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime);
    } catch (_) {
      try {
        await _np.zonedSchedule(1, 'GYMSHERONSO', '¡Descanso terminado! Hora de la siguiente serie 💪', when,
            _details('rest_v1', 'Temporizador de descanso', alarm: true),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime);
      } catch (_) {}
    }
  }

  static Future<void> cancelRest() async {
    if (!ready) return;
    try {
      await _np.cancel(1);
    } catch (_) {}
  }

  /// Recordatorios semanales: si el lunes a las 20:00 hiciste "Día de pecho",
  /// el siguiente lunes se avisa 5 horas antes (15:00) de que hoy toca "Día de pecho".
  static Future<void> scheduleReminders(AppStore s) async {
    if (!ready) return;
    try {
      for (var i = 0; i < 60; i++) {
        await _np.cancel(1000 + i);
      }
      if (!s.remindersOn) return;
      final now = DateTime.now();
      final seen = <String>{};
      var n = 0;
      final recent = s.sessions.where((x) => !x.demo && now.difference(x.start).inDays <= 30).toList()
        ..sort((a, b) => b.start.compareTo(a.start));
      for (final x in recent) {
        final key = '${x.userId}|${x.name}|${x.start.weekday}';
        if (!seen.add(key) || n >= 55) continue;
        var next = x.start.add(const Duration(days: 7));
        while (next.subtract(const Duration(hours: 5)).isBefore(now)) {
          next = next.add(const Duration(days: 7));
        }
        final at = next.subtract(const Duration(hours: 5));
        final who = s.users.length > 1 ? ' (${s.users.firstWhere((u) => u.id == x.userId, orElse: () => s.users.first).name})' : '';
        final hh = x.start.hour.toString().padLeft(2, '0');
        final mm = x.start.minute.toString().padLeft(2, '0');
        await _np.zonedSchedule(1000 + n, 'GYMSHERONSO', 'Hoy toca: ${x.name}$who · a las $hh:$mm', tz.TZDateTime.from(at, tz.UTC),
            _details('reminders_v1', 'Recordatorios de entrenamiento'),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
            matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime);
        n++;
      }
    } catch (_) {}
  }
}
