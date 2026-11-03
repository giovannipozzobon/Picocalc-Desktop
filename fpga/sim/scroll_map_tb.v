// Testbench di scroll_map contro un modello di riferimento con l'operatore %.
`timescale 1ns/1ps
module scroll_map_tb;
    reg clk = 0; always #5 clk = ~clk;
    reg [9:0] v, tfa, vsam, vsp; wire [9:0] row;
    scroll_map dut(.clk(clk), .v(v), .tfa(tfa), .vsam(vsam), .vsp(vsp), .row(row));

    integer errors = 0, checks = 0;
    function integer ref_row(input integer v, input integer tfa, input integer vsam, input integer vsp);
        integer off;
        begin
            off = (vsp >= tfa && vsp < tfa + vsam) ? vsp - tfa : 0;
            if (v >= tfa && v < tfa + vsam) ref_row = tfa + ((v - tfa + off) % vsam);
            else                            ref_row = v;
        end
    endfunction

    task sweep(input integer t, input integer bfa, input integer p);
        integer i, vm, exp;
        begin
            vm = 480 - t - bfa;
            tfa = t; vsam = vm; vsp = p;
            for (i = 0; i < 320; i = i + 1) begin
                v = i; @(posedge clk); @(posedge clk); #1;
                exp = ref_row(i, t, vm, p); checks = checks + 1;
                if (row !== exp[9:0]) begin
                    errors = errors + 1;
                    if (errors < 10) $display("ERR tfa=%0d bfa=%0d vsp=%0d v=%0d: got %0d exp %0d", t, bfa, p, i, row, exp);
                end
            end
        end
    endtask

    integer s, t, b;
    initial begin
        // caso del terminale: TFA=BFA=0, scroll di 10 righe alla volta
        for (s = 0; s < 480; s = s + 10) sweep(0, 0, s);
        // con area fissa alta e bassa, offset dentro l'area scorrevole
        for (t = 0; t <= 40; t = t + 20)
            for (b = 0; b <= 40; b = b + 20)
                for (s = t; s < 480 - b; s = s + 37) sweep(t, b, s);
        // VSP invalido (dentro l'area fissa): offset 0
        sweep(30, 0, 5);
        // casi limite
        sweep(0, 0, 479); sweep(0, 0, 0);
        if (errors == 0) $display("PASS scroll_map: %0d confronti", checks);
        else             $display("FAIL scroll_map: %0d errori su %0d", errors, checks);
        $finish;
    end
endmodule
