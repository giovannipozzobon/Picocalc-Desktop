// Testbench di cmd_decoder: riproduce le sequenze di lcd.c (set_window +
// blit, VSCRDEF/VSCSAD, MADCTL, INV/DISP) e confronta la memoria ricostruita
// con quella attesa.
`timescale 1ns/1ps
module cmd_decoder_tb;
    reg clk = 0, rst = 1; always #5 clk = ~clk;
    reg bv = 0, bf = 0, pe = 0; reg [7:0] bd = 0;
    wire wv; wire [8:0] wx, wy; wire [15:0] wdata;
    wire [9:0] tfa, vsam, vsp; wire [7:0] madctl; wire inv, don, rs;
    cmd_decoder dut(.clk(clk), .rst(rst), .byte_valid(bv), .byte_data(bd), .byte_first(bf), .pkt_end(pe),
        .wr_valid(wv), .wr_x(wx), .wr_y(wy), .wr_data(wdata),
        .tfa(tfa), .vsam(vsam), .vsp(vsp), .madctl(madctl), .inv_on(inv), .disp_on(don), .resync_pulse(rs));

    reg [15:0] mem [0:320*480-1];      // memoria ricostruita dal DUT
    reg [15:0] gold[0:320*480-1];      // modello atteso
    integer i, errors = 0, nwr = 0;
    always @(posedge clk) if (wv) begin mem[wy*320+wx] = wdata; nwr = nwr + 1; end

    task byte_(input [7:0] b, input first);
        begin @(posedge clk); bv <= 1; bd <= b; bf <= first; @(posedge clk); bv <= 0; bf <= 0; repeat (2) @(posedge clk); end
    endtask
    task cmd_(input [7:0] c);  begin byte_(8'h00, 1); byte_(c, 0); end endtask
    task data1(input [7:0] b); begin byte_(8'h01, 1); byte_(b, 0); end endtask   // un pacchetto per byte, come lcd_write_data
    task window(input integer x0, input integer y0, input integer x1, input integer y1);
        begin
            cmd_(8'h2A); data1(x0[15:8]); data1(x0[7:0]); data1(x1[15:8]); data1(x1[7:0]);
            cmd_(8'h2B); data1(y0[15:8]); data1(y0[7:0]); data1(y1[15:8]); data1(y1[7:0]);
            cmd_(8'h2C);
        end
    endtask
    // blit: finestra + un pacchetto DATA con tutti i pixel; aggiorna il modello
    task blit(input integer x, input integer y, input integer w, input integer h, input [15:0] seed);
        integer px, py; reg [15:0] p;
        begin
            window(x, y, x+w-1, y+h-1);
            byte_(8'h01, 1);
            for (py = 0; py < h; py = py + 1)
                for (px = 0; px < w; px = px + 1) begin
                    p = seed + py*7 + px*3 + 16'h0101;
                    byte_(p[15:8], 0); byte_(p[7:0], 0);
                    gold[(y+py)*320 + x+px] = p;
                end
        end
    endtask

    integer ok_regs = 1;
    initial begin
        for (i = 0; i < 320*480; i = i + 1) begin mem[i] = 16'hXXXX; gold[i] = 16'hXXXX; end
        #100 rst = 0; #50;
        // sequenza di init come lcd_init()
        cmd_(8'h01); cmd_(8'h3A); data1(8'h55); cmd_(8'h36); data1(8'h48); cmd_(8'h21);
        cmd_(8'h33); data1(0); data1(0); data1(8'h01); data1(8'h40); data1(0); data1(0);
        cmd_(8'h29);
        if (madctl !== 8'h48 || inv !== 1 || don !== 1) begin ok_regs = 0; $display("ERR registri dopo init: madctl=%h inv=%b don=%b", madctl, inv, don); end
        // blit di vario genere
        blit(0, 0, 8, 10, 16'h1000);          // glifo 8x10
        blit(8, 10, 5, 3, 16'h2000);
        blit(0, 470, 320, 10, 16'h3000);       // ultima fascia di memoria, riga intera
        blit(300, 100, 20, 4, 16'h4000);       // bordo destro
        // VSCSAD come lcd_scroll_up: 10 righe
        cmd_(8'h37); data1(8'h00); data1(8'h0A);
        if (vsp !== 10 || tfa !== 0 || vsam !== 480) begin ok_regs = 0; $display("ERR scroll: tfa=%0d vsam=%0d vsp=%0d", tfa, vsam, vsp); end
        // area fissa alta di 20 e bassa di 30 (VSA come da firmware: 320-50 = 270)
        cmd_(8'h33); data1(0); data1(20); data1(1); data1(14); data1(0); data1(30);
        if (tfa !== 20 || vsam !== 430) begin ok_regs = 0; $display("ERR VSCRDEF: tfa=%0d vsam=%0d (atteso 20/430)", tfa, vsam); end
        // pixel oltre YE scartati: finestra 2 righe, 3 righe di pixel
        window(0, 200, 3, 201);
        byte_(8'h01, 1);
        for (i = 0; i < 12; i = i + 1) begin byte_(8'hAB, 0); byte_(i[7:0], 0); end
        for (i = 0; i < 8; i = i + 1) gold[200*320 + (i/4)*320 + (i%4)] = {8'hAB, i[7:0]};
        // pacchetti DATA spezzati a meta' pixel: un byte per pacchetto
        window(50, 300, 51, 300);
        data1(8'hDE); data1(8'hAD); data1(8'hBE); data1(8'hEF);
        gold[300*320+50] = 16'hDEAD; gold[300*320+51] = 16'hBEEF;
        // CTRL resync: registri a default, memoria intatta
        byte_(8'h80, 1); byte_(8'h01, 0);
        repeat (4) @(posedge clk);
        if (tfa !== 0 || vsp !== 0 || vsam !== 480 || don !== 0) begin ok_regs = 0; $display("ERR CTRL: tfa=%0d vsam=%0d vsp=%0d don=%b", tfa, vsam, vsp, don); end
        #100;
        for (i = 0; i < 320*480; i = i + 1)
            if (mem[i] !== gold[i]) begin
                errors = errors + 1;
                if (errors < 10) $display("ERR mem[%0d,%0d]: got %h exp %h", i%320, i/320, mem[i], gold[i]);
            end
        if (errors == 0 && ok_regs) $display("PASS cmd_decoder: %0d pixel scritti", nwr);
        else $display("FAIL cmd_decoder: %0d errori memoria, regs_ok=%0d", errors, ok_regs);
        $finish;
    end
endmodule
