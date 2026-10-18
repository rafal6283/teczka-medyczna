import 'package:flutter/material.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../parse/text_utils.dart';
import 'common.dart';

class ProfileEditScreen extends StatefulWidget {
  final Profile? profile;
  const ProfileEditScreen({super.key, this.profile});
  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  late final name = TextEditingController(text: widget.profile?.name ?? '');
  late final height = TextEditingController(text: widget.profile?.heightCm == null ? '' : fmtNum(widget.profile!.heightCm));
  late final allergies = TextEditingController(text: widget.profile?.allergies ?? '');
  late final chronic = TextEditingController(text: widget.profile?.chronic ?? '');
  late final meds = TextEditingController(text: widget.profile?.medications ?? '');
  late final notes = TextEditingController(text: widget.profile?.notes ?? '');
  late DateTime? birth = widget.profile?.birthDate;
  late String? sex = widget.profile?.sex;
  late String? blood = widget.profile?.bloodType;
  late int color = widget.profile?.color ?? profileColors[0];

  static const bloodTypes = ['0 Rh+', '0 Rh−', 'A Rh+', 'A Rh−', 'B Rh+', 'B Rh−', 'AB Rh+', 'AB Rh−'];

  Future<void> _save() async {
    if (name.text.trim().isEmpty) {
      toast(context, 'Podaj imię');
      return;
    }
    final p = Profile(
      id: widget.profile?.id,
      name: name.text.trim(),
      birthDate: birth,
      sex: sex,
      heightCm: parseNum(height.text),
      bloodType: blood,
      allergies: allergies.text.trim().isEmpty ? null : allergies.text.trim(),
      chronic: chronic.text.trim().isEmpty ? null : chronic.text.trim(),
      medications: meds.text.trim().isEmpty ? null : meds.text.trim(),
      notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
      color: color,
    );
    final id = await AppDb.I.saveProfile(p);
    if (widget.profile == null) await AppDb.I.selectProfile(id);
    // wzrost zapisujemy też jako pomiar, żeby śledzić go w czasie (dzieci)
    final h = parseNum(height.text);
    if (h != null && h != widget.profile?.heightCm) {
      await AppDb.I.saveMeasurement(Measurement(profileId: id, date: DateTime.now(), type: MType.height.key, value: h));
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final p = widget.profile!;
    if (!await confirm(context, 'Usunąć ${p.name}?', 'Zostaną usunięte wszystkie dokumenty, pliki, wyniki i pomiary tej osoby. Tego nie da się cofnąć.')) return;
    await AppDb.I.deleteProfile(p.id!);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 14);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.profile == null ? 'Nowa osoba' : 'Dane osoby'),
        actions: [
          if (widget.profile != null) IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline), tooltip: 'Usuń osobę'),
          TextButton(onPressed: _save, child: const Text('Zapisz')),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Imię i nazwisko'), textCapitalization: TextCapitalization.words),
        gap,
        Row(children: [
          Expanded(child: DateField(label: 'Data urodzenia', value: birth, onChanged: (d) => setState(() => birth = d))),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: height,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Wzrost', suffixText: 'cm'),
            ),
          ),
        ]),
        if (birth != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text('Wiek: ${ageOn(birth!, DateTime.now())} lat', style: Theme.of(context).textTheme.bodySmall),
          ),
        gap,
        Text('Płeć (wpływa na normy, gdy wynik ich nie podaje)', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 6),
        SegmentedButton<String?>(
          segments: const [
            ButtonSegment(value: 'K', label: Text('Kobieta')),
            ButtonSegment(value: 'M', label: Text('Mężczyzna')),
            ButtonSegment(value: null, label: Text('Nie podano')),
          ],
          selected: {sex},
          onSelectionChanged: (s) => setState(() => sex = s.first),
        ),
        gap,
        DropdownButtonFormField<String?>(
          initialValue: blood,
          decoration: const InputDecoration(labelText: 'Grupa krwi'),
          items: [
            const DropdownMenuItem(value: null, child: Text('nieznana')),
            for (final b in bloodTypes) DropdownMenuItem(value: b, child: Text(b)),
          ],
          onChanged: (v) => setState(() => blood = v),
        ),
        gap,
        TextField(controller: allergies, decoration: const InputDecoration(labelText: 'Alergie'), maxLines: null),
        gap,
        TextField(controller: chronic, decoration: const InputDecoration(labelText: 'Choroby przewlekłe'), maxLines: null),
        gap,
        TextField(controller: meds, decoration: const InputDecoration(labelText: 'Przyjmowane leki'), maxLines: null),
        gap,
        TextField(controller: notes, decoration: const InputDecoration(labelText: 'Notatki'), maxLines: null),
        gap,
        Text('Kolor', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final c in profileColors)
            GestureDetector(
              onTap: () => setState(() => color = c),
              child: CircleAvatar(
                radius: 18,
                backgroundColor: Color(c),
                child: color == c ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
              ),
            ),
        ]),
        const SizedBox(height: 32),
      ]),
    );
  }
}
