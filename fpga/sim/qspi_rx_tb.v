// Testbench di qspi_rx: pacchetti CMD/DATA/CTRL, velocita' SCK = clk/4 e
// clk/8, pacchetto con nibble dispari, due pacchetti ravvicinati.
`timescale 1ns/1ps
module qspi_rx_tb;
    reg clk = 0, rst = 1;
    always #5 clk = ~clk;                 // 100 MHz

    reg sck = 0, csn = 1; reg [3:0] d = 0;
    wire bv, bf, pe, po; wire [7:0] bd;
    qspi_rx dut(.clk(clk), .rst(rst), .qspi_sck(sck), .qspi_csn(csn), .qspi_d(d),
                .byte_valid(bv), .byte_data(bd), .byte_first(bf), .pkt_end(pe), .pkt_odd(po));

    integer errors = 0, nbytes = 0, npkt = 0, nodd = 0;
    reg [7:0] exp [0:4095]; reg expf [0:4095];
    integer exp_n = 0, rx_n = 0;

    always @(posedge clk) begin
        if (bv) begin
            if (rx_n >= exp_n) begin errors = errors + 1; $display("byte in piu' %h", bd); end
            else begin
                if (bd !== exp[rx_n] || bf !== expf[rx_n]) begin
                    errors = errors + 1;
                    $display("ERR byte %0d: got %h/%b exp %h/%b", rx_n, bd, bf, exp[rx_n], expf[rx_n]);
                end
            end
            rx_n = rx_n + 1;
        end
        if (pe) begin npkt = npkt + 1; if (po) nodd = nodd + 1; end
    end

    integer HALF;                         // mezzo periodo SCK in ns
    task nib(input [3:0] n);              // un ciclo SCK: dati sul fronte di discesa
        begin
            d = n;                        // SCK e' basso: dati stabili prima della salita
            #(HALF) sck = 1;
            #(HALF) sck = 0;
        end
    endtask
    task pkt_start; begin #50 csn = 0; #30; end endtask
    task pkt_stop;  begin #30 csn = 1; #250; end endtask
    task sendb(input [7:0] b, input first);
        begin
            exp[exp_n] = b; expf[exp_n] = first; exp_n = exp_n + 1;
            nib(b[7:4]); nib(b[3:0]);
        end
    endtask

    integer i, k; reg [7:0] v;
    initial begin
        #100 rst = 0; #100;
        for (k = 0; k < 2; k = k + 1) begin
            HALF = (k == 0) ? 20 : 40;    // SCK = 25 MHz, poi 12,5 MHz
            // CMD: CASET
            pkt_start; sendb(8'h00, 1); sendb(8'h2A, 0); pkt_stop;
            // DATA 4 byte
            pkt_start; sendb(8'h01, 1); sendb(8'h00, 0); sendb(8'h10, 0); sendb(8'h01, 0); sendb(8'h3F, 0); pkt_stop;
            // DATA lungo, pixel pseudo-casuali
            pkt_start; sendb(8'h01, 1); v = 8'hA5;
            for (i = 0; i < 300; i = i + 1) begin v = {v[6:0], v[7]^v[5]^v[4]^v[3]}; sendb(v, 0); end
            pkt_stop;
            // CTRL
            pkt_start; sendb(8'h80, 1); sendb(8'h01, 0); pkt_stop;
        end
        // pacchetto con nibble dispari: solo tipo + mezzo byte
        HALF = 20;
        pkt_start; sendb(8'h01, 1); nib(4'h7); pkt_stop;
        // due pacchetti ravvicinati (CS_N alto solo 200 ns)
        pkt_start; sendb(8'h00, 1); sendb(8'h2C, 0); #30 csn = 1; #200;
        pkt_start; sendb(8'h01, 1); sendb(8'hFF, 0); pkt_stop;
        #200;
        if (rx_n !== exp_n) begin errors = errors + 1; $display("byte ricevuti %0d attesi %0d", rx_n, exp_n); end
        if (npkt !== 11) begin errors = errors + 1; $display("pacchetti %0d attesi 11", npkt); end
        if (nodd !== 1)  begin errors = errors + 1; $display("dispari %0d attesi 1", nodd); end
        if (errors == 0) $display("PASS qspi_rx: %0d byte, %0d pacchetti", rx_n, npkt);
        else             $display("FAIL qspi_rx: %0d errori", errors);
        $finish;
    end
endmodule
