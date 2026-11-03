// qspi_rx con FILT=3: glitch di 4 ns su SCK (a basso e a alto) e su CS_N non
// devono produrre fronti in piu'. SCK = 5 MHz, sys_clk = 108 MHz circa.
`timescale 1ns/1ps
module qspi_glitch_tb;
    reg clk = 0, rst = 1;
    always #4.63 clk = ~clk;

    reg sck = 0, csn = 1; reg [3:0] d = 0;
    wire bv, bf, pe, po; wire [7:0] bd;
    qspi_rx #(.FILT(3)) dut(.clk(clk), .rst(rst), .qspi_sck(sck), .qspi_csn(csn), .qspi_d(d),
                .byte_valid(bv), .byte_data(bd), .byte_first(bf), .pkt_end(pe), .pkt_odd(po));

    integer errors = 0, rx_n = 0, npkt = 0, nodd = 0;
    reg [7:0] exp [0:1023]; integer exp_n = 0;
    always @(posedge clk) begin
        if (bv) begin
            if (rx_n >= exp_n || bd !== exp[rx_n]) begin errors = errors + 1; $display("ERR byte %0d got %h", rx_n, bd); end
            rx_n = rx_n + 1;
        end
        if (pe) begin npkt = npkt + 1; if (po) nodd = nodd + 1; end
    end

    localparam HALF = 100;               // 5 MHz
    task glitch_sck_hi; begin sck = 1; #4 sck = 0; end endtask   // glitch alto su SCK basso
    task glitch_sck_lo; begin sck = 0; #4 sck = 1; end endtask   // glitch basso su SCK alto
    task nib(input [3:0] n);
        begin
            d = n;
            #(HALF/4) glitch_sck_hi;     // ringing prima del fronte vero
            #(HALF/4);
            sck = 1; #(HALF/4) glitch_sck_lo; #(HALF/2);
            sck = 0; #(HALF/2);
        end
    endtask
    task sendb(input [7:0] b); begin exp[exp_n] = b; exp_n = exp_n + 1; nib(b[7:4]); nib(b[3:0]); end endtask

    integer i, p;
    initial begin
        #200 rst = 0; #200;
        for (p = 0; p < 3; p = p + 1) begin
            #50 csn = 0; #4 csn = 1; #4 csn = 0; #100;       // glitch su CS_N all'inizio
            exp[exp_n] = 8'h01; exp_n = exp_n + 1; nib(4'h0); nib(4'h1);
            for (i = 0; i < 40; i = i + 1) sendb(8'h10 + i * 7 + p);
            #100 csn = 1; #4 csn = 0; #4 csn = 1; #300;      // glitch su CS_N alla fine
        end
        #500;
        if (errors == 0 && rx_n == exp_n && npkt == 3 && nodd == 0)
            $display("PASS qspi_glitch: %0d byte, %0d pacchetti", rx_n, npkt);
        else
            $display("FAIL qspi_glitch: err=%0d rx=%0d/%0d pkt=%0d odd=%0d", errors, rx_n, exp_n, npkt, nodd);
        $finish;
    end
endmodule
