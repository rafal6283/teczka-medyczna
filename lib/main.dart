import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:koofr_backup_ui/koofr_backup_ui.dart';

import 'data/db.dart';
import 'data/koofr_backup.dart';
import 'data/med_notify.dart';
import 'security/lock.dart';
import 'ui/lock_screen.dart';
import 'ui/common.dart';
import 'ui/home.dart';

/// Kopia na Koofr w tle (Android) — także przy zamkniętej aplikacji.
@pragma('vm:entry-point')
void koofrCallback() => KoofrBackground.dispatch(() async {
      await AppDb.I.init();
      return TeczkaBackup();
    });

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TeczkaApp());
}

/// Start bazy danych z widocznym ekranem i komunikatem błędu (zamiast zawieszenia na logo).
class StartupGate extends StatefulWidget {
  const StartupGate({super.key});
  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  late Future<void> _init = _start();

  Future<void> _start() async {
    await AppDb.I.init().timeout(const Duration(seconds: 25));
    // kopia na Koofr — konfiguracja i ewentualna kopia w tle, bez wpływu na start
    try {
      await KoofrBackup.setup(TeczkaBackup()).timeout(const Duration(seconds: 5));
      KoofrBackground.start(koofrCallback).ignore();
    } catch (_) {}
    MedNotify.reschedule().ignore();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _init,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasError) {
          return Scaffold(
            body: SafeArea(
              child: ListView(padding: const EdgeInsets.all(24), children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 12),
                const Text('Nie udało się uruchomić aplikacji', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                SelectableText('Etap: ${AppDb.I.initStage}\n${snap.error}\n\n${snap.stackTrace ?? ''}', style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                const SizedBox(height: 16),
                FilledButton(onPressed: () => setState(() => _init = _start()), child: const Text('Spróbuj ponownie')),
              ]),
            ),
          );
        }
        return const LockGate(child: HomeScreen());
      },
    );
  }
}

class TeczkaApp extends StatelessWidget {
  const TeczkaApp({super.key});

  ThemeData _theme(Brightness b) {
    final cs = ColorScheme.fromSeed(seedColor: seed, brightness: b);
    return ThemeData(
      colorScheme: cs,
      useMaterial3: true,
      appBarTheme: AppBarTheme(backgroundColor: cs.surface, scrolledUnderElevation: 1, centerTitle: false),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), isDense: true),
      listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Teczka Zdrowia',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      locale: const Locale('pl'),
      supportedLocales: const [Locale('pl'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const StartupGate(),
    );
  }
}

/// Logowanie do aplikacji (PIN, wzór, blokada telefonu, biometria).
class LockGate extends StatefulWidget {
  final Widget child;
  const LockGate({super.key, required this.child});

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  LockConfig? config;
  bool locked = true;
  DateTime? pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load() async {
    final c = await Lock.load();
    if (!mounted) return;
    setState(() {
      config = c;
      locked = c.method != LockMethod.none;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) pausedAt ??= DateTime.now();
    if (state == AppLifecycleState.resumed && pausedAt != null) {
      final away = DateTime.now().difference(pausedAt!);
      pausedAt = null;
      Lock.load().then((c) {
        if (!mounted) return;
        // krótkie wyjścia (wybór pliku, aparat, logowanie biometrią) nie blokują
        final limit = c.timeoutSec < 15 ? 15 : c.timeoutSec;
        if (c.method != LockMethod.none && away.inSeconds >= limit) {
          setState(() {
            config = c;
            locked = true;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = config;
    if (c == null) return const Scaffold(body: SizedBox());
    if (!locked) return widget.child;
    return LockScreen(config: c, onUnlocked: () => setState(() => locked = false));
  }
}
