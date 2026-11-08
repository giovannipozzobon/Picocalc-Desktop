/* pad_common.h -- what gamepad_test.c and pad_game.c share: the panel's text
 * grid, the keys (the PicoCalc's, a Bluetooth keyboard's and UART0's), the
 * radio, the gamepad's state, and the way back to the shell. Included by
 * each program; not a library.
 *
 * Both programs start Bluetooth and read the gamepad paired in its own place,
 * beside the keyboard and the mouse (btkbd.h). It is paired with btpair, or
 * from gamepad-test's page P: Search, then the number of the pad. They need /bluetooth/cyw43-fw.bin on the card, as
 * mouse-test does. */
#ifndef PAD_COMMON_H
#define PAD_COMMON_H

#include <malloc.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

#include "pico/cyw43_arch.h"
#include "pico/stdlib.h"

#include "btkbd.h"
#include "ff.h"
#include "gamepad.h"
#include "kbd.h"
#include "keycodes.h"
#include "keys.h"
#include "lcd.h"
#include "picocalc_shell.h"
#include "screen.h"
#include "southbridge.h"
#include "term.h"

#define KBD_POLL_US 33333u    /* the southbridge's keys, about 30 Hz (hardware-notes.md §6.1) */

#define PANEL_W 320
#define PANEL_H 320
#define COLS    40
#define ROWS    32
#define GLYPH_W 8
#define GLYPH_H 10

static term_t s_term;
static keys_t s_pc, s_bt;

/* FatFs's, for the pairing file's saves: a fixed date. */
DWORD get_fattime(void) {
    return (DWORD)(46u << 25 | 1u << 21 | 1u << 16);   /* 1 January 2026 */
}

static inline void flush(void) {
    screen_flush(&s_term, time_us_64());
}

/* A line of text at `row`, padded to 39 columns so that nothing wraps. */
static inline void put(int row, const char *fmt, ...) {
    char buf[96], at[16];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof buf, fmt, ap);
    va_end(ap);
    size_t n = strlen(buf);
    for (; n < COLS - 1; n++) buf[n] = ' ';
    buf[COLS - 1] = '\0';
    snprintf(at, sizeof at, "\033[%d;1H", row + 1);
    term_write(&s_term, at, strlen(at));
    term_write(&s_term, buf, COLS - 1);
}

static inline void tw(const char *s) {
    term_write(&s_term, s, strlen(s));
}

/* Text at a row and column, in reverse video if `on`. */
static inline void put_at(int row, int col, bool on, const char *s) {
    char at[16];
    snprintf(at, sizeof at, "\033[%d;%dH", row + 1, col + 1);
    tw(at);
    if (on) tw("\033[7m");
    tw(s);
    if (on) tw("\033[0m");
}

static inline void say(const char *s) {
    for (; *s; s++) {
        if (*s == '\n') term_write(&s_term, "\r", 1);
        term_write(&s_term, s, 1);
    }
    flush();
}

static inline void leave(void) {
    say("\nReturning to the shell.\n");
    sleep_ms(300);
    if (!picocalc_shell_card_present()) {
        say("Put the card back to return to\nthe shell.\n");
        while (!picocalc_shell_card_present()) tight_loop_contents();
        sleep_ms(500);
    }
    /* As picocalc_shell_exit(), less its check for a program in flash:
     * this one is in SRAM, started by stage3's BOOT_RAM, as ntp.uf2 is. */
    watchdog_hw->scratch[1] = PICOCALC_SHELL_BOOT_SD;
    watchdog_hw->scratch[2] = 0;
    watchdog_hw->scratch[0] = PICOCALC_SHELL_LOADER_MAGIC;
    watchdog_reboot(0, 0, 0);
    for (;;) tight_loop_contents();
}

/* The panel, the terminal and the radio. If the radio does not start, say
 * why and go back to the shell. */
static inline void pad_start(const char *title) {
    stdio_init_all();
#if !PICO_SHELL_HDMI
    gpio_pull_up(PICO_DEFAULT_UART_RX_PIN);   /* GP3 is the HDMI link's with the mirror */
#endif
    sb_init();
    lcd_init();
    screen_init();
    term_init(&s_term);
    keys_init(&s_pc);
    keys_init(&s_bt);
    tw("\033[1m");
    say(title);
    tw("\033[0m");
    say("\n\nStarting Bluetooth...\n");
    uint64_t t0 = time_us_64();
    if (!btkbd_init()) {
        say("  ");
        say(btkbd_status());
        say(".\n");
        leave();
    }
    char line[COLS];
    snprintf(line, sizeof line, "  Radio up in %lu ms.\n", (unsigned long)((time_us_64() - t0) / 1000u));
    say(line);
}

/* The next key as the shell's input has it (0x1B Esc, 9 Tab, '\r', the arrows
 * as keycodes.h's), or 0. Call it in a loop until it gives 0. */
static inline int pad_key(void) {
    static uint64_t next_kbd;
    uint16_t e;
    while ((e = btkbd_read()) != 0) {
        int k = keys_event(&s_bt, (uint8_t)(e >> 8), (uint8_t)e);
        if (k > 0) return k;
    }
    uint64_t now = time_us_64();
    if (now >= next_kbd) {
        next_kbd = now + KBD_POLL_US;
        kbd_poll();
    }
    uint8_t state, code;
    while (kbd_pop(&state, &code)) {
        int k = keys_event(&s_pc, state, code);
        if (k > 0) return k;
    }
    int c = getchar_timeout_us(0);
    if (c > 0 && c < 0x80) return c;
    return 0;
}

/* The gamepad now, and how many reports have come: false until the first. */
static unsigned s_pad_reports;
static inline bool pad_state(gamepad_t *g, btkbd_pad_t *raw) {
    if (btkbd_gamepad(raw)) s_pad_reports++;
    gamepad_set(g, raw->hat, raw->x, raw->y, raw->buttons);
    return s_pad_reports != 0;
}

static const char *const pad_state_names[] = {
    "off", "starting", "none paired", "waiting", "searching", "pairing", "connected",
};

static inline const char *pad_state_name(btkbd_state_t s) {
    return (unsigned)s < sizeof pad_state_names / sizeof pad_state_names[0] ? pad_state_names[s] : "?";
}

#endif /* PAD_COMMON_H */
