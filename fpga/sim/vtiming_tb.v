// Testbench del timing video: conta pixel/riga, righe/quadro, pixel attivi e
// polarita' dei sync, per entrambi i modi.
`timescale 1ns/1ps
module vtiming_tb;
    reg clk = 0, rst = 1;
    always #5 clk = ~clk;
    // 720p
    wire [10:0] x1; wire [9:0] y1; wire de1, hs1, vs1, vb1, ri1, qi1;
    j20k_vtiming u720(.clk_pix(clk), .rst_pix(rst), .x(x1), .y(y1), .de(de1), .hsync(hs1), .vsync(vs1),
                      .vblank_inizio(vb1), .riga_inizio(ri1), .quadro_inizio(qi1));
    // 480p, sync negativi
    wire [10:0] x2; wire [9:0] y2; wire de2, hs2, vs2, vb2, ri2, qi2;
    j20k_vtiming #(.H_ATT(640),.H_FP(16),.H_SY(96),.H_BP(48),.V_ATT(480),.V_FP(10),.V_SY(2),.V_BP(33),
                   .H_POS(1'b0),.V_POS(1'b0))
                 u480(.clk_pix(clk), .rst_pix(rst), .x(x2), .y(y2), .de(de2), .hsync(hs2), .vsync(vs2),
                      .vblank_inizio(vb2), .riga_inizio(ri2), .quadro_inizio(qi2));

    integer c1=0, c2=0, de_c1=0, de_c2=0, hs_c1=0, hs_c2=0, vs_c1=0, vs_c2=0, f1=0, f2=0, errors=0;
    integer tot_c1=0, tot_c2=0;
    always @(posedge clk) if (!rst) begin
        tot_c1 = tot_c1 + 1; tot_c2 = tot_c2 + 1;
        if (qi1) begin
            if (f1 == 1) begin
                if (tot_c1 !== 1650*750) begin errors=errors+1; $display("720p: %0d clock/quadro", tot_c1); end
                if (de_c1 !== 1280*720)  begin errors=errors+1; $display("720p: %0d pixel attivi", de_c1); end
                if (hs_c1 !== 40*750)    begin errors=errors+1; $display("720p: hsync alto %0d", hs_c1); end
                if (vs_c1 !== 5*1650)    begin errors=errors+1; $display("720p: vsync alto %0d", vs_c1); end
            end
            f1 = f1 + 1; tot_c1 = 0; de_c1 = 0; hs_c1 = 0; vs_c1 = 0;
        end
        if (qi2) begin
            if (f2 == 1) begin
                if (tot_c2 !== 800*525) begin errors=errors+1; $display("480p: %0d clock/quadro", tot_c2); end
                if (de_c2 !== 640*480)  begin errors=errors+1; $display("480p: %0d pixel attivi", de_c2); end
                // sync NEGATIVI: il tempo a livello basso e' la durata del sync
                if (hs_c2 !== 96*525)   begin errors=errors+1; $display("480p: hsync basso %0d", hs_c2); end
                if (vs_c2 !== 2*800)    begin errors=errors+1; $display("480p: vsync basso %0d", vs_c2); end
            end
            f2 = f2 + 1; tot_c2 = 0; de_c2 = 0; hs_c2 = 0; vs_c2 = 0;
        end
        if (de1) de_c1 = de_c1 + 1;   if (de2) de_c2 = de_c2 + 1;
        if (hs1) hs_c1 = hs_c1 + 1;   if (!hs2) hs_c2 = hs_c2 + 1;
        if (vs1) vs_c1 = vs_c1 + 1;   if (!vs2) vs_c2 = vs_c2 + 1;
    end
    initial begin
        #100 rst = 0;
        wait (f1 >= 3 && f2 >= 3);
        if (errors == 0) $display("PASS vtiming: 720p e 480p");
        else             $display("FAIL vtiming: %0d errori", errors);
        $finish;
    end
endmodule
