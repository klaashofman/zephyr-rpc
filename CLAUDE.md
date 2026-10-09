# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A west workspace (not a git repo itself) that builds OpenAMP demo firmware for the **NXP i.MX95 Cortex-M7** (`imx95_evk/mimx9596/m7`). The M7 runs Zephyr as the RPMsg *remote*; Linux on the A55 cluster is the *host* that loads and starts the ELF through `remoteproc` and talks to it over RPMsg/virtio. `README.md` has the full setup history, pinned revisions and on-target test steps.

Only `build.sh`, `flash.sh`, `README.md` and this file belong to the workspace. Everything else (`zephyr/`, `open-amp/`, `libmetal/`, `openamp-zephyr-modules/`, `openamp-system-reference/`, `modules/hal/*`) is a west-managed upstream checkout with no local changes. `west update` can overwrite edits there.

## Commands

```bash
./build.sh            # first run: venv + west init + west update + SDK install + build
./build.sh --all      # also build Zephyr's in-tree openamp_rsc_table sample
./build.sh --update   # re-run west update (after manifest/filter changes)

# Manual build (activate the venv first)
source .venv/bin/activate
west build -p always -b imx95_evk/mimx9596/m7 -d build/rpmsg_multi_services \
    openamp-system-reference/examples/zephyr/rpmsg_multi_services
west build -d build/rpmsg_multi_services          # incremental rebuild
west build -d build/rpmsg_multi_services -t menuconfig

# Deploy to the board over SSH (needs root; HOST defaults to "frdm")
HOST=root@frdm ./flash.sh build/rpmsg_multi_services/zephyr/rpmsg_multi_services.elf
```

There are no tests or linters for this workspace.

## Environment constraints

- **Python ≥ 3.12 is required** (Zephyr 4.4). The system python3 is 3.10, so always use `.venv/` (created from `/opt/homebrew/bin/python3.12`; override with `PYTHON=`).
- Zephyr SDK version comes from `zephyr/SDK_VERSION` (currently 1.0.1). It is installed at `~/zephyr-sdk-1.0.1` with only the `arm-zephyr-eabi` toolchain. `~/zephyr-sdk-0.17.4` and `~/zephyrproject` are unrelated and not used here.
- `.west/config` sets a **project filter** (`-.*,+zephyr,+libmetal,+open-amp,+openamp-zephyr-modules,+hal_nxp,+cmsis,+cmsis_6`) and clones are shallow, because of limited disk space. Samples or boards that need other modules will fail until the filter is widened. See README "West update".
- Expected warning: `PRINTK ... was assigned the value 'n' but got the value 'y'`. It is harmless.

## Architecture

- **Manifest**: `openamp-system-reference/west.yml` is the manifest repo. It pins Zephyr `v4.4.0` (with `import: true`) and replaces Zephyr's bundled libmetal/open-amp with upstream `main`, glued together by `openamp-zephyr-modules` (a Zephyr module, see its `zephyr/module.yml`).
- **Main app**: `openamp-system-reference/examples/zephyr/rpmsg_multi_services/`. `src/main_remote.c` announces three RPMsg channels: `rpmsg-client-sample` (echo, then destroy), `rpmsg-tty` (→ `/dev/ttyRPMSGx`), `rpmsg-raw` (→ `/dev/rpmsgX`).
- **Board glue**: `boards/imx95_evk_mimx9596_m7.overlay` + `.conf` in that app. The overlay defines `zephyr,ipc_shm` (0x88000000, 0x500000), `zephyr,ipc_rsc_table` (0x88220000), and `zephyr,ipc` as an `mbox-ipm` wrapper on **MU7**. These addresses **must match the Linux device tree** (reserved-memory, resource table, MU node) of the BSP running on the A55. A mismatch is the most likely cause of a remoteproc or virtio failure, not a Zephyr bug.
- **Memory map**: the default board variant runs from TCM (`itcm` at 0x0, `dtcm` at 0x20000000, 256 KB each). The `/ddr` and `/flash` board variants also exist. Console is `lpuart3`, 115200 8N1.
- **Cross-check sample**: `zephyr/samples/subsys/ipc/openamp_rsc_table` (the one NXP/Toradex docs use) builds to `build/openamp_rsc_table/zephyr/zephyr_openamp_rsc_table.elf`.

## FRDM-i.MX95 (the actual board)

The hardware is an FRDM-i.MX95, not the EVK. Build with `-b imx95_evk_15x15/mimx9596/m7` and always pass `-DEXTRA_ZEPHYR_MODULES=$PWD/frdm-imx95`. Without that module's DTCM ECC init, firmware started by remoteproc from a cold M7 dies silently before its first `printk`, even though remoteproc reports "is now up". The README section "FRDM-i.MX95 board" has the commands, the overlay/conf in `boards/frdm_imx95/`, the console port (`/dev/ttyACM2` on the host) and how to read the M7 log via `remoteproc1/trace0`. The M7 is `remoteproc1` on this board.

## Build output layout

Each app gets its own `-d build/<app>` directory, and the firmware ends up at `build/<app>/zephyr/<app>.elf`. The top-level `build/` directory also contains a stale default-dir build (CMakeCache, `build_info.yml` pointing at `zephyr/samples/hello_world`). Always pass `-d build/<app>` so you don't build into or read from it.

## Deploy notes (`flash.sh`)

`flash.sh` copies the ELF to `/lib/firmware/zephyr-remoteproc.elf` on the target and drives `/sys/class/remoteproc/remoteproc1` (stop → set firmware → start). That is correct for the FRDM board. The README's older EVK steps use `remoteproc0`, which on the FRDM is the Neutron NPU. If stopping fails with "not under Linux Control", the System Manager is not giving Linux control of the M7. That is a System Manager permissions issue, not something to fix in the firmware.
