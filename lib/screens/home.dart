import 'package:flutter/material.dart';
import '../models.dart';
import '../stats.dart';
import '../store.dart';
import '../widgets.dart';
import 'workout.dart';

class HomePage extends StatefulWidget {
  final AppStore store;
  const HomePage({super.key, required this.store});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  AppStore get s => widget.store;
  String? fUser; // null = usuario activo, '*' = todos
  Exercise? fEx;
  DateTimeRange? fRange;

  String? get _uid => fUser == null ? s.activeUserId : (fUser == '*' ? null : fUser);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final streak = Stats.streak(s.mySessions);
        final best = Stats.longestStreak(s.mySessions);
        final sess = Stats.sessionsFor(s.sessions, userId: _uid, range: fRange, exerciseId: fEx?.id);
        final rows = Stats.rows(sess, exerciseId: fEx?.id);
        final uFilterName = fUser == '*' ? 'Todos los usuarios' : s.users.firstWhere((u) => u.id == (_uid ?? s.activeUserId), orElse: () => s.user).name;
        return SafeArea(
          child: ListView(padding: const EdgeInsets.all(12), children: [
            Row(children: [
              PopupMenuButton<String>(
                tooltip: 'Cambiar usuario',
                onSelected: s.setActive,
                itemBuilder: (_) => [for (final u in s.users) PopupMenuItem(value: u.id, child: Text(u.name))],
                child: UserAvatar(s.user, size: 48),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('GYMSHERONSO', style: Theme.of(context).textTheme.labelMedium?.copyWith(letterSpacing: 2)),
                  Text(s.user.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                ]),
              ),
            ]),
            Panel(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Row(children: [
                Text(streak > 0 ? '🔥' : '💤', style: const TextStyle(fontSize: 40)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(streak > 0 ? '$streak ${streak == 1 ? 'día seguido' : 'días seguidos'}' : 'Sin racha activa',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                    Text(streak > 0 ? 'Entrena mañana para mantenerla. Si faltas un día, se reinicia.' : 'Entrena hoy para empezar una racha.'),
                    Text('Mejor racha: $best', style: Theme.of(context).textTheme.bodySmall),
                  ]),
                ),
              ]),
            ),
            if (s.draft != null)
              Panel(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.play_circle_fill, size: 36),
                  title: Text('Entrenamiento en curso: ${s.draft!.name}'),
                  subtitle: const Text('Se guardó automáticamente. Toca para continuar.'),
                  onTap: () => openWorkout(context, s),
                ),
              ),
            Text('Rutinas', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            SizedBox(
              height: 46,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(avatar: const Icon(Icons.add, size: 18), label: const Text('Vacío'), onPressed: () => _startEmpty(context)),
                ),
                for (final r in s.myRoutines)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(label: Text(r.name), onPressed: () => openWorkout(context, s, routine: r)),
                  ),
              ]),
            ),
            if (s.myRoutines.isEmpty)
              Text('Guarda un entrenamiento como rutina con el icono de marcador para cargarlo con un toque.', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            Text('Estadísticas', style: Theme.of(context).textTheme.titleMedium),
            Wrap(spacing: 8, children: [
              PopupMenuButton<String>(
                onSelected: (v) => setState(() => fUser = v),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: '*', child: Text('Todos los usuarios')),
                  for (final u in s.users) PopupMenuItem(value: u.id, child: Text(u.name)),
                ],
                child: Chip(avatar: const Icon(Icons.person, size: 18), label: Text(uFilterName)),
              ),
              ActionChip(
                avatar: const Icon(Icons.fitness_center, size: 18),
                label: Text(fEx?.name ?? 'Todos los ejercicios'),
                onPressed: () async {
                  final e = await pickExercise(context, s, allowCreate: false);
                  if (e != null) setState(() => fEx = e);
                },
              ),
              ActionChip(
                avatar: const Icon(Icons.date_range, size: 18),
                label: Text(fRange == null ? 'Todas las fechas' : fmtRange(fRange!)),
                onPressed: () async {
                  final r = await showDateRangePicker(
                      context: context, firstDate: DateTime(2000), lastDate: DateTime.now().add(const Duration(days: 1)), initialDateRange: fRange);
                  if (r != null) setState(() => fRange = r);
                },
              ),
              if (fEx != null || fRange != null || fUser != null)
                ActionChip(
                  avatar: const Icon(Icons.clear, size: 18),
                  label: const Text('Limpiar'),
                  onPressed: () => setState(() {
                    fEx = null;
                    fRange = null;
                    fUser = null;
                  }),
                ),
            ]),
            Row(children: [
              statTile(context, 'Sesiones', '${sess.length}'),
              statTile(context, 'Series', '${rows.length}'),
              statTile(context, 'Volumen (${s.unit})', fmtNum(s.toDisp(Stats.volume(rows)), 0)),
            ]),
            Row(children: [
              statTile(context, 'Peso máx (${s.unit})', fmtNum(s.toDisp(Stats.bestWeight(rows)), 1)),
              statTile(context, '1RM est. (${s.unit})', fmtNum(s.toDisp(Stats.best1rm(rows)), 1)),
            ]),
            const SizedBox(height: 8),
            Text('Sesiones recientes', style: Theme.of(context).textTheme.titleMedium),
            if (sess.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No hay sesiones con estos filtros.')),
            for (final x in sess.take(5))
              Panel(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(x.name),
                  subtitle: Text('${fmtDate(x.start)} · ${x.exercises.length} ejercicios · ${x.setCount} series'),
                  trailing: Text('${s.fmtW(x.volume)} ${s.unit}'),
                  onTap: () => openSessionEditor(context, s, x),
                ),
              ),
          ]),
        );
      },
    );
  }

  void _startEmpty(BuildContext context) => openWorkout(context, s);
}
