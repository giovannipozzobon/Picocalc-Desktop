/* pad_game.c -- a pseudo sprite moved with a Bluetooth gamepad's D-pad, its
 * colour changed by the other buttons, and a bullet shot upward with Fire.
 *
 * Copy build/pico-w/pad-game.uf2 to /pico2-apps/, and have the pad paired
 * (gamepad-test's page P) and /bluetooth/cyw43-fw.bin on the card. Type
 * `pad-game`.
 *
 *   D-pad (or the stick)  moves the ship, 3 pixels a frame
 *   button 1 (A, Fire)    shoots a bullet up, and keeps shooting every 150 ms
 *                         while held; it flies away off the top and goes out
 *   buttons 2-8           the ship's colour (the bullets take it as they leave)
 *   Start + Select        back to the shell
 *
 * Without a pad, the arrow keys move the ship, Space shoots, 1-7 are the
 * colours, and Esc leaves, from either keyboard.
 *
 * The ship is a 16x16 bitmap drawn pixel by pixel: the panel has no
 * sprites, so each frame redraws only the rectangles that changed (the
 * ship's old and new place, each bullet's), computed from the picture the
 * game holds. It runs at about 60 frames a second. */

#include "pad_common.h"

#define FRAME_US    16000u
#define FIELD_TOP   (GLYPH_H)                  /* the top text row is the status */
#define FIELD_BOT   (PANEL_H - GLYPH_H)        /* the bottom one too */
#define SHIP_W      16
#define SHIP_H      16
#define SPEED       3
#define BULLET_W    3
#define BULLET_H    8
#define BULLET_SPD  6
#define BULLETS     8
#define AUTOFIRE_US 150000u

static const uint16_t s_ship[SHIP_H] = {
    0x0180, 0x0180, 0x03C0, 0x03C0, 0x07E0, 0x07E0, 0x0FF0, 0x1FF8,
    0x1FF8, 0x3FFC, 0x3FFC, 0x7FFE, 0x7E7E, 0x7C3E, 0x7818, 0x0000,
};

static const struct { const char *name; uint16_t rgb; } s_colours[] = {
    { "white", 0xFFFF }, { "red", 0xF800 },    { "green", 0x07E0 },  { "blue", 0x041F },
    { "yellow", 0xFFE0 }, { "magenta", 0xF81F }, { "cyan", 0x07FF }, { "orange", 0xFD20 },
};
#define N_COLOURS ((int)(sizeof s_colours / sizeof s_colours[0]))

static int s_x = (PANEL_W - SHIP_W) / 2, s_y = FIELD_BOT - SHIP_H - 10;
static int s_colour;
static struct { bool on; int x, y; uint16_t rgb; } s_bullets[BULLETS];
static unsigned s_shots;

static uint16_t pixel(int x, int y) {
    int sx = x - s_x, sy = y - s_y;
    if (sx >= 0 && sx < SHIP_W && sy >= 0 && sy < SHIP_H && (s_ship[sy] >> (SHIP_W - 1 - sx)) & 1)
        return s_colours[s_colour].rgb;
    for (int i = 0; i < BULLETS; i++) {
        if (!s_bullets[i].on) continue;
        int bx = x - s_bullets[i].x, by = y - s_bullets[i].y;
        if (bx >= 0 && bx < BULLET_W && by >= 0 && by < BULLET_H) return s_bullets[i].rgb;
    }
    /* a few fixed stars, so that the ship is seen to move over something */
    unsigned h = (unsigned)(x * 7 + y * 13);
    if (h % 89 == 0 && (x ^ y) % 3 == 0) return 0x4208;
    return 0x0000;
}

/* Paint a rectangle of the field. A blit must stay inside one text row's
 * band (the panel's frame memory wraps in those), so it goes in pieces. */
static void paint(int x, int y, int w, int h) {
    static uint16_t line[2][PANEL_W];
    if (x < 0) { w += x; x = 0; }
    if (y < FIELD_TOP) { h -= FIELD_TOP - y; y = FIELD_TOP; }
    if (x + w > PANEL_W) w = PANEL_W - x;
    if (y + h > FIELD_BOT) h = FIELD_BOT - y;
    if (w <= 0 || h <= 0) return;
    for (int y0 = y; y0 < y + h;) {
        int y1 = (y0 / GLYPH_H + 1) * GLYPH_H;
        if (y1 > y + h) y1 = y + h;
        lcd_blit_begin((unsigned)x, (unsigned)y0, (unsigned)w, (unsigned)(y1 - y0));
        for (int r = y0; r < y1; r++) {
            uint16_t *l = line[r & 1];
            for (int c = 0; c < w; c++) l[c] = pixel(x + c, r);
            lcd_blit_row(l, (unsigned)w);
        }
        lcd_blit_end();
        y0 = y1;
    }
}

static void status(const gamepad_t *g, bool seen) {
    put(0, "pad-game  Start+Select or Esc leave");
    int live = 0;
    for (int i = 0; i < BULLETS; i++) live += s_bullets[i].on;
    put(31, "%s %-7s shots %u in flight %d", seen ? "pad" : "---", s_colours[s_colour].name, s_shots, live);
    (void)g;
    flush();
}

static void shoot(void) {
    for (int i = 0; i < BULLETS; i++) {
        if (s_bullets[i].on) continue;
        s_bullets[i].on = true;
        s_bullets[i].x = s_x + SHIP_W / 2 - BULLET_W / 2;
        s_bullets[i].y = s_y - BULLET_H;
        s_bullets[i].rgb = s_colours[s_colour].rgb;
        s_shots++;
        paint(s_bullets[i].x, s_bullets[i].y, BULLET_W, BULLET_H);
        return;
    }
}

static void set_colour(int c) {
    if (c < 0 || c >= N_COLOURS || c == s_colour) return;
    s_colour = c;
    paint(s_x, s_y, SHIP_W, SHIP_H);
}

int main(void) {
    pad_start("pad-game: a ship and its bullets");
    say("Move with the D-pad, button 1 shoots,\nbuttons 2-8 change the colour.\n");
    sleep_ms(1500);

    lcd_mirror_resync();
    tw("\033[?25l\033[0m\033[2J\033[H");
    screen_repaint(&s_term);
    flush();
    paint(0, FIELD_TOP, PANEL_W, FIELD_BOT - FIELD_TOP);

    gamepad_t g = { 0, 0 };
    gamepad_t was = { 0, 0 };
    btkbd_pad_t raw = { -1, 0, 0, 0, 0 };
    bool seen = false;
    int key_dx = 0, key_dy = 0;          /* the arrow keys' nudge, for a try without a pad */
    uint64_t next_frame = time_us_64(), next_shot = 0;
    status(&g, seen);

    for (;;) {
        uint64_t now = time_us_64();
        screen_tick(&s_term, now);
        btkbd_poll();

        int k;
        while ((k = pad_key()) != 0) {
            if (k == 0x1B) leave();
            if (k == KEY_LEFT) key_dx -= 2 * SPEED;
            else if (k == KEY_RIGHT) key_dx += 2 * SPEED;
            else if (k == KEY_UP) key_dy -= 2 * SPEED;
            else if (k == KEY_DOWN) key_dy += 2 * SPEED;
            else if (k == ' ') shoot();
            else if (k >= '1' && k <= '7') set_colour(k - '1');
        }

        if (now < next_frame) continue;
        next_frame = now + FRAME_US;

        seen = pad_state(&g, &raw);
        if ((g.buttons & (1u << GP_BTN_START)) && (g.buttons & (1u << GP_BTN_SELECT))) leave();

        /* the colour: the highest of buttons 2-8 held, as it was pressed */
        uint32_t newly = g.buttons & ~was.buttons;
        for (int b = 1; b < N_COLOURS; b++)
            if (newly & (1u << b)) set_colour(b);
        /* fire: on the press, and every 150 ms while held */
        if (g.buttons & (1u << GP_BTN_FIRE)) {
            if (now >= next_shot) {
                shoot();
                next_shot = now + AUTOFIRE_US;
            }
        } else {
            next_shot = 0;
        }

        int dx = key_dx, dy = key_dy;
        key_dx = key_dy = 0;
        if (g.dirs & GP_LEFT) dx -= SPEED;
        if (g.dirs & GP_RIGHT) dx += SPEED;
        if (g.dirs & GP_UP) dy -= SPEED;
        if (g.dirs & GP_DOWN) dy += SPEED;
        int ox = s_x, oy = s_y;
        s_x += dx;
        s_y += dy;
        if (s_x < 0) s_x = 0;
        if (s_x > PANEL_W - SHIP_W) s_x = PANEL_W - SHIP_W;
        if (s_y < FIELD_TOP) s_y = FIELD_TOP;
        if (s_y > FIELD_BOT - SHIP_H) s_y = FIELD_BOT - SHIP_H;
        if (s_x != ox || s_y != oy) {
            /* one rectangle over both places */
            int x0 = ox < s_x ? ox : s_x, y0 = oy < s_y ? oy : s_y;
            int x1 = (ox > s_x ? ox : s_x) + SHIP_W, y1 = (oy > s_y ? oy : s_y) + SHIP_H;
            paint(x0, y0, x1 - x0, y1 - y0);
        }

        /* the bullets climb, and go out at the top */
        bool changed = false;
        for (int i = 0; i < BULLETS; i++) {
            if (!s_bullets[i].on) continue;
            int by = s_bullets[i].y;
            s_bullets[i].y -= BULLET_SPD;
            if (s_bullets[i].y + BULLET_H <= FIELD_TOP) {
                s_bullets[i].on = false;
                paint(s_bullets[i].x, by, BULLET_W, BULLET_H);
            } else {
                paint(s_bullets[i].x, s_bullets[i].y, BULLET_W, BULLET_H + BULLET_SPD);
            }
            changed = true;
        }
        if (changed || g.buttons != was.buttons || s_x != ox || s_y != oy) status(&g, seen);
        was = g;
    }
}
