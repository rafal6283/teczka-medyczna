import 'package:flutter/material.dart';
import '../data/db.dart';

import '../parse/text_utils.dart';

const seed = Color(0xFF0E7466);

class StatusColors {
  static Color high(BuildContext c) => Theme.of(c).brightness == Brightness.dark ? const Color(0xFFFF8A80) : const Color(0xFFC62828);
  static Color low(BuildContext c) => Theme.of(c).brightness == Brightness.dark ? const Color(0xFF82B1FF) : const Color(0xFF1565C0);
  static Color ok(BuildContext c) => Theme.of(c).brightness == Brightness.dark ? const Color(0xFF69F0AE) : const Color(0xFF2E7D32);
  static Color warn(BuildContext c) => Theme.of(c).brightness == Brightness.dark ? const Color(0xFFFFD180) : const Color(0xFFE65100);
  static Color none(BuildContext c) => Theme.of(c).colorScheme.outline;

  static Color of(BuildContext c, int? status) {
    if (status == null) return none(c);
    if (status > 0) return high(c);
    if (status < 0) return low(c);
    return ok(c);
  }
}

String statusLabel(int? s) {
  if (s == null) return 'brak normy';
  if (s > 0) return 'powyżej normy';
  if (s < 0) return 'poniżej normy';
  return 'w normie';
}

class StatusDot extends StatelessWidget {
  final int? status;
  final double size;
  const StatusDot(this.status, {super.key, this.size = 10});
  @override
  Widget build(BuildContext context) =>
      Container(width: size, height: size, decoration: BoxDecoration(color: StatusColors.of(context, status), shape: BoxShape.circle));
}

class StatusChip extends StatelessWidget {
  final int? status;
  const StatusChip(this.status, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = StatusColors.of(context, status);
    final icon = status == null
        ? Icons.remove
        : status! > 0
            ? Icons.arrow_upward
            : status! < 0
                ? Icons.arrow_downward
                : Icons.check;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: c),
        const SizedBox(width: 4),
        Text(statusLabel(status), style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class TrendIcon extends StatelessWidget {
  final int trend;
  const TrendIcon(this.trend, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.onSurfaceVariant;
    if (trend > 0) return Icon(Icons.trending_up, size: 18, color: c);
    if (trend < 0) return Icon(Icons.trending_down, size: 18, color: c);
    return Icon(Icons.trending_flat, size: 18, color: c);
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 8, 8),
        child: Row(children: [
          Expanded(
              child: Text(text.toUpperCase(),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Theme.of(context).colorScheme.primary, letterSpacing: 0.8, fontWeight: FontWeight.w700))),
          if (trailing != null) trailing!,
        ]),
      );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.title, required this.text, this.action});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ]),
        ),
      );
}

class InfoCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? color;
  const InfoCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.color});
  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        elevation: 0,
        color: color ?? Theme.of(context).colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
      );
}

Future<bool> confirm(BuildContext context, String title, String text, {String ok = 'Usuń', bool destructive = true}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(text),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Anuluj')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

Future<DateTime?> pickDate(BuildContext context, DateTime initial, {DateTime? first}) => showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first ?? DateTime(1900),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('pl'),
    );

void toast(BuildContext context, String text) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
}

/// Pole daty jako przycisk.
class DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final DateTime? first;
  const DateField({super.key, required this.label, required this.value, required this.onChanged, this.first});
  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () async {
          final d = await pickDate(context, value ?? DateTime.now(), first: first);
          if (d != null) onChanged(d);
        },
        child: InputDecorator(
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), suffixIcon: const Icon(Icons.calendar_today, size: 20)),
          child: Text(value == null ? 'wybierz' : fmtDate(value)),
        ),
      );
}

double? parseInput(String s) => parseNum(s);

String fmtValue(double? v, String? text) => text ?? fmtNum(v);

const profileColors = [
  0xFF0E7466,
  0xFF1565C0,
  0xFF6A1B9A,
  0xFFC2185B,
  0xFFE65100,
  0xFF2E7D32,
  0xFF5D4037,
  0xFF455A64,
];

/// Ładuje dane i przeładowuje je po każdej zmianie w bazie, nie gubiąc poprzedniego widoku.
class Reloading<T> extends StatefulWidget {
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data) builder;
  final Object? dep;
  const Reloading({super.key, required this.load, required this.builder, this.dep});
  @override
  State<Reloading<T>> createState() => _ReloadingState<T>();
}

class _ReloadingState<T> extends State<Reloading<T>> {
  T? data;
  bool has = false;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    AppDb.I.addListener(_reload);
    _reload();
  }

  @override
  void didUpdateWidget(covariant Reloading<T> old) {
    super.didUpdateWidget(old);
    if (old.dep != widget.dep) {
      has = false;
      _reload();
    }
  }

  @override
  void dispose() {
    AppDb.I.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final g = ++_gen;
    final d = await widget.load();
    if (!mounted || g != _gen) return;
    setState(() {
      data = d;
      has = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!has) return const Center(child: CircularProgressIndicator());
    return widget.builder(context, data as T);
  }
}
