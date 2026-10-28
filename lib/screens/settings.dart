import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../models.dart';
import '../services.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';

class SettingsPage extends StatelessWidget {
  final AppStore store;
  const SettingsPage({super.key, required this.store});
  AppStore get s => store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final u = s.user;
        return SafeArea(
          child: ListView(padding: const EdgeInsets.all(12), children: [
            Text('Ajustes', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            _h(context, 'Usuarios'),
            for (final x in s.users)
              Panel(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: UserAvatar(x),
                  title: Text(x.name),
                  subtitle: Text(x.id == s.activeUserId ? 'Activo · ${x.unit} · paso ${fmtNum(x.step)} · descanso ${x.restSeconds}s' : 'Toca para activar'),
                  onTap: () => s.setActive(x.id),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(icon: const Icon(Icons.edit), onPressed: () => _editUser(context, x)),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        if (s.users.length <= 1) {
                          snack(context, 'Debe existir al menos un usuario');
                          return;
                        }
                        if (await confirm(context, 'Eliminar usuario', 'Se borrarán también sus sesiones, rutinas y medidas de ${x.name}. Esta acción no se puede deshacer.')) {
                          s.deleteUser(x.id);
                        }
                      },
                    ),
                  ]),
                ),
              ),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.person_add),
              label: const Text('Crear usuario'),
              onPressed: () async {
                final n = await askText(context, 'Nuevo usuario', hint: 'Nombre');
                if (n != null) s.addUser(n);
              },
            ),
            _h(context, 'Entrenamiento (${u.name})'),
            Panel(
              child: Column(children: [
                Row(children: [
                  const Expanded(child: Text('Unidad de peso')),
                  SegmentedButton<String>(
                    segments: const [ButtonSegment(value: 'kg', label: Text('kg')), ButtonSegment(value: 'lb', label: Text('lb'))],
                    selected: {u.unit},
                    onSelectionChanged: (v) {
                      u.unit = v.first;
                      s.changed();
                    },
                  ),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  const Expanded(child: Text('Paso de incremento')),
                  DropdownButton<double>(
                    value: [1.0, 1.25, 2.0, 2.5, 5.0].contains(u.step) ? u.step : 2.5,
                    items: [for (final v in [1.0, 1.25, 2.0, 2.5, 5.0]) DropdownMenuItem(value: v, child: Text('${fmtNum(v, 2)} ${u.unit}'))],
                    onChanged: (v) {
                      u.step = v ?? 2.5;
                      s.changed();
                    },
                  ),
                ]),
                Row(children: [
                  Expanded(child: Text('Descanso entre series: ${u.restSeconds == 0 ? 'desactivado' : '${u.restSeconds} s'}')),
                ]),
                Slider(
                  value: u.restSeconds.toDouble(),
                  min: 0,
                  max: 300,
                  divisions: 20,
                  label: '${u.restSeconds}s',
                  onChanged: (v) {
                    u.restSeconds = v.round();
                    s.changed();
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Recordatorios semanales'),
                  subtitle: const Text('Avisa 5 h antes de tu hora habitual (ej. lunes: día de pecho).'),
                  value: s.remindersOn,
                  onChanged: (v) {
                    s.remindersOn = v;
                    s.changed();
                    Services.scheduleReminders(s);
                  },
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(icon: const Icon(Icons.volume_up), label: const Text('Probar sonido de alarma'), onPressed: Services.beep),
                ),
              ]),
            ),
            _h(context, 'Apariencia'),
            Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (var i = 0; i < palettes.length; i++)
                    ChoiceChip(
                      avatar: CircleAvatar(backgroundColor: palettes[i].seed, radius: 8),
                      label: Text(palettes[i].name),
                      selected: s.palette == i,
                      onSelected: (_) {
                        s.palette = i;
                        s.changed();
                      },
                    ),
                ]),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Modo oscuro'),
                  value: s.dark,
                  onChanged: (v) {
                    s.dark = v;
                    s.changed();
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Negro puro (AMOLED)'),
                  value: s.amoled,
                  onChanged: s.dark
                      ? (v) {
                          s.amoled = v;
                          s.changed();
                        }
                      : null,
                ),
                Text('Redondez de las tarjetas: ${s.radius.round()}'),
                Slider(
                  value: s.radius,
                  min: 0,
                  max: 32,
                  divisions: 8,
                  onChanged: (v) {
                    s.radius = v;
                    s.changed();
                  },
                ),
              ]),
            ),
            _h(context, 'Rutinas'),
            for (final r in s.myRoutines)
              Panel(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(r.name),
                  subtitle: Text(r.exerciseIds.map(s.exName).join(', ')),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      if (await confirm(context, 'Eliminar rutina', '¿Eliminar «${r.name}»?')) s.deleteRoutine(r.id);
                    },
                  ),
                ),
              ),
            if (s.myRoutines.isEmpty) const Text('Aún no hay rutinas. Guarda un entrenamiento como rutina desde la pantalla de entrenamiento.'),
            _h(context, 'Ejercicios'),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.add),
              label: const Text('Nuevo ejercicio'),
              onPressed: () async {
                final n = await askText(context, 'Nuevo ejercicio', hint: 'Nombre');
                if (n == null || n.trim().isEmpty || !context.mounted) return;
                final m = await askMuscle(context);
                if (m != null) s.addExercise(n, m);
              },
            ),
            for (final e in ([...s.exercises]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()))))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(e.name, style: TextStyle(decoration: e.archived ? TextDecoration.lineThrough : null)),
                subtitle: Text(e.muscle),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    icon: Icon(e.favorite ? Icons.star : Icons.star_border),
                    onPressed: () {
                      e.favorite = !e.favorite;
                      s.changed();
                    },
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'rename') {
                        final n = await askText(context, 'Renombrar', initial: e.name);
                        if (n != null && n.trim().isNotEmpty) {
                          e.name = n.trim();
                          s.changed();
                        }
                      } else if (v == 'muscle') {
                        final m = await askMuscle(context);
                        if (m != null) {
                          e.muscle = m;
                          s.changed();
                        }
                      } else if (v == 'archive') {
                        e.archived = !e.archived;
                        s.changed();
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'rename', child: Text('Renombrar')),
                      const PopupMenuItem(value: 'muscle', child: Text('Cambiar grupo muscular')),
                      PopupMenuItem(value: 'archive', child: Text(e.archived ? 'Restaurar' : 'Archivar')),
                    ],
                  ),
                ]),
              ),
            _h(context, 'Datos y respaldo'),
            Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Todo se guarda solo en este teléfono. Nada se envía a servidores.'),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.upload),
                    label: const Text('Exportar respaldo JSON'),
                    onPressed: () => _guard(context, () async {
                      final f = await s.writeBackupFile();
                      await Share.shareXFiles([XFile(f.path)], text: 'Respaldo GYMSHERONSO');
                    }),
                  ),
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.download),
                    label: const Text('Importar respaldo JSON'),
                    onPressed: () => _import(context),
                  ),
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.table_chart),
                    label: const Text('Exportar a Excel'),
                    onPressed: () => _guard(context, () async {
                      final f = await s.exportXlsx();
                      await Share.shareXFiles([XFile(f.path)], text: 'Datos GYMSHERONSO');
                    }),
                  ),
                ]),
                const SizedBox(height: 8),
                Text('Copia automática: cada 7 días en la carpeta interna de la app (se conservan 5).'
                    '${s.lastBackup == null ? '' : ' Última: ${fmtDate(s.lastBackup!)}.'}', style: const TextStyle(fontSize: 12)),
              ]),
            ),
            Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Datos de demostración (marcados con «DEMO»)'),
                Wrap(spacing: 8, children: [
                  OutlinedButton(onPressed: s.loadDemo, child: const Text('Cargar demo')),
                  OutlinedButton(
                    onPressed: () async {
                      if (await confirm(context, 'Quitar demo', 'Se eliminarán solo las sesiones y medidas marcadas como DEMO.')) s.removeDemo();
                    },
                    child: const Text('Quitar demo'),
                  ),
                ]),
              ]),
            ),
            _h(context, 'Permisos de Android'),
            const Text(
                'POST_NOTIFICATIONS: avisos del temporizador y recordatorios.\n'
                'USE_EXACT_ALARM / SCHEDULE_EXACT_ALARM: que el aviso de descanso suene a tiempo con la pantalla apagada.\n'
                'WAKE_LOCK: mantener la pantalla encendida durante el entrenamiento.\n'
                'VIBRATE: vibración al terminar el descanso.\n'
                'RECEIVE_BOOT_COMPLETED: reprogramar recordatorios tras reiniciar el teléfono.\n'
                'No se solicita Internet ni acceso a ubicación, contactos o almacenamiento.',
                style: TextStyle(fontSize: 12)),
            const SizedBox(height: 24),
          ]),
        );
      },
    );
  }

  Widget _h(BuildContext c, String t) =>
      Padding(padding: const EdgeInsets.only(top: 16, bottom: 4), child: Text(t, style: Theme.of(c).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)));

  Future<void> _guard(BuildContext context, Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (context.mounted) snack(context, 'Error: $e');
    }
  }

  Future<void> _import(BuildContext context) async {
    try {
      final r = await FilePicker.platform.pickFiles(type: FileType.any);
      final path = r?.files.single.path;
      if (path == null) return;
      final text = await File(path).readAsString();
      if (!context.mounted) return;
      if (!await confirm(context, 'Importar respaldo', 'Esto REEMPLAZARÁ todos los datos actuales por los del archivo. ¿Continuar?')) return;
      s.importJson(text);
      if (context.mounted) snack(context, 'Respaldo importado');
    } catch (e) {
      if (context.mounted) snack(context, 'No se pudo importar (archivo inválido): $e');
    }
  }

  Future<void> _editUser(BuildContext context, AppUser x) async {
    final n = await askText(context, 'Editar usuario', initial: x.name, hint: 'Nombre');
    if (n != null && n.trim().isNotEmpty) {
      x.name = n.trim();
      s.changed();
    }
    if (!context.mounted) return;
    final photo = await confirm(context, 'Foto de perfil', '¿Quieres elegir una foto de la galería para ${x.name}?');
    if (!photo) return;
    try {
      final img = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 512, imageQuality: 85);
      if (img != null) await s.setPhoto(x, img.path);
    } catch (e) {
      if (context.mounted) snack(context, 'No se pudo cargar la foto: $e');
    }
  }
}
