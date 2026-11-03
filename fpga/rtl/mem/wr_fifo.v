// PicoCalc HDMI Mirror - FIFO asincrona delle scritture di pixel
//
// Porta le scritture del dominio QSPI (clk_q) a quello della SDRAM (clk_sys).
// Puntatori in codice Gray, due flip-flop di sincronizzazione per lato. In
// lettura e' "show-ahead": rdata e' gia' valido quando empty = 0, re scarta.
// Se e' piena la scrittura e' persa e ovf fa un impulso (nel dominio wclk).

`default_nettype none

module wr_fifo #(
    parameter integer W  = 34,
    parameter integer AW = 6              // profondita' 2^AW
) (
    input  wire         wclk,
    input  wire         wrst,             // attivo alto, sincrono a wclk
    input  wire         we,
    input  wire [W-1:0] wdata,
    output reg          ovf,

    input  wire         rclk,
    input  wire         rrst,             // attivo alto, sincrono a rclk
    input  wire         re,
    output wire [W-1:0] rdata,
    output wire         empty
);

    reg [W-1:0] mem [0:(1<<AW)-1];

    reg [AW:0] wbin, wgray, rbin, rgray;
    reg [AW:0] rgray_w1, rgray_w2;        // rgray visto da wclk
    reg [AW:0] wgray_r1, wgray_r2;        // wgray visto da rclk

    wire [AW:0] wbin_n  = wbin + 1'b1;
    wire [AW:0] wgray_n = (wbin_n >> 1) ^ wbin_n;
    wire full = (wgray_n == {~rgray_w2[AW:AW-1], rgray_w2[AW-2:0]});

    always @(posedge wclk) begin
        ovf <= 1'b0;
        if (wrst) begin
            wbin <= 0; wgray <= 0; rgray_w1 <= 0; rgray_w2 <= 0;
        end else begin
            rgray_w1 <= rgray; rgray_w2 <= rgray_w1;
            if (we) begin
                if (full) ovf <= 1'b1;
                else begin
                    mem[wbin[AW-1:0]] <= wdata;
                    wbin  <= wbin_n;
                    wgray <= wgray_n;
                end
            end
        end
    end

    wire [AW:0] rbin_n  = rbin + 1'b1;
    wire [AW:0] rgray_n = (rbin_n >> 1) ^ rbin_n;
    assign empty = (rgray == wgray_r2);
    assign rdata = mem[rbin[AW-1:0]];

    always @(posedge rclk) begin
        if (rrst) begin
            rbin <= 0; rgray <= 0; wgray_r1 <= 0; wgray_r2 <= 0;
        end else begin
            wgray_r1 <= wgray; wgray_r2 <= wgray_r1;
            if (re && !empty) begin
                rbin  <= rbin_n;
                rgray <= rgray_n;
            end
        end
    end

endmodule

`default_nettype wire
