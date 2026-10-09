#!/usr/bin/env bash
# Set up the west workspace (if needed) and build the OpenAMP demo for the
# i.MX95 EVK Cortex-M7 core. See README.md for details.
#
# Usage:
#   ./build.sh            # set up (first run only) + build rpmsg_multi_services
#   ./build.sh --all      # also build Zephyr's in-tree openamp_rsc_table sample
#   ./build.sh --update   # re-run 'west update' before building
set -euo pipefail

cd "$(dirname "$0")"
WS="$PWD"

BOARD="imx95_evk/mimx9596/m7"
PYTHON="${PYTHON:-/opt/homebrew/bin/python3.12}"   # Zephyr 4.4 needs Python >= 3.12
MANIFEST_URL="https://github.com/OpenAMP/openamp-system-reference"
# Only fetch what an i.MX95 M7 OpenAMP build needs (full Zephyr update is many GB).
PROJECT_FILTER='-.*,+zephyr,+libmetal,+open-amp,+openamp-zephyr-modules,+hal_nxp,+cmsis,+cmsis_6'

BUILD_ALL=0
DO_UPDATE=0
for arg in "$@"; do
	case "$arg" in
	--all) BUILD_ALL=1 ;;
	--update) DO_UPDATE=1 ;;
	*) echo "unknown argument: $arg" >&2; exit 1 ;;
	esac
done

# 1. Python virtualenv with west
if [ ! -x .venv/bin/west ]; then
	"$PYTHON" -m venv .venv
	.venv/bin/pip install --upgrade pip west
fi
# shellcheck disable=SC1091
source .venv/bin/activate

# 2. West workspace: manifest repo = openamp-system-reference
if [ ! -d .west ]; then
	west init -m "$MANIFEST_URL" --mr main .
	DO_UPDATE=1
fi
west config manifest.project-filter -- "$PROJECT_FILTER"

if [ "$DO_UPDATE" = 1 ]; then
	west update --narrow -o=--depth=1
	pip install -r zephyr/scripts/requirements-base.txt
fi

# 3. Zephyr SDK (ARM toolchain only), version taken from zephyr/SDK_VERSION
SDK_VER="$(cat zephyr/SDK_VERSION)"
if [ ! -x "$HOME/zephyr-sdk-$SDK_VER/gnu/arm-zephyr-eabi/bin/arm-zephyr-eabi-gcc" ]; then
	west sdk install -b "$HOME" -t arm-zephyr-eabi
fi

# 4. Build
west build -p always -b "$BOARD" -d build/rpmsg_multi_services \
	openamp-system-reference/examples/zephyr/rpmsg_multi_services

if [ "$BUILD_ALL" = 1 ]; then
	west build -p always -b "$BOARD" -d build/openamp_rsc_table \
		zephyr/samples/subsys/ipc/openamp_rsc_table
fi

echo
echo "Firmware:"
ls -l "$WS"/build/*/zephyr/*.elf | grep -v zephyr_pre0
