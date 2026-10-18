#!/usr/bin/env bash
# Własne uruchomienie emulatora (pełne logi) + test aplikacji.
set -x
APK=$1
SDK=${ANDROID_HOME:-$ANDROID_SDK_ROOT}
SM=$SDK/cmdline-tools/latest/bin/sdkmanager
AM=$SDK/cmdline-tools/latest/bin/avdmanager
IMG="system-images;android-34;google_apis;x86_64"
yes | $SM --licenses > /dev/null 2>&1
$SM "$IMG" "emulator" "platform-tools" > sdk.log 2>&1 || { echo "sdkmanager failed"; tail -20 sdk.log; }
echo no | $AM create avd -n smoke -k "$IMG" --force
export PATH=$SDK/platform-tools:$SDK/emulator:$PATH
nohup emulator -avd smoke -no-window -no-audio -no-boot-anim -gpu swiftshader_indirect -no-snapshot -memory 3072 > emu.log 2>&1 &
adb wait-for-device
for i in $(seq 1 90); do
  [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ] && break
  sleep 5
done
adb shell getprop sys.boot_completed
adb shell settings put global window_animation_scale 0
adb shell settings put global transition_animation_scale 0
adb shell settings put global animator_duration_scale 0
adb shell input keyevent 82
bash .github/smoke.sh "$APK"
rc=$?
adb exec-out screencap -p > screen.png
exit $rc
