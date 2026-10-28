import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymsheronso/models.dart';
import 'package:gymsheronso/stats.dart';
import 'package:gymsheronso/store.dart';

Session mk(String uidv, DateTime d, List<SetEntry> sets, {String ex = 'ex_0'}) =>
    Session(id: uid(), userId: uidv, name: 'Pecho', start: d, exercises: [WorkoutExercise(exerciseId: ex, sets: sets)]);

void main() {
  test('Epley y volumen (excluye calentamiento y series sin hacer)', () {
    expect(epley(100, 3), closeTo(110, 1e-9));
    expect(epley(0, 10), 0);
    final s = mk('u', DateTime(2026, 1, 1), [
      SetEntry(weight: 100, reps: 5, done: true),
      SetEntry(weight: 60, reps: 10, type: 'warmup', done: true),
      SetEntry(weight: 80, reps: 5, done: false),
      SetEntry(weight: 0, reps: 12, done: true), // peso corporal permitido
    ]);
    expect(s.volume, 500);
    expect(s.setCount, 2);
  });

  test('Racha: cuenta días consecutivos y se reinicia si falta un día', () {
    final now = DateTime(2026, 3, 10, 12);
    DateTime d(int back) => DateTime(2026, 3, 10 - back, 20);
    final ss = [for (final b in [0, 1, 2]) mk('u', d(b), [SetEntry(weight: 1, reps: 1, done: true)])];
    expect(Stats.streak(ss, now), 3);
    final cut = [mk('u', d(0), [SetEntry(weight: 1, reps: 1, done: true)]), mk('u', d(2), [SetEntry(weight: 1, reps: 1, done: true)])];
    expect(Stats.streak(cut, now), 1);
    expect(Stats.streak([mk('u', d(3), [SetEntry(weight: 1, reps: 1, done: true)])], now), 0);
  });

  test('Persistencia, edición, eliminación e importación', () async {
    final tmp = await Directory.systemTemp.createTemp('gym');
    final a = AppStore();
    await a.load(overrideDir: tmp);
    final sess = mk(a.activeUserId, DateTime(2026, 2, 1, 20), [SetEntry(weight: 50, reps: 8, done: true)]);
    a.sessions.add(sess);
    a.changed();
    await a.flush();

    final b = AppStore();
    await b.load(overrideDir: tmp);
    expect(b.sessions.length, 1);
    expect(b.sessions.first.exercises.first.sets.first.weight, 50);

    b.sessions.first.exercises.first.sets.first.reps = 10; // editar
    b.changed();
    await b.flush();
    final c = AppStore();
    await c.load(overrideDir: tmp);
    expect(c.sessions.first.exercises.first.sets.first.reps, 10);

    final json = c.exportJson();
    c.deleteSession(c.sessions.first.id);
    expect(c.sessions, isEmpty);
    c.importJson(json);
    expect(c.sessions.length, 1);

    expect(() => c.importJson('esto no es json'), throwsA(anything));
    expect(c.sessions.length, 1); // un respaldo inválido no borra los datos
    await tmp.delete(recursive: true);
  });

  test('Última vez, récords y siguiente serie automática tras el descanso', () async {
    final tmp = await Directory.systemTemp.createTemp('gym');
    final s = AppStore();
    await s.load(overrideDir: tmp);
    final u = s.activeUserId;
    s.sessions.add(mk(u, DateTime(2026, 1, 1), [SetEntry(weight: 40, reps: 8, done: true), SetEntry(weight: 40, reps: 8, done: true), SetEntry(weight: 40, reps: 8, done: true)]));
    final cur = s.startWorkout();
    cur.exercises.add(s.buildExercise('ex_0', u, excludeId: cur.id));
    expect(s.lastText('ex_0', cur), 'Última vez: 3×8 con 40 kg');
    expect(cur.exercises.first.sets.length, 3); // series prellenadas con lo último

    final st = cur.exercises.first.sets.first..weight = 45..done = true;
    expect(s.checkPr(cur, cur.exercises.first, st), 'peso');

    final n = cur.exercises.first.sets.length;
    s.startRest(cur, 0, n - 1, 60);
    s.finishRest(silent: true);
    expect(cur.exercises.first.sets.length, n + 1);
    s.cancelRest();
    await s.flush();
    await tmp.delete(recursive: true);
  });
}
