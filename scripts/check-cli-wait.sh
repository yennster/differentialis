#!/bin/bash
#
# Exercises the bundled `differentialis` launcher's argument handling and its --wait handshake
# without the app: `open`, `getconf`, `uuidgen`, and `pgrep` are replaced by stubs, and the stub
# `open` plays the app's part (acknowledge, then write a status). Runs on macOS and Linux.
#
#   scripts/check-cli-wait.sh

set -euo pipefail

root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
launcher="$root/Differentialis/Resources/differentialis"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
work="$(cd -- "$work" && pwd -P)"

mkdir -p "$work/bin" "$work/temp" "$work/files/sub"
export FAKE_TEMP="$work/temp"
export FAKE_LOG="$work/open.log"
export FAKE_RUNNING="$work/running"
export PATH="$work/bin:$PATH"

cat > "$work/bin/getconf" <<'STUB'
#!/bin/bash
[ "$1" = DARWIN_USER_TEMP_DIR ] && echo "$FAKE_TEMP/"
STUB
cat > "$work/bin/uuidgen" <<'STUB'
#!/bin/bash
echo 0F4C2B1A-6E7D-4C55-9C1B-7A2D3E4F5A6B
STUB
cat > "$work/bin/pgrep" <<'STUB'
#!/bin/bash
[ -e "$FAKE_RUNNING" ]
STUB
# The "app": logs its arguments, keeps a copy of a request, then answers per $FAKE_APP.
cat > "$work/bin/open" <<'STUB'
#!/bin/bash
shift 2   # -b <bundle id>
printf '%s\n' "$@" > "$FAKE_LOG"
request="$1"
case "$request" in *.differentialis-wait) ;; *) exit 0 ;; esac
cp "$request" "$FAKE_LOG.request"
base="${request%.differentialis-wait}"
(
  sleep 0.3
  touch "$base.ack"
  case "$FAKE_APP" in
    status-*) sleep 0.3; printf '%s\n' "${FAKE_APP#status-}" > "$base.status.tmp"; mv "$base.status.tmp" "$base.status" ;;
    quit) rm -f "$FAKE_RUNNING" ;;
  esac
) &
STUB
chmod +x "$work/bin/"*

printf 'a\n' > "$work/files/a.txt"
printf 'b\n' > "$work/files/b.txt"
printf 'c\n' > "$work/files/c.txt"
printf 'merged\n' > "$work/files/merged.txt"
cd "$work/files"

failures=0
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }

# expect_exit <code> <description> <launcher args...>
expect_exit() {
  local expected="$1" description="$2" actual=0
  shift 2
  "$launcher" "$@" >/dev/null 2>"$work/stderr" || actual=$?
  if [ "$actual" -ne "$expected" ]; then
    fail "$description: exit $actual, expected $expected ($(cat "$work/stderr"))"
  fi
}

# fields <file>: the NUL-delimited request fields, one per line.
fields() { tr '\0' '\n' < "$1"; }

wait_dir="$work/temp/differentialis-wait"

# Plain opens still hand the resolved paths straight to the app.
touch "$FAKE_RUNNING"
expect_exit 0 "plain compare" a.txt sub/../b.txt
[ "$(cat "$FAKE_LOG")" = "$work/files/a.txt"$'\n'"$work/files/b.txt" ] || fail "plain compare args: $(cat "$FAKE_LOG")"

# Usage errors.
expect_exit 64 "no arguments"
expect_exit 0 "--help" --help
expect_exit 64 "unknown option" --bogus a.txt b.txt
expect_exit 64 "--output without --wait" a.txt b.txt c.txt --output merged.txt
expect_exit 64 "--merge without --wait" --merge a.txt b.txt c.txt
expect_exit 64 "--wait with one path" --wait a.txt
expect_exit 64 "--wait with four paths" --wait a.txt b.txt c.txt merged.txt
expect_exit 64 "--output with two paths" --wait a.txt b.txt --output merged.txt
expect_exit 64 "--output names a folder" --wait --merge a.txt b.txt c.txt --output sub
expect_exit 64 "--output with no value" --wait a.txt b.txt c.txt --output
expect_exit 66 "missing path" --wait a.txt missing.txt
expect_exit 66 "--output in a missing folder" --wait a.txt b.txt c.txt --output nowhere/merged.txt

# --wait compare: blocks until the status, exits with it, and cleans up.
FAKE_APP=status-0 expect_exit 0 "--wait compare" --wait a.txt /dev/null
[ "$(fields "$FAKE_LOG.request")" = "differentialis-wait 1"$'\n'"compare"$'\n'$'\n'"$work/files/a.txt"$'\n'"/dev/null" ] \
  || fail "compare request fields: $(fields "$FAKE_LOG.request")"
[ -z "$(ls -A "$wait_dir")" ] || fail "compare left files behind: $(ls -A "$wait_dir")"
[ "$(stat -c %a "$wait_dir" 2>/dev/null || stat -f %Lp "$wait_dir")" = 700 ] || fail "wait directory is not owner-only"

# --wait merge: the output is resolved, and an unresolved merge exits 1.
FAKE_APP=status-1 expect_exit 1 "--wait merge unresolved" --wait --merge a.txt b.txt c.txt --output=merged.txt
[ "$(fields "$FAKE_LOG.request")" = "differentialis-wait 1"$'\n'"merge"$'\n'"$work/files/merged.txt"$'\n'"$work/files/a.txt"$'\n'"$work/files/b.txt"$'\n'"$work/files/c.txt" ] \
  || fail "merge request fields: $(fields "$FAKE_LOG.request")"
FAKE_APP=status-0 expect_exit 0 "--wait merge resolved (git mergetool order)" --wait a.txt b.txt c.txt --output merged.txt
FAKE_APP=status-0 expect_exit 0 "paths after --" --wait -- a.txt b.txt

# The app going away without answering ends the wait instead of hanging.
FAKE_APP=quit expect_exit 1 "app quit while waiting" --wait a.txt b.txt
[ -z "$(ls -A "$wait_dir")" ] || fail "quit left files behind: $(ls -A "$wait_dir")"

if [ "$failures" -ne 0 ]; then
  echo "$failures launcher check(s) failed" >&2
  exit 1
fi
echo "Launcher checks passed."
