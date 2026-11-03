// Integrazione qspi_rx + lfsr_check: flusso xorshift32 in piu' pacchetti,
// poi un byte corrotto e un pacchetto dispari, poi CTRL di reset.
`timescale 1ns/1ps
module link_test_tb;
    reg clk = 0, rst = 1; always #4.6 clk = ~clk;       // ~108 MHz
    reg sck = 0, csn = 1; reg [3:0] d = 0;
    wire bv, bf, pe, po; wire [7:0] bd;
    wire [31:0] nb, ne; wire [15:0] np; wire [7:0] no;
    qspi_rx rx(.clk(clk), .rst(rst), .qspi_sck(sck), .qspi_csn(csn), .qspi_d(d),
               .byte_valid(bv), .byte_data(bd), .byte_first(bf), .pkt_end(pe), .pkt_odd(po));
    lfsr_check chk(.clk(clk), .rst(rst), .byte_valid(bv), .byte_data(bd), .byte_first(bf),
                   .pkt_end(pe), .pkt_odd(po), .n_bytes(nb), .n_errors(ne), .n_pkts(np), .n_odd(no));

    integer HALF = 20;                                   // SCK ~25 MHz
    task nib(input [3:0] n); begin d = n; #(HALF) sck = 1; #(HALF) sck = 0; end endtask
    task sendb(input [7:0] b); begin nib(b[7:4]); nib(b[3:0]); end endtask
    task pstart; begin #50 csn = 0; #30; end endtask
    task pstop;  begin #30 csn = 1; #250; end endtask

    reg [31:0] x = 32'hC0FFEE01; integer errors = 0, i, k;
    task send_word; reg [31:0] y;
        begin
            sendb(x[31:24]); sendb(x[23:16]); sendb(x[15:8]); sendb(x[7:0]);
            y = x ^ (x << 13); y = y ^ (y >> 17); x = y ^ (y << 5);
        end
    endtask

    initial begin
        #200 rst = 0; #200;
        pstart; sendb(8'h80); sendb(8'h01); pstop;
        for (k = 0; k < 5; k = k + 1) begin
            pstart; sendb(8'h01); for (i = 0; i < 100; i = i + 1) send_word; pstop;
        end
        if (nb !== 2000 || ne !== 0 || np !== 5) begin errors = errors + 1; $display("ERR fase pulita: nb=%0d ne=%0d np=%0d", nb, ne, np); end
        // byte corrotto: un solo errore atteso
        pstart; sendb(8'h01); sendb(x[31:24] ^ 8'h10); sendb(x[23:16]); sendb(x[15:8]); sendb(x[7:0]); pstop;
        if (ne !== 1) begin errors = errors + 1; $display("ERR corrotto: ne=%0d (atteso 1)", ne); end
        // pacchetto dispari
        pstart; sendb(8'h01); nib(4'h5); pstop;
        if (no !== 1) begin errors = errors + 1; $display("ERR dispari: no=%0d", no); end
        // CTRL: azzera
        pstart; sendb(8'h80); sendb(8'h01); pstop;
        if (nb !== 0 || ne !== 0 || np !== 0 || no !== 0) begin errors = errors + 1; $display("ERR reset: %0d %0d %0d %0d", nb, ne, np, no); end
        if (errors == 0) $display("PASS link_test (qspi_rx + lfsr_check)"); else $display("FAIL link_test");
        $finish;
    end
endmodule
