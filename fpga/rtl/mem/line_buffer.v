// PicoCalc HDMI Mirror - buffer di riga: due banchi da 160 word (320 pixel)
//
// Scrittura nel dominio clk_sys (32 bit), lettura nel dominio clk_pix (32 bit,
// uscita registrata). Indirizzo = {banco, indice di word[7:0]}.

`default_nettype none

module line_buffer (
    input  wire        wclk,
    input  wire        we,
    input  wire [8:0]  waddr,
    input  wire [31:0] wdata,

    input  wire        rclk,
    input  wire [8:0]  raddr,
    output reg  [31:0] rdata
);

    reg [31:0] mem [0:511];

    always @(posedge wclk) if (we) mem[waddr] <= wdata;
    always @(posedge rclk) rdata <= mem[raddr];

endmodule

`default_nettype wire
