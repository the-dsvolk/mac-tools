#!/bin/bash
# Install or remove awdl-guard (root LaunchDaemon) and the `awdl` command.
#
#   sudo ./install.sh              install / update
#   sudo ./install.sh --uninstall  remove everything and bring awdl0 back up
#
# Without a terminal (e.g. from a script), the macOS admin dialog works too:
#   osascript -e 'do shell script "/path/to/awdl/install.sh" with administrator privileges'
#
# The guard is copied to a root-owned path, so root never runs a file the user can edit.
set -eu

LABEL=io.github.the-dsvolk.awdl-guard
GUARD=/usr/local/libexec/awdl-guard
PLIST=/Library/LaunchDaemons/$LABEL.plist
HERE=$(cd "$(dirname "$0")" && pwd)

[ "$(id -u)" = 0 ] || { echo "run as root: sudo $0 $*" >&2; exit 1; }
# The user the `awdl` command is for: sudo's caller, else whoever is logged in at the console (osascript).
TARGET_USER=${SUDO_USER:-$(stat -f %Su /dev/console)}
[ -n "$TARGET_USER" ] && [ "$TARGET_USER" != root ] || { echo "can't tell which user to install for" >&2; exit 1; }
TARGET_HOME=$(dscl . -read "/Users/$TARGET_USER" NFSHomeDirectory | awk '{print $2}')
ALLOW_FILE=$TARGET_HOME/.local/state/awdl-guard/allow-until
LINK=$TARGET_HOME/.local/bin/awdl

stop_daemon() { launchctl bootout "system/$LABEL" 2>/dev/null || true; }

if [ "${1:-}" = --uninstall ]; then
  stop_daemon
  rm -f "$PLIST" "$GUARD"
  [ -L "$LINK" ] && [ "$(readlink "$LINK")" = "$HERE/awdl" ] && rm -f "$LINK"
  /sbin/ifconfig awdl0 up || true
  echo "awdl-guard removed; awdl0 is up again (allow file left at $ALLOW_FILE)"
  exit 0
fi

mkdir -p "$(dirname "$GUARD")"
install -o root -g wheel -m 755 "$HERE/awdl-guard" "$GUARD"
sudo -u "$TARGET_USER" mkdir -p "$(dirname "$ALLOW_FILE")" "$(dirname "$LINK")"
sed -e "s#@GUARD@#$GUARD#" -e "s#@ALLOW_FILE@#$ALLOW_FILE#" "$HERE/$LABEL.plist.in" >"$PLIST.tmp"
chown root:wheel "$PLIST.tmp" && chmod 644 "$PLIST.tmp"
plutil -lint "$PLIST.tmp" >/dev/null
mv -f "$PLIST.tmp" "$PLIST"

stop_daemon
launchctl bootstrap system "$PLIST"
sudo -u "$TARGET_USER" ln -sfn "$HERE/awdl" "$LINK"

sleep 3
echo "awdl-guard installed for $TARGET_USER (allow file: $ALLOW_FILE)"
echo "awdl0: $(/sbin/ifconfig awdl0 | head -1 | grep -q '<UP[,>]' && echo up || echo down)"
echo "Use: awdl on [minutes] | awdl off | awdl status"
