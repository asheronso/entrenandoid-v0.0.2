import 'dart:math';
import 'package:flutter/material.dart' show DateTimeRange;
import 'models.dart';

class SetRow {
  final Session s;
  final WorkoutExercise we;
  final SetEntry set;
  SetRow(this.s, this.we, this.set);
}

class ExPoint {
  final DateTime date;
  final double maxWeight, e1rm, volume;
  final int sets;
  ExPoint(this.date, this.maxWeight, this.e1rm, this.volume, this.sets);
}

class Best {
  final double weight, e1rm;
  const Best(this.weight, this.e1rm);
}

class FF {
  final List<DateTime> days;
  final List<double> fitness, fatigue, form;
  FF(this.days, this.fitness, this.fatigue, this.form);
}

class Stats {
  static DateTime day(DateTime x) => DateTime(x.year, x.month, x.day);

  static bool inRange(DateTime d, DateTimeRange? r) {
    if (r == null) return true;
    final a = day(r.start);
    final b = DateTime(r.end.year, r.end.month, r.end.day + 1);
    return !d.isBefore(a) && d.isBefore(b);
  }

  /// Series completadas, no calentamiento, con repeticiones.
  static List<SetRow> rows(List<Session> ss, {String? exerciseId, String? muscle, Map<String, Exercise>? exMap}) {
    final out = <SetRow>[];
    for (final s in ss) {
      for (final we in s.exercises) {
        if (exerciseId != null && we.exerciseId != exerciseId) continue;
        if (muscle != null && exMap?[we.exerciseId]?.muscle != muscle) continue;
        for (final st in we.sets) {
          if (st.counts) out.add(SetRow(s, we, st));
        }
      }
    }
    return out;
  }

  static List<Session> sessionsFor(List<Session> all,
      {String? userId, DateTimeRange? range, String? exerciseId, String? muscle, Map<String, Exercise>? exMap}) {
    var out = all.where((s) => (userId == null || s.userId == userId) && inRange(s.start, range)).toList();
    if (exerciseId != null || muscle != null) {
      out = out.where((s) => rows([s], exerciseId: exerciseId, muscle: muscle, exMap: exMap).isNotEmpty).toList();
    }
    out.sort((a, b) => b.start.compareTo(a.start));
    return out;
  }

  static double volume(Iterable<SetRow> r) => r.fold(0.0, (a, e) => a + e.set.weight * e.set.reps);
  static double bestWeight(Iterable<SetRow> r) => r.fold(0.0, (a, e) => max(a, e.set.weight));
  static double best1rm(Iterable<SetRow> r) => r.fold(0.0, (a, e) => max(a, epley(e.set.weight, e.set.reps)));

  static List<ExPoint> exerciseSeries(List<Session> ss, String exerciseId) {
    final sorted = [...ss]..sort((a, b) => a.start.compareTo(b.start));
    final pts = <ExPoint>[];
    for (final s in sorted) {
      final r = rows([s], exerciseId: exerciseId);
      if (r.isEmpty) continue;
      pts.add(ExPoint(s.start, bestWeight(r), best1rm(r), volume(r), r.length));
    }
    return pts;
  }

  static int streak(Iterable<Session> ss, [DateTime? now]) {
    final days = ss.map((s) => day(s.start)).toSet();
    final t = day(now ?? DateTime.now());
    var d = days.contains(t) ? t : DateTime(t.year, t.month, t.day - 1);
    var n = 0;
    while (days.contains(d)) {
      n++;
      d = DateTime(d.year, d.month, d.day - 1);
    }
    return n;
  }

  static int longestStreak(Iterable<Session> ss) {
    final days = ss.map((s) => day(s.start)).toSet().toList()..sort();
    var best = 0, cur = 0;
    DateTime? prev;
    for (final d in days) {
      if (prev != null && DateTime(prev.year, prev.month, prev.day + 1) == d) {
        cur++;
      } else {
        cur = 1;
      }
      best = max(best, cur);
      prev = d;
    }
    return best;
  }

  static List<SetEntry>? lastSets(List<Session> ss, String exerciseId, String userId, {String? excludeId}) {
    final c = ss.where((s) => s.userId == userId && s.id != excludeId).toList()
      ..sort((a, b) => b.start.compareTo(a.start));
    for (final s in c) {
      for (final we in s.exercises) {
        if (we.exerciseId == exerciseId) {
          final l = we.sets.where((x) => x.counts).toList();
          if (l.isNotEmpty) return l;
        }
      }
    }
    return null;
  }

  static Best bestBefore(List<Session> ss, String userId, String exerciseId, {String? excludeId}) {
    final r = rows(ss.where((s) => s.userId == userId && s.id != excludeId).toList(), exerciseId: exerciseId);
    return Best(bestWeight(r), best1rm(r));
  }

  /// Sesiones entrenadas por semana (lunes a domingo), últimas [weeks] semanas.
  static List<MapEntry<DateTime, int>> weeklyFreq(List<Session> ss, {int weeks = 8}) {
    final t = day(DateTime.now());
    final monday = DateTime(t.year, t.month, t.day - (t.weekday - 1));
    final out = <MapEntry<DateTime, int>>[];
    for (var w = weeks - 1; w >= 0; w--) {
      final start = DateTime(monday.year, monday.month, monday.day - 7 * w);
      final end = DateTime(start.year, start.month, start.day + 7);
      final days = ss.map((s) => day(s.start)).where((d) => !d.isBefore(start) && d.isBefore(end)).toSet();
      out.add(MapEntry(start, days.length));
    }
    return out;
  }

  static Map<String, double> volumeByMuscle(List<Session> ss, Map<String, Exercise> exMap) {
    final m = {for (final k in muscles) k: 0.0};
    for (final r in rows(ss)) {
      final k = exMap[r.we.exerciseId]?.muscle ?? 'Otro';
      m[k] = (m[k] ?? 0) + r.set.weight * r.set.reps;
    }
    return m;
  }

  /// Modelo Fitness/Fatiga (medias móviles exponenciales de la carga diaria).
  /// carga de una serie = reps * peso (o reps si el peso es 0).
  static FF fitnessFatigue(List<Session> ss, {int days = 90}) {
    final today = day(DateTime.now());
    final first = DateTime(today.year, today.month, today.day - days + 1 - 60);
    final load = <DateTime, double>{};
    for (final s in ss) {
      var l = 0.0;
      for (final r in rows([s])) {
        l += r.set.reps * (r.set.weight > 0 ? r.set.weight : 1);
      }
      final d = day(s.start);
      if (!d.isBefore(first)) load[d] = (load[d] ?? 0) + l;
    }
    final kf = exp(-1 / 28), kg = exp(-1 / 7);
    var fit = 0.0, fat = 0.0;
    final ds = <DateTime>[], f1 = <double>[], f2 = <double>[], f3 = <double>[];
    for (var i = 0; i < days + 60; i++) {
      final d = DateTime(first.year, first.month, first.day + i);
      final l = load[d] ?? 0;
      fit = fit * kf + l * (1 - kf);
      fat = fat * kg + l * (1 - kg);
      if (i >= 60) {
        ds.add(d);
        f1.add(fit);
        f2.add(fat);
        f3.add(fit - fat);
      }
    }
    return FF(ds, f1, f2, f3);
  }
}
