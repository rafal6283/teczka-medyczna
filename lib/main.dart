import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/db.dart';
import 'ui/common.dart';
import 'ui/home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppDb.I.init();
  runApp(const TeczkaApp());
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
      home: const LockGate(child: HomeScreen()),
    );
  }
}

/// Blokada aplikacji odciskiem palca / twarzą / kodem telefonu (opcjonalna).
class LockGate extends StatefulWidget {
  final Widget child;
  const LockGate({super.key, required this.child});

  static Future<bool> isEnabled() async => (await SharedPreferences.getInstance()).getBool('lock') ?? false;
  static Future<void> setEnabled(bool v) async => (await SharedPreferences.getInstance()).setBool('lock', v);

  static Future<bool> authenticate() async {
    final auth = LocalAuthentication();
    try {
      if (!await auth.isDeviceSupported()) return true;
      return await auth.authenticate(localizedReason: 'Odblokuj Teczkę Zdrowia');
    } catch (_) {
      return false;
    }
  }

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  bool locked = true;
  bool checking = false;
  DateTime? pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _check() async {
    if (!await LockGate.isEnabled()) {
      setState(() => locked = false);
      return;
    }
    if (checking) return;
    checking = true;
    final ok = await LockGate.authenticate();
    checking = false;
    if (mounted) setState(() => locked = !ok);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) pausedAt = DateTime.now();
    if (state == AppLifecycleState.resumed && pausedAt != null) {
      final away = DateTime.now().difference(pausedAt!);
      pausedAt = null;
      // krótkie wyjścia (np. wybór pliku, aparat) nie blokują
      if (away.inSeconds > 90) {
        LockGate.isEnabled().then((on) {
          if (on && mounted) {
            setState(() => locked = true);
            _check();
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!locked) return widget.child;
    return Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.lock_outline, size: 64, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text('Teczka Zdrowia', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 24),
          FilledButton.icon(onPressed: _check, icon: const Icon(Icons.fingerprint), label: const Text('Odblokuj')),
        ]),
      ),
    );
  }
}
