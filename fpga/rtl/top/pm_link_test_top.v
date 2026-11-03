// PicoCalc HDMI Mirror - top della fase 2: test LFSR del collegamento QSPI
//
// LED (attivi bassi): 0 heartbeat 1 Hz, 1 attivita' (stira ~0,1 s ad ogni
// byte), 2 raggiunto 1 MiB di byte DATA, 3 PASS (>= 1 MiB e zero errori),
// 4 FAIL (almeno un errore o nibble dispari), 5 PLL agganciata.
// Seriale (USB-C, 115200): vedi pm_report.v.

`default_nettype none

module pm_link_test_top (
    input  wire       sys_clk,
    output wire [5:0] led,
    output wire       uart_tx_pin,
    input  wire [3:0] qspi_d,
    input  wire       qspi_sck,
    input  wire       qspi_csn
);

    wire clk, lock;
    pm_pll_sys u_pll (.clkin(sys_clk), .clk_sys(clk), .lock(lock));

    reg [7:0] rst_cnt = 8'd0;
    wire rst_n = rst_cnt[7];
    always @(posedge clk)
        if (!lock) rst_cnt <= 8'd0;
        else if (!rst_cnt[7]) rst_cnt <= rst_cnt + 8'd1;

    wire bv, bf, pe, po; wire [7:0] bd;
    qspi_rx #(.FILT(3)) u_rx (
        .clk(clk), .rst(!rst_n),
        .qspi_sck(qspi_sck), .qspi_csn(qspi_csn), .qspi_d(qspi_d),
        .byte_valid(bv), .byte_data(bd), .byte_first(bf), .pkt_end(pe), .pkt_odd(po)
    );

    wire [31:0] nb, ne; wire [15:0] np; wire [7:0] no;
    lfsr_check u_chk (
        .clk(clk), .rst(!rst_n),
        .byte_valid(bv), .byte_data(bd), .byte_first(bf), .pkt_end(pe), .pkt_odd(po),
        .n_bytes(nb), .n_errors(ne), .n_pkts(np), .n_odd(no)
    );

    pm_report #(.CLK_HZ(108_000_000)) u_rep (
        .clk(clk), .rst_n(rst_n), .n_bytes(nb), .n_errors(ne), .n_pkts(np), .n_odd(no), .tx(uart_tx_pin)
    );

    reg [26:0] hb = 27'd0; reg hb_led = 1'b0;
    always @(posedge clk)
        if (hb == 27'd53_999_999) begin hb <= 27'd0; hb_led <= ~hb_led; end
        else hb <= hb + 27'd1;

    reg [23:0] act = 24'd0;
    always @(posedge clk)
        if (bv) act <= 24'd10_800_000;
        else if (act != 0) act <= act - 24'd1;

    wire done = (nb >= 32'd1_048_576);
    wire bad  = (ne != 0) || (no != 0);

    assign led = {~lock, ~bad, ~(done && !bad), ~done, ~(act != 0), ~hb_led};

endmodule

`default_nettype wire
