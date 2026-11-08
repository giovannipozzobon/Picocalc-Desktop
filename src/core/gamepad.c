/* gamepad.c -- a gamepad's state and its keys (gamepad.h). */
#include "gamepad.h"

#include "keycodes.h"

int gamepad_hat(int value, int logical_min)
{
    int i = value - logical_min;
    return i >= 0 && i <= 7 ? i : -1;
}

int gamepad_axis(int value, int logical_min, int bits)
{
    if (bits < 1 || bits > 16) bits = 8;
    int v;
    if (logical_min < 0) {			/* signed: centred on 0 */
        v = value;
        if (bits > 8) v >>= bits - 8;
        else if (bits < 8) v <<= 8 - bits;
    } else {				/* unsigned: centred on half the range */
        v = (int)(((int64_t)(value - logical_min) << 8 >> bits)) - 128;
    }
    return v < -128 ? -128 : v > 127 ? 127 : v;
}

void gamepad_set(gamepad_t *g, int hat, int x, int y, uint32_t buttons)
{
    static const uint8_t hat_dirs[8] = {
        GP_UP, GP_UP | GP_RIGHT, GP_RIGHT, GP_DOWN | GP_RIGHT,
        GP_DOWN, GP_DOWN | GP_LEFT, GP_LEFT, GP_UP | GP_LEFT,
    };
    uint8_t d = hat >= 0 && hat <= 7 ? hat_dirs[hat] : 0;
    if (x < -GP_STICK_ZONE) d |= GP_LEFT;
    if (x > GP_STICK_ZONE) d |= GP_RIGHT;
    if (y < -GP_STICK_ZONE) d |= GP_UP;
    if (y > GP_STICK_ZONE) d |= GP_DOWN;
    if ((d & (GP_LEFT | GP_RIGHT)) == (GP_LEFT | GP_RIGHT)) d &= (uint8_t)~(GP_LEFT | GP_RIGHT);	/* hat and stick disagree */
    if ((d & (GP_UP | GP_DOWN)) == (GP_UP | GP_DOWN)) d &= (uint8_t)~(GP_UP | GP_DOWN);
    g->dirs = d;
    g->buttons = buttons;
}

void gamepad_keys_init(gamepad_keys_t *k)
{
    k->last.dirs = 0;
    k->last.buttons = 0;
    k->held = 0;
    k->next_ms = 0;
}

static const struct { uint8_t bit, code; } dir_keys[4] = {
    { GP_UP, KEY_UP }, { GP_DOWN, KEY_DOWN }, { GP_LEFT, KEY_LEFT }, { GP_RIGHT, KEY_RIGHT },
};

int gamepad_keys(gamepad_keys_t *k, const gamepad_t *now, uint32_t now_ms, uint8_t *out, int max)
{
    int n = 0;
    uint8_t pressed = now->dirs & (uint8_t)~k->last.dirs;
    for (int i = 0; i < 4; i++)
        if ((pressed & dir_keys[i].bit) && n < max) out[n++] = dir_keys[i].code;
    if (pressed) {				/* a new direction restarts the repeat */
        k->held = now->dirs;
        k->next_ms = now_ms + GP_REPEAT_FIRST_MS;
    } else if (now->dirs && k->held) {
        k->held &= now->dirs;
        if (k->held && (int32_t)(now_ms - k->next_ms) >= 0) {
            for (int i = 0; i < 4; i++)
                if ((k->held & dir_keys[i].bit) && n < max) out[n++] = dir_keys[i].code;
            k->next_ms = now_ms + GP_REPEAT_MS;
        }
    } else {
        k->held = 0;
    }

    uint32_t b = now->buttons & ~k->last.buttons;
    if ((b & (1u << GP_BTN_FIRE)) && n < max) out[n++] = KEY_ENTER;
    if ((b & (1u << GP_BTN_FIRE2)) && n < max) out[n++] = KEY_ESC;
    if ((b & (1u << GP_BTN_SELECT)) && n < max) out[n++] = KEY_TAB;
    if ((b & (1u << GP_BTN_START)) && n < max) out[n++] = KEY_ENTER;
    k->last = *now;
    return n;
}
