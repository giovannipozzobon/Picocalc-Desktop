// PicoCalc HDMI Mirror - top della fase 1: barre di colore su HDMI
//
// MODE_720P = 1 : 1280x720@60, pixel 74,25 MHz, seriale 371,25 MHz
// MODE_720P = 0 : 640x480@60,  pixel 25,20 MHz, seriale 126,00 MHz
// I due wrapper pm_bars_720p / pm_bars_480p scelgono il modo per la sintesi.
//
// LED (attivi bassi): vedi in fondo al modulo. S1 non e' usato.

`default_nettype none

module pm_bars_top #(
    parameter MODE_720P = 1
) (
    input  wire       sys_clk,        // 27 MHz
    input  wire       s1,             // tasto, attivo basso
    output wire [5:0] led,
    output wire       tmds_clk_p,
    output wire       tmds_clk_n,
    output wire [2:0] tmds_d_p,
    output wire [2:0] tmds_d_n
);

    localparam integer H_ATT = MODE_720P ? 1280 : 640;
    localparam integer V_ATT = MODE_720P ? 720  : 480;
    localparam integer PIX_HZ = MODE_720P ? 74_250_000 : 25_200_000;

    wire clk_pix, clk_5x, locked;

    j20k_pll_video #(
        .IDIV_SEL (MODE_720P ? 3  : 2),
        .FBDIV_SEL(MODE_720P ? 54 : 13),
        .ODIV_SEL (MODE_720P ? 2  : 8)
    ) u_pll (
        .sys_clk(sys_clk), .clk_pix(clk_pix), .clk_5x(clk_5x), .locked(locked)
    );

    // reset nel dominio pixel (attivo ALTO): tenuto finche' la PLL non
    // aggancia, poi 128 cicli di margine (stesso schema di J20K, provato su
    // questa scheda). S1 NON partecipa: la sua polarita' non e' verificata e
    // un reset permanente darebbe uno schermo nero.
    reg [7:0] rstp_cnt = 8'd0;
    wire rst_pix = !rstp_cnt[7];
    always @(posedge clk_pix)
        if (!locked) rstp_cnt <= 8'd0;
        else if (!rstp_cnt[7]) rstp_cnt <= rstp_cnt + 8'd1;

    wire [10:0] x;
    wire [9:0]  y;
    wire        de, hsync, vsync, vblank_inizio, riga_inizio, quadro_inizio;

    j20k_vtiming #(
        .H_ATT(H_ATT), .V_ATT(V_ATT),
        .H_FP (MODE_720P ? 110 : 16),  .H_SY(MODE_720P ? 40 : 96),
        .H_BP (MODE_720P ? 220 : 48),
        .V_FP (MODE_720P ? 5   : 10),  .V_SY(MODE_720P ? 5  : 2),
        .V_BP (MODE_720P ? 20  : 33),
        .H_POS(MODE_720P ? 1'b1 : 1'b0),
        .V_POS(MODE_720P ? 1'b1 : 1'b0)
    ) u_tim (
        .clk_pix(clk_pix), .rst_pix(rst_pix),
        .x(x), .y(y), .de(de), .hsync(hsync), .vsync(vsync),
        .vblank_inizio(vblank_inizio), .riga_inizio(riga_inizio),
        .quadro_inizio(quadro_inizio)
    );

    reg [7:0] quadro = 8'd0;
    always @(posedge clk_pix)
        if (quadro_inizio) quadro <= quadro + 8'd1;

    wire [7:0] r, g, b;
    pm_bars #(.H_ATT(H_ATT), .V_ATT(V_ATT)) u_bars (
        .x(x), .y(y), .quadro(quadro), .rosso(r), .verde(g), .blu(b)
    );

    j20k_hdmi u_hdmi (
        .clk_pix(clk_pix), .clk_5x(clk_5x), .rst_pix(rst_pix),
        .rosso(r), .verde(g), .blu(b),
        .hsync(hsync), .vsync(vsync), .de(de),
        .tmds_clk_p(tmds_clk_p), .tmds_clk_n(tmds_clk_n),
        .tmds_d_p(tmds_d_p),     .tmds_d_n(tmds_d_n)
    );

    // heartbeat: 1 Hz dal clock pixel
    reg        hb_led = 1'b0;
    reg [26:0] hb = 27'd0;
    always @(posedge clk_pix)
        if (hb == PIX_HZ/2 - 1) begin hb <= 27'd0; hb_led <= ~hb_led; end
        else hb <= hb + 27'd1;

    // led[0] PLL agganciata, led[1] heartbeat 1 Hz, led[2] fuori dal reset,
    // led[3] de visto almeno una volta (il timing gira), led[5:4] spenti
    reg de_visto = 1'b0;
    always @(posedge clk_pix) if (de) de_visto <= 1'b1;
    assign led = {2'b11, ~de_visto, ~rst_pix, ~hb_led, ~locked};

endmodule

module pm_bars_720p (
    input  wire sys_clk, input wire s1, output wire [5:0] led,
    output wire tmds_clk_p, output wire tmds_clk_n,
    output wire [2:0] tmds_d_p, output wire [2:0] tmds_d_n
);
    pm_bars_top #(.MODE_720P(1)) u (.*);
endmodule

module pm_bars_480p (
    input  wire sys_clk, input wire s1, output wire [5:0] led,
    output wire tmds_clk_p, output wire tmds_clk_n,
    output wire [2:0] tmds_d_p, output wire [2:0] tmds_d_n
);
    pm_bars_top #(.MODE_720P(0)) u (.*);
endmodule

`default_nettype wire
