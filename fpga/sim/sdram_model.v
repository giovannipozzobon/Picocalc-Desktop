// Modello comportamentale della SDRAM 32 bit del GW2AR-18 (solo simulazione).
// CAS latency 2, burst 1: il dato di un READ al fronte E0 compare sul bus dopo
// E1 ed e' campionato al fronte E2 (come fa j20k_sdram sul fronte di discesa
// di clk, che coincide col fronte di salita di SDRAM_CLK). Le scritture
// catturano dato e DQM al fronte del comando. Niente controlli di timing.
`timescale 1ns/1ps
module sdram_model (
    input  wire        clk,
    input  wire        cke, cs_n, ras_n, cas_n, we_n,
    input  wire [10:0] a,
    input  wire [1:0]  ba,
    input  wire [3:0]  dqm,
    inout  wire [31:0] dq
);
    reg [31:0] mem [0:2097151];
    reg [10:0] row [0:3];
    reg [3:0]  row_ok;
    integer i;
    initial begin
        for (i = 0; i < 2097152; i = i + 1) mem[i] = 32'h0;
        row_ok = 4'b0;
    end

    reg        rd1_v;  reg [20:0] rd1_a;
    reg [31:0] dq_o;   reg dq_oe = 0;
    assign dq = dq_oe ? dq_o : 32'bz;

    integer errs = 0;
    wire [2:0] cmd = {ras_n, cas_n, we_n};
    wire [20:0] caddr = {ba, row[ba], a[7:0]};

    always @(posedge clk) begin
        // stadio dati: il READ di E0 e' valido da E1
        dq_oe <= rd1_v;
        if (rd1_v) dq_o <= mem[rd1_a];
        rd1_v <= 1'b0;
        if (!cs_n) case (cmd)
            3'b011: begin row[ba] <= a; row_ok[ba] <= 1'b1; end          // ACTIVATE
            3'b010: begin if (a[10]) row_ok <= 4'b0; else row_ok[ba] <= 1'b0; end // PRECHARGE
            3'b101: begin                                                // READ
                if (!row_ok[ba]) begin errs = errs + 1; $display("%t SDRAM: READ su banco %0d chiuso", $time, ba); end
                rd1_v <= 1'b1; rd1_a <= caddr;
            end
            3'b100: begin                                                // WRITE
                if (!row_ok[ba]) begin errs = errs + 1; $display("%t SDRAM: WRITE su banco %0d chiuso", $time, ba); end
                if (!dqm[0]) mem[caddr][7:0]   <= dq[7:0];
                if (!dqm[1]) mem[caddr][15:8]  <= dq[15:8];
                if (!dqm[2]) mem[caddr][23:16] <= dq[23:16];
                if (!dqm[3]) mem[caddr][31:24] <= dq[31:24];
            end
            default: ;
        endcase
    end
endmodule
