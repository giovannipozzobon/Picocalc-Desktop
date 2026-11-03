// PicoCalc HDMI Mirror - scrittore del framebuffer (dominio clk_sys)
//
// Svuota wr_fifo e scrive un pixel per volta nella porta CPU di j20k_sdram.
// Il pixel sta in meta' della word da 32 bit: wa = indice di word
// (riga * 160 + x/2), half = x[0]; la maschera ben sceglie la meta'.
// Il controller aggancia indirizzo e dato quando accetta (cpu_acc): subito
// dopo si presenta la richiesta successiva, mentre lui finisce la scrittura.
//
// Dato in FIFO: {half, data[15:0], wa[16:0]}.

`default_nettype none

module fb_write (
    input  wire        clk,
    input  wire        rst,

    input  wire        f_empty,
    input  wire [33:0] f_rdata,
    output reg         f_re,

    output reg         cpu_req,
    output wire        cpu_we,
    output reg  [22:0] cpu_addr,
    output reg  [31:0] cpu_wdata,
    output reg  [3:0]  cpu_ben,
    input  wire        cpu_acc
);

    assign cpu_we = 1'b1;

    wire        h  = f_rdata[33];
    wire [15:0] d  = f_rdata[32:17];
    wire [16:0] wa = f_rdata[16:0];

    task load; begin
        cpu_addr  <= {4'b0, wa, 2'b00};
        cpu_wdata <= {d, d};
        cpu_ben   <= h ? 4'b1100 : 4'b0011;
        f_re      <= 1'b1;
    end endtask

    always @(posedge clk) begin
        f_re <= 1'b0;
        if (rst) begin
            cpu_req <= 1'b0;
        end else if (!cpu_req) begin
            if (!f_empty && !f_re) begin load; cpu_req <= 1'b1; end
        end else if (cpu_acc) begin
            if (!f_empty && !f_re) load;       // la richiesta resta alta col dato nuovo
            else cpu_req <= 1'b0;
        end
    end

endmodule

`default_nettype wire
