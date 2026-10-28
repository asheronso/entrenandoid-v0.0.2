import 'package:flutter/material.dart';
import 'screens/history.dart';
import 'screens/home.dart';
import 'screens/progress.dart';
import 'screens/settings.dart';
import 'screens/workout.dart';
import 'services.dart';
import 'store.dart';
import 'theme.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = AppStore();
  await store.load();
  await Services.init();
  runApp(GymApp(store));
  Services.scheduleReminders(store);
}

class GymApp extends StatelessWidget {
  final AppStore store;
  const GymApp(this.store, {super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) => MaterialApp(
          title: 'GYMSHERONSO',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(store),
          home: Shell(store: store),
        ),
      );
}

class Shell extends StatefulWidget {
  final AppStore store;
  const Shell({super.key, required this.store});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  int tab = 0;
  AppStore get s => widget.store;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (s.lastError != null && mounted) {
        snack(context, s.lastError!);
        s.lastError = null;
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) s.tick();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: tab, children: [
        HomePage(store: s),
        HistoryPage(store: s),
        ProgressPage(store: s),
        SettingsPage(store: s),
      ]),
      floatingActionButton: ListenableBuilder(
        listenable: s,
        builder: (context, _) => FloatingActionButton.extended(
          onPressed: () => openWorkout(context, s),
          icon: Icon(s.draft != null ? Icons.play_arrow : Icons.fitness_center),
          label: Text(s.draft != null ? 'Continuar' : 'Entrenar'),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Inicio'),
          NavigationDestination(icon: Icon(Icons.history), label: 'Historial'),
          NavigationDestination(icon: Icon(Icons.show_chart), label: 'Progreso'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Ajustes'),
        ],
      ),
    );
  }
}
