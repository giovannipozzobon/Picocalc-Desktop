// PicoCalc HDMI Mirror - nucleo della fase 3: QSPI -> decoder -> SDRAM -> video
//
// Tre domini di clock, senza PLL ne' IO (sta tutto in pm_mirror_top, qui si
// puo' simulare):
//   clk_q    123,75 MHz  qspi_rx, cmd_decoder, scrittura in wr_fifo
//   clk_sys   60,75 MHz  wr_fifo (lettura), controller SDRAM, fb_write, fb_read
//   clk_pix   74,25 MHz  j20k_vtiming, mirror_video, buffer di riga (lettura)
// I passaggi fra domini: wr_fifo (asincrona), show_gray pixel -> sys (Gray),
// tfa/vsam/vsp e inv/disp quasi statici con due flip-flop (possono tearare per
// un quadro durante uno scroll: accettato in fase 3).

`default_nettype none

module pm_mirror_core #(
    parameter integer FILT = 3
) (
    input  wire        clk_q,
    input  wire        rst_q,          // attivo alto
    input  wire        clk_sys,
    input  wire        clk_sdram,      // clk_sys sfasato di 180 gradi
    input  wire        rst_sys_n,      // attivo basso
    input  wire        clk_pix,
    input  wire        rst_pix,        // attivo alto

    input  wire [3:0]  qspi_d,
    input  wire        qspi_sck,
    input  wire        qspi_csn,

    output wire [7:0]  rosso,
    output wire [7:0]  verde,
    output wire [7:0]  blu,
    output wire        de,
    output wire        hsync,
    output wire        vsync,

    inout  wire [31:0] SDRAM_DQ,
    output wire [10:0] SDRAM_A,
    output wire [1:0]  SDRAM_BA,
    output wire        SDRAM_nCS,
    output wire        SDRAM_nWE,
    output wire        SDRAM_nRAS,
    output wire        SDRAM_nCAS,
    output wire        SDRAM_CLK,
    output wire        SDRAM_CKE,
    output wire [3:0]  SDRAM_DQM,

    // diagnostica (dominio clk_q, tranne sdram_busy / video_de)
    output reg  [31:0] n_pix,          // pixel scritti
    output reg  [31:0] n_ovf,          // pixel persi per FIFO piena
    output reg  [15:0] n_pkts,
    output reg  [7:0]  n_odd,
    output wire        sdram_busy
);

    // ---------------------------------------------------------------- QSPI
    wire bv, bf, pe, po; wire [7:0] bd;
    qspi_rx #(.FILT(FILT)) u_rx (
        .clk(clk_q), .rst(rst_q),
        .qspi_sck(qspi_sck), .qspi_csn(qspi_csn), .qspi_d(qspi_d),
        .byte_valid(bv), .byte_data(bd), .byte_first(bf), .pkt_end(pe), .pkt_odd(po)
    );

    wire        w_valid; wire [8:0] w_x, w_y; wire [15:0] w_data;
    wire [9:0]  tfa, vsam, vsp; wire [7:0] madctl; wire inv_on, disp_on, resync;
    cmd_decoder u_dec (
        .clk(clk_q), .rst(rst_q),
        .byte_valid(bv), .byte_data(bd), .byte_first(bf), .pkt_end(pe),
        .wr_valid(w_valid), .wr_x(w_x), .wr_y(w_y), .wr_data(w_data),
        .tfa(tfa), .vsam(vsam), .vsp(vsp), .madctl(madctl),
        .inv_on(inv_on), .disp_on(disp_on), .resync_pulse(resync)
    );

    // indirizzo di word: riga * 160 + x / 2
    reg        f_we;
    reg [33:0] f_wdata;
    wire [16:0] wa = ({8'd0, w_y} << 7) + ({8'd0, w_y} << 5) + {9'd0, w_x[8:1]};
    always @(posedge clk_q) begin
        f_we    <= w_valid;
        f_wdata <= {w_x[0], w_data, wa};
    end

    wire f_ovf;
    wire        f_empty, f_re;
    wire [33:0] f_rdata;
    wr_fifo #(.W(34), .AW(6)) u_fifo (
        .wclk(clk_q), .wrst(rst_q), .we(f_we), .wdata(f_wdata), .ovf(f_ovf),
        .rclk(clk_sys), .rrst(!rst_sys_n), .re(f_re), .rdata(f_rdata), .empty(f_empty)
    );

    always @(posedge clk_q) begin
        if (rst_q) begin
            n_pix <= 32'd0; n_ovf <= 32'd0; n_pkts <= 16'd0; n_odd <= 8'd0;
        end else begin
            if (f_we)  n_pix <= n_pix + 32'd1;
            if (f_ovf) n_ovf <= n_ovf + 32'd1;
            if (pe)  begin n_pkts <= n_pkts + 16'd1; if (po) n_odd <= n_odd + 8'd1; end
        end
    end

    // ---------------------------------------------------------------- SDRAM
    wire        c_req, c_we, c_acc; wire [22:0] c_addr; wire [31:0] c_wdata; wire [3:0] c_ben;
    wire        d_req, d_acc, d_valid, d_done; wire [22:0] d_addr; wire [31:0] d_rdata, d_rdata_t;
    wire [31:0] c_rdata; wire c_ack, c_dabuf;

    fb_write u_fbw (
        .clk(clk_sys), .rst(!rst_sys_n),
        .f_empty(f_empty), .f_rdata(f_rdata), .f_re(f_re),
        .cpu_req(c_req), .cpu_we(c_we), .cpu_addr(c_addr), .cpu_wdata(c_wdata),
        .cpu_ben(c_ben), .cpu_acc(c_acc)
    );

    j20k_sdram #(.FREQ(60_750_000), .BURST(8)) u_sdram (
        .clk(clk_sys), .clk_sdram(clk_sdram), .rst_n(rst_sys_n),
        .cpu_req(c_req), .cpu_we(c_we), .cpu_addr(c_addr), .cpu_wdata(c_wdata),
        .cpu_ben(c_ben), .cpu_rdata(c_rdata), .cpu_acc(c_acc), .cpu_ack(c_ack),
        .cpu_da_buf(c_dabuf),
        .dma_req(d_req), .dma_addr(d_addr), .dma_rdata(d_rdata),
        .dma_rdata_tardi(d_rdata_t), .dma_acc(d_acc), .dma_valid(d_valid),
        .dma_done(d_done),
        .blt_req(1'b0), .blt_we(1'b0), .blt_addr(23'd0), .blt_wdata(32'd0),
        .blt_ben(4'd0), .blt_rdata(), .blt_acc(), .blt_ack(),
        .busy(sdram_busy),
        .SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_BA(SDRAM_BA),
        .SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE), .SDRAM_nRAS(SDRAM_nRAS),
        .SDRAM_nCAS(SDRAM_nCAS), .SDRAM_CLK(SDRAM_CLK), .SDRAM_CKE(SDRAM_CKE),
        .SDRAM_DQM(SDRAM_DQM)
    );

    // ------------------------------------------------- lato video e righe
    wire [8:0] show_gray;
    wire       lb_we; wire [8:0] lb_waddr; wire [31:0] lb_wdata;
    wire [8:0] lb_raddr; wire [31:0] lb_rdata;

    fb_read u_fbr (
        .clk(clk_sys), .rst(!rst_sys_n),
        .show_gray(show_gray), .tfa(tfa), .vsam(vsam), .vsp(vsp),
        .dma_req(d_req), .dma_addr(d_addr), .dma_acc(d_acc), .dma_valid(d_valid),
        .dma_rdata(d_rdata),
        .lb_we(lb_we), .lb_waddr(lb_waddr), .lb_wdata(lb_wdata)
    );

    line_buffer u_lb (
        .wclk(clk_sys), .we(lb_we), .waddr(lb_waddr), .wdata(lb_wdata),
        .rclk(clk_pix), .raddr(lb_raddr), .rdata(lb_rdata)
    );

    wire [10:0] vx; wire [9:0] vy; wire v_de, v_hs, v_vs, v_vbl, v_ri, v_qi;
    j20k_vtiming u_tim (
        .clk_pix(clk_pix), .rst_pix(rst_pix),
        .x(vx), .y(vy), .de(v_de), .hsync(v_hs), .vsync(v_vs),
        .vblank_inizio(v_vbl), .riga_inizio(v_ri), .quadro_inizio(v_qi)
    );

    mirror_video u_vid (
        .clk_pix(clk_pix), .x(vx), .y(vy), .de(v_de), .hsync(v_hs), .vsync(v_vs),
        .inv_on(inv_on), .disp_on(disp_on),
        .show_gray(show_gray), .lb_raddr(lb_raddr), .lb_rdata(lb_rdata),
        .rosso(rosso), .verde(verde), .blu(blu),
        .de_o(de), .hsync_o(hsync), .vsync_o(vsync)
    );

endmodule

`default_nettype wire
