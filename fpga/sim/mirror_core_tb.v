// Fase 3 in simulazione: pacchetti QSPI (CASET/RASET/RAMWR di un'immagine
// 320 x ROWS) -> decoder -> wr_fifo -> SDRAM (modello) -> lettore di righe ->
// buffer di riga -> uscita video 720p. Confronta ogni pixel di un quadro
// completo con quello atteso (scala 2x, finestra a x=320 y=40, nero fuori).
`timescale 1ns/1ps
module mirror_core_tb;
    parameter ROWS = 40;
    parameter HALF = 33;                       // mezzo periodo SCK: ~15 MHz

    reg clk_q = 0, clk_sys = 0, clk_pix = 0;
    always #4.040 clk_q   = ~clk_q;            // 123,75 MHz
    always #8.230 clk_sys = ~clk_sys;          // 60,75 MHz
    always #6.734 clk_pix = ~clk_pix;          // 74,25 MHz
    wire clk_sdram = ~clk_sys;

    reg rst_q = 1, rst_sys_n = 0, rst_pix = 1;
    reg sck = 0, csn = 1; reg [3:0] d = 0;

    wire [7:0] r, g, b; wire de, hs, vs;
    wire [31:0] dq; wire [10:0] sa; wire [1:0] sba; wire scs, swe, sras, scas, sclk, scke; wire [3:0] sdqm;
    wire [31:0] n_pix, n_ovf; wire [15:0] n_pkts; wire [7:0] n_odd; wire sbusy;

    pm_mirror_core #(.FILT(3)) dut (
        .clk_q(clk_q), .rst_q(rst_q), .clk_sys(clk_sys), .clk_sdram(clk_sdram),
        .rst_sys_n(rst_sys_n), .clk_pix(clk_pix), .rst_pix(rst_pix),
        .qspi_d(d), .qspi_sck(sck), .qspi_csn(csn),
        .rosso(r), .verde(g), .blu(b), .de(de), .hsync(hs), .vsync(vs),
        .SDRAM_DQ(dq), .SDRAM_A(sa), .SDRAM_BA(sba), .SDRAM_nCS(scs), .SDRAM_nWE(swe),
        .SDRAM_nRAS(sras), .SDRAM_nCAS(scas), .SDRAM_CLK(sclk), .SDRAM_CKE(scke), .SDRAM_DQM(sdqm),
        .n_pix(n_pix), .n_ovf(n_ovf), .n_pkts(n_pkts), .n_odd(n_odd), .sdram_busy(sbusy)
    );
    sdram_model mdl (.clk(sclk), .cke(scke), .cs_n(scs), .ras_n(sras), .cas_n(scas),
                     .we_n(swe), .a(sa), .ba(sba), .dqm(sdqm), .dq(dq));

    // ---- generatore di pacchetti ----
    task nib(input [3:0] n); begin d = n; #(HALF) sck = 1; #(HALF) sck = 0; end endtask
    task sendb(input [7:0] v); begin nib(v[7:4]); nib(v[3:0]); end endtask
    task pstart; begin #200 csn = 0; #60; end endtask
    task pstop;  begin #60 csn = 1; #300; end endtask
    task cmd(input [7:0] c); begin pstart; sendb(8'h00); sendb(c); pstop; end endtask

    function [15:0] pix(input integer x, input integer y);
        pix = (x * 131 + y * 251 + 16'h1234) & 16'hFFFF;
    endfunction

    integer x, y;
    reg wrote = 0;
    initial begin
        #1000 rst_q = 0; rst_pix = 0;
        #300 rst_sys_n = 1;
        #250000;                                   // init SDRAM: 200 us
        cmd(8'h21);                                // INVON, come lcd_init: il pannello lo vuole
        cmd(8'h29);                                // DISPON: dopo il reset l'uscita e' nera
        cmd(8'h2A); pstart; sendb(8'h01); sendb(0); sendb(0); sendb(8'h01); sendb(8'h3F); pstop;
        cmd(8'h2B); pstart; sendb(8'h01); sendb(0); sendb(0); sendb((ROWS-1) >> 8); sendb((ROWS-1) & 255); pstop;
        cmd(8'h2C);
        for (y = 0; y < ROWS; y = y + 1) begin
            pstart; sendb(8'h01);
            for (x = 0; x < 320; x = x + 1) begin sendb(pix(x, y) >> 8); sendb(pix(x, y) & 255); end
            pstop;
        end
        #20000 wrote = 1;
    end

    // ---- verifica: un quadro completo dopo la fine della scrittura ----
    reg vs_q = 0; integer frame = -1; integer ox = 0, oy = -1; reg de_q = 0;
    integer errors = 0, checked = 0;
    reg [7:0] er, eg, eb; reg [15:0] p;
    always @(posedge clk_pix) begin
        vs_q <= vs; de_q <= de;
        if (vs && !vs_q && wrote) frame = frame + 1;      // frame 0 = quello in cui finisce la scrittura
        if (de && !de_q) begin ox = 0; oy = oy + 1; end
        else if (de) ox = ox + 1;
        if (vs && !vs_q) oy = -1;
        if (de && frame == 1) begin
            if (ox >= 320 && ox < 960 && oy >= 40 && oy < 680 && ((oy - 40) / 2) < ROWS) begin
                p = pix((ox - 320) / 2, (oy - 40) / 2);
                er = {p[15:11], p[15:13]}; eg = {p[10:5], p[10:9]}; eb = {p[4:0], p[4:2]};
            end else begin er = 0; eg = 0; eb = 0; end
            checked = checked + 1;
            if ({r, g, b} !== {er, eg, eb}) begin
                errors = errors + 1;
                if (errors < 10) $display("ERR x=%0d y=%0d got %h%h%h exp %h%h%h", ox, oy, r, g, b, er, eg, eb);
            end
        end
        if (frame == 2) begin
            $display("pixel scritti=%0d persi=%0d pacchetti=%0d dispari=%0d sdram_errs=%0d", n_pix, n_ovf, n_pkts, n_odd, mdl.errs);
            if (errors == 0 && checked > 900000 && n_pix == 320*ROWS && n_ovf == 0 && mdl.errs == 0)
                $display("PASS mirror_core: %0d pixel verificati", checked);
            else
                $display("FAIL mirror_core: errori=%0d verificati=%0d", errors, checked);
            $finish;
        end
    end

    initial begin #200000000; $display("FAIL mirror_core: timeout"); $finish; end
endmodule
