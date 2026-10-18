#!/usr/bin/env bash
# Instaluje APK release na emulatorze, uruchamia i sprawdza, czy pojawia się ekran startowy.
set -u
APK=$1
adb install -r "$APK" || { echo "::error::Instalacja APK nie powiodła się"; exit 1; }
# emulator po starcie bywa przeciążony – zamknij systemowe okna "nie odpowiada"
dismiss() {
  adb shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS >/dev/null 2>&1
  adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1; adb shell cat /sdcard/ui.xml > ui.xml 2>/dev/null
  python3 - <<'PY'
import re,subprocess
x=open('ui.xml',encoding='utf-8',errors='ignore').read()
if "isn't responding" in x or 'nie odpowiada' in x:
    m=re.search(r'text="(?:Wait|Czekaj)"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',x)
    if m:
        a,b,c,d=map(int,m.groups()); subprocess.run(['adb','shell','input','tap',str((a+c)//2),str((b+d)//2)])
        print('zamknięto okno ANR')
PY
}
sleep 20
dismiss
adb logcat -c
adb shell am start -W -n pl.teczka.zdrowie/pl.teczka.teczka_zdrowia.MainActivity
ok=0
for i in $(seq 1 18); do
  sleep 5
  dismiss
  adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
  adb shell cat /sdcard/ui.xml > ui.xml 2>/dev/null
  if grep -q "Witaj w Teczce Zdrowia\|Dodaj pierwszą osobę\|Nie udało się uruchomić" ui.xml; then ok=1; break; fi
done
adb logcat -d > logcat.txt
grep -E "flutter|AndroidRuntime|FATAL|Exception" logcat.txt | tail -60 > logcat_err.txt
grep -E "flutter|AndroidRuntime|FATAL|Exception" logcat.txt | tail -60 > logcat_err.txt
echo "--- UI:"; grep -o 'text="[^"]*"' ui.xml | head -30
if grep -q "Nie udało się uruchomić" ui.xml; then
  echo "::error::Aplikacja pokazała błąd startu:%0A$(grep -o 'text="[^"]*"' ui.xml | head -20 | sed ':a;N;$!ba;s/\n/%0A/g')"
  bash .github/report.sh logcat_err.txt
  exit 1
fi
if [ $ok -ne 1 ]; then
  echo "::error::Ekran startowy nie pojawił się w ciągu 60 s"
  bash .github/report.sh logcat_err.txt
  exit 1
fi
# Tworzenie profilu: kliknij przycisk, wpisz imię, zapisz
python3 - <<'PY'
import re,subprocess
x=open('ui.xml',encoding='utf-8').read()
m=re.search(r'(?:text|content-desc)="Dodaj pierwszą osobę"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',x)
if m:
    a,b,c,d=map(int,m.groups()); subprocess.run(['adb','shell','input','tap',str((a+c)//2),str((b+d)//2)])
PY
sleep 4
adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1; adb shell cat /sdcard/ui.xml > ui.xml
python3 - <<'PY'
import re,subprocess
x=open('ui.xml',encoding='utf-8').read()
m=re.search(r'class="android.widget.EditText"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',x)
if m:
    a,b,c,d=map(int,m.groups()); subprocess.run(['adb','shell','input','tap',str((a+c)//2),str((b+d)//2)])
else:
    print("brak pola EditText")
PY
sleep 2
adb shell input text "Test"
sleep 1
adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1; adb shell cat /sdcard/ui.xml > ui.xml
python3 - <<'PY'
import re,subprocess
x=open('ui.xml',encoding='utf-8').read()
m=re.search(r'(?:text|content-desc)="Zapisz"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',x)
if m:
    a,b,c,d=map(int,m.groups()); subprocess.run(['adb','shell','input','tap',str((a+c)//2),str((b+d)//2)])
PY
sleep 5
adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1; adb shell cat /sdcard/ui.xml > ui.xml
echo "--- UI po utworzeniu profilu:"; grep -o '\(text\|content-desc\)="[^"]*"' ui.xml | head -40
if grep -q "Podsumowanie" ui.xml; then echo "::notice::Smoke test OK – start i utworzenie profilu działa"; else
  adb logcat -d | grep -E "flutter|AndroidRuntime|FATAL|Exception" | tail -60 > logcat_err.txt
  echo "::warning::Po utworzeniu profilu nie widać ekranu głównego%0A$(grep -o '\(text\|content-desc\)="[^"]*"' ui.xml | head -20 | sed ':a;N;$!ba;s/\n/%0A/g')"
  bash .github/report.sh logcat_err.txt
  exit 1
fi
