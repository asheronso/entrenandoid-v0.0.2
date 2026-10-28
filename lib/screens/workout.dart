import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models.dart';
import '../stats.dart';
import '../store.dart';
import '../widgets.dart';

/// Abre el entrenamiento en curso (o crea uno nuevo, opcionalmente desde una rutina).
Future<void> openWorkout(BuildContext context, AppStore s, {Routine? routine}) async {
  if (s.draft != null && routine != null) {
    final discard = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Entrenamiento en curso'),
        content: const Text('Ya tienes un entrenamiento sin terminar. ¿Descartarlo y empezar este?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Continuar el actual')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Descartar')),
        ],
      ),
    );
    if (discard == null) return;
    if (discard) s.discardDraft();
  }
  final sess = s.draft ?? s.startWorkout(routine);
  if (!context.mounted) return;
  await Navigator.push(context, MaterialPageRoute(builder: (_) => WorkoutScreen(store: s, session: sess, isDraft: true)));
}

Future<void> openSessionEditor(BuildContext context, AppStore s, Session sess) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => WorkoutScreen(store: s, session: sess, isDraft: false)));

class WorkoutScreen extends StatefulWidget {
  final AppStore store;
  final Session session;
  final bool isDraft;
  const WorkoutScreen({super.key, required this.store, required this.session, required this.isDraft});
  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> with WidgetsBindingObserver {
  AppStore get s => widget.store;
  Session get sess => widget.session;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable().catchError((_) {}); // pantalla encendida durante el entrenamiento
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable().catchError((_) {});
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) s.tick(); // si el descanso terminó en segundo plano
  }

  Future<void> _finish() async {
    if (widget.isDraft) {
      final any = sess.exercises.any((e) => e.sets.any((x) => x.done));
      if (!any) {
        if (!await confirm(context, 'Sin series completadas', 'No hay series marcadas como hechas. ¿Descartar este entrenamiento?')) return;
        s.discardDraft();
        if (mounted) Navigator.pop(context);
        return;
      }
      s.finishDraft();
      final streak = Stats.streak(s.mySessions);
      if (mounted) {
        snack(context, '¡Entrenamiento guardado! 🔥 Racha: $streak ${streak == 1 ? 'día' : 'días'}');
        Navigator.pop(context);
      }
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !widget.isDraft) s.cleanEdited(sess);
      },
      child: ListenableBuilder(
        listenable: s,
        builder: (context, _) => Scaffold(
          appBar: AppBar(
            title: Text(widget.isDraft ? 'Entrenamiento en curso' : 'Editar sesión'),
            actions: [
              IconButton(icon: const Icon(Icons.bookmark_add_outlined), tooltip: 'Guardar como rutina', onPressed: _saveRoutine),
              IconButton(icon: const Icon(Icons.check), tooltip: widget.isDraft ? 'Terminar' : 'Listo', onPressed: _finish),
            ],
          ),
          body: Column(children: [
            Expanded(
              child: ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 96), children: [
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: sess.name,
                      decoration: const InputDecoration(labelText: 'Nombre (ej. Día de pecho)', isDense: true),
                      onChanged: (v) {
                        sess.name = v;
                        s.touch();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.event, size: 18),
                    label: Text(fmtShort(sess.start)),
                    onPressed: () async {
                      final d = await showDatePicker(
                          context: context, initialDate: sess.start, firstDate: DateTime(2000), lastDate: DateTime.now().add(const Duration(days: 1)));
                      if (d == null) return;
                      sess.start = DateTime(d.year, d.month, d.day, sess.start.hour, sess.start.minute);
                      s.changed();
                    },
                  ),
                ]),
                const SizedBox(height: 6),
                for (var i = 0; i < sess.exercises.length; i++) _exCard(i),
                const SizedBox(height: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Añadir ejercicio'),
                  onPressed: () async {
                    final e = await pickExercise(context, s);
                    if (e == null) return;
                    sess.exercises.add(s.buildExercise(e.id, sess.userId, excludeId: sess.id));
                    s.changed();
                  },
                ),
              ]),
            ),
            _restBar(),
          ]),
        ),
      ),
    );
  }

  Future<void> _saveRoutine() async {
    if (sess.exercises.isEmpty) {
      snack(context, 'Añade ejercicios primero');
      return;
    }
    final name = await askText(context, 'Guardar como rutina', initial: sess.name);
    if (name == null || name.trim().isEmpty) return;
    s.addRoutine(name, sess.exercises.map((e) => e.exerciseId).toList());
    if (mounted) snack(context, 'Rutina «${name.trim()}» guardada');
  }

  Widget _exCard(int i) {
    final we = sess.exercises[i];
    final ex = s.exMap[we.exerciseId];
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (we.superset) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.link, size: 18)),
          Expanded(
            child: Text(ex?.name ?? 'Ejercicio eliminado', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'ss') we.superset = !we.superset;
              if (v == 'up' && i > 0) sess.exercises.insert(i - 1, sess.exercises.removeAt(i));
              if (v == 'down' && i < sess.exercises.length - 1) sess.exercises.insert(i + 1, sess.exercises.removeAt(i));
              if (v == 'del') sess.exercises.removeAt(i);
              s.changed();
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'ss', child: Text(we.superset ? 'Quitar superserie' : 'Superserie con el siguiente')),
              const PopupMenuItem(value: 'up', child: Text('Subir')),
              const PopupMenuItem(value: 'down', child: Text('Bajar')),
              const PopupMenuItem(value: 'del', child: Text('Quitar ejercicio')),
            ],
          ),
        ]),
        Text(s.lastText(we.exerciseId, sess), style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 13)),
        const SizedBox(height: 6),
        TextFormField(
          key: ObjectKey(we),
          initialValue: we.note,
          decoration: const InputDecoration(isDense: true, hintText: 'Nota (agarre, máquina, asiento…)', prefixIcon: Icon(Icons.notes, size: 18)),
          onChanged: (v) {
            we.note = v;
            s.touch();
          },
        ),
        const SizedBox(height: 6),
        for (var k = 0; k < we.sets.length; k++) _setTile(i, k),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Añadir serie'),
            onPressed: () {
              final l = we.sets.isEmpty ? null : we.sets.last;
              we.sets.add(SetEntry(weight: l?.weight ?? 0, reps: l?.reps ?? 10, type: (l == null || l.type == 'warmup') ? 'normal' : l.type));
              s.changed();
            },
          ),
        ),
      ]),
    );
  }

  Widget _setTile(int i, int k) {
    final we = sess.exercises[i];
    final st = we.sets[k];
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: ObjectKey(st),
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(6, 4, 2, 4),
      decoration: BoxDecoration(
          color: st.done ? cs.primaryContainer.withOpacity(0.5) : cs.surface.withOpacity(0.4), borderRadius: BorderRadius.circular(Panel.radius * 0.7)),
      child: Column(children: [
        Row(children: [
          CircleAvatar(radius: 13, child: Text('${k + 1}', style: const TextStyle(fontSize: 12))),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            initialValue: st.type,
            onSelected: (v) {
              st.type = v;
              s.changed();
            },
            itemBuilder: (_) => [for (final e in setTypes.entries) PopupMenuItem(value: e.key, child: Text(e.value))],
            child: Chip(label: Text(setTypes[st.type] ?? st.type, style: const TextStyle(fontSize: 12)), visualDensity: VisualDensity.compact),
          ),
          const SizedBox(width: 6),
          PopupMenuButton<double>(
            onSelected: (v) {
              st.rpe = v < 0 ? null : v;
              s.changed();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: -1, child: Text('Sin RPE')),
              for (final v in [6.0, 6.5, 7.0, 7.5, 8.0, 8.5, 9.0, 9.5, 10.0]) PopupMenuItem(value: v, child: Text('RPE ${fmtNum(v)}')),
            ],
            child: Chip(label: Text(st.rpe == null ? 'RPE' : 'RPE ${fmtNum(st.rpe!)}', style: const TextStyle(fontSize: 12)), visualDensity: VisualDensity.compact),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              we.sets.removeAt(k);
              s.changed();
            },
          ),
          IconButton(
            iconSize: 30,
            color: cs.primary,
            icon: Icon(st.done ? Icons.check_circle : Icons.radio_button_unchecked),
            onPressed: () => _toggleDone(i, k),
          ),
        ]),
        Row(children: [
          Expanded(
            child: NumStepper(
              label: s.unit,
              value: s.toDisp(st.weight),
              step: s.user.step,
              onChanged: (v) {
                st.weight = s.fromDisp(v);
                s.touch();
              },
            ),
          ),
          Expanded(
            child: NumStepper(
              label: 'reps',
              value: st.reps.toDouble(),
              step: 1,
              decimals: 0,
              onChanged: (v) {
                st.reps = v.round();
                s.touch();
              },
            ),
          ),
        ]),
      ]),
    );
  }

  void _toggleDone(int i, int k) {
    final we = sess.exercises[i];
    final st = we.sets[k];
    if (st.done) {
      st.done = false;
      s.changed();
      return;
    }
    if (st.reps <= 0 || st.weight < 0) {
      snack(context, 'Indica las repeticiones (el peso puede ser 0 en ejercicios de peso corporal)');
      return;
    }
    st.done = true;
    final pr = s.checkPr(sess, we, st);
    s.changed();
    if (pr != null) snack(context, '🏆 ¡Nuevo récord de $pr en ${s.exName(we.exerciseId)}!');
    final secs = s.user.restSeconds;
    if (secs > 0) s.startRest(sess, i, k, secs);
  }

  Widget _restBar() {
    if (s.restEndsAt == null || !identical(s.restSession, sess)) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.primaryContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(children: [
            const Icon(Icons.timer),
            const SizedBox(width: 8),
            ValueListenableBuilder<int>(
              valueListenable: s.restLeftN,
              builder: (_, left, __) => Text(
                '${(left ~/ 60).toString().padLeft(2, '0')}:${(left % 60).toString().padLeft(2, '0')}',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const Spacer(),
            TextButton(onPressed: () => s.addRest(-15), child: const Text('−15s')),
            TextButton(onPressed: () => s.addRest(15), child: const Text('+15s')),
            FilledButton.tonal(onPressed: () => s.finishRest(silent: true), child: const Text('Saltar')),
            IconButton(onPressed: s.cancelRest, icon: const Icon(Icons.close)),
          ]),
        ),
      ),
    );
  }
}
