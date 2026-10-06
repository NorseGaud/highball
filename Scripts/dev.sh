#!/bin/zsh
# Rebuild dist/Highball.app and reopen it when Sources change. A change in the sibling
# highball-db checkout reopens the app without a compile. Steam and Wine stay up.
# Stop with Ctrl+C. Run from the repository: Scripts/dev.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP="$ROOT/dist/Highball.app"
BIN="$APP/Contents/MacOS/Highball"
DB="$ROOT/../highball-db"
STAMP="$ROOT/.build/dev-make-app.stamp"
pid=""

stop_app() {
  if [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  pid=""
  # A copy started with `open` before this watcher. Match the binary path only.
  ps -ax -o pid=,command= | awk -v bin="$BIN" 'index($0, bin) { print $1 }' | while IFS= read -r old; do
    [[ -n "$old" ]] || continue
    kill "$old" 2>/dev/null || true
  done
}

code_stamp() {
  find Sources Package.swift Scripts/make-app.sh -type f \
      \( -name '*.swift' -o -name '*.json' -o -name 'Package.swift' -o -name 'make-app.sh' \) \
      -exec stat -f '%m %N' {} + 2>/dev/null | sort | shasum | awk '{print $1}'
}

data_stamp() {
  [[ -d "$DB/db" ]] || { echo none; return; }
  find "$DB/db" "$DB/recipes" -type f -name '*.json' \
      -exec stat -f '%m %N' {} + 2>/dev/null | sort | shasum | awk '{print $1}'
}

combined_stamp() { echo "$(code_stamp) $(data_stamp)"; }

wait_until_stable() {
  local current next
  current="$(combined_stamp)"
  while true; do
    sleep 0.5
    next="$(combined_stamp)"
    if [[ "$next" == "$current" ]]; then
      printf '%s\n' "$current"
      return 0
    fi
    echo "Still writing. Waiting…"
    current="$next"
  done
}

build_swift() {
  local attempt=1
  while (( attempt <= 6 )); do
    if swift build -c debug --product HighballApp; then
      return 0
    fi
    echo "Build did not finish. Retrying ($attempt/6)…"
    sleep 0.6
    attempt=$((attempt + 1))
  done
  return 1
}

make_app_hash() { shasum Scripts/make-app.sh | awk '{print $1}'; }

needs_full_assemble() {
  [[ -x "$BIN" ]] || return 0
  [[ -f "$STAMP" ]] || return 1
  [[ "$(cat "$STAMP")" == "$(make_app_hash)" ]] && return 1
  return 0
}

install_binary() {
  local built
  built="$(swift build -c debug --product HighballApp --show-bin-path)/HighballApp"
  cp "$built" "$BIN"
  # The bundle seal breaks when the executable is replaced. Sign locally, with no Apple timestamp.
  codesign --force --sign - "$BIN"
  codesign --force --sign - "$APP" || codesign --force --deep --sign - "$APP"
}

launch() {
  echo "Launching $APP"
  "$BIN" &
  pid=$!
}

# full | swift | relaunch
start_app() {
  local mode="$1"
  if [[ "$mode" == relaunch ]]; then
    stop_app
    launch
    return 0
  fi
  if [[ "$mode" == swift ]] && needs_full_assemble; then
    mode=full
  fi
  echo "Building Highball…"
  if [[ "$mode" == full ]]; then
    stop_app
    if ! Scripts/make-app.sh debug; then
      echo "Build failed. The last window stays open if it is still running."
      return 0
    fi
    mkdir -p "$ROOT/.build"
    make_app_hash > "$STAMP"
  else
    if ! build_swift; then
      echo "Build failed. The last window stays open if it is still running."
      return 0
    fi
    stop_app
    if ! install_binary; then
      echo "Could not update $BIN."
      return 0
    fi
    mkdir -p "$ROOT/.build"
    [[ -f "$STAMP" ]] || make_app_hash > "$STAMP"
  fi
  launch
}

trap 'stop_app; exit 0' INT TERM

if [[ -x "$BIN" ]]; then
  start_app swift
else
  start_app full
fi
stamp="$(combined_stamp)"
code_at_launch="${stamp%% *}"
echo "Watching Sources and ../highball-db. Ctrl+C stops the app. Steam keeps running."
while true; do
  sleep 1
  now="$(combined_stamp)"
  if [[ "$now" != "$stamp" ]]; then
    echo "Files changed. Waiting 10s for edits to settle…"
    sleep 10
    stamp="$(wait_until_stable)"
    code_now="${stamp%% *}"
    data_now="${stamp#* }"
    # code_stamp is the first field. A database-only edit relaunches the same binary:
    # the debug app reads the sibling highball-db checkout at launch.
    if [[ "$code_now" != "$code_at_launch" ]]; then
      start_app swift
    else
      echo "Database files changed. Relaunching."
      start_app relaunch
    fi
    code_at_launch="$code_now"
  fi
  if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
    echo "The app exited. Waiting for the next file change."
    pid=""
  fi
done
