/* test_gamepad.c -- a gamepad's state and its keys (gamepad.h). */

#include "gamepad.h"
#include "keycodes.h"
#include "test_util.h"

int main(void) {
    gamepad_t g;

    /* the hat, with either way of marking neutral */
    CHECK(gamepad_hat(0, 0) == 0 && gamepad_hat(7, 0) == 7 && gamepad_hat(8, 0) == -1, "hat 0..7, 8 neutral");
    CHECK(gamepad_hat(1, 1) == 0 && gamepad_hat(8, 1) == 7 && gamepad_hat(0, 1) == -1, "hat 1..8, 0 neutral");
    CHECK(gamepad_hat(15, 0) == -1, "hat out of range is neutral");

    /* axes */
    CHECK(gamepad_axis(0, 0, 8) == -128 && gamepad_axis(255, 0, 8) == 127, "unsigned 8 bits spans the range");
    CHECK(gamepad_axis(128, 0, 8) == 0, "unsigned 8 bits is centred");
    CHECK(gamepad_axis(-127, -127, 8) == -127 && gamepad_axis(100, -127, 8) == 100, "signed 8 bits as it is");
    CHECK(gamepad_axis(32768, 0, 16) == 0, "unsigned 16 bits is centred");
    CHECK(gamepad_axis(65535, 0, 16) == 127 && gamepad_axis(0, 0, 16) == -128, "unsigned 16 bits spans the range");
    CHECK(gamepad_axis(-32768, -32768, 16) == -128, "signed 16 bits");

    /* directions from a hat */
    gamepad_set(&g, 0, 0, 0, 0);
    CHECK(g.dirs == GP_UP, "hat up");
    gamepad_set(&g, 3, 0, 0, 0);
    CHECK(g.dirs == (GP_DOWN | GP_RIGHT), "hat down-right");
    gamepad_set(&g, 6, 0, 0, 0);
    CHECK(g.dirs == GP_LEFT, "hat left");
    gamepad_set(&g, -1, 0, 0, 0);
    CHECK(g.dirs == 0, "hat neutral");

    /* ... and from a stick, with a dead zone */
    gamepad_set(&g, -1, 60, -60, 0);
    CHECK(g.dirs == 0, "a stick inside the zone");
    gamepad_set(&g, -1, 100, -100, 0);
    CHECK(g.dirs == (GP_RIGHT | GP_UP), "a stick right and up (y negative is up)");
    gamepad_set(&g, 6, 100, 0, 0);
    CHECK(!(g.dirs & (GP_LEFT | GP_RIGHT)), "hat left and stick right cancel");

    /* buttons */
    gamepad_set(&g, -1, 0, 0, 0x0805);
    CHECK(g.buttons == 0x0805, "buttons kept");

    gamepad_set(&g, -1, 0, 0, 0x80010001u);
    CHECK(g.buttons == 0x80010001u, "extra buttons 17-32 kept");

    /* keys */
    gamepad_keys_t k;
    uint8_t out[8];
    gamepad_keys_init(&k);
    gamepad_set(&g, 0, 0, 0, 0);
    CHECK(gamepad_keys(&k, &g, 1000, out, 8) == 1 && out[0] == KEY_UP, "up presses Up once");
    CHECK(gamepad_keys(&k, &g, 1100, out, 8) == 0, "held: no repeat yet");
    CHECK(gamepad_keys(&k, &g, 1399, out, 8) == 0, "still waiting for the first repeat");
    CHECK(gamepad_keys(&k, &g, 1400, out, 8) == 1 && out[0] == KEY_UP, "first repeat after 400 ms");
    CHECK(gamepad_keys(&k, &g, 1450, out, 8) == 0, "then every 100 ms");
    CHECK(gamepad_keys(&k, &g, 1500, out, 8) == 1, "the next one");
    gamepad_set(&g, -1, 0, 0, 0);
    CHECK(gamepad_keys(&k, &g, 1510, out, 8) == 0, "let go");
    gamepad_set(&g, 2, 0, 0, 0);
    CHECK(gamepad_keys(&k, &g, 1520, out, 8) == 1 && out[0] == KEY_RIGHT, "right presses Right");
    gamepad_set(&g, 1, 0, 0, 0);
    CHECK(gamepad_keys(&k, &g, 1530, out, 8) == 1 && out[0] == KEY_UP, "up-right: only the new direction presses");

    gamepad_set(&g, -1, 0, 0, 1u << GP_BTN_FIRE);
    CHECK(gamepad_keys(&k, &g, 2000, out, 8) == 1 && out[0] == KEY_ENTER, "fire is Enter");
    CHECK(gamepad_keys(&k, &g, 2100, out, 8) == 0, "buttons do not repeat");
    gamepad_set(&g, -1, 0, 0, (1u << GP_BTN_FIRE) | (1u << GP_BTN_FIRE2));
    CHECK(gamepad_keys(&k, &g, 2200, out, 8) == 1 && out[0] == KEY_ESC, "fire 2 is Esc");
    gamepad_set(&g, 0, 0, 0, 1u << GP_BTN_START);
    CHECK(gamepad_keys(&k, &g, 2300, out, 2) == 2 && out[0] == KEY_UP && out[1] == KEY_ENTER, "a direction and Start together");

    /* the clock wraps */
    gamepad_keys_init(&k);
    gamepad_set(&g, 0, 0, 0, 0);
    gamepad_keys(&k, &g, 0xFFFFFF00u, out, 8);
    CHECK(gamepad_keys(&k, &g, 0xFFFFFF00u + 400, out, 8) == 1, "repeat across the clock's wrap");

    TEST_DONE();
}
