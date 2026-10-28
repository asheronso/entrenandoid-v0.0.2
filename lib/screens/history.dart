import 'package:flutter/material.dart';
import '../models.dart';
import '../stats.dart';
import '../store.dart';
import '../widgets.dart';
import 'workout.dart';

const _meses = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];

class HistoryPage extends StatefulWidget {
  final AppStore store;
  const HistoryPage({super.key, required this.store});
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  AppStore get s => widget.store;
  DateTimeRange? range;
  Exercise? ex;
  String? muscle;
  bool cal = false;
  late DateTime month = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final list = Stats.sessionsFor(s.mySessions, range: range, exerciseId: ex?.id, muscle: muscle, exMap: s.exMap);
        return SafeArea(
          child: ListView(padding: const EdgeInsets.all(12), children: [
            Row(children: [
              Expanded(child: Text('Historial', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold))),
              IconButton(
                tooltip: cal ? 'Ver lista' : 'Ver calendario',
                icon: Icon(cal ? Icons.view_list : Icons.calendar_month),
                onPressed: () => setState(() => cal = !cal),
              ),
            ]),
            Wrap(spacing: 8, children: [
              ActionChip(
                avatar: const Icon(Icons.date_range, size: 18),
                label: Text(range == null ? 'Rango de fechas' : fmtRange(range!)),
                onPressed: () async {
                  final r = await showDateRangePicker(
                      context: context, firstDate: DateTime(2000), lastDate: DateTime.now().add(const Duration(days: 1)), initialDateRange: range);
                  if (r != null) setState(() => range = r);
                },
              ),
              ActionChip(
                avatar: const Icon(Icons.fitness_center, size: 18),
                label: Text(ex?.name ?? 'Ejercicio'),
                onPressed: () async {
                  final e = await pickExercise(context, s, allowCreate: false);
                  if (e != null) setState(() => ex = e);
                },
              ),
              PopupMenuButton<String>(
                onSelected: (v) => setState(() => muscle = v),
                itemBuilder: (_) => [for (final m in muscles) PopupMenuItem(value: m, child: Text(m))],
                child: Chip(avatar: const Icon(Icons.accessibility_new, size: 18), label: Text(muscle ?? 'Grupo muscular')),
              ),
              if (range != null || ex != null || muscle != null)
                ActionChip(
                  avatar: const Icon(Icons.clear, size: 18),
                  label: const Text('Limpiar'),
                  onPressed: () => setState(() {
                    range = null;
                    ex = null;
                    muscle = null;
                  }),
                ),
            ]),
            if (cal) _calendar(context),
            const SizedBox(height: 6),
            Text('${list.length} sesiones', style: Theme.of(context).textTheme.bodySmall),
            if (list.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Sin sesiones para mostrar.'))),
            for (final x in list)
              Dismissible(
                key: ValueKey(x.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: Colors.red,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                confirmDismiss: (_) => confirm(context, 'Eliminar sesión', '¿Eliminar «${x.name}» del ${fmtDate(x.start)}? No se puede deshacer.'),
                onDismissed: (_) => s.deleteSession(x.id),
                child: Panel(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(x.name),
                    subtitle: Text(
                        '${fmtDate(x.start)} ${fmtTime(x.start)} · ${x.exercises.map((e) => s.exName(e.exerciseId)).take(3).join(', ')}${x.exercises.length > 3 ? '…' : ''}'),
                    trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('${s.fmtW(x.volume)} ${s.unit}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text('${x.setCount} series', style: Theme.of(context).textTheme.bodySmall),
                    ]),
                    onTap: () => openSessionEditor(context, s, x),
                  ),
                ),
              ),
          ]),
        );
      },
    );
  }

  Widget _calendar(BuildContext context) {
    final trained = s.mySessions.map((x) => Stats.day(x.start)).toSet();
    final first = DateTime(month.year, month.month, 1);
    final daysIn = DateTime(month.year, month.month + 1, 0).day;
    final lead = first.weekday - 1;
    final cs = Theme.of(context).colorScheme;
    final cells = <Widget>[
      for (final h in ['L', 'M', 'X', 'J', 'V', 'S', 'D']) Center(child: Text(h, style: const TextStyle(fontWeight: FontWeight.bold))),
      for (var i = 0; i < lead; i++) const SizedBox.shrink(),
      for (var d = 1; d <= daysIn; d++)
        Builder(builder: (_) {
          final date = DateTime(month.year, month.month, d);
          final has = trained.contains(date);
          final sel = range != null && Stats.day(range!.start) == date && Stats.day(range!.end) == date;
          return InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => setState(() => range = sel ? null : DateTimeRange(start: date, end: date)),
            child: Container(
              margin: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: has ? cs.primary : null,
                border: sel ? Border.all(color: cs.tertiary, width: 3) : null,
              ),
              alignment: Alignment.center,
              child: Text('$d', style: TextStyle(color: has ? cs.onPrimary : null)),
            ),
          );
        }),
    ];
    return Panel(
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => month = DateTime(month.year, month.month - 1))),
          Text('${_meses[month.month - 1]} ${month.year}', style: Theme.of(context).textTheme.titleMedium),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => setState(() => month = DateTime(month.year, month.month + 1))),
        ]),
        GridView.count(crossAxisCount: 7, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), children: cells),
        const Text('Los días entrenados están marcados. Toca un día para filtrar.', style: TextStyle(fontSize: 12)),
      ]),
    );
  }
}
