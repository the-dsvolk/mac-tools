#!/bin/bash
# Tests for awdl-guard and awdl, with a fake ifconfig — no root, the real awdl0 is never touched.
#   ./test.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

cat >"$T/ifconfig" <<'EOF'
#!/bin/bash
# fake: `ifconfig IF` prints flags from $T/state; `ifconfig IF up|down` sets it and logs the call
if [ $# -eq 1 ]; then
  if [ "$(cat "$FAKE_DIR/state")" = up ]; then echo "$1: flags=8863<UP,BROADCAST,SMART,RUNNING> mtu 1500"
  else echo "$1: flags=8822<BROADCAST,SMART,SIMPLEX,MULTICAST> mtu 1500"; fi
else
  echo "$2" >"$FAKE_DIR/state"; echo "$2" >>"$FAKE_DIR/calls"
fi
EOF
chmod +x "$T/ifconfig"
export FAKE_DIR=$T AWDL_GUARD_IFCONFIG=$T/ifconfig AWDL_IFCONFIG=$T/ifconfig AWDL_GUARD_ONCE=1 AWDL_GUARD_LOGGER=true
export AWDL_ALLOW_FILE=$T/state-dir/allow-until AWDL_WAIT=0
ALLOW=$AWDL_ALLOW_FILE

fails=0
check() {  # check NAME EXPECTED ACTUAL
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected '$2', got '$3'"; fails=$((fails + 1)); fi
}
guard() { : >"$T/calls"; "$HERE/awdl-guard" "$ALLOW"; }
state() { cat "$T/state"; }
calls() { tr '\n' ' ' <"$T/calls" | sed 's/ $//'; }

# guard
echo up >"$T/state"; rm -f "$ALLOW"; guard
check "no allow file: up -> down" down "$(state)"
guard
check "no allow file, already down: no call" "" "$(calls)"
mkdir -p "$(dirname "$ALLOW")"; echo $(( $(date +%s) + 600 )) >"$ALLOW"; guard
check "allowed: down -> up" up "$(state)"
guard
check "allowed, already up: no call" "" "$(calls)"
echo $(( $(date +%s) - 1 )) >"$ALLOW"; guard
check "allow expired: up -> down" down "$(state)"
echo up >"$T/state"; echo 'rm -rf /; 99999999999' | tr -d '0-9' >"$ALLOW"; guard
check "garbage allow file (no digits): down" down "$(state)"
echo up >"$T/state"; : >"$ALLOW"; guard
check "empty allow file: down" down "$(state)"

# awdl command
rm -f "$ALLOW"
out=$("$HERE/awdl" on 5 2>&1)
until=$(cat "$ALLOW"); left=$(( until - $(date +%s) ))
check "awdl on 5 writes ~5 min" yes "$( [ "$left" -gt 290 ] && [ "$left" -le 300 ] && echo yes || echo no )"
check "awdl on: says allowed" yes "$(echo "$out" | grep -q 'AWDL allowed until' && echo yes || echo no)"
guard
check "guard honours awdl on" up "$(state)"
check "awdl status: minutes left" yes "$("$HERE/awdl" status | grep -q 'allowed: 5 min left' && echo yes || echo no)"
"$HERE/awdl" off >/dev/null 2>&1
check "awdl off removes allow file" no "$( [ -e "$ALLOW" ] && echo yes || echo no )"
guard
check "guard after awdl off: down" down "$(state)"
check "awdl status: blocked" yes "$("$HERE/awdl" status | grep -q 'allowed: no' && echo yes || echo no)"
"$HERE/awdl" on 10 >/dev/null 2>&1; left=$(( $(cat "$ALLOW") - $(date +%s) ))
check "awdl on (default) = 10 min" yes "$( [ "$left" -gt 590 ] && [ "$left" -le 600 ] && echo yes || echo no )"
check "awdl on abc rejected" 1 "$("$HERE/awdl" on abc >/dev/null 2>&1; echo $?)"
check "awdl on 0 rejected" 1 "$("$HERE/awdl" on 0 >/dev/null 2>&1; echo $?)"
check "unknown command rejected" 1 "$("$HERE/awdl" bogus >/dev/null 2>&1; echo $?)"

# the shipped plist template is valid once filled in
sed -e 's#@GUARD@#/usr/local/libexec/awdl-guard#' -e "s#@ALLOW_FILE@#$ALLOW#" \
  "$HERE/io.github.the-dsvolk.awdl-guard.plist.in" >"$T/test.plist"
check "plist template lints" 0 "$(plutil -lint "$T/test.plist" >/dev/null; echo $?)"
for f in awdl-guard awdl install.sh test.sh; do
  check "bash -n $f" 0 "$(bash -n "$HERE/$f"; echo $?)"
done

echo; [ "$fails" = 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
