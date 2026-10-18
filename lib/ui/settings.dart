import 'package:flutter/material.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../data/storage.dart';
import '../main.dart';
import 'common.dart';
import 'home.dart';
import 'profile_edit.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool lock = false;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    LockGate.isEnabled().then((v) => setState(() => lock = v));
  }

  Future<void> _toggleLock(bool v) async {
    // włączenie wymaga potwierdzenia, że odblokowanie działa
    if (v && !await LockGate.authenticate()) {
      if (mounted) toast(context, 'Nie udało się potwierdzić – blokada nie została włączona');
      return;
    }
    await LockGate.setEnabled(v);
    setState(() => lock = v);
  }

  Future<void> _export() async {
    setState(() => busy = true);
    try {
      final ok = await Storage.exportBackup();
      if (mounted && ok) toast(context, 'Kopia zapasowa zapisana');
    } catch (e) {
      if (mounted) toast(context, 'Błąd: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _import() async {
    if (!await confirm(context, 'Przywrócić kopię?', 'Wszystkie obecne dane w aplikacji zostaną zastąpione danymi z kopii.', ok: 'Przywróć')) return;
    setState(() => busy = true);
    final err = await Storage.importBackup();
    if (!mounted) return;
    setState(() => busy = false);
    if (err == null) {
      toast(context, 'Przywrócono dane z kopii');
    } else if (err != 'Anulowano') {
      toast(context, err);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ustawienia')),
      body: AbsorbPointer(
        absorbing: busy,
        child: ListView(children: [
          if (busy) const LinearProgressIndicator(),
          const SectionTitle('Osoby'),
          Reloading<List<Profile>>(
            load: () => AppDb.I.getProfiles(),
            builder: (context, list) => Column(children: [
              for (final p in list)
                ListTile(
                  leading: ProfileAvatar(p),
                  title: Text(p.name),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileEditScreen(profile: p))),
                ),
              ListTile(
                leading: const Icon(Icons.person_add_alt),
                title: const Text('Dodaj osobę'),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileEditScreen())),
              ),
            ]),
          ),
          const SectionTitle('Prywatność'),
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint),
            title: const Text('Blokada aplikacji'),
            subtitle: const Text('Odcisk palca, twarz lub kod telefonu przy otwieraniu'),
            value: lock,
            onChanged: _toggleLock,
          ),
          const ListTile(
            leading: Icon(Icons.phonelink_lock_outlined),
            title: Text('Dane tylko na tym urządzeniu'),
            subtitle: Text('Pliki, wyniki i OCR nie są nigdzie wysyłane. Rób kopie zapasowe, by ich nie stracić.'),
          ),
          const SectionTitle('Kopia zapasowa'),
          ListTile(
            leading: const Icon(Icons.save_alt),
            title: const Text('Zapisz kopię zapasową'),
            subtitle: const Text('Plik .zip z bazą i wszystkimi dokumentami – np. na Dysk Google, iCloud, komputer'),
            onTap: _export,
          ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('Przywróć z kopii'),
            subtitle: const Text('Także do przeniesienia danych między Androidem a iPhonem'),
            onTap: _import,
          ),
          const SectionTitle('O aplikacji'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Teczka Zdrowia'),
            subtitle: Text('Wyniki rozpoznawane są automatycznie – zawsze porównaj je z oryginałem. '
                'Aplikacja nie jest wyrobem medycznym i nie zastępuje porady lekarza.'),
          ),
        ]),
      ),
    );
  }
}
