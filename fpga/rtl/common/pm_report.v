// PicoCalc HDMI Mirror - rapporto sulla seriale (BL616, 115200 8N1), 1 Hz:
//   B=xxxxxxxx E=xxxxxxxx P=xxxx O=xx\r\n
// byte ricevuti, byte errati, pacchetti, pacchetti dispari (tutto esadecimale).

`default_nettype none

module pm_report #(
    parameter CLK_HZ = 108_000_000
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] n_bytes,
    input  wire [31:0] n_errors,
    input  wire [15:0] n_pkts,
    input  wire [7:0]  n_odd,
    output wire        tx
);

    reg [26:0] tick;
    reg        go;
    always @(posedge clk)
        if (!rst_n) begin tick <= 27'd0; go <= 1'b0; end
        else if (tick == CLK_HZ - 1) begin tick <= 27'd0; go <= 1'b1; end
        else begin tick <= tick + 27'd1; go <= 1'b0; end

    reg [31:0] sb, se; reg [15:0] sp; reg [7:0] so;
    reg [5:0]  idx; reg running;
    reg [7:0]  ch; reg send;
    wire busy;

    function [7:0] hex(input [3:0] n);
        hex = (n < 10) ? 8'h30 + n : 8'h37 + n;
    endfunction

    reg [7:0] c;
    always @* begin
        case (idx)
            0: c = "B";  1: c = "=";
            2: c = hex(sb[31:28]); 3: c = hex(sb[27:24]); 4: c = hex(sb[23:20]); 5: c = hex(sb[19:16]);
            6: c = hex(sb[15:12]); 7: c = hex(sb[11:8]);  8: c = hex(sb[7:4]);   9: c = hex(sb[3:0]);
            10: c = " "; 11: c = "E"; 12: c = "=";
            13: c = hex(se[31:28]); 14: c = hex(se[27:24]); 15: c = hex(se[23:20]); 16: c = hex(se[19:16]);
            17: c = hex(se[15:12]); 18: c = hex(se[11:8]);  19: c = hex(se[7:4]);   20: c = hex(se[3:0]);
            21: c = " "; 22: c = "P"; 23: c = "=";
            24: c = hex(sp[15:12]); 25: c = hex(sp[11:8]); 26: c = hex(sp[7:4]); 27: c = hex(sp[3:0]);
            28: c = " "; 29: c = "O"; 30: c = "=";
            31: c = hex(so[7:4]); 32: c = hex(so[3:0]);
            33: c = 8'h0D;
            default: c = 8'h0A;
        endcase
    end

    always @(posedge clk) begin
        send <= 1'b0;
        if (!rst_n) begin running <= 1'b0; idx <= 6'd0; end
        else if (!running) begin
            if (go) begin sb <= n_bytes; se <= n_errors; sp <= n_pkts; so <= n_odd; idx <= 6'd0; running <= 1'b1; end
        end else if (!busy && !send) begin
            ch <= c; send <= 1'b1;
            if (idx == 6'd34) running <= 1'b0; else idx <= idx + 6'd1;
        end
    end

    uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(115200)) u_tx (
        .clk(clk), .rst_n(rst_n), .data(ch), .send(send), .tx(tx), .busy(busy)
    );

endmodule

`default_nettype wire
