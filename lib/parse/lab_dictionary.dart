// Słownik najczęstszych parametrów badań w polskich wynikach laboratoryjnych.
// Zakresy są orientacyjne – używane tylko wtedy, gdy wynik nie podaje własnej normy.

import 'text_utils.dart';

class LabParam {
  final String key;
  final String name;
  final String category;
  final String unit;
  final double? low, high;
  double? mLow, mHigh, fLow, fHigh;
  final List<String> aliases = [];

  /// Klucz wariantu procentowego (np. neutrofile % obok bezwzględnych).
  String? pctKey;

  /// wartość w jednostce X * mnożnik = wartość w jednostce podstawowej
  final Map<String, double> conv = {};

  LabParam(this.key, this.name, this.category, this.unit, this.low, this.high);

  LabParam a(List<String> al) {
    for (final s in al) {
      final n = normText(s);
      aliases.add(n);
      // "P/c. anty-tTG", "Przeciwciała anty-…" – ten sam parametr
      if (n.startsWith('anty ')) {
        aliases.add('p c $n');
        aliases.add('pc $n');
        aliases.add('przeciwciala $n');
        aliases.add('p c p $n');
      }
    }
    return this;
  }

  LabParam m(double? l, double? h) {
    mLow = l;
    mHigh = h;
    return this;
  }

  LabParam f(double? l, double? h) {
    fLow = l;
    fHigh = h;
    return this;
  }

  LabParam pct(String k) {
    pctKey = k;
    return this;
  }

  LabParam c(String u, double factor) {
    conv[normUnit(u)] = factor;
    return this;
  }

  bool _hasM() => mLow != null || mHigh != null;
  bool _hasF() => fLow != null || fHigh != null;

  double? lowFor(String? sex) {
    if (sex == 'M' && _hasM()) return mLow;
    if (sex == 'K' && _hasF()) return fLow;
    return low;
  }

  double? highFor(String? sex) {
    if (sex == 'M' && _hasM()) return mHigh;
    if (sex == 'K' && _hasF()) return fHigh;
    return high;
  }

  /// Przelicza na jednostkę podstawową; null gdy nie wiadomo jak.
  double? toBase(double v, String? fromUnit) {
    final u = normUnit(fromUnit ?? '');
    if (u.isEmpty || u == normUnit(unit)) return v;
    final f = conv[u];
    return f == null ? null : v * f;
  }
}

class LabDictionary {
  static const morf = 'Morfologia';
  static const bio = 'Biochemia';
  static const lip = 'Lipidogram';
  static const wat = 'Wątroba i trzustka';
  static const ner = 'Nerki i elektrolity';
  static const tar = 'Tarczyca';
  static const hor = 'Hormony';
  static const zel = 'Żelazo i witaminy';
  static const zap = 'Stan zapalny';
  static const krz = 'Krzepnięcie';
  static const moc = 'Mocz';
  static const ekg = 'EKG i Holter';
  static const imm = 'Immunologia i serologia';
  static const inne = 'Inne';

  static const categoryOrder = [morf, bio, lip, wat, ner, tar, hor, zel, zap, imm, krz, moc, ekg, inne];

  static final Map<String, LabParam> byKey = {};

  /// (alias, parametr) od najdłuższego aliasu.
  static final List<MapEntry<String, LabParam>> aliases = [];

  static bool _ready = false;

  static LabParam _p(String key, String name, String cat, String unit, double? low, double? high) {
    final x = LabParam(key, name, cat, unit, low, high);
    byKey[key] = x;
    return x;
  }

  static LabParam? get(String key) {
    ensure();
    return byKey[key];
  }

  static List<LabParam> all() {
    ensure();
    return byKey.values.toList();
  }

  static LabParam resolve(LabParam base, bool percent) {
    if (percent && base.pctKey != null) return byKey[base.pctKey!] ?? base;
    return base;
  }

  static LabParam? findByName(String name) {
    ensure();
    final n = normText(name);
    for (final a in aliases) {
      if (a.key == n) return a.value;
    }
    for (final x in byKey.values) {
      if (normText(x.name) == n) return x;
    }
    return null;
  }

  static void ensure() {
    if (_ready) return;
    _ready = true;
    const cell = ['10^9/l', 'g/l', '10^3/ul', 'k/ul', 'tys/ul', 'tys./ul'];
    LabParam cells(LabParam p) {
      for (final u in cell) {
        p.c(u, 1);
      }
      return p;
    }

    LabParam enz(LabParam p) => p.c('iu/l', 1).c('j/l', 1).c('u/l', 1);

    // ---------- Morfologia ----------
    cells(_p('WBC', 'Leukocyty (WBC)', morf, 'tys/µl', 4.0, 10.0)
        .a(['leukocyty', 'wbc', 'krwinki białe', 'białe krwinki', 'leukocyty wbc', 'wbc leukocyty', 'krwinki białe wbc']));
    _p('RBC', 'Erytrocyty (RBC)', morf, 'mln/µl', 4.2, 5.4)
        .m(4.5, 5.9)
        .f(4.0, 5.2)
        .a(['erytrocyty', 'rbc', 'krwinki czerwone', 'czerwone krwinki', 'erytrocyty rbc', 'rbc erytrocyty', 'krwinki czerwone rbc'])
        .c('10^12/l', 1)
        .c('t/l', 1)
        .c('10^6/ul', 1)
        .c('m/ul', 1)
        .c('mln/ul', 1);
    _p('HGB', 'Hemoglobina (HGB)', morf, 'g/dl', 12.0, 16.0)
        .m(13.5, 17.5)
        .f(12.0, 15.5)
        .a(['hemoglobina', 'hgb', 'hb', 'hemoglobina hgb', 'hgb hemoglobina'])
        .c('g/l', 0.1)
        .c('mmol/l', 1.611);
    _p('HCT', 'Hematokryt (HCT)', morf, '%', 37.0, 47.0)
        .m(40.0, 52.0)
        .f(36.0, 46.0)
        .a(['hematokryt', 'hct', 'hematokryt hct', 'hct hematokryt'])
        .c('l/l', 100);
    _p('MCV', 'MCV', morf, 'fl', 80.0, 100.0).a(['mcv', 'średnia objętość krwinki', 'średnia objętość krwinki czerwonej', 'średnia objętość erytrocytu', 'mcv średnia objętość krwinki czerwonej']);
    _p('MCH', 'MCH', morf, 'pg', 27.0, 34.0).a(['mch', 'średnia masa hemoglobiny w krwince', 'średnia zawartość hemoglobiny w erytrocycie', 'średnia masa hemoglobiny w krwince czerwonej']);
    _p('MCHC', 'MCHC', morf, 'g/dl', 32.0, 36.0)
        .a(['mchc', 'średnie stężenie hemoglobiny w krwince', 'średnie stężenie hemoglobiny w krwince czerwonej'])
        .c('g/l', 0.1)
        .c('mmol/l', 1.611);
    _p('RDW', 'RDW-CV', morf, '%', 11.5, 14.5).a(['rdw', 'rdw cv', 'wskaźnik anizocytozy', 'rozkład objętości erytrocytów']);
    _p('RDWSD', 'RDW-SD', morf, 'fl', 37.0, 54.0).a(['rdw sd']);
    cells(_p('PLT', 'Płytki krwi (PLT)', morf, 'tys/µl', 150.0, 400.0)
        .a(['płytki krwi', 'plt', 'trombocyty', 'płytki krwi plt', 'plt płytki krwi', 'trombocyty plt', 'plt trombocyty']));
    _p('MPV', 'MPV', morf, 'fl', 7.5, 11.5).a(['mpv', 'średnia objętość płytki', 'średnia objętość płytek krwi']);
    _p('PDW', 'PDW', morf, 'fl', 9.0, 17.0).a(['pdw', 'wskaźnik zmienności objętości płytek']);
    _p('PCT', 'Płytkokryt (PCT)', morf, '%', 0.15, 0.40).a(['pct', 'płytkokryt', 'plateletkryt', 'płytkokryt pct']);
    _p('PLCR', 'P-LCR', morf, '%', 13.0, 43.0).a(['p lcr', 'plcr']);
    cells(_p('NEU', 'Neutrofile', morf, 'tys/µl', 1.8, 7.7)
        .pct('NEU_P')
        .a(['neutrofile', 'neu', 'neut', 'neutrocyty', 'granulocyty obojętnochłonne', 'neutrofile neu', 'neu neutrofile', 'neutrofile segmentowane']));
    _p('NEU_P', 'Neutrofile %', morf, '%', 40.0, 70.0);
    cells(_p('LYM', 'Limfocyty', morf, 'tys/µl', 1.0, 4.5).pct('LYM_P').a(['limfocyty', 'lym', 'lymph', 'limfocyty lym', 'lym limfocyty', 'limfocyty lymph']));
    _p('LYM_P', 'Limfocyty %', morf, '%', 20.0, 45.0);
    cells(_p('MON', 'Monocyty', morf, 'tys/µl', 0.1, 0.8).pct('MON_P').a(['monocyty', 'mon', 'mono', 'monocyty mono', 'mono monocyty', 'monocyty mon']));
    _p('MON_P', 'Monocyty %', morf, '%', 2.0, 10.0);
    cells(_p('EOS', 'Eozynofile', morf, 'tys/µl', 0.0, 0.5)
        .pct('EOS_P')
        .a(['eozynofile', 'eos', 'eozynocyty', 'granulocyty kwasochłonne', 'eozynofile eos', 'eos eozynofile']));
    _p('EOS_P', 'Eozynofile %', morf, '%', 0.0, 5.0);
    cells(_p('BAS', 'Bazofile', morf, 'tys/µl', 0.0, 0.2)
        .pct('BAS_P')
        .a(['bazofile', 'baso', 'bas', 'bazocyty', 'granulocyty zasadochłonne', 'bazofile baso', 'baso bazofile', 'bazofile bas']));
    _p('BAS_P', 'Bazofile %', morf, '%', 0.0, 1.0);
    cells(_p('IG', 'Niedojrzałe granulocyty (IG)', morf, 'tys/µl', 0.0, 0.06).pct('IG_P').a(['niedojrzałe granulocyty', 'ig', 'ig niedojrzałe granulocyty', 'niedojrzałe granulocyty ig']));
    _p('IG_P', 'Niedojrzałe granulocyty %', morf, '%', 0.0, 0.6);
    cells(_p('NRBC', 'NRBC', morf, 'tys/µl', 0.0, 0.01).pct('NRBC_P').a(['nrbc', 'erytroblasty', 'nrbc erytroblasty']));
    _p('NRBC_P', 'NRBC %', morf, '%', 0.0, 0.2);
    _p('RET', 'Retikulocyty', morf, '‰', 5.0, 15.0).a(['retikulocyty', 'ret']);

    // ---------- Biochemia ----------
    _p('GLU', 'Glukoza', bio, 'mg/dl', 70.0, 99.0)
        .a(['glukoza', 'glukoza na czczo', 'glukoza w surowicy', 'glukoza surowica', 'glu', 'glukoza w osoczu', 'glukoza osocze', 'glukoza w surowicy na czczo'])
        .c('mmol/l', 18.016);
    _p('HBA1C', 'Hemoglobina glikowana (HbA1c)', bio, '%', 4.0, 5.6)
        .a(['hemoglobina glikowana', 'hba1c', 'hb a1c', 'hemoglobina glikowana hba1c', 'hba1c hemoglobina glikowana', 'hemoglobina glikowana hb a1c']);
    _p('INS', 'Insulina', bio, 'µIU/ml', 2.6, 24.9).a(['insulina', 'insulina na czczo']).c('mu/l', 1).c('miu/l', 1).c('uu/ml', 1).c('pmol/l', 0.144);
    _p('HOMA', 'HOMA-IR', bio, '', null, 2.0).a(['homa ir', 'wskaźnik homa ir', 'homa']);
    _p('TP', 'Białko całkowite', bio, 'g/dl', 6.4, 8.3).a(['białko całkowite', 'białko całkowite w surowicy']).c('g/l', 0.1);
    _p('ALB', 'Albumina', bio, 'g/dl', 3.5, 5.2).a(['albumina', 'albuminy', 'albumina w surowicy']).c('g/l', 0.1);
    _p('UA', 'Kwas moczowy', bio, 'mg/dl', 2.6, 7.0).m(3.4, 7.0).f(2.4, 5.7).a(['kwas moczowy', 'kwas moczowy w surowicy']).c('umol/l', 0.01681);
    enz(_p('CK', 'Kinaza kreatynowa (CK)', bio, 'U/l', null, 190.0).a(['kinaza kreatynowa', 'ck', 'cpk', 'kinaza kreatynowa ck']));
    enz(_p('LDH', 'LDH', bio, 'U/l', 135.0, 225.0).a(['ldh', 'dehydrogenaza mleczanowa', 'dehydrogenaza mleczanowa ldh']));
    _p('HCY', 'Homocysteina', bio, 'µmol/l', 5.0, 15.0).a(['homocysteina']);

    // ---------- Lipidogram ----------
    _p('CHOL', 'Cholesterol całkowity', lip, 'mg/dl', null, 190.0)
        .a(['cholesterol całkowity', 'cholesterol', 'cholesterol całkowity w surowicy', 'chol', 'cholesterol całk', 'cholesterol w surowicy'])
        .c('mmol/l', 38.67);
    _p('HDL', 'Cholesterol HDL', lip, 'mg/dl', 40.0, null)
        .m(40.0, null)
        .f(45.0, null)
        .a(['cholesterol hdl', 'hdl', 'hdl cholesterol', 'cholesterol frakcji hdl', 'cholesterol hdl w surowicy'])
        .c('mmol/l', 38.67);
    _p('LDL', 'Cholesterol LDL', lip, 'mg/dl', null, 115.0)
        .a([
          'cholesterol ldl',
          'ldl',
          'ldl cholesterol',
          'cholesterol ldl wyliczany',
          'cholesterol ldl wyliczony',
          'cholesterol ldl oznaczany bezpośrednio',
          'cholesterol ldl metodą bezpośrednią',
          'cholesterol frakcji ldl',
          'ldl wyliczany',
          'cholesterol ldl w surowicy'
        ])
        .c('mmol/l', 38.67);
    _p('NHDL', 'Cholesterol nie-HDL', lip, 'mg/dl', null, 130.0)
        .a(['cholesterol nie hdl', 'nie hdl cholesterol', 'non hdl', 'cholesterol non hdl', 'non hdl cholesterol'])
        .c('mmol/l', 38.67);
    _p('TG', 'Triglicerydy', lip, 'mg/dl', null, 150.0)
        .a(['triglicerydy', 'trójglicerydy', 'tg', 'triacyloglicerole', 'triglicerydy tg', 'triglicerydy w surowicy'])
        .c('mmol/l', 88.57);
    _p('LPA', 'Lipoproteina (a)', lip, 'mg/dl', null, 30.0).a(['lipoproteina a', 'lp a', 'lpa']);

    // ---------- Wątroba / trzustka ----------
    enz(_p('ALT', 'ALT (AlAT)', wat, 'U/l', null, 40.0)
        .m(null, 41.0)
        .f(null, 33.0)
        .a(['alt', 'alat', 'aminotransferaza alaninowa', 'alt alat', 'alat alt', 'aminotransferaza alaninowa alt', 'aminotransferaza alaninowa alat']));
    enz(_p('AST', 'AST (AspAT)', wat, 'U/l', null, 40.0)
        .m(null, 40.0)
        .f(null, 32.0)
        .a(['ast', 'aspat', 'aminotransferaza asparaginianowa', 'ast aspat', 'aspat ast', 'aminotransferaza asparaginianowa ast', 'aminotransferaza asparaginianowa aspat']));
    enz(_p('GGT', 'GGTP', wat, 'U/l', null, 50.0)
        .m(null, 60.0)
        .f(null, 40.0)
        .a(['ggtp', 'ggt', 'gamma glutamylotranspeptydaza', 'gamma gt', 'ggtp gamma glutamylotranspeptydaza', 'gamma glutamylotransferaza']));
    enz(_p('ALP', 'Fosfataza alkaliczna (ALP)', wat, 'U/l', 40.0, 130.0)
        .f(35.0, 105.0)
        .a(['fosfataza alkaliczna', 'alp', 'fosfataza zasadowa', 'fosfataza alkaliczna alp', 'alp fosfataza alkaliczna']));
    _p('BIL', 'Bilirubina całkowita', wat, 'mg/dl', 0.3, 1.2).a(['bilirubina całkowita', 'bilirubina', 'bilirubina całk', 'bil', 'bilirubina całkowita w surowicy']).c('umol/l', 0.0585);
    _p('BILD', 'Bilirubina bezpośrednia', wat, 'mg/dl', null, 0.3).a(['bilirubina bezpośrednia', 'bilirubina sprzężona']).c('umol/l', 0.0585);
    enz(_p('AMY', 'Amylaza', wat, 'U/l', 28.0, 100.0).a(['amylaza', 'alfa amylaza', 'amylaza w surowicy']));
    enz(_p('LIP', 'Lipaza', wat, 'U/l', 13.0, 60.0).a(['lipaza', 'lipaza w surowicy']));

    // ---------- Nerki / elektrolity ----------
    _p('CREA', 'Kreatynina', ner, 'mg/dl', 0.6, 1.2)
        .m(0.7, 1.2)
        .f(0.5, 0.9)
        .a(['kreatynina', 'kreatynina w surowicy', 'crea', 'kreatynina surowica'])
        .c('umol/l', 0.01131);
    _p('EGFR', 'eGFR', ner, 'ml/min/1,73m²', 90.0, null).a([
      'egfr',
      'gfr',
      'egfr wg ckd epi',
      'egfr ckd epi',
      'szacunkowy gfr',
      'egfr mdrd',
      'przesączanie kłębuszkowe egfr',
      'egfr wg wzoru ckd epi',
      'szacowany wskaźnik filtracji kłębuszkowej'
    ]);
    _p('UREA', 'Mocznik', ner, 'mg/dl', 17.0, 43.0).a(['mocznik', 'mocznik w surowicy']).c('mmol/l', 6.006);
    _p('BUN', 'Azot mocznikowy (BUN)', ner, 'mg/dl', 8.0, 23.0).a(['azot mocznikowy', 'bun']);
    _p('NA', 'Sód', ner, 'mmol/l', 136.0, 145.0).a(['sód', 'na', 'sód na', 'na sód', 'sód w surowicy']).c('meq/l', 1);
    _p('K', 'Potas', ner, 'mmol/l', 3.5, 5.1).a(['potas', 'k', 'potas k', 'k potas', 'potas w surowicy']).c('meq/l', 1);
    _p('CL', 'Chlorki', ner, 'mmol/l', 98.0, 107.0).a(['chlorki', 'cl', 'chlorki cl', 'chlorki w surowicy']).c('meq/l', 1);
    _p('CA', 'Wapń całkowity', ner, 'mg/dl', 8.6, 10.2).a(['wapń', 'wapń całkowity', 'ca', 'wapń całkowity w surowicy', 'wapń w surowicy']).c('mmol/l', 4.008);
    _p('MG', 'Magnez', ner, 'mg/dl', 1.6, 2.6).a(['magnez', 'mg', 'magnez w surowicy']).c('mmol/l', 2.431);
    _p('P', 'Fosfor nieorganiczny', ner, 'mg/dl', 2.5, 4.5).a(['fosfor', 'fosfor nieorganiczny', 'fosforany']).c('mmol/l', 3.097);

    // ---------- Tarczyca ----------
    _p('TSH', 'TSH', tar, 'µIU/ml', 0.27, 4.2)
        .a(['tsh', 'tsh trzeciej generacji', 'tsh iii generacji', 'tsh 3 generacji', 'tyreotropina', 'hormon tyreotropowy', 'tsh 3 gen', 'tsh iii gen', 'tsh ultraczułe'])
        .c('miu/l', 1)
        .c('mu/l', 1)
        .c('uu/ml', 1)
        .c('uiu/ml', 1)
        .c('miu/ml', 1);
    _p('FT4', 'FT4', tar, 'ng/dl', 0.93, 1.7).a(['ft4', 'wolna tyroksyna', 'ft4 wolna tyroksyna', 'wolna tyroksyna ft4']).c('pmol/l', 0.0777);
    _p('FT3', 'FT3', tar, 'pg/ml', 2.0, 4.4).a(['ft3', 'wolna trójjodotyronina', 'ft3 wolna trójjodotyronina', 'wolna trijodotyronina', 'wolna trójjodotyronina ft3']).c('pmol/l', 0.651);
    _p('ATPO', 'Anty-TPO', tar, 'IU/ml', null, 34.0)
        .a(['anty tpo', 'atpo', 'przeciwciała anty tpo', 'przeciwciała przeciw peroksydazie tarczycowej', 'anti tpo', 'przeciwciała anty tpo atpo'])
        .c('u/ml', 1)
        .c('j/ml', 1);
    _p('ATG', 'Anty-TG', tar, 'IU/ml', null, 115.0)
        .a(['anty tg', 'atg', 'przeciwciała anty tg', 'przeciwciała przeciw tyreoglobulinie', 'anti tg', 'przeciwciała anty tg atg'])
        .c('u/ml', 1)
        .c('j/ml', 1);
    _p('TRAB', 'TRAb', tar, 'IU/l', null, 1.75).a(['trab', 'przeciwciała anty trsh', 'anty trsh']);

    // ---------- Hormony ----------
    _p('CORT', 'Kortyzol', hor, 'µg/dl', 6.2, 19.4).a(['kortyzol', 'kortyzol rano', 'kortyzol w surowicy']).c('nmol/l', 0.03625);
    _p('TEST', 'Testosteron', hor, 'ng/ml', null, null).m(2.5, 8.4).f(0.06, 0.82).a(['testosteron', 'testosteron całkowity']).c('nmol/l', 0.2884).c('ng/dl', 0.01);
    _p('FTEST', 'Testosteron wolny', hor, 'pg/ml', null, null).a(['testosteron wolny']);
    _p('E2', 'Estradiol', hor, 'pg/ml', null, null).a(['estradiol', 'e2']).c('pmol/l', 0.2724);
    _p('PRL', 'Prolaktyna', hor, 'ng/ml', null, null).m(4.0, 15.2).f(4.8, 23.3).a(['prolaktyna', 'prl']).c('uiu/ml', 0.0472).c('miu/l', 0.0472);
    _p('FSH', 'FSH', hor, 'mIU/ml', null, null).a(['fsh', 'folitropina']).c('iu/l', 1).c('miu/l', 1);
    _p('LH', 'LH', hor, 'mIU/ml', null, null).a(['lh', 'lutropina']).c('iu/l', 1).c('miu/l', 1);
    _p('PROG', 'Progesteron', hor, 'ng/ml', null, null).a(['progesteron']).c('nmol/l', 0.3145);
    _p('DHEAS', 'DHEA-SO4', hor, 'µg/dl', null, null).a(['dhea so4', 'dhea s', 'dheas', 'siarczan dehydroepiandrosteronu']);
    _p('SHBG', 'SHBG', hor, 'nmol/l', null, null).a(['shbg']);
    _p('AMH', 'AMH', hor, 'ng/ml', null, null).a(['amh', 'hormon antymullerowski']);
    _p('PTH', 'Parathormon (PTH)', hor, 'pg/ml', 15.0, 65.0).a(['parathormon', 'pth', 'parathormon pth']);
    _p('PSA', 'PSA całkowity', hor, 'ng/ml', null, 4.0).a(['psa', 'psa całkowity', 'psa całkowite', 'tpsa', 'antygen swoisty dla stercza']);
    _p('FPSA', 'PSA wolny', hor, 'ng/ml', null, null).a(['psa wolny', 'psa wolne', 'fpsa']);

    // ---------- Żelazo / witaminy ----------
    _p('FE', 'Żelazo', zel, 'µg/dl', 60.0, 170.0).m(65.0, 175.0).f(50.0, 170.0).a(['żelazo', 'fe', 'żelazo w surowicy', 'żelazo fe']).c('umol/l', 5.585);
    _p('FERR', 'Ferrytyna', zel, 'ng/ml', null, null).m(30.0, 400.0).f(15.0, 150.0).a(['ferrytyna', 'ferrytyna w surowicy']).c('ug/l', 1);
    _p('TRF', 'Transferyna', zel, 'mg/dl', 200.0, 360.0).a(['transferyna']).c('g/l', 100);
    _p('TIBC', 'TIBC', zel, 'µg/dl', 250.0, 450.0).a(['tibc', 'całkowita zdolność wiązania żelaza', 'całkowita zdolność wiązania żelaza tibc']).c('umol/l', 5.585);
    _p('UIBC', 'UIBC', zel, 'µg/dl', 110.0, 370.0).a(['uibc', 'utajona zdolność wiązania żelaza']).c('umol/l', 5.585);
    _p('TSAT', 'Wysycenie transferyny', zel, '%', 20.0, 45.0).a(['wysycenie transferyny', 'saturacja transferyny', 'tsat']);
    _p('VITD', 'Witamina D (25-OH)', zel, 'ng/ml', 30.0, 50.0)
        .a([
          'witamina d',
          'witamina d3',
          '25 oh witamina d',
          '25 oh d',
          'witamina d 25 oh',
          'witamina d3 metabolit 25 oh',
          'witamina d metabolit 25 oh',
          'witamina d 25 oh d',
          'witamina d total',
          '25 hydroksywitamina d',
          '25 oh d3',
          'witamina 25 oh d',
          'witamina d3 25 oh',
          'witamina d 25 oh d3'
        ])
        .c('nmol/l', 0.4006);
    _p('B12', 'Witamina B12', zel, 'pg/ml', 197.0, 771.0).a(['witamina b12', 'b12', 'kobalamina', 'wit b12']).c('pmol/l', 1.355);
    _p('FOL', 'Kwas foliowy', zel, 'ng/ml', 3.9, 26.8).a(['kwas foliowy', 'foliany']).c('nmol/l', 0.4413);

    // ---------- Stan zapalny ----------
    _p('OB', 'OB (odczyn Biernackiego)', zap, 'mm/h', 0.0, 15.0)
        .m(0.0, 15.0)
        .f(0.0, 20.0)
        .a(['ob', 'odczyn biernackiego', 'ob odczyn biernackiego', 'esr', 'odczyn biernackiego ob'])
        .c('mm/godz', 1)
        .c('mm/1h', 1)
        .c('mm/godz.', 1)
        .c('mm/1godz', 1);
    _p('CRP', 'CRP', zap, 'mg/l', null, 5.0)
        .a(['crp', 'białko c reaktywne', 'białko crp', 'crp ilościowo', 'crp białko c reaktywne', 'hs crp', 'crp hs', 'białko c reaktywne crp'])
        .c('mg/dl', 10);
    _p('PCTN', 'Prokalcytonina', zap, 'ng/ml', null, 0.5).a(['prokalcytonina']);
    _p('RF', 'Czynnik reumatoidalny (RF)', zap, 'IU/ml', null, 14.0).a(['czynnik reumatoidalny', 'rf', 'czynnik reumatoidalny rf', 'rf ilościowo']);
    _p('ASO', 'ASO', zap, 'IU/ml', null, 200.0).a(['aso', 'antystreptolizyna o']);

    // ---------- Krzepnięcie ----------
    _p('INR', 'INR', krz, '', 0.8, 1.2).a(['inr', 'pt inr', 'czas protrombinowy inr', 'wskaźnik inr']);
    _p('PT', 'Czas protrombinowy (PT)', krz, 's', 9.0, 13.0).a(['czas protrombinowy', 'pt', 'czas protrombinowy pt']).c('sek', 1).c('sek.', 1);
    _p('APTT', 'APTT', krz, 's', 25.0, 37.0).a(['aptt', 'czas kaolinowo kefalinowy', 'czas częściowej tromboplastyny po aktywacji']).c('sek', 1).c('sek.', 1);
    _p('FIB', 'Fibrynogen', krz, 'mg/dl', 200.0, 400.0).a(['fibrynogen']).c('g/l', 100);
    _p('DDIM', 'D-dimery', krz, 'ng/ml', null, 500.0).a(['d dimery', 'd dimer', 'dimery d']).c('ug/l', 1).c('mg/l', 1000).c('ug/ml', 1000);

    // ---------- Mocz ----------
    _p('U_SG', 'Mocz: ciężar właściwy', moc, 'g/ml', 1.010, 1.030).a(['ciężar właściwy', 'ciężar właściwy moczu', 'gęstość względna']);
    _p('U_PH', 'Mocz: pH', moc, '', 4.5, 8.0).a(['odczyn ph', 'ph moczu', 'odczyn moczu', 'odczyn']);
    _p('U_LEU', 'Mocz: leukocyty w osadzie', moc, 'wpw', null, 5.0).a(['leukocyty w osadzie', 'leukocyty wpw', 'leukocyty w polu widzenia']);
    _p('U_ERY', 'Mocz: erytrocyty w osadzie', moc, 'wpw', null, 2.0).a(['erytrocyty w osadzie', 'erytrocyty wpw', 'erytrocyty świeże', 'erytrocyty wyługowane']);
    _p('U_NAB', 'Mocz: nabłonki płaskie', moc, 'wpw', null, 5.0).a(['nabłonki płaskie', 'komórki nabłonka płaskiego']);
    _p('UACR', 'Albumina/kreatynina w moczu (ACR)', moc, 'mg/g', null, 30.0).a(['acr', 'wskaźnik albumina kreatynina', 'albumina kreatynina w moczu', 'uacr']);

    // ---------- Immunologia / celiakia / immunoglobuliny ----------
    LabParam ab(LabParam p) => p.c('u/ml', 1).c('ru/ml', 1).c('eu/ml', 1).c('j/ml', 1);
    ab(_p('TTG_IGA', 'Anty-tTG IgA (celiakia)', imm, 'AU/ml', null, 20.0).a([
      'anty ttg iga',
      'anty ttg w klasie iga',
      'ttg iga',
      'przeciwciala przeciw transglutaminazie tkankowej iga',
      'przeciwciala przeciwko transglutaminazie tkankowej w klasie iga',
      'p c p transglutaminazie tkankowej iga',
      'anty transglutaminaza iga',
      'anty tg2 iga'
    ]));
    ab(_p('TTG_IGG', 'Anty-tTG IgG (celiakia)', imm, 'AU/ml', null, 20.0).a([
      'anty ttg igg',
      'anty ttg w klasie igg',
      'ttg igg',
      'przeciwciala przeciw transglutaminazie tkankowej igg',
      'przeciwciala przeciwko transglutaminazie tkankowej w klasie igg',
      'p c p transglutaminazie tkankowej igg',
      'anty transglutaminaza igg',
      'anty tg2 igg'
    ]));
    ab(_p('DGP_IGA', 'Anty-DGP IgA (celiakia)', imm, 'U/ml', null, 20.0).a(['anty dgp iga', 'dgp iga', 'przeciwciala przeciw deamidowanym peptydom gliadyny iga']));
    ab(_p('DGP_IGG', 'Anty-DGP IgG (celiakia)', imm, 'U/ml', null, 20.0).a(['anty dgp igg', 'dgp igg', 'przeciwciala przeciw deamidowanym peptydom gliadyny igg']));
    _p('EMA_IGA', 'Anty-EMA IgA (celiakia)', imm, '', null, null).a(['anty ema iga', 'ema iga', 'przeciwciala przeciw endomysium iga', 'przeciwciala przeciwendomyzjalne iga']);
    _p('IGA', 'IgA całkowite', imm, 'g/l', 0.7, 4.0).a(['iga calkowite', 'immunoglobulina a', 'iga w surowicy', 'iga total']).c('mg/dl', 0.01);
    _p('IGG', 'IgG całkowite', imm, 'g/l', 7.0, 16.0).a(['igg calkowite', 'immunoglobulina g', 'igg w surowicy']).c('mg/dl', 0.01);
    _p('IGM', 'IgM całkowite', imm, 'g/l', 0.4, 2.3).a(['igm calkowite', 'immunoglobulina m', 'igm w surowicy']).c('mg/dl', 0.01);
    _p('IGE', 'IgE całkowite', imm, 'IU/ml', null, 100.0).a(['ige calkowite', 'ige total', 'immunoglobulina e', 'ige w surowicy']).c('kiu/l', 1).c('ku/l', 1);
    ab(_p('CCP', 'Anty-CCP', imm, 'U/ml', null, 17.0).a(['anty ccp', 'przeciwciala przeciw cyklicznemu cytrulinowanemu peptydowi', 'acpa']));

    // ---------- Holter EKG ----------
    _p('HR_MIN', 'Holter: tętno minimalne', ekg, '/min', null, null)
        .a(['minimalna czestosc rytmu', 'czestosc minimalna', 'hr min', 'min hr', 'minimalne tetno', 'tetno minimalne', 'najnizsza czestosc rytmu', 'czestosc rytmu minimalna', 'minimalna czestosc akcji serca'])
        .c('ud/min', 1)
        .c('bpm', 1);
    _p('HR_AVG', 'Holter: tętno średnie', ekg, '/min', null, null)
        .a(['srednia czestosc rytmu', 'czestosc srednia', 'hr srednie', 'sredni hr', 'srednie tetno', 'tetno srednie', 'srednia czestosc akcji serca', 'czestosc rytmu srednia', 'hr sredni'])
        .c('ud/min', 1)
        .c('bpm', 1);
    _p('HR_MAX', 'Holter: tętno maksymalne', ekg, '/min', null, null)
        .a(['maksymalna czestosc rytmu', 'czestosc maksymalna', 'hr max', 'max hr', 'maksymalne tetno', 'tetno maksymalne', 'najwyzsza czestosc rytmu', 'czestosc rytmu maksymalna', 'maksymalna czestosc akcji serca'])
        .c('ud/min', 1)
        .c('bpm', 1);
    _p('SVE', 'Holter: pobudzenia nadkomorowe', ekg, '', null, null)
        .a(['pobudzenia nadkomorowe', 'pobudzen nadkomorowych', 'svpb', 'svpc', 'ekstrasystolie nadkomorowe', 'liczba pobudzen nadkomorowych', 'pobudzenia przedwczesne nadkomorowe', 'sve']);
    _p('VE', 'Holter: pobudzenia komorowe', ekg, '', null, null)
        .a(['pobudzenia komorowe', 'pobudzen komorowych', 'vpb', 'pvc', 'ekstrasystolie komorowe', 'liczba pobudzen komorowych', 'pobudzenia przedwczesne komorowe', 'ves']);
    _p('PAUSE', 'Holter: pauzy > 2 s', ekg, '', null, 0.0).a(['pauzy', 'pauzy powyzej 2 s', 'pauzy 2 s', 'liczba pauz', 'pauzy dluzsze niz 2 s', 'pauzy 2s']);
    _p('PAUSE_MAX', 'Holter: najdłuższa pauza', ekg, 's', null, 2.0).a(['najdluzsza pauza', 'najdluzszy odstep rr', 'max rr', 'najdluzszy rr']).c('ms', 0.001).c('sek', 1);

    for (final x in byKey.values) {
      for (final al in x.aliases) {
        aliases.add(MapEntry(al, x));
      }
    }
    aliases.sort((a, b) => b.key.length.compareTo(a.key.length));
  }
}
