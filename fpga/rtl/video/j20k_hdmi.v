// J20K — uscita HDMI: tre canali TMDS serializzati, piu' il clock
//
// Tre stadi, ognuno con un mestiere:
//
//   1. tre j20k_tmds, uno per colore. Il canale BLU porta anche hsync e
//      vsync nei simboli di controllo del blanking; gli altri due mandano
//      controllo nullo. E' cosi' che il protocollo trasporta i sincronismi
//      senza fili dedicati.
//
//   2. tre OSER10, che sputano fuori i dieci bit di ogni simbolo uno alla
//      volta a 371,25 MHz. Sono primitive del dispositivo: la logica normale
//      non arriva a quella frequenza.
//
//   3. quattro ELVDS_OBUF, che fanno le coppie differenziali. Tre dati e il
//      clock.
//
// IL CANALE CLOCK NON E' SERIALIZZATO: ci va clk_pix diretto. Sembra
// un'incongruenza — gli altri tre passano da un serializzatore e questo no —
// e invece e' proprio quel che serve. Il ricevitore non deve leggere dei bit
// da quel canale: deve vedere un'onda quadra alla frequenza del pixel, da cui
// moltiplicare per dieci e ricavare il proprio clock di bit. Serializzare un
// pattern 1111100000 darebbe la stessa forma d'onda con piu' logica e piu'
// modi di sbagliare.
//
// I VINCOLI SONO IN FORMA ACCOPPIATA: nel .cst si scrive un IO_LOC solo con
// due numeri di pin, e Gowin lega il segnale _n al secondo quando entrambi
// _p e _n compaiono nel top. Se il _n non compare, la coppia resta muta senza
// che niente protesti.

`default_nettype none

module j20k_hdmi (
    input  wire       clk_pix,
    input  wire       clk_5x,
    input  wire       rst_pix,

    input  wire [7:0] rosso,
    input  wire [7:0] verde,
    input  wire [7:0] blu,
    input  wire       hsync,
    input  wire       vsync,
    input  wire       de,

    output wire       tmds_clk_p,
    output wire       tmds_clk_n,
    output wire [2:0] tmds_d_p,       // [2] rosso, [1] verde, [0] blu
    output wire [2:0] tmds_d_n
);

    wire [9:0] sym_blu, sym_verde, sym_rosso;

    j20k_tmds enc_blu (
        .clk_pix(clk_pix), .rst_pix(rst_pix),
        .dato(blu),   .ctrl({vsync, hsync}), .de(de), .tmds(sym_blu)
    );
    j20k_tmds enc_verde (
        .clk_pix(clk_pix), .rst_pix(rst_pix),
        .dato(verde), .ctrl(2'b00), .de(de), .tmds(sym_verde)
    );
    j20k_tmds enc_rosso (
        .clk_pix(clk_pix), .rst_pix(rst_pix),
        .dato(rosso), .ctrl(2'b00), .de(de), .tmds(sym_rosso)
    );

    wire [2:0] seriale;

    OSER10 tmds_serdes [2:0] (
        .Q (seriale),
        .D0({sym_rosso[0], sym_verde[0], sym_blu[0]}),
        .D1({sym_rosso[1], sym_verde[1], sym_blu[1]}),
        .D2({sym_rosso[2], sym_verde[2], sym_blu[2]}),
        .D3({sym_rosso[3], sym_verde[3], sym_blu[3]}),
        .D4({sym_rosso[4], sym_verde[4], sym_blu[4]}),
        .D5({sym_rosso[5], sym_verde[5], sym_blu[5]}),
        .D6({sym_rosso[6], sym_verde[6], sym_blu[6]}),
        .D7({sym_rosso[7], sym_verde[7], sym_blu[7]}),
        .D8({sym_rosso[8], sym_verde[8], sym_blu[8]}),
        .D9({sym_rosso[9], sym_verde[9], sym_blu[9]}),
        .PCLK (clk_pix),
        .FCLK (clk_5x),
        .RESET(rst_pix)
    );

    ELVDS_OBUF tmds_buf [3:0] (
        .I ({clk_pix,    seriale}),
        .O ({tmds_clk_p, tmds_d_p}),
        .OB({tmds_clk_n, tmds_d_n})
    );

endmodule

`default_nettype wire
