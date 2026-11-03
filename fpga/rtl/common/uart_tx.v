// J20K — trasmettitore UART 8N1
//
// Minimale di proposito: serve solo a far uscire i risultati dei banchi di
// prova. Il ricevitore e le FIFO arriveranno col blocco UART vero, quello
// mappato a $D03000.
//
// A 60,75 MHz e 115200 baud il divisore è 527, che dà 115.275 baud reali:
// un errore dello 0,065%, ampiamente dentro il ±2% che una UART tollera.
//
// Se il PLL producesse una frequenza diversa da quella dichiarata in CLK_HZ,
// il baud rate sballerebbe e l'uscita diventerebbe illeggibile. È un effetto
// collaterale utile: rende un errore di clock immediatamente visibile.

`default_nettype none

module uart_tx #(
    parameter CLK_HZ = 60_750_000,
    parameter BAUD   = 115200
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] data,
    input  wire       send,      // impulso di un ciclo, ignorato se busy
    output reg        tx,
    output wire       busy
);

    localparam integer DIV = CLK_HZ / BAUD;

    reg [15:0] div_cnt;
    reg [3:0]  bit_idx;      // 0 = start, 1..8 = dati, 9 = stop
    reg [9:0]  shifter;      // {stop, dati[7:0], start}
    reg        active;

    assign busy = active;

    always @(posedge clk) begin
        if (!rst_n) begin
            tx      <= 1'b1;
            active  <= 1'b0;
            div_cnt <= 16'd0;
            bit_idx <= 4'd0;
            shifter <= 10'h3FF;
        end else if (!active) begin
            tx <= 1'b1;
            if (send) begin
                shifter <= {1'b1, data, 1'b0};   // stop, dati, start
                active  <= 1'b1;
                div_cnt <= 16'd0;
                bit_idx <= 4'd0;
                tx      <= 1'b0;                 // start bit subito
            end
        end else begin
            if (div_cnt == DIV[15:0] - 16'd1) begin
                div_cnt <= 16'd0;
                shifter <= {1'b1, shifter[9:1]};
                tx      <= shifter[1];
                if (bit_idx == 4'd9)
                    active <= 1'b0;
                else
                    bit_idx <= bit_idx + 4'd1;
            end else begin
                div_cnt <= div_cnt + 16'd1;
            end
        end
    end

endmodule

`default_nettype wire
