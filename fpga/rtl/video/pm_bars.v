// PicoCalc HDMI Mirror - generatore di barre di colore per la fase 1
//
// Otto barre verticali (bianco, giallo, ciano, verde, magenta, rosso, blu,
// nero), una rampa di grigi nel quarto inferiore e un quadratino che scorre
// in basso: se lo schermo e' fermo il quadratino non si muove.
//
// L'uscita e' combinatoria da x/y: il ritardo di pipeline e' gia' assorbito
// da j20k_vtiming, che registra x, y, de, hsync e vsync nello stesso stadio.

`default_nettype none

module pm_bars #(
    parameter integer H_ATT = 1280,
    parameter integer V_ATT = 720
) (
    input  wire [10:0] x,
    input  wire [9:0]  y,
    input  wire [7:0]  quadro,        // contatore di quadri
    output reg  [7:0]  rosso,
    output reg  [7:0]  verde,
    output reg  [7:0]  blu
);

    localparam integer BW = H_ATT / 8;

    wire [2:0]  barra  = x / BW;
    wire        rampa  = (y >= (V_ATT * 3) / 4);
    wire [7:0]  grigio = (x * 256) / H_ATT;
    wire [10:0] marker = {3'b000, quadro} * (H_ATT / 256);
    wire        quadr  = (y >= V_ATT - 24) && (x >= marker) && (x < marker + 16);

    always @* begin
        if (quadr)
            {rosso, verde, blu} = {8'hFF, 8'hFF, 8'hFF};
        else if (rampa)
            {rosso, verde, blu} = {grigio, grigio, grigio};
        else case (barra)
            3'd0: {rosso, verde, blu} = {8'hFF, 8'hFF, 8'hFF};
            3'd1: {rosso, verde, blu} = {8'hFF, 8'hFF, 8'h00};
            3'd2: {rosso, verde, blu} = {8'h00, 8'hFF, 8'hFF};
            3'd3: {rosso, verde, blu} = {8'h00, 8'hFF, 8'h00};
            3'd4: {rosso, verde, blu} = {8'hFF, 8'h00, 8'hFF};
            3'd5: {rosso, verde, blu} = {8'hFF, 8'h00, 8'h00};
            3'd6: {rosso, verde, blu} = {8'h00, 8'h00, 8'hFF};
            default: {rosso, verde, blu} = {8'h00, 8'h00, 8'h00};
        endcase
    end

endmodule

`default_nettype wire
