/* gamepad_test.c -- tries every key of a Bluetooth gamepad (the 8BitDo M30),
 * in three pages, and pairs it.
 *
 * Copy build/pico-w/gamepad-test.uf2 to /pico2-apps/, and
 * build/pico-w/cyw43fw/cyw43-fw.bin to /bluetooth/ on the card. Type
 * `gamepad-test`. Put the pad in pairing mode (the M30: hold Start and the
 * pad's pairing key until its light flashes; its manual has the combination
 * for the mode you want, D-input is the one with a hat and buttons), go to
 * page P and press s, then the number of the pad. The pairing is kept on the
 * card, in the gamepad's own place (btpair pairs it too), so a mouse and a pad
 * can be used together.
 *
 *   A  the numbers: the radio's state, the pad's name, the last raw report
 *      (hat, sticks, triggers, the button mask), the directions it makes, how many
 *      reports come a second.
 *   B  every key drawn: the four directions and 32 buttons light up while
 *      held, and a mark stays on each one that has been pressed, so that one
 *      pass over the pad shows what is missing. c clears the marks.
 *   P  pairing: s searches, 1-8 pairs the pad found, f forgets the pad.
 *
 * Tab goes to the next page; Esc, on either keyboard or on the pad (Fire 2
 * is Esc in the shell, but here the pad's Start and Select together leave),
 * returns to the shell. The buttons are numbered as the pad's report numbers
 * them; if the M30's are not where gamepad.h expects Fire and the others,
 * this page shows the numbers to change there. */

#include "pad_common.h"

#define TEXT_US 100000u

enum { PAGE_A, PAGE_B, PAGE_P, PAGES };
static int s_page = PAGE_A;

static uint32_t s_seen_buttons;     /* every button held since the last clear */
static uint8_t  s_seen_dirs;
static unsigned s_rate;

static void clear_seen(void) {
    s_seen_buttons = 0;
    s_seen_dirs = 0;
}

/* ---- page A -------------------------------------------------------------- */

static void page_a(const gamepad_t *g, const btkbd_pad_t *raw, bool seen) {
    struct mallinfo mi = mallinfo();
    put(0, "gamepad-test A numbers Tab page Esc exit");
    put(2, "Pad:   %s", pad_state_name(btkbd_device_state(BTKBD_GAMEPAD)));
    put(3, "       '%.28s'", btkbd_device_name(BTKBD_GAMEPAD));
    put(4, "Reports: %s, %u, %u a second", seen ? "a pad" : "none yet", s_pad_reports, s_rate);
    put(6, "hat    %d  (-1 neutral, 0 up, clockwise)", raw->hat);
    put(7, "L x %+4d y %+4d  R z %+4d rz %+4d", raw->x, raw->y, raw->z, raw->rz);
    put(8, "buttons 0x%08lX", (unsigned long)raw->buttons);
    put(10, "directions  %c %c %c %c  (U D L R)", g->dirs & GP_UP ? 'U' : '.', g->dirs & GP_DOWN ? 'D' : '.',
        g->dirs & GP_LEFT ? 'L' : '.', g->dirs & GP_RIGHT ? 'R' : '.');
    char list[COLS] = "";
    for (int i = 0; i < 32; i++)
        if (g->buttons & (1u << i)) {
            char n[6];
            snprintf(n, sizeof n, "%d ", i + 1);
            if (strlen(list) + strlen(n) < sizeof list) strcat(list, n);
        }
    put(11, "held: %s", list);
    put(13, "In the shell: button %d Enter, %d Esc,", GP_BTN_FIRE + 1, GP_BTN_FIRE2 + 1);
    put(14, "%d Tab, %d Enter.", GP_BTN_SELECT + 1, GP_BTN_START + 1);
    put(16, "rx %+4d ry %+4d", raw->rx, raw->ry);
    put(17, "triggers: brake %3u gas %3u", raw->brake, raw->gas);
    /* the other fields of the report: which page:usage each is, and held now */
    for (int i = 0; i < 4; i++) {
        unsigned pg, us, pg2, us2;
        char l[COLS] = "";
        if (btkbd_gamepad_extra(2 * i, &pg, &us)) {
            snprintf(l, sizeof l, "x%d%c %04X:%04X", 2 * i + 1, raw->extra >> (2 * i) & 1 ? '*' : ' ', pg, us);
            if (btkbd_gamepad_extra(2 * i + 1, &pg2, &us2))
                snprintf(l + strlen(l), sizeof l - strlen(l), "  x%d%c %04X:%04X", 2 * i + 2,
                         raw->extra >> (2 * i + 1) & 1 ? '*' : ' ', pg2, us2);
        }
        put(19 + i, "%s", l);
    }
    uint8_t rep[16];
    int rn = btkbd_gamepad_report(rep, 16);
    char hex[COLS] = "";
    for (int i = 0; i < rn && i < 8; i++) { char h[4]; snprintf(h, sizeof h, "%02X ", rep[i]); strcat(hex, h); }
    put(23, "report %2d bytes: %s", rn, hex);
    hex[0] = '\0';
    for (int i = 8; i < rn; i++) { char h[4]; snprintf(h, sizeof h, "%02X ", rep[i]); strcat(hex, h); }
    put(24, "                 %s", hex);
    put(27, "heap %d bytes taken", mi.uordblks);
    put(28, "The radio: %.28s", btkbd_status());
    flush();
}

/* ---- page B -------------------------------------------------------------- */

#define PAD_ROW 4      /* the direction cross */
#define BTN_ROW 12     /* the buttons, 8 rows of 4 */

static void cell(int row, int col, const char *s, bool held, bool seen) {
    char b[12];
    snprintf(b, sizeof b, "%c%s%c", seen ? '*' : ' ', s, seen ? '*' : ' ');
    put_at(row, col, held, b);
}

static void page_b(const gamepad_t *g) {
    put(0, "gamepad-test B keys  * = pressed once");
    put(1, "c clears the marks, Tab page");
    cell(PAD_ROW, 12, " UP ", g->dirs & GP_UP, s_seen_dirs & GP_UP);
    cell(PAD_ROW + 2, 5, " LEFT ", g->dirs & GP_LEFT, s_seen_dirs & GP_LEFT);
    cell(PAD_ROW + 2, 20, " RIGHT ", g->dirs & GP_RIGHT, s_seen_dirs & GP_RIGHT);
    cell(PAD_ROW + 4, 11, " DOWN ", g->dirs & GP_DOWN, s_seen_dirs & GP_DOWN);
    put(BTN_ROW - 1, "buttons, as the pad numbers them:");
    for (int i = 0; i < 32; i++) {
        char n[8];
        snprintf(n, sizeof n, " %2d ", i + 1);
        cell(BTN_ROW + i / 4, 2 + (i % 4) * 9, n, g->buttons & (1u << i), s_seen_buttons & (1u << i));
    }
    int nb = 0;
    for (int i = 0; i < 32; i++) nb += (s_seen_buttons >> i) & 1;
    int nd = ((s_seen_dirs & GP_UP) != 0) + ((s_seen_dirs & GP_DOWN) != 0) + ((s_seen_dirs & GP_LEFT) != 0) +
             ((s_seen_dirs & GP_RIGHT) != 0);
    put(21, "Directions %d of 4, buttons seen %d", nd, nb);
    put(22, "%s", nd == 4 && nb ? "Every direction has been tried." : "");
    put(30, "Start + Select (%d + %d) leave", GP_BTN_START + 1, GP_BTN_SELECT + 1);
    flush();
}

/* ---- page P: pairing ------------------------------------------------------ */

static void page_p(void) {
    put(0, "gamepad-test P pairing   Tab page");
    put(2, "s search, 1-8 pair that one, f forget");
    put(4, "Pad now: %s", pad_state_name(btkbd_device_state(BTKBD_GAMEPAD)));
    put(5, "         '%.28s'", btkbd_device_name(BTKBD_GAMEPAD));
    put(7, "Found:");
    int n = btkbd_found();
    for (int i = 0; i < 8; i++) {
        if (i < n)
            put(8 + i, "%d %c%c %.30s", i + 1, (btkbd_found_kind(i) == BTKBD_GAMEPAD) ? 'P' : ' ', btkbd_found_le(i) ? 'L' : ' ',
                btkbd_found_name(i));
        else
            put(8 + i, "");
    }
    put(17, "P: it says it is a gamepad, L: BLE.");
    put(18, "Put the pad in pairing mode first.");
    put(20, "%.38s", btkbd_status());
    flush();
}

/* ---- the pages ------------------------------------------------------------ */

static void draw(const gamepad_t *g, const btkbd_pad_t *raw, bool seen) {
    if (s_page == PAGE_A) page_a(g, raw, seen);
    else if (s_page == PAGE_B) page_b(g);
    else page_p();
}

static void enter(int page, const gamepad_t *g, const btkbd_pad_t *raw, bool seen) {
    s_page = page;
    lcd_mirror_resync();   /* an FPGA that joined late, or a page change: the HDMI starts clean */
    tw("\033[?25l\033[0m\033[2J\033[H");
    screen_repaint(&s_term);
    flush();
    draw(g, raw, seen);
}

int main(void) {
    pad_start("gamepad-test: a Bluetooth gamepad");
    say("Page P pairs the pad. Tab changes\nthe page.\n");
    sleep_ms(1500);

    gamepad_t g = { 0, 0 };
    btkbd_pad_t raw = { .hat = -1 };
    bool seen = false;
    enter(PAGE_A, &g, &raw, seen);

    uint64_t next_text = 0, next_rate = 0;
    unsigned rate_base = 0;
    for (;;) {
        uint64_t now = time_us_64();
        screen_tick(&s_term, now);
        btkbd_poll();

        gamepad_t was = g;
        seen = pad_state(&g, &raw);
        s_seen_buttons |= g.buttons;
        s_seen_dirs |= g.dirs;
        if (g.dirs != was.dirs || g.buttons != was.buttons) {
            printf("pad dirs %02X buttons %08lX (hat %d x %d y %d)\n", g.dirs, (unsigned long)g.buttons, raw.hat, raw.x, raw.y);
            if (s_page == PAGE_B) page_b(&g);
        }
        if ((g.buttons & (1u << GP_BTN_START)) && (g.buttons & (1u << GP_BTN_SELECT))) leave();

        if (now >= next_rate) {
            next_rate = now + 1000000u;
            s_rate = s_pad_reports - rate_base;
            rate_base = s_pad_reports;
        }
        if (s_page != PAGE_B && now >= next_text) {
            next_text = now + TEXT_US;
            draw(&g, &raw, seen);
        }

        int k;
        while ((k = pad_key()) != 0) {
            if (k == 0x1B) leave();
            if (k == 0x09) { enter((s_page + 1) % PAGES, &g, &raw, seen); continue; }
            if (s_page == PAGE_B && k == 'c') {
                clear_seen();
                page_b(&g);
            } else if (s_page == PAGE_P) {
                if (k == 's') btkbd_search();
                else if (k == 'f') btkbd_forget_device(BTKBD_GAMEPAD);
                else if (k >= '1' && k <= '8') btkbd_pair_as(k - '1', BTKBD_GAMEPAD);
                page_p();
            }
        }
    }
}
