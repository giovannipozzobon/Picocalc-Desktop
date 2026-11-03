// PicoCalc HDMI Mirror - scroll_map: riga visibile -> riga di memoria
//
// Modello dello scroll verticale dell'ST7365P (datasheet sez. 9.2.25 VSCRDEF,
// 9.2.29 VSCSAD, 10.7 Rolling scroll), con MADCTL MV=0, ML=0:
//
//   v <  TFA                    -> riga = v                       (area fissa alta)
//   TFA <= v < TFA + VSAM       -> riga = TFA + ((v - TFA + (VSP - TFA)) mod VSAM)
//   v >= TFA + VSAM             -> riga = v                       (area fissa bassa)
//
// VSAM e' l'altezza dell'area scorrevole NELLA MEMORIA (480 - TFA - BFA nel
// caso normale): la sceglie il chiamante (cmd_decoder), perche' il firmware
// manda in VSCRDEF un VSA (320) diverso da quello che il datasheet richiede
// (somma = 480) e il comportamento reale va confermato a banco.
//
// VSP fuori dall'area scorrevole (VSP < TFA o >= TFA+VSAM) e' una condizione
// "indefinita" da datasheet: qui si tratta come offset 0.
//
// Uscita registrata (1 ciclo di latenza).

`default_nettype none

module scroll_map (
    input  wire        clk,
    input  wire [9:0]  v,       // riga visibile 0..479
    input  wire [9:0]  tfa,
    input  wire [9:0]  vsam,    // altezza area scorrevole in memoria
    input  wire [9:0]  vsp,     // VSCSAD
    output reg  [9:0]  row      // riga di memoria 0..479
);

    wire [10:0] tfa_vsam = {1'b0, tfa} + {1'b0, vsam};
    wire        in_scroll = (v >= tfa) && ({1'b0, v} < tfa_vsam);
    wire        vsp_ok    = (vsp >= tfa) && ({1'b0, vsp} < tfa_vsam);
    wire [9:0]  off       = vsp_ok ? (vsp - tfa) : 10'd0;
    wire [10:0] t         = {1'b0, v - tfa} + {1'b0, off};      // < 2*VSAM
    wire [10:0] tm        = (t >= {1'b0, vsam}) ? (t - {1'b0, vsam}) : t;

    always @(posedge clk)
        row <= in_scroll ? (tfa + tm[9:0]) : v;

endmodule

`default_nettype wire
