#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
	echo "Usage: bash flash.sh path/to/application.elf" >&2
	exit 1
fi

HOST="${HOST:-frdm}"
ELF="$1"
REMOTE_FILE="$(ssh "$HOST" 'if [ "$(id -u)" -ne 0 ]; then echo "SSH must connect as root (use HOST=root@frdm)." >&2; exit 1; fi; mktemp /tmp/zephyr-remoteproc.XXXXXX')"

cleanup() {
	ssh "$HOST" "rm -f -- '$REMOTE_FILE'" || true
}
trap cleanup EXIT

scp "$ELF" "$HOST:$REMOTE_FILE"
ssh "$HOST" bash -s -- "$REMOTE_FILE" <<'REMOTE'
set -euo pipefail

REMOTE_FILE="$1"
RPROC=/sys/class/remoteproc/remoteproc1
FIRMWARE=zephyr-remoteproc.elf

STATE="$(cat "$RPROC/state")"
case "$STATE" in
	running|attached)
		if ! printf 'stop\n' > "$RPROC/state"; then
			echo "Cannot stop M7. Check dmesg; 'not under Linux Control' requires a System Manager permissions change." >&2
			exit 1
		fi
		;;
	offline) ;;
	*) echo "Unexpected remoteproc state: $STATE" >&2; exit 1 ;;
esac

if [ "$(cat "$RPROC/state")" != offline ]; then
	echo "M7 is not offline; refusing to replace firmware." >&2
	exit 1
fi

install -m 644 "$REMOTE_FILE" "/lib/firmware/$FIRMWARE"
printf '%s\n' "$FIRMWARE" > "$RPROC/firmware"
printf 'start\n' > "$RPROC/state"
printf 'M7 state: '
cat "$RPROC/state"
REMOTE