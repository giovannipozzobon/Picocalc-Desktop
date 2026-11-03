// PicoCalc HDMI Mirror - verificatore del test LFSR del collegamento (fase 2)
//
// Il Pico manda, in pacchetti DATA (0x01), il flusso di byte di un xorshift32
// (x ^= x<<13; x ^= x>>17; x ^= x<<5), 4 byte per passo, big-endian, a partire
// da SEED. Il flusso e' continuo fra pacchetti. Un pacchetto CTRL (0x80) con
// byte 0x01 azzera verificatore e contatori, con byte 0x02 li congela (fine
// test: il traffico LCD normale, che e' anch'esso DATA, non li sporca piu').
// Pacchetti CMD sono ignorati.
//
// Contatori: byte DATA ricevuti, byte errati, pacchetti DATA, pacchetti con nibble
// dispari (errore di linea). Dopo un byte errato il generatore atteso resta
// agganciato al flusso (non si risincronizza): gli errori successivi contano
// come tali, quindi un solo byte perso si vede come raffica di errori.

`default_nettype none

module lfsr_check #(
    parameter [31:0] SEED = 32'hC0FFEE01
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        byte_valid,
    input  wire [7:0]  byte_data,
    input  wire        byte_first,
    input  wire        pkt_end,
    input  wire        pkt_odd,

    output reg  [31:0] n_bytes,
    output reg  [31:0] n_errors,
    output reg  [15:0] n_pkts,
    output reg  [7:0]  n_odd
);

    reg [7:0]  ptype;
    reg [31:0] x;
    reg [1:0]  idx;
    reg        frozen;

    wire [31:0] x1 = x ^ (x << 13);
    wire [31:0] x2 = x1 ^ (x1 >> 17);
    wire [31:0] x3 = x2 ^ (x2 << 5);

    reg [7:0] expected;
    always @* case (idx)
        2'd0: expected = x[31:24];
        2'd1: expected = x[23:16];
        2'd2: expected = x[15:8];
        default: expected = x[7:0];
    endcase

    always @(posedge clk) begin
        if (rst) begin
            ptype <= 8'hFF; x <= SEED; idx <= 2'd0; frozen <= 1'b0;
            n_bytes <= 32'd0; n_errors <= 32'd0; n_pkts <= 16'd0; n_odd <= 8'd0;
        end else begin
            if (byte_valid) begin
                if (byte_first) ptype <= byte_data;
                else if (ptype == 8'h80 && byte_data == 8'h02) frozen <= 1'b1;
                else if (ptype == 8'h80 && byte_data == 8'h01) begin
                    x <= SEED; idx <= 2'd0; frozen <= 1'b0;
                    n_bytes <= 32'd0; n_errors <= 32'd0; n_pkts <= 16'd0; n_odd <= 8'd0;
                end else if (ptype == 8'h01 && !frozen) begin
                    n_bytes <= n_bytes + 32'd1;
                    if (byte_data != expected) n_errors <= n_errors + 32'd1;
                    idx <= idx + 2'd1;
                    if (idx == 2'd3) x <= x3;
                end
            end
            if (pkt_end && ptype == 8'h01 && !frozen) begin      // solo pacchetti DATA
                n_pkts <= n_pkts + 16'd1;
                if (pkt_odd) n_odd <= n_odd + 8'd1;
            end
        end
    end

endmodule

`default_nettype wire
