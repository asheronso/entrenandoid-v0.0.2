import 'dart:io';
import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'models.dart';
import 'store.dart';

String fmtDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
String fmtShort(DateTime d) => '${d.day}/${d.month}';
String fmtTime(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
String fmtRange(DateTimeRange r) => '${fmtShort(r.start)} – ${fmtShort(r.end)}';

class Panel extends StatelessWidget {
  static double radius = 16;
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(12), this.color});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: padding,
        decoration: BoxDecoration(
            color: color ?? Theme.of(context).colorScheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(radius)),
        child: child,
      );
}

class UserAvatar extends StatelessWidget {
  final AppUser user;
  final double size;
  const UserAvatar(this.user, {super.key, this.size = 40});
  @override
  Widget build(BuildContext context) {
    final has = user.photo != null && File(user.photo!).existsSync();
    return CircleAvatar(
      radius: size / 2,
      backgroundImage: has ? FileImage(File(user.photo!)) : null,
      child: has ? null : Text(user.name.isEmpty ? '?' : user.name[0].toUpperCase()),
    );
  }
}

/// Campo numérico con botones +/− (cómodo con una mano). Impide valores negativos.
class NumStepper extends StatefulWidget {
  final double value, step, min;
  final int decimals;
  final String label;
  final ValueChanged<double> onChanged;
  const NumStepper(
      {super.key, required this.value, required this.step, required this.onChanged, required this.label, this.min = 0, this.decimals = 1});
  @override
  State<NumStepper> createState() => _NumStepperState();
}

class _NumStepperState extends State<NumStepper> {
  late final TextEditingController c;
  @override
  void initState() {
    super.initState();
    c = TextEditingController(text: fmtNum(widget.value, widget.decimals));
  }

  @override
  void didUpdateWidget(NumStepper o) {
    super.didUpdateWidget(o);
    final typed = double.tryParse(c.text.replaceAll(',', '.'));
    if (typed != widget.value) c.text = fmtNum(widget.value, widget.decimals);
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  void _set(double v) {
    v = max(widget.min, v);
    c.text = fmtNum(v, widget.decimals);
    widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.remove_circle_outline), onPressed: () => _set(widget.value - widget.step)),
      Expanded(
        child: TextField(
          controller: c,
          textAlign: TextAlign.center,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(isDense: true, labelText: widget.label, contentPadding: const EdgeInsets.symmetric(vertical: 10)),
          onChanged: (t) {
            final v = double.tryParse(t.replaceAll(',', '.'));
            if (v == null) return;
            if (v < widget.min) {
              _set(widget.min);
            } else {
              widget.onChanged(v);
            }
          },
        ),
      ),
      IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.add_circle_outline), onPressed: () => _set(widget.value + widget.step)),
    ]);
  }
}

Future<String?> askMuscle(BuildContext context) => showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Grupo muscular'),
        children: [for (final m in muscles) SimpleDialogOption(onPressed: () => Navigator.pop(c, m), child: Text(m))],
      ),
    );

Future<String?> askText(BuildContext context, String title, {String initial = '', String hint = ''}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: TextField(controller: c, autofocus: true, decoration: InputDecoration(hintText: hint)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('Aceptar')),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext context, String title, String body) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Confirmar')),
      ],
    ),
  );
  return r == true;
}

void snack(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));

/// Buscador de ejercicios: favoritos y recientes arriba, archivados ocultos.
Future<Exercise?> pickExercise(BuildContext context, AppStore store, {bool allowCreate = true}) =>
    showModalBottomSheet<Exercise>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ExercisePicker(store: store, allowCreate: allowCreate),
    );

class _ExercisePicker extends StatefulWidget {
  final AppStore store;
  final bool allowCreate;
  const _ExercisePicker({required this.store, required this.allowCreate});
  @override
  State<_ExercisePicker> createState() => _ExercisePickerState();
}

class _ExercisePickerState extends State<_ExercisePicker> {
  String q = '';
  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final recent = s.recentExerciseIds();
    final list = s.exercises.where((e) => !e.archived).toList();
    int rank(Exercise e) => e.favorite ? 0 : (recent.contains(e.id) ? 1 : 2);
    list.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    final ql = q.trim().toLowerCase();
    final shown = ql.isEmpty ? list : list.where((e) => e.name.toLowerCase().contains(ql) || e.muscle.toLowerCase().contains(ql)).toList();
    final exact = list.any((e) => e.name.toLowerCase() == ql);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar ejercicio o grupo muscular'),
              onChanged: (v) => setState(() => q = v),
            ),
          ),
          Expanded(
            child: ListView(children: [
              if (widget.allowCreate && ql.isNotEmpty && !exact)
                ListTile(
                  leading: const Icon(Icons.add),
                  title: Text('Crear «${q.trim()}»'),
                  onTap: () async {
                    final m = await askMuscle(context);
                    if (m == null) return;
                    final e = s.addExercise(q, m);
                    if (context.mounted) Navigator.pop(context, e);
                  },
                ),
              for (final e in shown)
                ListTile(
                  leading: Icon(e.favorite ? Icons.star : (recent.contains(e.id) ? Icons.history : Icons.fitness_center)),
                  title: Text(e.name),
                  subtitle: Text(e.muscle),
                  onTap: () => Navigator.pop(context, e),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------ gráficas
class LineSeries {
  final String name;
  final Color color;
  final List<double> ys;
  LineSeries(this.name, this.color, this.ys);
}

Widget legend(List<LineSeries> s) => Wrap(spacing: 12, children: [
      for (final x in s)
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.circle, size: 10, color: x.color),
          const SizedBox(width: 4),
          Text(x.name, style: const TextStyle(fontSize: 12)),
        ])
    ]);

Widget lineChart(List<LineSeries> series, List<String> labels, {double height = 190}) {
  final n = labels.length;
  if (n == 0 || series.every((s) => s.ys.isEmpty)) {
    return SizedBox(height: 80, child: Center(child: Text('Sin datos en este rango')));
  }
  return SizedBox(
    height: height,
    child: Padding(
      padding: const EdgeInsets.only(top: 8, right: 8),
      child: LineChart(LineChartData(
        minX: 0,
        maxX: max(1, n - 1).toDouble(),
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 42)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: max(1, (n / 5).ceil()).toDouble(),
              getTitlesWidget: (v, meta) {
                final i = v.round();
                if ((v - i).abs() > 0.01 || i < 0 || i >= n) return const SizedBox.shrink();
                return Padding(padding: const EdgeInsets.only(top: 6), child: Text(labels[i], style: const TextStyle(fontSize: 10)));
              },
            ),
          ),
        ),
        lineBarsData: [
          for (final s in series)
            LineChartBarData(
              spots: [for (var i = 0; i < s.ys.length; i++) FlSpot(i.toDouble(), s.ys[i])],
              color: s.color,
              isCurved: s.ys.length > 2,
              barWidth: 3,
              dotData: FlDotData(show: s.ys.length <= 30),
            ),
        ],
      )),
    ),
  );
}

Widget barChart(List<String> labels, List<double> values, Color color, {double height = 180}) {
  if (values.isEmpty || values.every((v) => v == 0)) {
    return const SizedBox(height: 80, child: Center(child: Text('Sin datos en este rango')));
  }
  return SizedBox(
    height: height,
    child: Padding(
      padding: const EdgeInsets.only(top: 8, right: 8),
      child: BarChart(BarChartData(
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 42)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (v, meta) {
                final i = v.round();
                if (i < 0 || i >= labels.length) return const SizedBox.shrink();
                return Padding(padding: const EdgeInsets.only(top: 6), child: Text(labels[i], style: const TextStyle(fontSize: 10)));
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < values.length; i++)
            BarChartGroupData(x: i, barRods: [BarChartRodData(toY: values[i], width: 14, color: color, borderRadius: BorderRadius.circular(4))]),
        ],
      )),
    ),
  );
}

Widget statTile(BuildContext c, String label, String value) => Expanded(
      child: Panel(
        child: Column(children: [
          Text(value, style: Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label, style: Theme.of(c).textTheme.bodySmall, textAlign: TextAlign.center),
        ]),
      ),
    );
