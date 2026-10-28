import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'models.dart';
import 'services.dart';
import 'stats.dart';

/// Capa de datos: persistencia local en JSON, borrador de entrenamiento,
/// temporizador de descanso, copias de seguridad y exportación.
class AppStore extends ChangeNotifier {
  late Directory dir;
  late File _file;
  Future<void> _q = Future.value();
  String? lastError;

  List<AppUser> users = [];
  List<Exercise> exercises = [];
  List<Session> sessions = [];
  List<Routine> routines = [];
  List<BodyMetric> metrics = [];
  Session? draft;
  String activeUserId = '';

  int palette = 0;
  bool dark = true, amoled = false, remindersOn = true;
  double radius = 16;
  DateTime? lastBackup;

  // Temporizador de descanso
  DateTime? restEndsAt;
  Session? restSession;
  int restExercise = -1, restSetIndex = -1;
  Timer? _ticker;
  final ValueNotifier<int> restLeftN = ValueNotifier(0);

  AppUser get user => users.firstWhere((u) => u.id == activeUserId, orElse: () => users.first);
  List<Session> get mySessions => sessions.where((s) => s.userId == activeUserId).toList();
  List<Routine> get myRoutines => routines.where((r) => r.userId == activeUserId).toList();
  List<BodyMetric> get myMetrics =>
      metrics.where((m) => m.userId == activeUserId).toList()..sort((a, b) => a.date.compareTo(b.date));
  Map<String, Exercise> get exMap => {for (final e in exercises) e.id: e};
  String exName(String id) => exMap[id]?.name ?? 'Ejercicio eliminado';
  String get unit => user.unit;
  double toDisp(double kg) => user.unit == 'lb' ? kg * 2.20462 : kg;
  double fromDisp(double v) => user.unit == 'lb' ? v / 2.20462 : v;
  String fmtW(double kg) => fmtNum(toDisp(kg), 1);

  // ---------------------------------------------------------------- carga/guardado
  Future<void> load({Directory? overrideDir}) async {
    dir = overrideDir ?? await _docsDir();
    _file = File('${dir.path}/gymsheronso.json');
    try {
      if (await _file.exists()) {
        _fromMap(jsonDecode(await _file.readAsString()));
      }
    } catch (e) {
      lastError = 'No se pudo leer la base de datos ($e). Se conservó una copia del archivo dañado.';
      try {
        await _file.copy('${dir.path}/gymsheronso_dañado_${DateTime.now().millisecondsSinceEpoch}.json');
      } catch (_) {}
    }
    if (users.isEmpty) {
      users.add(AppUser(id: uid(), name: 'Usuario 1'));
    }
    if (!users.any((u) => u.id == activeUserId)) activeUserId = users.first.id;
    if (exercises.isEmpty) _seedExercises();
    try {
      await autoBackup();
    } catch (_) {}
    changed();
  }

  Future<Directory> _docsDir() => getApplicationDocumentsDirectory();

  Map<String, dynamic> _toMap() => {
        'version': 1,
        'activeUserId': activeUserId,
        'users': users.map((e) => e.toJson()).toList(),
        'exercises': exercises.map((e) => e.toJson()).toList(),
        'sessions': sessions.map((e) => e.toJson()).toList(),
        'routines': routines.map((e) => e.toJson()).toList(),
        'metrics': metrics.map((e) => e.toJson()).toList(),
        'draft': draft?.toJson(),
        'settings': {
          'palette': palette,
          'dark': dark,
          'amoled': amoled,
          'radius': radius,
          'remindersOn': remindersOn,
          'lastBackup': lastBackup?.toIso8601String(),
        },
      };

  /// Valida y carga; si el formato es inválido lanza excepción sin tocar el estado actual.
  void _fromMap(dynamic raw) {
    if (raw is! Map) throw const FormatException('Formato de respaldo inválido');
    final m = Map<String, dynamic>.from(raw);
    List<T> list<T>(String k, T Function(Map<String, dynamic>) f) =>
        ((m[k] ?? []) as List).map((e) => f(Map<String, dynamic>.from(e as Map))).toList();
    final u = list('users', AppUser.fromJson);
    final e = list('exercises', Exercise.fromJson);
    final s = list('sessions', Session.fromJson);
    final r = list('routines', Routine.fromJson);
    final b = list('metrics', BodyMetric.fromJson);
    final d = m['draft'] == null ? null : Session.fromJson(Map<String, dynamic>.from(m['draft'] as Map));
    final st = Map<String, dynamic>.from((m['settings'] ?? {}) as Map);
    users = u;
    exercises = e;
    sessions = s;
    routines = r;
    metrics = b;
    draft = d;
    activeUserId = (m['activeUserId'] as String?) ?? (u.isNotEmpty ? u.first.id : '');
    palette = (st['palette'] as num?)?.toInt() ?? 0;
    dark = st['dark'] != false;
    amoled = st['amoled'] == true;
    radius = (st['radius'] as num?)?.toDouble() ?? 16;
    remindersOn = st['remindersOn'] != false;
    lastBackup = st['lastBackup'] == null ? null : DateTime.tryParse(st['lastBackup'] as String);
    if (users.isEmpty) users.add(AppUser(id: uid(), name: 'Usuario 1'));
    if (!users.any((x) => x.id == activeUserId)) activeUserId = users.first.id;
  }

  Future<void> _write(String json) async {
    try {
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(json, flush: true);
      await tmp.rename(_file.path);
    } catch (e) {
      lastError = 'Error al guardar los datos: $e';
    }
  }

  /// Guarda sin notificar a la interfaz (p. ej. al escribir una nota).
  void touch() {
    final json = jsonEncode(_toMap());
    _q = _q.then((_) => _write(json));
  }

  void changed() {
    touch();
    notifyListeners();
  }

  /// Espera a que terminen las escrituras pendientes (útil en pruebas).
  Future<void> flush() => _q;

  // ---------------------------------------------------------------- usuarios
  AppUser addUser(String name) {
    final u = AppUser(id: uid(), name: name.trim().isEmpty ? 'Usuario ${users.length + 1}' : name.trim());
    users.add(u);
    activeUserId = u.id;
    changed();
    return u;
  }

  bool deleteUser(String id) {
    if (users.length <= 1) return false;
    users.removeWhere((u) => u.id == id);
    sessions.removeWhere((s) => s.userId == id);
    routines.removeWhere((r) => r.userId == id);
    metrics.removeWhere((m) => m.userId == id);
    if (draft?.userId == id) draft = null;
    if (activeUserId == id) activeUserId = users.first.id;
    changed();
    Services.scheduleReminders(this);
    return true;
  }

  void setActive(String id) {
    activeUserId = id;
    changed();
  }

  Future<void> setPhoto(AppUser u, String srcPath) async {
    final dst = '${dir.path}/photo_${u.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(srcPath).copy(dst);
    final old = u.photo;
    u.photo = dst;
    if (old != null) {
      try {
        await File(old).delete();
      } catch (_) {}
    }
    changed();
  }

  // ---------------------------------------------------------------- ejercicios y rutinas
  Exercise addExercise(String name, String muscle) {
    final e = Exercise(id: uid(), name: name.trim(), muscle: muscle);
    exercises.add(e);
    changed();
    return e;
  }

  List<String> recentExerciseIds({int max = 8}) {
    final out = <String>[];
    for (final s in mySessions..sort((a, b) => b.start.compareTo(a.start))) {
      for (final e in s.exercises) {
        if (!out.contains(e.exerciseId)) out.add(e.exerciseId);
      }
      if (out.length >= max) break;
    }
    return out.take(max).toList();
  }

  void addRoutine(String name, List<String> ids) {
    routines.add(Routine(id: uid(), userId: activeUserId, name: name.trim(), exerciseIds: ids));
    changed();
  }

  void deleteRoutine(String id) {
    routines.removeWhere((r) => r.id == id);
    changed();
  }

  // ---------------------------------------------------------------- entrenamiento
  WorkoutExercise buildExercise(String exId, String userId, {String? excludeId}) {
    final last = Stats.lastSets(sessions, exId, userId, excludeId: excludeId);
    final sets = (last ?? [SetEntry(reps: 10)])
        .map((s) => SetEntry(weight: s.weight, reps: s.reps, type: s.type == 'warmup' ? 'normal' : s.type))
        .toList();
    return WorkoutExercise(exerciseId: exId, sets: sets);
  }

  Session startWorkout([Routine? r]) {
    final s = Session(id: uid(), userId: activeUserId, name: r?.name ?? 'Entrenamiento', start: DateTime.now());
    if (r != null) {
      for (final id in r.exerciseIds) {
        if (exMap.containsKey(id)) s.exercises.add(buildExercise(id, s.userId));
      }
    }
    draft = s;
    changed();
    return s;
  }

  void _clean(Session d) {
    for (final e in d.exercises) {
      e.sets.removeWhere((s) => !s.done);
    }
    d.exercises.removeWhere((e) => e.sets.isEmpty);
  }

  void finishDraft() {
    final d = draft;
    if (d == null) return;
    _clean(d);
    cancelRest();
    if (d.exercises.isNotEmpty) {
      d.end = DateTime.now();
      sessions.add(d);
    }
    draft = null;
    changed();
    Services.scheduleReminders(this);
  }

  void discardDraft() {
    cancelRest();
    draft = null;
    changed();
  }

  /// Al salir de editar una sesión guardada: quita series sin completar; si queda vacía se elimina.
  void cleanEdited(Session s) {
    _clean(s);
    if (s.exercises.isEmpty) sessions.removeWhere((x) => x.id == s.id);
    changed();
    Services.scheduleReminders(this);
  }

  void deleteSession(String id) {
    sessions.removeWhere((s) => s.id == id);
    changed();
    Services.scheduleReminders(this);
  }

  String lastText(String exId, Session cur) {
    final l = Stats.lastSets(sessions, exId, cur.userId, excludeId: cur.id);
    if (l == null) return 'Primera vez con este ejercicio';
    final same = l.every((x) => x.weight == l.first.weight && x.reps == l.first.reps);
    if (same) return 'Última vez: ${l.length}×${l.first.reps} con ${fmtW(l.first.weight)} $unit';
    return 'Última vez: ${l.map((x) => '${fmtW(x.weight)}×${x.reps}').join(', ')} $unit';
  }

  /// Devuelve 'peso' o '1RM estimado' si la serie supera el récord previo del usuario.
  String? checkPr(Session s, WorkoutExercise we, SetEntry st) {
    if (st.type == 'warmup' || st.reps <= 0) return null;
    final b = Stats.bestBefore(sessions, s.userId, we.exerciseId, excludeId: s.id);
    if (b.weight == 0 && b.e1rm == 0) return null; // sin historial previo
    var bw = b.weight, be = b.e1rm;
    for (final x in s.exercises) {
      if (x.exerciseId != we.exerciseId) continue;
      for (final y in x.sets) {
        if (!identical(y, st) && y.counts) {
          bw = max(bw, y.weight);
          be = max(be, epley(y.weight, y.reps));
        }
      }
    }
    if (st.weight > 0 && st.weight > bw + 1e-9) return 'peso';
    if (epley(st.weight, st.reps) > be + 1e-9) return '1RM estimado';
    return null;
  }

  // ---------------------------------------------------------------- temporizador de descanso
  void startRest(Session s, int exIndex, int setIndex, int seconds) {
    restSession = s;
    restExercise = exIndex;
    restSetIndex = setIndex;
    restEndsAt = DateTime.now().add(Duration(seconds: seconds));
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) => tick());
    Services.scheduleRest(restEndsAt!);
    tick();
    notifyListeners();
  }

  int get restLeft {
    final e = restEndsAt;
    if (e == null) return 0;
    return max(0, (e.difference(DateTime.now()).inMilliseconds / 1000).ceil());
  }

  void tick() {
    if (restEndsAt == null) return;
    if (!DateTime.now().isBefore(restEndsAt!)) {
      finishRest();
    } else {
      restLeftN.value = restLeft;
    }
  }

  void addRest(int seconds) {
    if (restEndsAt == null) return;
    restEndsAt = restEndsAt!.add(Duration(seconds: seconds));
    Services.scheduleRest(restEndsAt!);
    tick();
  }

  /// Termina el descanso: suena la alarma y añade automáticamente la siguiente serie.
  void finishRest({bool silent = false}) {
    final s = restSession, i = restExercise, k = restSetIndex;
    _clearRest();
    Services.cancelRest();
    if (!silent) Services.beep();
    if (s != null && i >= 0 && i < s.exercises.length) {
      final sets = s.exercises[i].sets;
      if (sets.isNotEmpty && k == sets.length - 1) {
        final l = sets[k];
        sets.add(SetEntry(weight: l.weight, reps: l.reps, type: l.type == 'warmup' ? 'normal' : l.type));
      }
    }
    changed();
  }

  void cancelRest() {
    if (restEndsAt == null) return;
    _clearRest();
    Services.cancelRest();
    notifyListeners();
  }

  void _clearRest() {
    _ticker?.cancel();
    _ticker = null;
    restEndsAt = null;
    restSession = null;
    restExercise = -1;
    restSetIndex = -1;
    restLeftN.value = 0;
  }

  // ---------------------------------------------------------------- medidas corporales
  void addMetric(BodyMetric m) {
    metrics.add(m);
    changed();
  }

  void deleteMetric(String id) {
    metrics.removeWhere((m) => m.id == id);
    changed();
  }

  // ---------------------------------------------------------------- respaldos
  String exportJson() => const JsonEncoder.withIndent('  ').convert(_toMap());

  Future<File> writeBackupFile() async {
    final t = DateTime.now();
    final stamp =
        '${t.year}${t.month.toString().padLeft(2, '0')}${t.day.toString().padLeft(2, '0')}_${t.hour.toString().padLeft(2, '0')}${t.minute.toString().padLeft(2, '0')}';
    final f = File('${dir.path}/gymsheronso_respaldo_$stamp.json');
    await f.writeAsString(exportJson(), flush: true);
    return f;
  }

  /// Reemplaza todos los datos por los del respaldo. Lanza excepción si el archivo es inválido.
  void importJson(String text) {
    _fromMap(jsonDecode(text));
    if (exercises.isEmpty) _seedExercises();
    cancelRest();
    changed();
    Services.scheduleReminders(this);
  }

  /// Copia automática cada 7 días en /backups (se conservan las 5 últimas).
  Future<void> autoBackup() async {
    final now = DateTime.now();
    if (lastBackup != null && now.difference(lastBackup!).inDays < 7) return;
    if (sessions.isEmpty) return;
    final bd = Directory('${dir.path}/backups');
    if (!await bd.exists()) await bd.create(recursive: true);
    final stamp = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    await File('${bd.path}/auto_$stamp.json').writeAsString(exportJson(), flush: true);
    final files = (await bd.list().toList()).whereType<File>().toList()..sort((a, b) => a.path.compareTo(b.path));
    while (files.length > 5) {
      await files.removeAt(0).delete();
    }
    lastBackup = now;
  }

  Future<File> exportXlsx() async {
    final x = Excel.createExcel();
    x.rename('Sheet1', 'Series');
    final sh = x['Series'];
    TextCellValue t(String s) => TextCellValue(s);
    sh.appendRow([
      t('Fecha'), t('Usuario'), t('Sesión'), t('Ejercicio'), t('Grupo'), t('Serie'), t('Tipo'),
      t('Peso (kg)'), t('Reps'), t('RPE'), t('1RM estimado (kg)'), t('Nota')
    ]);
    final ex = exMap;
    final sorted = [...sessions]..sort((a, b) => a.start.compareTo(b.start));
    for (final s in sorted) {
      final uname = users.firstWhere((u) => u.id == s.userId, orElse: () => users.first).name;
      for (final we in s.exercises) {
        for (var i = 0; i < we.sets.length; i++) {
          final st = we.sets[i];
          if (!st.done) continue;
          sh.appendRow([
            t(s.start.toIso8601String().substring(0, 16).replaceFirst('T', ' ')),
            t(uname),
            t(s.name),
            t(ex[we.exerciseId]?.name ?? '?'),
            t(ex[we.exerciseId]?.muscle ?? '?'),
            IntCellValue(i + 1),
            t(setTypes[st.type] ?? st.type),
            DoubleCellValue(st.weight),
            IntCellValue(st.reps),
            st.rpe == null ? t('') : DoubleCellValue(st.rpe!),
            DoubleCellValue(double.parse(epley(st.weight, st.reps).toStringAsFixed(1))),
            t(we.note),
          ]);
        }
      }
    }
    final mt = x['Medidas'];
    mt.appendRow([t('Fecha'), t('Usuario'), t('Peso (kg)'), t('% grasa'), t('Cintura (cm)'), t('Brazo (cm)')]);
    for (final m in [...metrics]..sort((a, b) => a.date.compareTo(b.date))) {
      final uname = users.firstWhere((u) => u.id == m.userId, orElse: () => users.first).name;
      mt.appendRow([
        t(m.date.toIso8601String().substring(0, 10)),
        t(uname),
        m.weight == null ? t('') : DoubleCellValue(m.weight!),
        m.fat == null ? t('') : DoubleCellValue(m.fat!),
        m.waist == null ? t('') : DoubleCellValue(m.waist!),
        m.arm == null ? t('') : DoubleCellValue(m.arm!),
      ]);
    }
    final bytes = x.save();
    if (bytes == null) throw Exception('No se pudo generar el archivo Excel');
    final f = File('${dir.path}/gymsheronso_datos.xlsx');
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  // ---------------------------------------------------------------- datos de demostración
  void loadDemo() {
    removeDemo();
    final now = DateTime.now();
    final plans = <String, List<String>>{
      'DEMO · Día de pecho': ['Press banca', 'Press inclinado con mancuernas', 'Aperturas en polea'],
      'DEMO · Día de espalda': ['Dominadas', 'Remo con barra', 'Curl con barra'],
      'DEMO · Día de pierna': ['Sentadilla', 'Prensa', 'Peso muerto rumano'],
    };
    final names = plans.keys.toList();
    final byName = {for (final e in exercises) e.name: e};
    var n = 0;
    for (var d = 21; d >= 1; d -= 2) {
      final key = names[n % 3];
      n++;
      final date = DateTime(now.year, now.month, now.day - d, 20, 0);
      final s = Session(id: uid(), userId: activeUserId, name: key, start: date, end: date.add(const Duration(hours: 1)), demo: true);
      for (final exName in plans[key]!) {
        final ex = byName[exName];
        if (ex == null) continue;
        final base = exName == 'Dominadas' ? 0.0 : 30.0 + (exName.length % 5) * 10 + (21 - d) * 0.4;
        s.exercises.add(WorkoutExercise(
            exerciseId: ex.id,
            sets: List.generate(
                3, (i) => SetEntry(weight: (base * 2).round() / 2, reps: 10 - i, done: true, rpe: i == 2 ? 9 : null))));
      }
      sessions.add(s);
    }
    for (var k = 0; k < 4; k++) {
      metrics.add(BodyMetric(
          id: uid(),
          userId: activeUserId,
          date: DateTime(now.year, now.month, now.day - 21 + k * 7),
          weight: 80 - k * 0.4,
          fat: 18 - k * 0.2,
          waist: 85 - k * 0.3,
          arm: 36 + k * 0.1,
          demo: true));
    }
    changed();
  }

  void removeDemo() {
    sessions.removeWhere((s) => s.demo);
    metrics.removeWhere((m) => m.demo);
    changed();
    Services.scheduleReminders(this);
  }

  void _seedExercises() {
    const base = {
      'Pecho': ['Press banca', 'Press inclinado con mancuernas', 'Aperturas en polea', 'Fondos'],
      'Espalda': ['Dominadas', 'Remo con barra', 'Jalón al pecho'],
      'Hombros': ['Press militar', 'Elevaciones laterales'],
      'Bíceps': ['Curl con barra'],
      'Tríceps': ['Extensión de tríceps'],
      'Piernas': ['Sentadilla', 'Prensa', 'Peso muerto rumano', 'Curl femoral', 'Elevación de talones'],
      'Glúteos': ['Hip thrust'],
      'Core': ['Plancha', 'Crunch abdominal'],
      'Cardio': ['Cinta (cardio)'],
    };
    var i = 0;
    base.forEach((m, l) {
      for (final n in l) {
        exercises.add(Exercise(id: 'ex_${i++}', name: n, muscle: m));
      }
    });
  }
}
