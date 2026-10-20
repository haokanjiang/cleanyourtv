#!/usr/bin/env bash
# Build, install and launch CleanYourTV without taking over Home.
# Installing another HOME-capable APK can reset Android's preferred Home, so the previous component
# is recorded and restored when needed. No package is ever disabled here.
set -euo pipefail
cd "$(dirname "$0")"
: "${TV_HOST:?set TV_HOST to the TV IP address, e.g. TV_HOST=192.168.1.50 $0}"

export JAVA_HOME="${JAVA_HOME:-$(/usr/libexec/java_home -v 17 2>/dev/null || { [ -d /opt/homebrew/opt/openjdk@17 ] && echo /opt/homebrew/opt/openjdk@17; } || java -XshowSettings:properties -version 2>&1 | awk '/java.home/ {print $3}')}"
export ANDROID_HOME="${ANDROID_HOME:-$(for d in ~/Library/Android/sdk ~/Android/Sdk; do [ -d "$d" ] && echo "$d" && break; done)}"
export ANDROID_HOME="${ANDROID_HOME:-/opt/homebrew/share/android-commandlinetools}"
export PATH="$JAVA_HOME/bin:$PATH"
[ -f local.properties ] || echo "sdk.dir=$ANDROID_HOME" > local.properties

TOOLS="$(cd ../tools && pwd)"
PY=$TOOLS/venv/bin/python
[ -x "$PY" ] || PY=$TOOLS/venv/Scripts/python.exe
export MSYS_NO_PATHCONV=1
[ -x "$PY" ] || {
  echo "Create tools/venv first: python3 -m venv tools/venv && tools/venv/bin/pip install -r tools/requirements.txt" >&2
  exit 1
}

HOME_QUERY='cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME'
query_home() {
  "$PY" -I ../tools/tv.py "$HOME_QUERY" | tail -n 1 | tr -d '\r'
}

BEFORE_HOME=$(query_home)
echo "Home before install: $BEFORE_HOME"

./gradlew assembleRelease -q --console=plain
APK=app/build/outputs/apk/release/app-release.apk
"$PY" -I ../tools/b64push.py "$APK" /data/local/tmp/tvhome.apk
OUT=$("$PY" -I ../tools/tv.py 'pm install -r /data/local/tmp/tvhome.apk; rm -f /data/local/tmp/tvhome.apk')
echo "$OUT"
case "$OUT" in
  *Success*) ;;
  *) echo "pm install failed; no launcher settings were changed" >&2; exit 1 ;;
esac

AFTER_INSTALL=$(query_home)
if [ -n "$BEFORE_HOME" ] && [ "$BEFORE_HOME" != android ] && [ "$AFTER_INSTALL" != "$BEFORE_HOME" ]; then
  echo "Installing another HOME app changed the default to '$AFTER_INSTALL'; restoring '$BEFORE_HOME'."
  "$PY" -I ../tools/tv.py "cmd package set-home-activity --user 0 $BEFORE_HOME"
  RESTORED=$(query_home)
  [ "$RESTORED" = "$BEFORE_HOME" ] || {
    echo "could not restore the previous Home; expected '$BEFORE_HOME', got '$RESTORED'" >&2
    exit 1
  }
fi

START=$("$PY" -I ../tools/tv.py 'am start -W -n com.gathin.tvhome/.MainActivity')
echo "$START"
printf '%s' "$START" | grep -qF 'Status: ok' || { echo "launcher installed but did not start" >&2; exit 1; }
printf '%s\n' "$START" | grep -qi '^Error' && { echo "launcher installed but did not start" >&2; exit 1; }

echo
echo "Validation launcher is running."
echo "Default Home remains: $(query_home)"
echo "Pressing Home should return to the original TV launcher."
