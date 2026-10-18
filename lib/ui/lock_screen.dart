import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../security/lock.dart';
import 'common.dart';

// ---------------- klawiatura PIN ----------------

class PinPad extends StatelessWidget {
  final int length;
  final int maxLength;
  final ValueChanged<String> onDigit;
  final VoidCallback onDelete;
  final VoidCallback? onBiometric;
  final VoidCallback? onOk;
  const PinPad({super.key, required this.length, required this.onDigit, required this.onDelete, this.onBiometric, this.onOk, this.maxLength = 8});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget key(Widget child, VoidCallback? onTap) => Padding(
          padding: const EdgeInsets.all(8),
          child: SizedBox(
            width: 74,
            height: 74,
            child: Material(
              color: onTap == null ? Colors.transparent : cs.surfaceContainerHigh,
              shape: const CircleBorder(),
              child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: Center(child: child)),
            ),
          ),
        );
    Widget digit(String d) => key(Text(d, style: Theme.of(context).textTheme.headlineSmall), () {
          HapticFeedback.selectionClick();
          onDigit(d);
        });
    return Column(mainAxisSize: MainAxisSize.min, children: [
      for (final row in const [
        ['1', '2', '3'],
        ['4', '5', '6'],
        ['7', '8', '9']
      ])
        Row(mainAxisSize: MainAxisSize.min, children: [for (final d in row) digit(d)]),
      Row(mainAxisSize: MainAxisSize.min, children: [
        onBiometric != null
            ? key(Icon(Icons.fingerprint, size: 30, color: cs.primary), onBiometric)
            : onOk != null
                ? key(Icon(Icons.check, size: 30, color: cs.primary), length >= 4 ? onOk : null)
                : key(const SizedBox(), null),
        digit('0'),
        key(const Icon(Icons.backspace_outlined), length > 0 ? onDelete : null),
      ]),
    ]);
  }
}

class PinDots extends StatelessWidget {
  final int filled;
  final int count;
  final bool error;
  const PinDots({super.key, required this.filled, this.count = 4, this.error = false});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final n = max(count, filled);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < n; i++)
        AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(horizontal: 7),
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: i < filled ? (error ? cs.error : cs.primary) : Colors.transparent,
            border: Border.all(color: error ? cs.error : cs.outline, width: 1.6),
          ),
        ),
    ]);
  }
}

// ---------------- wzór (siatka 3×3) ----------------

class PatternPad extends StatefulWidget {
  final ValueChanged<List<int>> onComplete;
  final bool error;
  final double size;
  const PatternPad({super.key, required this.onComplete, this.error = false, this.size = 280});
  @override
  State<PatternPad> createState() => _PatternPadState();
}

class _PatternPadState extends State<PatternPad> {
  final List<int> path = [];
  Offset? finger;

  Offset _center(int i) {
    final cell = widget.size / 3;
    return Offset((i % 3) * cell + cell / 2, (i ~/ 3) * cell + cell / 2);
  }

  void _hit(Offset p) {
    final r = widget.size / 3 * 0.32;
    for (var i = 0; i < 9; i++) {
      if ((p - _center(i)).distance <= r && !path.contains(i)) {
        // punkt pośredni na linii (np. 0 → 2 przechodzi przez 1)
        if (path.isNotEmpty) {
          final a = path.last;
          final mid = (a + i) ~/ 2;
          final sameRowOrColOrDiag = (a + i) % 2 == 0 && (_center(mid) - (_center(a) + _center(i)) / 2).distance < 1;
          if (sameRowOrColOrDiag && !path.contains(mid)) path.add(mid);
        }
        path.add(i);
        HapticFeedback.selectionClick();
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onPanStart: (d) => setState(() {
        path.clear();
        finger = d.localPosition;
        _hit(d.localPosition);
      }),
      onPanUpdate: (d) => setState(() {
        finger = d.localPosition;
        _hit(d.localPosition);
      }),
      onPanEnd: (_) {
        final done = List<int>.of(path);
        setState(() => finger = null);
        if (done.isNotEmpty) widget.onComplete(done);
        Future.delayed(const Duration(milliseconds: 350), () {
          if (mounted) setState(() => path.clear());
        });
      },
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _PatternPainter(path, finger, _center, widget.error ? cs.error : cs.primary, cs.outline),
      ),
    );
  }
}

class _PatternPainter extends CustomPainter {
  final List<int> path;
  final Offset? finger;
  final Offset Function(int) center;
  final Color active, idle;
  _PatternPainter(this.path, this.finger, this.center, this.active, this.idle);

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = active.withValues(alpha: 0.6)
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    for (var i = 1; i < path.length; i++) {
      canvas.drawLine(center(path[i - 1]), center(path[i]), line);
    }
    if (finger != null && path.isNotEmpty) canvas.drawLine(center(path.last), finger!, line);
    for (var i = 0; i < 9; i++) {
      final on = path.contains(i);
      canvas.drawCircle(center(i), on ? 14 : 8, Paint()..color = on ? active : idle);
      if (on) {
        canvas.drawCircle(center(i), 26, Paint()
          ..color = active.withValues(alpha: 0.15));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PatternPainter o) => true;
}

String patternToSecret(List<int> p) => 'P:${p.join('-')}';

// ---------------- ekran logowania ----------------

class LockScreen extends StatefulWidget {
  final LockConfig config;
  final VoidCallback onUnlocked;
  const LockScreen({super.key, required this.config, required this.onUnlocked});
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String pin = '';
  bool error = false;
  bool busy = false;
  int wait = 0;
  Timer? timer;
  String? message;

  @override
  void initState() {
    super.initState();
    _refreshWait();
    if (widget.config.method == LockMethod.device || widget.config.biometric) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _system());
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _refreshWait() async {
    final w = await Lock.waitSeconds();
    if (!mounted) return;
    setState(() => wait = w);
    timer?.cancel();
    if (w > 0) {
      timer = Timer.periodic(const Duration(seconds: 1), (t) async {
        final x = await Lock.waitSeconds();
        if (!mounted) return;
        setState(() => wait = x);
        if (x <= 0) t.cancel();
      });
    }
  }

  Future<void> _system() async {
    final ok = await Lock.systemAuth(biometricOnly: widget.config.method != LockMethod.device);
    if (ok && mounted) widget.onUnlocked();
  }

  Future<void> _check(String secret) async {
    if (busy || wait > 0) return;
    setState(() => busy = true);
    final ok = await Lock.verify(secret);
    if (!mounted) return;
    if (ok) {
      widget.onUnlocked();
      return;
    }
    HapticFeedback.heavyImpact();
    final f = await Lock.failures();
    setState(() {
      busy = false;
      error = true;
      pin = '';
      message = widget.config.method == LockMethod.pin ? 'Nieprawidłowy PIN' : 'Nieprawidłowy wzór';
      if (f >= 3 && f < 5) message = '$message (pozostało prób: ${5 - f})';
    });
    await _refreshWait();
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => error = false);
    });
  }

  Future<void> _forgot() async {
    final ok = await confirm(
      context,
      'Nie pamiętasz?',
      'Możesz odblokować aplikację blokadą ekranu telefonu (PIN, wzór lub odcisk palca telefonu), a potem ustawić nowe zabezpieczenie w Ustawieniach.',
      ok: 'Użyj blokady telefonu',
      destructive: false,
    );
    if (!ok) return;
    if (await Lock.systemAuth(biometricOnly: false, reason: 'Potwierdź, że to Ty')) {
      await Lock.resetFailures();
      if (mounted) widget.onUnlocked();
    } else if (mounted) {
      toast(context, 'Nie udało się potwierdzić tożsamości');
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.config.method;
    final cs = Theme.of(context).colorScheme;
    final waiting = wait > 0;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.lock_outline, size: 44, color: cs.primary),
              const SizedBox(height: 10),
              Text('Teczka Zdrowia', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 6),
              Text(
                waiting
                    ? 'Zbyt wiele prób. Spróbuj za $wait s.'
                    : message ?? (m == LockMethod.pin ? 'Wpisz PIN' : m == LockMethod.pattern ? 'Narysuj wzór' : 'Odblokuj, aby kontynuować'),
                style: TextStyle(color: (error || waiting) ? cs.error : cs.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              if (m == LockMethod.pin) ...[
                PinDots(filled: pin.length, count: max(4, pin.length), error: error),
                const SizedBox(height: 24),
                IgnorePointer(
                  ignoring: waiting || busy,
                  child: Opacity(
                    opacity: waiting ? 0.4 : 1,
                    child: PinPad(
                      length: pin.length,
                      onDigit: (d) {
                        if (pin.length >= 8) return;
                        setState(() {
                          pin += d;
                          message = null;
                        });
                      },
                      onDelete: () => setState(() => pin = pin.substring(0, pin.length - 1)),
                      onBiometric: widget.config.biometric ? _system : null,
                      onOk: () => _check(pin),
                    ),
                  ),
                ),
                if (widget.config.biometric)
                  TextButton(onPressed: pin.length >= 4 ? () => _check(pin) : null, child: const Text('Zatwierdź PIN')),
              ],
              if (m == LockMethod.pattern) ...[
                IgnorePointer(
                  ignoring: waiting || busy,
                  child: Opacity(opacity: waiting ? 0.4 : 1, child: PatternPad(error: error, onComplete: (p) => _check(patternToSecret(p)))),
                ),
                if (widget.config.biometric)
                  TextButton.icon(onPressed: _system, icon: const Icon(Icons.fingerprint), label: const Text('Użyj biometrii')),
              ],
              if (m == LockMethod.device)
                FilledButton.icon(onPressed: _system, icon: const Icon(Icons.fingerprint), label: const Text('Odblokuj')),
              if (m == LockMethod.pin || m == LockMethod.pattern)
                TextButton(onPressed: _forgot, child: Text(m == LockMethod.pin ? 'Nie pamiętam PIN-u' : 'Nie pamiętam wzoru')),
            ]),
          ),
        ),
      ),
    );
  }
}

// ---------------- ustawianie PIN-u / wzoru ----------------

class LockSetupScreen extends StatefulWidget {
  final LockMethod method;
  const LockSetupScreen({super.key, required this.method});
  @override
  State<LockSetupScreen> createState() => _LockSetupScreenState();
}

class _LockSetupScreenState extends State<LockSetupScreen> {
  String? first;
  String pin = '';
  String? error;

  bool get isPin => widget.method == LockMethod.pin;

  Future<void> _submit(String secret, {int points = 0}) async {
    if (!isPin && points < 4) {
      setState(() => error = 'Połącz co najmniej 4 punkty');
      return;
    }
    if (first == null) {
      setState(() {
        first = secret;
        pin = '';
        error = null;
      });
      return;
    }
    if (first != secret) {
      setState(() {
        first = null;
        pin = '';
        error = isPin ? 'PIN-y się różnią – zacznij od nowa' : 'Wzory się różnią – zacznij od nowa';
      });
      return;
    }
    await Lock.setSecret(widget.method, secret);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = isPin ? (first == null ? 'Ustaw PIN (4–8 cyfr)' : 'Powtórz PIN') : (first == null ? 'Narysuj wzór' : 'Narysuj wzór ponownie');
    return Scaffold(
      appBar: AppBar(title: Text(isPin ? 'Nowy PIN' : 'Nowy wzór')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(error ?? ' ', style: TextStyle(color: cs.error)),
            const SizedBox(height: 18),
            if (isPin) ...[
              PinDots(filled: pin.length, count: max(4, pin.length)),
              const SizedBox(height: 24),
              PinPad(
                length: pin.length,
                onDigit: (d) {
                  if (pin.length >= 8) return;
                  setState(() {
                    pin += d;
                    error = null;
                  });
                },
                onDelete: () => setState(() => pin = pin.substring(0, pin.length - 1)),
                onOk: () => _submit(pin),
              ),
              const SizedBox(height: 8),
              Text('Zatwierdź przyciskiem ✓', style: Theme.of(context).textTheme.bodySmall),
            ] else
              PatternPad(onComplete: (p) => _submit(patternToSecret(p), points: p.length)),
          ]),
        ),
      ),
    );
  }
}
