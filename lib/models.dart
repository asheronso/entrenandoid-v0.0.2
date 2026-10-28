import 'dart:math';

final _rnd = Random();
String uid() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_rnd.nextInt(46656).toRadixString(36)}';

const muscles = ['Pecho', 'Espalda', 'Hombros', 'Bíceps', 'Tríceps', 'Piernas', 'Glúteos', 'Core', 'Cardio', 'Otro'];
const setTypes = {'normal': 'Normal', 'warmup': 'Calentamiento', 'drop': 'Dropset', 'failure': 'Al fallo'};

/// 1RM estimado (Epley). Peso 0 (ejercicios de peso corporal) => 0.
double epley(double weight, int reps) => (weight <= 0 || reps <= 0) ? 0 : weight * (1 + reps / 30);

String fmtNum(double v, [int dec = 1]) {
  var s = v.toStringAsFixed(dec);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
  }
  return s;
}

double _d(dynamic v, [double def = 0]) => v is num ? v.toDouble() : def;
double? _dn(dynamic v) => v is num ? v.toDouble() : null;

class AppUser {
  String id, name, unit;
  String? photo;
  double step;
  int restSeconds;
  AppUser({required this.id, required this.name, this.photo, this.unit = 'kg', this.step = 2.5, this.restSeconds = 90});
  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'photo': photo, 'unit': unit, 'step': step, 'restSeconds': restSeconds};
  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
      id: j['id'] as String,
      name: j['name'] as String,
      photo: j['photo'] as String?,
      unit: (j['unit'] as String?) ?? 'kg',
      step: _d(j['step'], 2.5),
      restSeconds: (j['restSeconds'] as num?)?.toInt() ?? 90);
}

class Exercise {
  String id, name, muscle;
  bool favorite, archived;
  Exercise({required this.id, required this.name, this.muscle = 'Otro', this.favorite = false, this.archived = false});
  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'muscle': muscle, 'favorite': favorite, 'archived': archived};
  factory Exercise.fromJson(Map<String, dynamic> j) => Exercise(
      id: j['id'] as String,
      name: j['name'] as String,
      muscle: (j['muscle'] as String?) ?? 'Otro',
      favorite: j['favorite'] == true,
      archived: j['archived'] == true);
}

class SetEntry {
  double weight; // siempre en kg
  int reps;
  String type;
  double? rpe;
  bool done;
  SetEntry({this.weight = 0, this.reps = 0, this.type = 'normal', this.rpe, this.done = false});

  /// Cuenta para estadísticas: completada, no calentamiento y con repeticiones.
  bool get counts => done && type != 'warmup' && reps > 0;

  Map<String, dynamic> toJson() => {'weight': weight, 'reps': reps, 'type': type, 'rpe': rpe, 'done': done};
  factory SetEntry.fromJson(Map<String, dynamic> j) => SetEntry(
      weight: _d(j['weight']),
      reps: (j['reps'] as num?)?.toInt() ?? 0,
      type: (j['type'] as String?) ?? 'normal',
      rpe: _dn(j['rpe']),
      done: j['done'] != false);
}

class WorkoutExercise {
  String exerciseId, note;
  bool superset; // enlazado con el siguiente ejercicio
  List<SetEntry> sets;
  WorkoutExercise({required this.exerciseId, this.note = '', this.superset = false, List<SetEntry>? sets})
      : sets = sets ?? [];
  Map<String, dynamic> toJson() =>
      {'exerciseId': exerciseId, 'note': note, 'superset': superset, 'sets': sets.map((s) => s.toJson()).toList()};
  factory WorkoutExercise.fromJson(Map<String, dynamic> j) => WorkoutExercise(
      exerciseId: j['exerciseId'] as String,
      note: (j['note'] as String?) ?? '',
      superset: j['superset'] == true,
      sets: ((j['sets'] ?? []) as List).map((e) => SetEntry.fromJson(Map<String, dynamic>.from(e as Map))).toList());
}

class Session {
  String id, userId, name;
  DateTime start;
  DateTime? end;
  bool demo;
  List<WorkoutExercise> exercises;
  Session(
      {required this.id,
      required this.userId,
      required this.name,
      required this.start,
      this.end,
      this.demo = false,
      List<WorkoutExercise>? exercises})
      : exercises = exercises ?? [];

  double get volume {
    var v = 0.0;
    for (final e in exercises) {
      for (final s in e.sets) {
        if (s.counts) v += s.weight * s.reps;
      }
    }
    return v;
  }

  int get setCount => exercises.fold(0, (a, e) => a + e.sets.where((s) => s.counts).length);

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'name': name,
        'start': start.toIso8601String(),
        'end': end?.toIso8601String(),
        'demo': demo,
        'exercises': exercises.map((e) => e.toJson()).toList()
      };
  factory Session.fromJson(Map<String, dynamic> j) => Session(
      id: j['id'] as String,
      userId: j['userId'] as String,
      name: (j['name'] as String?) ?? 'Entrenamiento',
      start: DateTime.parse(j['start'] as String),
      end: j['end'] == null ? null : DateTime.parse(j['end'] as String),
      demo: j['demo'] == true,
      exercises: ((j['exercises'] ?? []) as List)
          .map((e) => WorkoutExercise.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList());
}

class Routine {
  String id, userId, name;
  List<String> exerciseIds;
  Routine({required this.id, required this.userId, required this.name, required this.exerciseIds});
  Map<String, dynamic> toJson() => {'id': id, 'userId': userId, 'name': name, 'exerciseIds': exerciseIds};
  factory Routine.fromJson(Map<String, dynamic> j) => Routine(
      id: j['id'] as String,
      userId: j['userId'] as String,
      name: j['name'] as String,
      exerciseIds: ((j['exerciseIds'] ?? []) as List).map((e) => e as String).toList());
}

class BodyMetric {
  String id, userId;
  DateTime date;
  double? weight, fat, waist, arm; // kg, %, cm, cm
  bool demo;
  BodyMetric(
      {required this.id,
      required this.userId,
      required this.date,
      this.weight,
      this.fat,
      this.waist,
      this.arm,
      this.demo = false});
  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'date': date.toIso8601String(),
        'weight': weight,
        'fat': fat,
        'waist': waist,
        'arm': arm,
        'demo': demo
      };
  factory BodyMetric.fromJson(Map<String, dynamic> j) => BodyMetric(
      id: j['id'] as String,
      userId: j['userId'] as String,
      date: DateTime.parse(j['date'] as String),
      weight: _dn(j['weight']),
      fat: _dn(j['fat']),
      waist: _dn(j['waist']),
      arm: _dn(j['arm']),
      demo: j['demo'] == true);
}
