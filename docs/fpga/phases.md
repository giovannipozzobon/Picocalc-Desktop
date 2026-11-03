# PicoCalc HDMI Mirror — note di fase dell'FPGA

Note di lavoro portate da `pico_tang20k_hdmi` (2026-11-03). Il firmware di quel repository (copia di `picocalc-text-starter` con lo specchio) non è stato portato: lo specchio è ora nella shell (`src/port/mirror.c`, comando `hdmi`, design.md §3.11). Dove queste note parlano di `hdmipat`, `linktest` o del firmware `picocalc-hdmi-mirror.uf2`, si riferiscono a quel repository. Si compila con `tools/build-fpga.sh`, si simula con `tools/test-fpga.sh`.

Specchio HDMI del display del PicoCalc con una Tang Nano 20K. Specifica e piano: [hdmi-mirror-protocol.md](hdmi-mirror-protocol.md).

## Struttura

| Percorso | Contenuto |
| --- | --- |
| `fpga/rtl/video` | timing, TMDS, PLL (da J20K) e barre di colore |
| `fpga/rtl/link` | `qspi_rx` |
| `fpga/rtl/lcd` | `cmd_decoder`, `scroll_map` |
| `fpga/rtl/top` | top di sintesi per fase |
| `fpga/sim` | testbench Icarus Verilog (`run_sim.sh`) |
| `fpga/gowin` | `run_synth.sh` (Gowin EDA) |
| `fpga/constraints` | `.cst` / `.sdc` |

## Stato

- Fase 0: completata.
- Fase 1: **verificata su monitor** (barre e quadratino mobile).
- Fase 2: verificata su fili volanti senza resistenze serie, con filtro anti-glitch `FILT=3` (SCK <= circa 15 MHz) e driver Pico 2 mA: `linktest` da 1 MiB con zero errori a 1, 5, 10 e 15 MHz. A 20 MHz fallisce (anche con `FILT=2`: problema di segnale, non di filtro). Frequenza predefinita 15 MHz; 20-25 MHz da riprovare con resistenze serie e `FILT=1`. Il firmware `firmware/out/picocalc-hdmi-mirror.uf2` ha il comando `linktest [MHz] [KiB]`; la FPGA `linktest` si carica con `[FILT=n] fpga/gowin/run_synth.sh linktest --program`.
- Fase 3: verificata su hardware con `hdmipat` (immagine 320x320 su HDMI 720p, forma e colori coincidenti con l'LCD; simulazione `mirror_core` PASS). FPGA `fpga/gowin/run_synth.sh mirror --program` (QSPI -> decoder -> SDRAM -> HDMI, scala 2x, scroll_map, DISPON/INV agganciati). Con INVON (sempre mandato da `lcd_init`) l'HDMI mostra la memoria com'e'; con INVOFF la inverte. Il confronto e' a occhio: un controllo pixel per pixel di linee sottili e testo piccolo resta da fare. Margine di timing stretto sul dominio QSPI (circa 125 MHz su 123,75).
- Fase 4: chiusa con un limite noto. Scroll del terminale verificato su LCD e HDMI (anche oltre il giro della memoria da 480 righe), che conferma `vsam = 480 - TFA - BFA`. Overhead dello specchio su `lcd_blit` misurato con `lcdbench`: strip +11,7%, glifo +44,3% (a 15 MHz), sopra il 5% richiesto; accettato, con i rimedi descritti nel documento. Non ho un riscontro scritto sulle schermate dei `test` del firmware.
- Fase 5: verificata su hardware. Colori, inversione e orientamento coincidono con l'LCD (`hdmipat`); dopo lo spegnimento della sola FPGA, ricaricato il bitstream `mirror`, `hdmi` + ridisegno riportano l'immagine corretta. `MADCTL` e' memorizzato dal decoder ma il video non lo applica (il firmware non lo cambia).

## Comandi

```bash
fpga/sim/run_sim.sh                         # testbench
fpga/gowin/run_synth.sh bars480 --program   # fase 1
fpga/gowin/run_synth.sh linktest --program  # fase 2
fpga/gowin/run_synth.sh mirror --program    # fase 3
# firmware (SDK 2.3.x, cartella firmware/picocalc-text-starter):
cmake -S . -B build -G Ninja -DPICOCALC_HDMI_MIRROR=ON && cmake --build build
```

## Origine e licenze

- `firmware/picocalc-text-starter/` è una copia di [BlairLeduc/picocalc-text-starter](https://github.com/BlairLeduc/picocalc-text-starter) (licenza MIT, vedi il suo `LICENSE`) con le modifiche per lo specchio HDMI: `drivers/mirror.*`, agganci in `drivers/lcd.c`, comandi `hdmi` e `linktest`.
- Compatibilita' con il Bluetooth di [picocalc-extras](https://github.com/ctorkildson-netizen/picocalc-extras) (Chris Torkildson): la copia del text-starter qui ha la stessa base upstream (v0.17, commit `0bfdb5d`) del text-starter usato da `btpair` e dalla libreria `btkbd` (controllato il 2 novembre 2026: le sole differenze sono i nostri agganci allo specchio, in `lcd.c`, `lcd.h`, `commands.*` e `CMakeLists.txt`). `btpair` compila anche contro questa copia. Il firmware dello specchio non usa ancora `btkbd`: l'abbinamento si fa con `btpair` (programma separato, pairing salvato in `/bluetooth/pairing.dat` sulla SD, formato KBD0/KBL0 per la tastiera e PTR0/PTL0 per il mouse), quindi le modifiche a `btpair` non toccano questo repository. Se in futuro si integra `btkbd`: scheda `pico2_w`, nessun conflitto di pin (la radio usa GP23-25 e GP29, lo specchio GP2-5, GP20, GP21 e GP28) ne' di PIO (il driver della radio prende da solo una state machine libera fra i tre PIO).
- `fpga/rtl/video/j20k_*.v` e `fpga/rtl/common/uart_tx.v` vengono dal progetto J20K.
