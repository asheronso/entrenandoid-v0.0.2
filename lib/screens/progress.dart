import 'package:flutter/material.dart';
import '../models.dart';
import '../stats.dart';
import '../store.dart';
import '../widgets.dart';

class ProgressPage extends StatefulWidget {
  final AppStore store;
  const ProgressPage({super.key, required this.store});
  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage> {
  AppStore get s => widget.store;
  DateTimeRange? range;
  String? exId;
  String q = '';

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(children: [
              Expanded(child: Text('Progreso', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold))),
              ActionChip(
                avatar: const Icon(Icons.date_range, size: 18),
                label: Text(range == null ? 'Rango de fechas' : fmtRange(range!)),
                onPressed: () async {
                  final r = await showDateRangePicker(
                      context: context, firstDate: DateTime(2000), lastDate: DateTime.now().add(const Duration(days: 1)), initialDateRange: range);
                  if (r != null) setState(() => range = r);
                },
              ),
              if (range != null) IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => range = null)),
            ]),
          ),
          const TabBar(isScrollable: true, tabs: [Tab(text: 'Ejercicio'), Tab(text: 'Resumen'), Tab(text: 'Fatiga'), Tab(text: 'Cuerpo')]),
          Expanded(
            child: ListenableBuilder(
              listenable: s,
              builder: (context, _) => TabBarView(children: [_exerciseTab(context), _summaryTab(context), _fatigueTab(context), _bodyTab(context)]),
            ),
          ),
        ]),
      ),
    );
  }

  // ------------------------------------------------------------ Ejercicio
  Widget _exerciseTab(BuildContext context) {
    final mine = s.mySessions;
    if (exId == null) {
      final ql = q.trim().toLowerCase();
      final withData = mine.expand((x) => x.exercises.map((e) => e.exerciseId)).toSet();
      final list = s.exercises.where((e) => !e.archived && (ql.isEmpty || e.name.toLowerCase().contains(ql) || e.muscle.toLowerCase().contains(ql))).toList()
        ..sort((a, b) {
          final r = (withData.contains(b.id) ? 1 : 0).compareTo(withData.contains(a.id) ? 1 : 0);
          return r != 0 ? r : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      return ListView(padding: const EdgeInsets.all(12), children: [
        TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar ejercicio…'),
          onChanged: (v) => setState(() => q = v),
        ),
        const SizedBox(height: 8),
        for (final e in list)
          ListTile(
            leading: Icon(withData.contains(e.id) ? Icons.show_chart : Icons.fitness_center, color: withData.contains(e.id) ? null : Colors.grey),
            title: Text(e.name),
            subtitle: Text(e.muscle),
            onTap: () => setState(() => exId = e.id),
          ),
        if (list.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Sin resultados.'))),
      ]);
    }
    final sess = Stats.sessionsFor(mine, range: range);
    final pts = Stats.exerciseSeries(sess, exId!);
    final labels = pts.map((p) => fmtShort(p.date)).toList();
    final all = Stats.rows(Stats.sessionsFor(mine), exerciseId: exId); // récords históricos (sin filtro de fecha)
    final cs = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.all(12), children: [
      Row(children: [
        IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => exId = null)),
        Expanded(child: Text(s.exName(exId!), style: Theme.of(context).textTheme.titleLarge)),
      ]),
      Row(children: [
        statTile(context, '🏆 Mejor peso (${s.unit})', fmtNum(s.toDisp(Stats.bestWeight(all)), 1)),
        statTile(context, '🏆 Mejor 1RM est. (${s.unit})', fmtNum(s.toDisp(Stats.best1rm(all)), 1)),
      ]),
      Text('Peso máximo por sesión (${s.unit})', style: Theme.of(context).textTheme.titleSmall),
      lineChart([LineSeries('Peso', cs.primary, pts.map((p) => s.toDisp(p.maxWeight)).toList())], labels),
      Text('1RM estimado – Epley (${s.unit})', style: Theme.of(context).textTheme.titleSmall),
      lineChart([LineSeries('1RM', cs.tertiary, pts.map((p) => s.toDisp(p.e1rm)).toList())], labels),
      Text('Volumen por sesión (${s.unit})', style: Theme.of(context).textTheme.titleSmall),
      lineChart([LineSeries('Volumen', cs.secondary, pts.map((p) => s.toDisp(p.volume)).toList())], labels),
      const Text('Las series de calentamiento no cuentan en las estadísticas.', style: TextStyle(fontSize: 12)),
    ]);
  }

  // ------------------------------------------------------------ Resumen
  Widget _summaryTab(BuildContext context) {
    final mine = s.mySessions;
    final cs = Theme.of(context).colorScheme;
    final freq = Stats.weeklyFreq(mine);
    final vol = Stats.volumeByMuscle(Stats.sessionsFor(mine, range: range), s.exMap);
    final ms = muscles.where((m) => (vol[m] ?? 0) > 0).toList();
    return ListView(padding: const EdgeInsets.all(12), children: [
      Row(children: [
        statTile(context, 'Racha actual', '${Stats.streak(mine)} 🔥'),
        statTile(context, 'Mejor racha', '${Stats.longestStreak(mine)}'),
      ]),
      Text('Frecuencia semanal (días entrenados, últimas 8 semanas)', style: Theme.of(context).textTheme.titleSmall),
      barChart(freq.map((e) => fmtShort(e.key)).toList(), freq.map((e) => e.value.toDouble()).toList(), cs.primary),
      const SizedBox(height: 12),
      Text('Volumen por grupo muscular (${s.unit})', style: Theme.of(context).textTheme.titleSmall),
      barChart(ms.map((m) => m.length > 4 ? m.substring(0, 4) : m).toList(), ms.map((m) => s.toDisp(vol[m] ?? 0)).toList(), cs.tertiary),
      if (ms.isNotEmpty) Text('Grupos: ${ms.join(', ')}', style: const TextStyle(fontSize: 12)),
    ]);
  }

  // ------------------------------------------------------------ Fatiga
  Widget _fatigueTab(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ff = Stats.fitnessFatigue(s.mySessions);
    final labels = ff.days.map(fmtShort).toList();
    final series = [
      LineSeries('Fitness (constancia)', cs.primary, ff.fitness),
      LineSeries('Fatiga (carga reciente)', Colors.orange, ff.fatigue),
      LineSeries('Forma (fitness − fatiga)', Colors.green, ff.form),
    ];
    return ListView(padding: const EdgeInsets.all(12), children: [
      Text('Fitness / Fatiga (últimos 90 días)', style: Theme.of(context).textTheme.titleSmall),
      legend(series),
      lineChart(series, labels, height: 240),
      const SizedBox(height: 8),
      const Text(
          'Fitness = media de carga a 28 días (acumulación de entrenamiento). Fatiga = media a 7 días. '
          'Forma positiva = descansado; negativa = acumulando fatiga. La carga diaria es reps × peso.',
          style: TextStyle(fontSize: 12)),
    ]);
  }

  // ------------------------------------------------------------ Cuerpo
  Widget _bodyTab(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ms = s.myMetrics.where((m) => Stats.inRange(m.date, range)).toList();
    // Cada gráfica usa solo los registros que tienen ese dato, para que fechas y valores coincidan.
    final wm = ms.where((m) => m.weight != null).toList();
    final fm = ms.where((m) => m.fat != null).toList();
    return ListView(padding: const EdgeInsets.all(12), children: [
      FilledButton.icon(icon: const Icon(Icons.add), label: const Text('Registrar peso y medidas'), onPressed: () => _addMetric(context)),
      const SizedBox(height: 8),
      Text('Peso corporal (${s.unit})', style: Theme.of(context).textTheme.titleSmall),
      lineChart([LineSeries('Peso', cs.primary, wm.map((m) => s.toDisp(m.weight!)).toList())], wm.map((m) => fmtShort(m.date)).toList()),
      Text('% de grasa', style: Theme.of(context).textTheme.titleSmall),
      lineChart([LineSeries('% grasa', Colors.orange, fm.map((m) => m.fat!).toList())], fm.map((m) => fmtShort(m.date)).toList()),
      Text('Cintura y brazo (cm)', style: Theme.of(context).textTheme.titleSmall),
      Builder(builder: (_) {
        final cm = ms.where((m) => m.waist != null && m.arm != null).toList();
        final ser = [LineSeries('Cintura', Colors.teal, cm.map((m) => m.waist!).toList()), LineSeries('Brazo', cs.tertiary, cm.map((m) => m.arm!).toList())];
        return Column(children: [legend(ser), lineChart(ser, cm.map((m) => fmtShort(m.date)).toList())]);
      }),
      const SizedBox(height: 8),
      Text('Registros', style: Theme.of(context).textTheme.titleSmall),
      for (final m in ms.reversed)
        ListTile(
          dense: true,
          title: Text(fmtDate(m.date) + (m.demo ? '  [DEMO]' : '')),
          subtitle: Text([
            if (m.weight != null) '${fmtNum(s.toDisp(m.weight!))} ${s.unit}',
            if (m.fat != null) '${fmtNum(m.fat!)} % grasa',
            if (m.waist != null) 'cintura ${fmtNum(m.waist!)} cm',
            if (m.arm != null) 'brazo ${fmtNum(m.arm!)} cm',
          ].join(' · ')),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (await confirm(context, 'Eliminar registro', '¿Eliminar el registro del ${fmtDate(m.date)}?')) s.deleteMetric(m.id);
            },
          ),
        ),
      if (ms.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Aún no hay registros corporales.')),
    ]);
  }

  Future<void> _addMetric(BuildContext context) async {
    final w = TextEditingController(), f = TextEditingController(), c = TextEditingController(), a = TextEditingController();
    DateTime date = DateTime.now();
    double? parse(TextEditingController t) {
      final v = double.tryParse(t.text.replaceAll(',', '.'));
      return (v == null || v <= 0) ? null : v;
    }

    await showDialog<void>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setD) => AlertDialog(
          title: const Text('Peso y medidas'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.event),
                label: Text(fmtDate(date)),
                onPressed: () async {
                  final p = await showDatePicker(context: d, initialDate: date, firstDate: DateTime(2000), lastDate: DateTime.now());
                  if (p != null) setD(() => date = p);
                },
              ),
              const SizedBox(height: 8),
              for (final e in [(w, 'Peso (${s.unit})'), (f, '% grasa'), (c, 'Cintura (cm)'), (a, 'Brazo (cm)')])
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextField(controller: e.$1, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: e.$2, isDense: true)),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                final wv = parse(w), fv = parse(f), cv = parse(c), av = parse(a);
                if (wv == null && fv == null && cv == null && av == null) {
                  snack(context, 'Escribe al menos un valor mayor que 0');
                  return;
                }
                s.addMetric(BodyMetric(id: uid(), userId: s.activeUserId, date: date, weight: wv == null ? null : s.fromDisp(wv), fat: fv, waist: cv, arm: av));
                Navigator.pop(d);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }
}
