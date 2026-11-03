# picocalc_desktop

A **desktop PicoCalc**: the [ClockworkPi PicoCalc](https://www.clockworkpi.com/picocalc)
used with a real keyboard, a mouse and a monitor.

- **Monitor.** The PicoCalc's 320x320 panel is copied, as it is drawn, to a
  Sipeed **Tang Nano 20K** FPGA board, which scales it 2x and shows it on
  HDMI (1280x720).
- **Keyboard and mouse.** A Bluetooth keyboard and mouse work through the
  Pico 2 W's radio, beside the PicoCalc's own keyboard.
- **The shell.** The PicoCalc runs [picocalc-shell](SHELL.md), a UNIX-like (or
  DOS-like) command line that also runs UF2 programs from the SD card. The
  mouse's wheel scrolls the history, `more` and the editors; a pointer and
  clicks are the next step.

The repository holds both halves: the shell's firmware (C, Pico SDK) and the
FPGA's gateware (Verilog, Gowin EDA).

| What | Where |
|---|---|
| The shell: commands, install, the two flavours | [SHELL.md](SHELL.md), [docs/user-guide-unix.md](docs/user-guide-unix.md), [docs/user-guide-dos.md](docs/user-guide-dos.md) |
| Code from other projects, licences | [THIRD-PARTY.md](THIRD-PARTY.md) |

## What you need

- A PicoCalc with a **Pico 2 W** or **Pimoroni Pico Plus 2 W** (RP2350 with
  the CYW43439 radio). Bluetooth needs the W. The HDMI mirror should work
  on a Pico 2 too, but it has never been tried there.
- A **Sipeed Tang Nano 20K** (Gowin GW2AR-18C), with an HDMI cable to the monitor.
- **Gowin EDA**, Gowin's FPGA tool, to build the bitstream: download and install it from
  [gowinsemi.com](https://www.gowinsemi.com/en/support/download_eda/).
  Without it only the simulation and the firmware can be built.
- A Bluetooth keyboard and/or mouse.
- To build: [CMake](https://cmake.org), the Pico SDK with its Arm toolchain
  (the build finds the newest under `~/.pico-sdk/`, as the VS Code extension
  installs it); for the FPGA, Gowin EDA (on macOS under `/Applications`, or
  set `GOWIN_HOME`) and [openFPGALoader](https://github.com/trabucayre/openFPGALoader)
  to load it; for its simulation, Icarus Verilog.

## Build the PicoCalc's firmware

```sh
# The shell for the Pico 2 W with the HDMI mirror and Bluetooth
tools/build.sh -DPICO_SHELL_UART=OFF -DPICO_BOARD=pico2_w -DPICO_SHELL_HDMI=ON build/pico-w-hdmi

# The same, in the DOS flavour
tools/build.sh -DPICO_SHELL_UART=OFF -DPICO_BOARD=pico2_w -DPICO_SHELL_HDMI=ON \
               -DPICO_SHELL_FLAVOUR=dos build/pico-dos-w-hdmi
```

- `build/pico-w-hdmi/BOOT2350.uf2` is the shell. Copy it to the card as
  `/BOOT2350.UF2`; [SHELL.md](SHELL.md) says how it is installed and how to
  get back to UF2 Loader's menu.
- The same directory has the test programs (below), `ntp.uf2` and
  `cyw43fw/cyw43-fw.bin`, the radio's firmware, which the shell reads from
  the card at `/bluetooth/cyw43-fw.bin`.
- `-DPICO_SHELL_HDMI=ON` needs `-DPICO_SHELL_UART=OFF`: the HDMI link takes
  GP2 and GP3, the debug UART's pins, and GP4 and GP5, the DS3231
  clock's. Without the option, the shell has no HDMI code and `hdmi` says
  `not on this machine`; without `-DPICO_BOARD=pico2_w`, there is no Bluetooth.
- The host tests need no hardware: `cmake -S . -B build/host -DPICO_SHELL_HOST=ON && cmake --build build/host -j && ctest --test-dir build/host --output-on-failure`.

## Build the FPGA's bitstream (Tang Nano 20K)

**Install Gowin EDA first**; `tools/build-fpga.sh` stops with `gw_sh non
trovato` if it cannot find it. It looks in `/Applications` and
`~/Applications`, or in `$GOWIN_HOME` (the directory that holds `IDE/bin/gw_sh`).

```sh
tools/build-fpga.sh mirror              # build/fpga/mirror.fs
tools/build-fpga.sh mirror --program    # and load it into the FPGA's SRAM (lost at power-off)
tools/build-fpga.sh mirror --flash      # and load it into its SPI flash (kept)
tools/test-fpga.sh                      # the testbenches (Icarus Verilog); mirror_core takes about a minute
```

| Target | What it is |
|---|---|
| `mirror` | the mirror: QSPI link, decoder, SDRAM frame memory, HDMI. The one to use |
| `linktest` | tests the link's wiring and speed with a pseudo-random sequence (the Pico's side of it is not in this repository) |
| `bars480`, `bars720` | colour bars on HDMI, to check the monitor and the board alone |

The synthesis is for the device `GW2AR-LV18QN88C8/I7`, the Tang Nano 20K's.
Gowin's work directory, `fpga/gowin/work/`, is not kept in git.

## Wiring PicoCalc to Tang Nano 20K

The link is one-way, a 4-bit QSPI from the PicoCalc's **J703** header
(the pins of the PSRAM chip, which the board does not use) to the FPGA
board. For now it is loose wires:

| PicoCalc J703 | Pico | Signal | Tang Nano 20K pin |
|---:|---|---|---:|
| 2 | GP2 | D0 | 73 |
| 3 | GP3 | D1 | 74 |
| 4 | GP4 | D2 | 75 |
| 5 | GP5 | D3 | 77 |
| 6 | GP21 | SCK | 76 |
| 7 | GP28 | CS_N | 86 |
| 8 | — | GND | GND |
| 1 | — | 3V3_OUT | **not connected** |

The FPGA's pins are in `fpga/constraints/link_qspi.cst`, which says they
were chosen from Sipeed's pin map and are to be checked against the board's
schematic. The shell holds GP20, the PSRAM's chip select, high. HDMI goes
out on the Tang Nano 20K's own HDMI connector.

## Turn on the HDMI mirror

1. Load the `mirror` bitstream into the FPGA (above), wire the boards, and
   connect the monitor.
2. Install the shell built with `-DPICO_SHELL_HDMI=ON`. If the FPGA is
   powered when the PicoCalc starts, the mirror works from the first screen.
3. If the FPGA came up later, or a cable moved, type `hdmi` (DOS: `HDMI`).
   It sends the FPGA the panel's state again, redraws the screen, and says
   `HDMI mirror on, QSPI 15000 kHz`.

`info` ends its `build` line with `hdmi` and `BT` when the build has them.
The mirror is in the shell and in the programs built with it, such as
`mouse-test`; a program with its own display code, such as an emulator, does
not copy to the HDMI.

## Pair a Bluetooth keyboard and mouse

Pairing is done by **btpair**, a program of
[picocalc-extras](https://github.com/ctorkildson-netizen/picocalc-extras/tree/main/bluetooth)
(Chris Torkildson), not by this repository. Use btpair 2.1 or later, which
keeps one keyboard and one mouse:

1. Build `btpair.uf2` from picocalc-extras and copy it to `/pico2-apps/` on
   the card. Copy this build's `cyw43fw/cyw43-fw.bin` to `/bluetooth/`.
2. In the shell type `btpair`, put the keyboard or mouse in pairing mode, and
   follow it. The pairing is kept in `/bluetooth/pairing.dat`.
3. Restart the shell. The radio starts only when that file exists, in about a
   second, and the paired devices connect when you press a key or button.
   `bt` says what Bluetooth is doing (`connected: K380`, `waiting for K380`,
   ...).

If a device stops connecting, pair it again: it forgets the PicoCalc when it is
put in pairing mode elsewhere. In the shell, the mouse's wheel scrolls the
history, `more`, vi and EDIT. Low Energy (BLE) devices, the mouse and the
keyboard together, and a keyboard's trackpad as a mouse have not all been
checked on the board.

## Test programs

The test programs are built beside the shell. Copy each `.uf2` to
`/pico2-apps/` on the card and type its name at the prompt; Esc (for some,
any key) returns to the shell. The Bluetooth ones need
`/bluetooth/cyw43-fw.bin` and, except `cyw43fw-test`, `/bluetooth/pairing.dat`.

| Program | What it does |
|---|---|
| `mouse-test` | Starts Bluetooth and shows what the mouse does, on three pages; **Tab** changes page. **A**: the numbers (counts, wheel, buttons, reports per second). **B**: an arrow in pixels that follows the mouse, coloured by the buttons, with marks for clicks, a grid every 40 pixels and the wheel's bar. **C**: a pointer cell on the text grid over a list of items, which a click chooses and the wheel scrolls. `+` and `-` change the gain (0.5 pixel per count by default), `a` turns acceleration on and off, `c` clears. Built with the HDMI mirror, its pages show on the monitor |
| `btkbd-test` | Starts Bluetooth and shows each key from the Bluetooth keyboard (`bt`) and from the PicoCalc (`pc`), with the memory BTstack has taken; press a key to wake the keyboard |
| `cyw43fw-test` | Starts the radio with its firmware read from the card, says how long it took and scans for networks, to check `cyw43-fw.bin` |
| `exit-test`, `restart-test`, `restart-ram` | the shell's: leaving a program, and the way out of a restart loop |
| `clock-test`, `rtc-stop` | the shell's: the clock handed to programs, and a DS3231 that loses its time (`rtc-stop` needs the DS3231, which the HDMI link's pins exclude) |

Each program's header, at the top of its file in `test/pico/`, tells what
it shows and how to use it.

## Next steps

- **A board in place of the loose wires.** A small PCB between J703 and the
  Tang Nano 20K, to raise the link from 15 MHz to 20-25 MHz. On loose wires
  with no series resistors the link carried 1 MiB with no errors at 1, 5, 10
  and 15 MHz and failed at 20 MHz, even with a shorter glitch filter
  (`FILT=2`). 20-25 MHz is to be tried with series resistors and `FILT=1`
  (`FILT=1 tools/build-fpga.sh linktest`).
- **The mouse in the shell.** A pointer on the screen and clicks at the
  prompt, in vi, EDIT and the menus.

## Licence

MIT, see [LICENSE](LICENSE). The files derived from UF2 Loader and pico-oric stay
under the GPL-3.0 ([LICENSE-GPL-3.0](LICENSE-GPL-3.0)), so a firmware image that
links them is distributed under it. [THIRD-PARTY.md](THIRD-PARTY.md) lists them, and the
other code and fonts used.
