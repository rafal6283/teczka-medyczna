import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teczka_zdrowia/security/lock.dart';
import 'package:teczka_zdrowia/ui/lock_screen.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('PIN: zapis skrótu, weryfikacja i blokada po błędnych próbach', () async {
    await Lock.setSecret(LockMethod.pin, '2580');
    final c = await Lock.load();
    expect(c.method, LockMethod.pin);
    final p = await SharedPreferences.getInstance();
    expect(p.getKeys().any((k) => (p.get(k)?.toString() ?? '').contains('2580')), isFalse, reason: 'PIN nie może być zapisany wprost');
    expect(await Lock.verify('2580'), isTrue);
    for (var i = 0; i < 5; i++) {
      expect(await Lock.verify('1111'), isFalse);
    }
    expect(await Lock.waitSeconds(), greaterThan(0));
    await Lock.resetFailures();
    expect(await Lock.verify('2580'), isTrue);
  });

  test('Wzór i migracja ze starej blokady', () async {
    SharedPreferences.setMockInitialValues({'lock': true});
    expect((await Lock.load()).method, LockMethod.device);
    await Lock.setSecret(LockMethod.pattern, patternToSecret([0, 1, 2, 5, 8]));
    expect((await Lock.load()).method, LockMethod.pattern);
    expect(await Lock.verify(patternToSecret([0, 1, 2, 5, 8])), isTrue);
    expect(await Lock.verify(patternToSecret([0, 1, 2, 5])), isFalse);
    await Lock.setMethod(LockMethod.none);
    expect((await Lock.load()).method, LockMethod.none);
  });

  test('Długość PIN-u zapamiętana do odblokowania bez zatwierdzania', () async {
    await Lock.setSecret(LockMethod.pin, '123456');
    expect(await Lock.pinLength(), 6);
    await Lock.setSecret(LockMethod.pattern, patternToSecret([0, 4, 8, 7]));
    expect(await Lock.pinLength(), isNull);
  });
}
