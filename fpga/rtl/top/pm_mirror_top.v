// PicoCalc HDMI Mirror - top della fase 3: framebuffer in SDRAM su HDMI 720p
//
// PLL video (27 -> 371,25 / 74,25 / 123,75 MHz) + PLL di sistema (60,75 MHz e
// 180 gradi per la SDRAM), pm_mirror_core, uscita HDMI. I pin O_sdram_* /
// IO_sdram_dq sono i nomi che il compilatore Gowin collega alla SDRAM interna
// (non vanno vincolati a mano).
//
// LED (attivi bassi): 0 heartbeat 1 Hz, 1 entrambe le PLL agganciate,
// 2 SDRAM inizializzata, 3 attivita' QSPI (pixel scritti), 4 overflow della
// FIFO (sticky), 5 de visto. Seriale 115200: stesso report di linktest, con
// B = pixel scritti, E = pixel persi, P = pacchetti, O = pacchetti dispari.

`default_nettype none

module pm_mirror_top #(
    parameter integer FILT = 3
) (
    input  wire        sys_clk,        // 27 MHz
    input  wire        s1,             // non usato
    output wire [5:0]  led,
    output wire        uart_tx_pin,
    input  wire [3:0]  qspi_d,
    input  wire        qspi_sck,
    input  wire        qspi_csn,
    output wire        tmds_clk_p,
    output wire        tmds_clk_n,
    output wire [2:0]  tmds_d_p,
    output wire [2:0]  tmds_d_n,

    output wire        O_sdram_clk,
    output wire        O_sdram_cke,
    output wire        O_sdram_cs_n,
    output wire        O_sdram_cas_n,
    output wire        O_sdram_ras_n,
    output wire        O_sdram_wen_n,
    inout  wire [31:0] IO_sdram_dq,
    output wire [10:0] O_sdram_addr,
    output wire [1:0]  O_sdram_ba,
    output wire [3:0]  O_sdram_dqm
);

    wire clk_pix, clk_5x, clk_q, lock_v;
    j20k_pll_video u_pllv (
        .sys_clk(sys_clk), .clk_pix(clk_pix), .clk_5x(clk_5x), .clk_d3(clk_q), .locked(lock_v)
    );

    wire clk_sys, clk_sdram, lock_s;
    pm_pll_sdram u_plls (.clkin(sys_clk), .clk_sys(clk_sys), .clk_sdram(clk_sdram), .lock(lock_s));

    wire locks = lock_v & lock_s;

    // reset pixel (alto)
    reg [7:0] rstp_cnt = 8'd0;
    wire rst_pix = !rstp_cnt[7];
    always @(posedge clk_pix)
        if (!locks) rstp_cnt <= 8'd0;
        else if (!rstp_cnt[7]) rstp_cnt <= rstp_cnt + 8'd1;

    // reset QSPI (alto)
    reg [1:0] lq = 2'b00;
    reg [7:0] rstq_cnt = 8'd0;
    wire rst_q = !rstq_cnt[7];
    always @(posedge clk_q) begin
        lq <= {lq[0], locks};
        if (!lq[1]) rstq_cnt <= 8'd0;
        else if (!rstq_cnt[7]) rstq_cnt <= rstq_cnt + 8'd1;
    end

    // reset sistema (basso)
    reg [7:0] rst_sh = 8'h00;
    always @(posedge clk_sys) rst_sh <= {rst_sh[6:0], locks};
    wire rst_sys_n = rst_sh[7];

    wire [7:0] r, g, b; wire de, hs, vs;
    wire [31:0] n_pix, n_ovf; wire [15:0] n_pkts; wire [7:0] n_odd; wire sbusy;

    pm_mirror_core #(.FILT(FILT)) u_core (
        .clk_q(clk_q), .rst_q(rst_q),
        .clk_sys(clk_sys), .clk_sdram(clk_sdram), .rst_sys_n(rst_sys_n),
        .clk_pix(clk_pix), .rst_pix(rst_pix),
        .qspi_d(qspi_d), .qspi_sck(qspi_sck), .qspi_csn(qspi_csn),
        .rosso(r), .verde(g), .blu(b), .de(de), .hsync(hs), .vsync(vs),
        .SDRAM_DQ(IO_sdram_dq), .SDRAM_A(O_sdram_addr), .SDRAM_BA(O_sdram_ba),
        .SDRAM_nCS(O_sdram_cs_n), .SDRAM_nWE(O_sdram_wen_n), .SDRAM_nRAS(O_sdram_ras_n),
        .SDRAM_nCAS(O_sdram_cas_n), .SDRAM_CLK(O_sdram_clk), .SDRAM_CKE(O_sdram_cke),
        .SDRAM_DQM(O_sdram_dqm),
        .n_pix(n_pix), .n_ovf(n_ovf), .n_pkts(n_pkts), .n_odd(n_odd), .sdram_busy(sbusy)
    );

    j20k_hdmi u_hdmi (
        .clk_pix(clk_pix), .clk_5x(clk_5x), .rst_pix(rst_pix),
        .rosso(r), .verde(g), .blu(b), .hsync(hs), .vsync(vs), .de(de),
        .tmds_clk_p(tmds_clk_p), .tmds_clk_n(tmds_clk_n),
        .tmds_d_p(tmds_d_p), .tmds_d_n(tmds_d_n)
    );

    pm_report #(.CLK_HZ(123_750_000)) u_rep (
        .clk(clk_q), .rst_n(!rst_q), .n_bytes(n_pix), .n_errors(n_ovf),
        .n_pkts(n_pkts), .n_odd(n_odd), .tx(uart_tx_pin)
    );

    // ---- LED ----
    reg        hb_led = 1'b0;
    reg [26:0] hb = 27'd0;
    always @(posedge clk_pix)
        if (hb == 27'd37_124_999) begin hb <= 27'd0; hb_led <= ~hb_led; end
        else hb <= hb + 27'd1;

    reg de_visto = 1'b0;
    always @(posedge clk_pix) if (de) de_visto <= 1'b1;

    reg sdram_ok = 1'b0;                       // busy sceso almeno una volta dopo il reset
    always @(posedge clk_sys)
        if (!rst_sys_n) sdram_ok <= 1'b0;
        else if (!sbusy) sdram_ok <= 1'b1;

    reg [31:0] pix_q = 32'd0; reg [23:0] act = 24'd0;
    always @(posedge clk_q) begin
        pix_q <= n_pix;
        if (n_pix != pix_q) act <= 24'd12_375_000;
        else if (act != 0) act <= act - 24'd1;
    end
    reg ovf_seen = 1'b0;
    always @(posedge clk_q) if (n_ovf != 0) ovf_seen <= 1'b1;

    assign led = ~{de_visto, ovf_seen, (act != 0), sdram_ok, locks, hb_led};

endmodule

`default_nettype wire
