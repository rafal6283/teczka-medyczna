const Map<String, String> _dia = {
  'ą': 'a', 'ć': 'c', 'ę': 'e', 'ł': 'l', 'ń': 'n', 'ó': 'o', 'ś': 's', 'ź': 'z', 'ż': 'z',
  'µ': 'u', 'μ': 'u', 'γ': 'g', 'ü': 'u', 'ö': 'o', 'ä': 'a', 'é': 'e', 'á': 'a', 'í': 'i', 'č': 'c', 'š': 's', 'ž': 'z',
};

final RegExp _alnum = RegExp(r'[a-z0-9]');

/// Normalizacja znak-w-znak (ta sama długość co wejście): małe litery, bez polskich znaków,
/// wszystko poza [a-z0-9] zamienione na spację.
String normSameLength(String s) {
  final sb = StringBuffer();
  for (final orig in s.split('')) {
    final ch = orig.toLowerCase();
    final m = _dia[ch] ?? ch;
    sb.write(_alnum.hasMatch(m) && m.length == 1 ? m : ' ');
  }
  return sb.toString();
}

/// Normalizacja do porównań nazw: jak wyżej + zwinięte spacje.
String normText(String s) => normSameLength(s).trim().replaceAll(RegExp(r' +'), ' ');

/// Normalizacja jednostek do porównań.
String normUnit(String u) {
  var s = u.toLowerCase().trim();
  s = s.replaceAll('µ', 'u').replaceAll('μ', 'u');
  s = s.replaceAll('³', '^3').replaceAll('⁶', '^6').replaceAll('⁹', '^9').replaceAll('¹²', '^12').replaceAll('²', '2');
  s = s.replaceAll(' ', '');
  s = s.replaceAll(RegExp(r'^(x|\*)10'), '10');
  s = s.replaceAll(RegExp(r'^10(\d)'), r'10^$1');
  s = s.replaceAll('tys.', 'tys').replaceAll('mln.', 'mln');
  s = s.replaceAll('mm3', 'ul');
  if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  return s;
}

double? parseNum(String s) {
  final t = s.trim().replaceAll(' ', '').replaceAll(',', '.');
  return double.tryParse(t);
}

/// Formatuje liczbę po polsku (przecinek), bez zbędnych zer.
String fmtNum(double? v, {int maxDecimals = 2}) {
  if (v == null) return '–';
  if (v.isNaN || v.isInfinite) return '–';
  var dec = maxDecimals;
  final a = v.abs();
  if (a >= 100) dec = 0;
  if (a >= 10 && dec > 1) dec = 1;
  if (a < 1 && a > 0) dec = maxDecimals + 1;
  var s = v.toStringAsFixed(dec);
  if (s.contains('.')) {
    s = s.replaceAll(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  }
  return s.replaceAll('.', ',');
}

String two(int n) => n.toString().padLeft(2, '0');

String fmtDate(DateTime? d) => d == null ? '–' : '${two(d.day)}.${two(d.month)}.${d.year}';

String fmtDateShort(DateTime d) => '${two(d.month)}.${d.year % 100}';

const monthsPl = ['sty', 'lut', 'mar', 'kwi', 'maj', 'cze', 'lip', 'sie', 'wrz', 'paź', 'lis', 'gru'];

String fmtMonthYear(DateTime d) => '${monthsPl[d.month - 1]} ${d.year}';

int ageOn(DateTime birth, DateTime on) {
  var a = on.year - birth.year;
  if (on.month < birth.month || (on.month == birth.month && on.day < birth.day)) a--;
  return a;
}
