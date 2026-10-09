# Zephyr OpenAMP demo on i.MX95 Cortex-M7

This workspace builds the OpenAMP **`rpmsg_multi_services`** demo, a Zephyr
application, for the **NXP i.MX95 EVK Cortex-M7 core**
(`imx95_evk/mimx9596/m7`). The M7 firmware is the RPMsg *remote*. Linux on the
A55 cluster is the *host*: it loads and starts the firmware through
`remoteproc` and talks to it over RPMsg/virtio.

Build status: **compiles cleanly** (one harmless Kconfig warning, see
[Known warnings](#known-warnings)).

---

## FRDM-i.MX95 board (the board actually in use)

Zephyr v4.4.0 has no FRDM-i.MX95 board. The closest match, used for all FRDM
builds, is **`imx95_evk_15x15/mimx9596/m7`** (same 15x15 SoC package, LPDDR4x).
The board runs NXP Linux `6.12.49-lts-next` with device tree
`imx95-15x15-lpddr4x-frdm`.

| Item | Value |
|------|-------|
| M7 console | LPUART3, 115200 8N1, shows up as **`/dev/ttyACM2`** (the **third** USB serial port of the debug USB-C) on the Linux host machine |
| M7 console on macOS | `/dev/cu.usbmodem01234567895` (third port of the WCH "USB Quad_Serial" adapter). `hello_world` prints only once at start-up, so open the terminal *before* running `flash.sh` |
| A55 Linux console | LPUART1 (`ttyLP0` on the board), first USB port: `/dev/ttyACM0` on Linux, `/dev/cu.usbmodem01234567891` on macOS |
| M7 remoteproc instance | **`remoteproc1`** (`imx-rproc`). `remoteproc0` is the Neutron NPU |
| SSH | `HOST=root@frdm` (default in `flash.sh`) |

### Required fix: M7 DTCM ECC initialisation

The M7 TCMs have ECC. When Linux remoteproc starts the M7 from a **cold** state
(`dmesg` shows `imx-rproc is available` at boot, not `attaching to
imx-rproc`), only the ELF sections are written to TCM. Any other DTCM word
faults on its first read or byte write, so the firmware stops silently
before it prints anything. `remoteproc` still reports `remote processor
imx-rproc is now up`. For RPMsg firmware, Linux then logs
`imx_rproc_kick: failed (0, err:-62)`, because the M7 never reads the MU7
mailbox.

It only "worked" once, right after the boot chain had started another M7
image that had already initialised the TCM.

The workspace Zephyr module **`frdm-imx95/`** fixes this. It hooks
`soc_early_reset_hook` (`CONFIG_FRDM_IMX95_DTCM_ECC_INIT`, on by default for
the i.MX95 M7) and writes the full 256 KB DTCM once, before Zephyr touches
RAM. Pass it to every FRDM build with
`-DEXTRA_ZEPHYR_MODULES=$PWD/frdm-imx95`.

### Building the FRDM apps

There are three apps for the FRDM. All commands run from the workspace root
with the venv active (`source .venv/bin/activate`). `flash.sh` copies the
ELF to `/lib/firmware/zephyr-remoteproc.elf` on the board, stops
`remoteproc1` and starts it again with the new firmware.

| App | Source | Console | Status |
|-----|--------|---------|--------|
| `hello_world` | `zephyr/samples/hello_world` (upstream) | UART, `/dev/ttyACM2` | works |
| `tcm_ecc_test` | `apps/tcm_ecc_test` (workspace) | `trace0` in Linux | works |
| `rpmsg_multi_services` | `openamp-system-reference/examples/zephyr/rpmsg_multi_services` (upstream) + `boards/frdm_imx95/` (workspace) | `trace0` in Linux | builds; RPMsg on the board **not yet verified** with the ECC fix |

#### Options shared by every FRDM build

| Option | What it does | Why it is needed |
|--------|--------------|------------------|
| `-b imx95_evk_15x15/mimx9596/m7` | Board target: the i.MX95 15x15 EVK, `mimx9596` SoC, Cortex-M7 core | Zephyr has no FRDM-i.MX95 board. The 15x15 EVK has the same SoC package and LPDDR4x, and the same console (LPUART3) and memory map (code in ITCM at `0x0`, data in DTCM at `0x20000000`). Do **not** use `imx95_evk/...` (19x19, LPDDR5). |
| `-d build/<app>` | Build directory | One directory per app, so builds don't overwrite each other. Without `-d`, west builds into `build/` itself. |
| `-p always` | Pristine build: deletes the build directory first | Kconfig and devicetree changes are always picked up, and no leftovers from an earlier build (for example the SPSDK/LPDDR settings) remain. |
| `--` | Everything after it goes to CMake | Needed before the `-D...` options. |
| `-DEXTRA_ZEPHYR_MODULES=$PWD/frdm-imx95` | Adds the workspace module `frdm-imx95/`. It turns on `CONFIG_FRDM_IMX95_DTCM_ECC_INIT`, which selects `CONFIG_SOC_EARLY_RESET_HOOK` and links `frdm-imx95/src/dtcm_ecc_init.S` | **Required.** Without it, the firmware dies silently on a cold M7 start (see [Required fix](#required-fix-m7-dtcm-ecc-initialisation)). Must be an absolute path. |

The SPSDK boot image (`CONFIG_BOARD_NXP_SPSDK_IMAGE`) and the LPDDR choice
(`CONFIG_BOARD_NXP_LPDDR4/5`) are **left off on purpose**. They only matter
for a standalone SD-card boot image. Linux's boot chain has already set up
DDR before remoteproc loads the M7, and the M7 apps run from TCM.

#### 1. `hello_world` (UART console)

```bash
west build -p always -b imx95_evk_15x15/mimx9596/m7 -d build/hello_world \
    zephyr/samples/hello_world -- \
    -DEXTRA_ZEPHYR_MODULES=$PWD/frdm-imx95
HOST=root@frdm ./flash.sh build/hello_world/zephyr/zephyr.elf
```

Only the shared options are needed. The board defconfig already turns on
the UART console on LPUART3, plus the SCMI clock and pin drivers it needs
(`CONFIG_SERIAL`, `CONFIG_UART_CONSOLE`, `CONFIG_CLOCK_CONTROL`,
`CONFIG_ARM_SCMI`, `CONFIG_MBOX`). The firmware has no resource table, so
`dmesg` shows `No resource table in elf`. That is expected.

`hello_world` prints once at start-up and then idles. Open
`/dev/ttyACM2` (macOS: `/dev/cu.usbmodem01234567895`) at 115200 8N1
**before** running `flash.sh`:

```
*** Booting Zephyr OS build v4.4.0 ***
Hello World! imx95_evk_15x15/mimx9596/m7
```

#### 2. `tcm_ecc_test` (log in Linux, no drivers)

```bash
west build -p always -b imx95_evk_15x15/mimx9596/m7 -d build/tcm_ecc_test \
    apps/tcm_ecc_test -- \
    -DEXTRA_ZEPHYR_MODULES=$PWD/frdm-imx95
HOST=root@frdm ./flash.sh build/tcm_ecc_test/zephyr/zephyr.elf
ssh root@frdm cat /sys/kernel/debug/remoteproc/remoteproc1/trace0
```

This is the smallest possible check that the M7 runs. It was used to find
the ECC problem. It prints `alive N` every second to a RAM buffer that Linux
reads as `trace0`, so no UART is involved. Settings in
`apps/tcm_ecc_test/prj.conf`:

| Kconfig | Why |
|---------|-----|
| `CONFIG_CONSOLE=y`, `CONFIG_RAM_CONSOLE=y` | `printk` writes to the RAM buffer `ram_console_buf` (1 KB by default) |
| `CONFIG_UART_CONSOLE=n` | Zephyr has only one `printk` output, and the UART console would take it |
| `CONFIG_OPENAMP_RSC_TABLE=y` | Adds a `.resource_table` section to the ELF. Because `RAM_CONSOLE` is on, the table gets a `Zephyr_log` trace entry that points at `ram_console_buf`. Linux remoteproc exposes it as `trace0` |
| `CONFIG_OPENAMP_RSC_TABLE_NUM_RPMSG_BUFF=0` | Resource table with **only** the trace entry, no virtio/RPMsg device. Linux then never uses the mailbox for this firmware |
| `CONFIG_SERIAL=n`, `CONFIG_ARM_SCMI=n`, `CONFIG_MBOX=n`, `CONFIG_CLOCK_CONTROL=n`, `CONFIG_PINCTRL=n` | Turns off every driver that talks to the System Manager or the UART. If this app prints, the M7 core, TCM and the remoteproc load are fine. Any remaining problem is in a driver |

The Kconfig warnings about `UART_INTERRUPT_DRIVEN`, `MBOX_INIT_PRIORITY`
and `ARM_SCMI_NXP_VENDOR_EXTENSIONS` are expected. They are board defaults
for drivers this app turns off.

#### 3. `rpmsg_multi_services` (OpenAMP demo)

```bash
west build -p always -b imx95_evk_15x15/mimx9596/m7 -d build/rpmsg_multi_services_frdm \
    openamp-system-reference/examples/zephyr/rpmsg_multi_services -- \
    -DEXTRA_ZEPHYR_MODULES=$PWD/frdm-imx95 \
    -DDTC_OVERLAY_FILE=$PWD/boards/frdm_imx95/rpmsg_multi_services.overlay \
    -DEXTRA_CONF_FILE=$PWD/boards/frdm_imx95/rpmsg_multi_services.conf
HOST=root@frdm ./flash.sh build/rpmsg_multi_services_frdm/zephyr/rpmsg_multi_services.elf
ssh root@frdm cat /sys/kernel/debug/remoteproc/remoteproc1/trace0
```

Extra options on top of the shared ones:

| Option | What it does | Why it is needed |
|--------|--------------|------------------|
| `-DDTC_OVERLAY_FILE=.../rpmsg_multi_services.overlay` | Devicetree overlay that sets `zephyr,ipc_shm` (shared memory `0x88000000`, 5 MB), `zephyr,ipc_rsc_table` (`0x88220000`) and `zephyr,ipc` (a `zephyr,mbox-ipm` wrapper on **MU7 channel 1**, tx and rx), and enables `mu7` | The demo only ships overlays for named boards (`boards/imx95_evk_mimx9596_m7.overlay`). There is none for the 15x15 target, so we pass a copy of the EVK one explicitly. Its addresses match the FRDM Linux device tree: `vdev0vring0/1` at `0x88000000`/`0x88008000`, `vdevbuffer` at `0x88020000`, `rsc-table` at `0x88220000`, and the `imx95-cm7` node's mailbox `mu7` channel 1. If any of these differ from Linux, RPMsg fails. Setting `DTC_OVERLAY_FILE` also stops Zephyr from auto-loading overlays from the app's `boards/` directory. |
| `-DEXTRA_CONF_FILE=.../rpmsg_multi_services.conf` | Kconfig fragment merged after the demo's `prj.conf` | Same reason: the demo's `boards/imx95_evk_mimx9596_m7.conf` is only picked up for the 19x19 EVK target. Contents below. |

What the demo's own `prj.conf` already sets (not changed):
`CONFIG_OPENAMP=y`, `CONFIG_OPENAMP_RSC_TABLE=y` (resource table with a
vdev), `CONFIG_OPENAMP_RSC_TABLE_NUM_RPMSG_BUFF=8` (8 buffers per vring),
`CONFIG_OPENAMP_MASTER=n` (the M7 is the remote, Linux is the host),
`CONFIG_IPM=y`, `CONFIG_HEAP_MEM_POOL_SIZE`, `CONFIG_MAIN_STACK_SIZE`, and
`CONFIG_PRINTK=n`, which our fragment overrides.

`boards/frdm_imx95/rpmsg_multi_services.conf`:

| Kconfig | Why |
|---------|-----|
| `CONFIG_ARM_SCMI=y`, `CONFIG_CLOCK_CONTROL=y` | Clocks and pins go through the i.MX95 System Manager (SCMI) |
| `CONFIG_IPM_MBOX=y`, `CONFIG_MBOX_NXP_IMX_MU=y` | The `zephyr,mbox-ipm` wrapper and the NXP MU mailbox driver: the "doorbell" between Linux and the M7 |
| `CONFIG_MBOX_INIT_PRIORITY=0` | The MU must be ready before SCMI and IPM, which use it |
| `CONFIG_OPENAMP_WITH_DCACHE=y` | The M7 has a data cache. OpenAMP must flush and invalidate vrings and buffers, or Linux and the M7 see stale data |
| `CONFIG_OPENAMP_COPY_RSC_TABLE=y` | The M7 copies its resource table to `zephyr,ipc_rsc_table` (`0x88220000`), where Linux expects it |
| `CONFIG_CONSOLE=y`, `CONFIG_LOG=y`, `CONFIG_LOG_MODE_MINIMAL=y`, `CONFIG_LOG_DEFAULT_LEVEL=0` | Keep logging small. Only the demo's own `printk` and `LOG_*` output appears |
| `CONFIG_RAM_CONSOLE=y`, `CONFIG_RAM_CONSOLE_BUFFER_SIZE=4096`, `CONFIG_UART_CONSOLE=n`, `CONFIG_PRINTK=y` | **FRDM addition.** The M7 log goes to `trace0` in Linux instead of the UART, so the RPMsg handshake can be followed from Linux. 4 KB because the demo logs more than `hello_world`. `PRINTK=y` overrides the demo's `=n`, because the RAM console is fed through `printk` |

This FRDM build has no Kconfig warnings. The `PRINTK ... was assigned the
value 'n' but got the value 'y'` warning in [Known warnings](#known-warnings)
only shows up in the plain EVK build, where nothing overrides the demo's
`CONFIG_PRINTK=n`.

---

## Quick start

```bash
./build.sh            # first run: venv + west init + west update + SDK + build
./build.sh --all      # also build Zephyr's in-tree openamp_rsc_table sample
./build.sh --update   # re-run west update (e.g. after changing the manifest)
```

The firmware is written to `build/rpmsg_multi_services/zephyr/rpmsg_multi_services.elf`.

To rebuild by hand:

```bash
source .venv/bin/activate
west build -p always -b imx95_evk/mimx9596/m7 -d build/rpmsg_multi_services \
    openamp-system-reference/examples/zephyr/rpmsg_multi_services
```

---

## What was downloaded

### Demo application repo (west manifest repo)

[OpenAMP/openamp-system-reference](https://github.com/OpenAMP/openamp-system-reference)
on branch `main`. This repo contains the demo and is also the west manifest
repo, so it decides which Zephyr and which OpenAMP libraries are used.
Its `west.yml`:

| Project                  | Revision | Notes                                                    |
|--------------------------|----------|----------------------------------------------------------|
| `zephyr`                 | `v4.4.0` | `import: true`, so it also pulls Zephyr's own module list |
| `libmetal`               | `main`   | replaces Zephyr's copy                                   |
| `open-amp`               | `main`   | replaces Zephyr's copy                                   |
| `openamp-zephyr-modules` | `main`   | Zephyr module glue that combines libmetal and open-amp    |

### Revisions checked out (2026-10-06)

| Path                         | Commit / version |
|------------------------------|------------------|
| `openamp-system-reference/`  | `c515eff` |
| `zephyr/`                    | `v4.4.0` (`684c9e8f`) |
| `libmetal/`                  | `f05a041` |
| `open-amp/`                  | `a0ec4fc` |
| `openamp-zephyr-modules/`    | `8ba9f59` |
| `modules/hal/nxp`            | `2c2f28ac` |
| `modules/hal/cmsis`          | `512cc7e8` |
| `modules/hal/cmsis_6`        | `30a859f4` |

Run `west list` to see the current state.

### Workspace layout

```
zephyr-rpc/
├── README.md                    ← this file
├── build.sh                     ← setup + build script
├── .venv/                       ← Python 3.12 venv (west + Zephyr requirements)
├── .west/config                 ← west workspace config (incl. project filter)
├── openamp-system-reference/    ← demo app repo / west manifest
│   └── examples/zephyr/rpmsg_multi_services/   ← the app that gets built
├── zephyr/                      ← Zephyr RTOS v4.4.0
├── libmetal/  open-amp/  openamp-zephyr-modules/
├── modules/hal/{nxp,cmsis,cmsis_6}/
└── build/
    ├── rpmsg_multi_services/    ← main demo build
    └── openamp_rsc_table/       ← in-tree Zephyr sample (cross-check)
```

---

## Step-by-step: what was done

### 1. Host prerequisites (macOS arm64)

Already installed through Homebrew: `cmake` 4.4.3, `ninja` 1.13.2, `dtc` 1.8.1, `git`,
and `python3.12`.

> **Python ≥ 3.12 is required.** Zephyr 4.4 rejects older versions. The
> system default here is 3.10.11, and configuration then fails with
> `Could NOT find Python3: Found unsuitable version "3.10.11", but required is at least "3.12"`.
> This is why the venv is created with `/opt/homebrew/bin/python3.12`. Set
> `PYTHON=...` to use a different interpreter with `build.sh`.

### 2. Python venv + west

```bash
/opt/homebrew/bin/python3.12 -m venv .venv
.venv/bin/pip install --upgrade pip west
source .venv/bin/activate
```

### 3. Check out the demo repo (west init)

```bash
west init -m https://github.com/OpenAMP/openamp-system-reference --mr main .
```

### 4. West update (restricted to the modules needed)

Zephyr's manifest imports about 60 modules, and all HALs together take several GB.
Disk space was limited on this machine (about 6 GB free), so a **project filter**
keeps only what this target needs. Clones are also shallow:

```bash
west config manifest.project-filter -- \
  '-.*,+zephyr,+libmetal,+open-amp,+openamp-zephyr-modules,+hal_nxp,+cmsis,+cmsis_6'
west update --narrow -o=--depth=1
pip install -r zephyr/scripts/requirements-base.txt
```

The workspace takes about 1.6 GB, including build output.

To fetch **all** modules instead (for other boards or samples):

```bash
west config -d manifest.project-filter
west update
pip install -r zephyr/scripts/requirements.txt
```

### 5. Zephyr SDK

Zephyr v4.4.0 requires SDK **1.0.1** (`zephyr/SDK_VERSION`). Only the ARM
toolchain was installed, in `~/zephyr-sdk-1.0.1`. Zephyr CMake finds it there
automatically.

```bash
west sdk install -b ~ -t arm-zephyr-eabi
```

Toolchain: `arm-zephyr-eabi-gcc (Zephyr SDK 1.0.1) 14.3.0`. The SDK does not
yet ship macOS host tools (`SKIPPED: macOS host tools are not available yet`).
Building does not need them.

> `~/zephyr-sdk-0.17.4` and `~/zephyrproject` already existed on this machine
> and are not used by this workspace.

### 6. Build

```bash
west build -p always -b imx95_evk/mimx9596/m7 -d build/rpmsg_multi_services \
    openamp-system-reference/examples/zephyr/rpmsg_multi_services
```

No source changes were needed. The demo already has i.MX95 M7 board files.

---

## Build results

### `rpmsg_multi_services` (main demo)

```
Memory region         Used Size  Region Size  %age Used
           FLASH:       31212 B       256 KB     11.91%
             RAM:       13796 B       256 KB      5.26%
            ITCM:           0 B       256 KB      0.00%
        IDT_LIST:           0 B        32 KB      0.00%
```

Output files in `build/rpmsg_multi_services/zephyr/`:
- `rpmsg_multi_services.elf`: the file to load with Linux remoteproc
- `rpmsg_multi_services.bin`: raw image

### `openamp_rsc_table` (Zephyr in-tree sample, cross-check)

This is `zephyr/samples/subsys/ipc/openamp_rsc_table`, the sample that NXP and
Toradex docs use for i.MX95. It also builds without changes:

```
FLASH: 56536 B / 256 KB (21.57%)    RAM: 18652 B / 256 KB (7.12%)
```

Output: `build/openamp_rsc_table/zephyr/zephyr_openamp_rsc_table.elf`

### Known warnings

```
warning: PRINTK (defined at subsys/debug/Kconfig:145) was assigned the value 'n' but got the value 'y'
```

The demo's `prj.conf` sets `CONFIG_PRINTK=n`, but the board/console
configuration forces it back on. This is harmless and has no effect on
functionality.

---

## How the demo is configured for i.MX95 M7

### Target memory map (`imx95_evk/mimx9596/m7`, default variant)

The code runs from the M7 TCM: `zephyr,flash = &itcm` at `0x0`, and
`zephyr,sram = &dtcm` at `0x20000000`, 256 KB each. Two other variants exist,
`imx95_evk/mimx9596/m7/ddr` and `imx95_evk/mimx9596/m7/flash`, if the image
has to run from DDR or flash instead.

Console: `lpuart3`, 115200 8N1.

### Board files used by the demo

`openamp-system-reference/examples/zephyr/rpmsg_multi_services/boards/`:

**`imx95_evk_mimx9596_m7.overlay`**
- `zephyr,ipc_shm`: shared memory (vrings + buffers) at `0x88000000`, size `0x500000`
- `zephyr,ipc_rsc_table`: resource table at `0x88220000`, size `0x100`
- `zephyr,ipc`: `zephyr,mbox-ipm` wrapper on **MU7** (`mu7`, channel 1 for tx and rx)

**Key Kconfig (`prj.conf` + board `.conf`)**
- `CONFIG_OPENAMP=y`, `CONFIG_OPENAMP_RSC_TABLE=y`, `CONFIG_OPENAMP_COPY_RSC_TABLE=y`
- `CONFIG_OPENAMP_RSC_TABLE_NUM_RPMSG_BUFF=8`
- `CONFIG_OPENAMP_WITH_DCACHE=y` (M7 has a D-cache, so buffers are flushed and invalidated)
- `CONFIG_IPM=y`, `CONFIG_IPM_MBOX=y`, `CONFIG_MBOX_NXP_IMX_MU=y`, `CONFIG_MBOX_INIT_PRIORITY=0`
- `CONFIG_ARM_SCMI=y` (clocks and power through the i.MX95 System Manager)

> The addresses in the overlay have to match the Linux device tree for the
> M7 remoteproc node: the `reserved-memory` regions for vdev vrings and
> buffers, the resource table, and the MU7 mailbox. If you use a different BSP
> memory layout, change the overlay to match.

### What the firmware does

`src/main_remote.c` announces three RPMsg channels to Linux:

| Channel               | Linux side                         | Behaviour |
|-----------------------|------------------------------------|-----------|
| `rpmsg-client-sample` | `rpmsg_client_sample.ko`           | Echoes the 100 ping messages back to Linux, then destroys the channel |
| `rpmsg-tty`           | `rpmsg_tty.ko` → `/dev/ttyRPMSG0`  | TTY echo |
| `rpmsg-raw`           | `rpmsg_char.ko` → `/dev/rpmsg0`    | Raw data endpoint (use with `rpmsg-utils`) |

---

## Running on the board (Linux on A55 as host)

Not yet tested on hardware. These steps come from the demo README.

1. Linux must have `remoteproc` support for the i.MX95 M7, with
   reserved-memory and MU nodes that match the overlay, plus these modules:
   `CONFIG_SAMPLE_RPMSG_CLIENT`, `CONFIG_RPMSG_TTY`, `CONFIG_RPMSG_CHAR`.
2. Copy the firmware to the target:
   ```bash
   scp build/rpmsg_multi_services/zephyr/rpmsg_multi_services.elf root@<board>:/lib/firmware/
   ```
3. On the target:
   ```bash
   modprobe rpmsg_client_sample; modprobe rpmsg_tty; modprobe rpmsg_char; modprobe rpmsg_ctrl
   echo rpmsg_multi_services.elf > /sys/class/remoteproc/remoteproc0/firmware
   echo start > /sys/class/remoteproc/remoteproc0/state
   dmesg | grep -i rpmsg            # channel creation + 100 sample messages
   ls /dev/ttyRPMSG* /dev/rpmsg*
   echo hello > /dev/ttyRPMSG0 && cat /dev/ttyRPMSG0
   ```
4. Watch the Zephyr console on the M7 debug UART (lpuart3, 115200 8N1). You
   can also read the remoteproc trace buffer:
   `cat /sys/kernel/debug/remoteproc/remoteproc0/trace0`.

---

## References

- Demo repo: https://github.com/OpenAMP/openamp-system-reference
- Demo docs: https://openamp.readthedocs.io/en/latest/openamp-system-reference/examples/zephyr/rpmsg_multi_services/README.html
- Zephyr i.MX95 EVK board: https://docs.zephyrproject.org/latest/boards/nxp/imx95_evk/doc/index.html
- Zephyr OpenAMP rsc_table sample: https://docs.zephyrproject.org/latest/samples/subsys/ipc/openamp_rsc_table/README.html
- Toradex: Loading Zephyr on i.MX95 Cortex-M from Linux with OpenAMP: https://www.toradex.com/blog/imx95-zephyr-asymmetric-multiprocessing
