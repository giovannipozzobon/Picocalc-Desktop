/* gamepad.h -- a Bluetooth gamepad's state and its keys (portable: no SDK).
 *
 * btkbd.c reads a gamepad's HID reports (hat switch, two axes, buttons) and
 * hands the raw values to gamepad_set(), which gives one state: the four
 * directions and up to 32 buttons. gamepad_keys() turns a state into key
 * presses for the shell, with auto-repeat on the directions.
 *
 * Written for the 8BitDo M30 (a Sega-style pad: D-pad, A B C X Y Z, Start,
 * Select) in its Bluetooth D-input mode, but nothing here is the M30's alone:
 * any HID gamepad with a hat or a stick gives the same.
 *
 * Buttons are numbered as the HID report numbers them (button page, usage
 * 1 is bit 0). If a pad lays them out differently, the roles below are the
 * one place to change. gamepad-test shows each button's number.
 *
 * SPDX-License-Identifier: MIT */
#ifndef SHELL_GAMEPAD_H
#define SHELL_GAMEPAD_H

#include <stdbool.h>
#include <stdint.h>

/* directions, as bits */
#define GP_UP    0x01
#define GP_DOWN  0x02
#define GP_LEFT  0x04
#define GP_RIGHT 0x08

/* what the buttons do (bit numbers, 0 is HID button 1). For the M30 in
   D-input mode, in the order its report lists them: */
#define GP_BTN_FIRE    0     /* A: fire, and Enter in the shell */
#define GP_BTN_FIRE2   1     /* B: second button, and Esc in the shell */
#define GP_BTN_SELECT  10    /* Select, as HID lists it for the M30: Tab */
#define GP_BTN_START   11    /* Start: Enter */

/* a stick counts as a direction beyond this far from the centre (of 127) */
#define GP_STICK_ZONE 64

typedef struct {
    uint8_t  dirs;       /* GP_UP | GP_DOWN | GP_LEFT | GP_RIGHT */
    uint32_t buttons;    /* bit n: HID button n+1 held (up to 32) */
} gamepad_t;

/* The raw values of one report. hat: 0-7 clockwise from up, or -1 for the
   neutral position or no hat; x, y: a stick, centred, -128..127 (0 if none,
   y positive is down, as HID has it). */
void gamepad_set(gamepad_t *g, int hat, int x, int y, uint32_t buttons);

/* A hat's value as 0-7, from its report value and logical minimum (0..7
   with 8 for neutral, or 1..8 with 0 for it, are both handled): -1 neutral. */
int gamepad_hat(int value, int logical_min);

/* An axis's value as -128..127 from the report value, its logical minimum
   and its size in bits (an unsigned axis is centred on half its range). */
int gamepad_axis(int value, int logical_min, int bits);

/* Key presses for the shell. The directions are the arrows and repeat after
   a delay; Fire is Enter, Fire 2 Esc, Select Tab, Start Enter. */
typedef struct {
    gamepad_t last;
    uint8_t   held;          /* the directions repeating */
    uint32_t  next_ms;       /* when the held directions repeat next */
} gamepad_keys_t;

#define GP_REPEAT_FIRST_MS 400
#define GP_REPEAT_MS       100

void gamepad_keys_init(gamepad_keys_t *k);

/* Compare the state with the last: write the key codes (keycodes.h) pressed
   since into out[], up to max, and return how many. now_ms runs on. */
int gamepad_keys(gamepad_keys_t *k, const gamepad_t *now, uint32_t now_ms, uint8_t *out, int max);

#endif /* SHELL_GAMEPAD_H */
