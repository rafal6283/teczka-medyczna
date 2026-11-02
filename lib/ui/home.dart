import 'package:flutter/material.dart';

import '../data/db.dart';
import '../data/models.dart';
import 'common.dart';
import 'documents.dart';
import 'import_flow.dart';
import 'measurements.dart';
import 'meds.dart';
import 'params.dart';
import 'profile_edit.dart';
import 'settings.dart';
import 'summary.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int tab = 0;
  List<Profile>? profiles;

  @override
  void initState() {
    super.initState();
    AppDb.I.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    AppDb.I.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final l = await AppDb.I.getProfiles();
    if (mounted) setState(() => profiles = l);
  }

  @override
  Widget build(BuildContext context) {
    final profiles = this.profiles;
    if (profiles == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (profiles.isEmpty) return const _Welcome();
    final cur = profiles.firstWhere((p) => p.id == AppDb.I.currentProfileId, orElse: () => profiles.first);
    final pages = [
      SummaryTab(profile: cur, goTo: (t) => setState(() => tab = t)),
      DocumentsTab(profile: cur),
      ParamsTab(profile: cur),
      MeasurementsTab(profile: cur),
      MedsTab(profile: cur),
    ];
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 8,
        title: _ProfileSwitcher(current: cur, profiles: profiles),
        actions: [
          IconButton(
            tooltip: 'Ustawienia',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: IndexedStack(index: tab, children: pages),
      floatingActionButton: tab == 1 || tab == 0
          ? FloatingActionButton.extended(
              onPressed: () => startImport(context, cur),
              icon: const Icon(Icons.add),
              label: const Text('Dodaj wynik'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Podsumowanie'),
          NavigationDestination(icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder), label: 'Dokumenty'),
          NavigationDestination(icon: Icon(Icons.show_chart), selectedIcon: Icon(Icons.insights), label: 'Parametry'),
          NavigationDestination(icon: Icon(Icons.monitor_heart_outlined), selectedIcon: Icon(Icons.monitor_heart), label: 'Pomiary'),
          NavigationDestination(icon: Icon(Icons.medication_outlined), selectedIcon: Icon(Icons.medication), label: 'Leki'),
        ],
      ),
    );
  }
}

class ProfileAvatar extends StatelessWidget {
  final Profile p;
  final double radius;
  const ProfileAvatar(this.p, {super.key, this.radius = 16});
  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: radius,
        backgroundColor: Color(p.color),
        child: Text(p.initials, style: TextStyle(color: Colors.white, fontSize: radius * 0.8, fontWeight: FontWeight.w600)),
      );
}

class _ProfileSwitcher extends StatelessWidget {
  final Profile current;
  final List<Profile> profiles;
  const _ProfileSwitcher({required this.current, required this.profiles});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => showModalBottomSheet(
        context: context,
        showDragHandle: true,
        builder: (c) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final p in profiles)
              ListTile(
                leading: ProfileAvatar(p),
                title: Text(p.name),
                trailing: p.id == current.id ? const Icon(Icons.check) : null,
                onTap: () {
                  Navigator.pop(c);
                  AppDb.I.selectProfile(p.id);
                },
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.person_add_alt),
              title: const Text('Dodaj osobę'),
              onTap: () {
                Navigator.pop(c);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileEditScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text('Edytuj dane: ${current.name}'),
              onTap: () {
                Navigator.pop(c);
                Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileEditScreen(profile: current)));
              },
            ),
          ]),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          ProfileAvatar(current),
          const SizedBox(width: 10),
          Flexible(child: Text(current.name, overflow: TextOverflow.ellipsis)),
          const Icon(Icons.arrow_drop_down),
        ]),
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome();
  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: EmptyState(
            icon: Icons.folder_shared_outlined,
            title: 'Witaj w Teczce Zdrowia',
            text: 'Przechowuj wyniki badań całej rodziny w jednym miejscu. Aplikacja odczyta wartości z PDF-ów i skanów, '
                'a potem pokaże, jak zmieniają się w czasie.\n\nDane zostają tylko na tym telefonie.',
            action: FilledButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileEditScreen())),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Dodaj pierwszą osobę'),
            ),
          ),
        ),
      );
}
