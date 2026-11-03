// J20K — generatore di timing 1280x720 @ 60 Hz, CEA-861
//
// Il quadro fisico e' 1650 x 750, di cui 1280 x 720 visibili. Il resto sono i
// margini che il monitor usa per riposizionare il pennello — un'eredita' dei
// tubi catodici che il digitale si porta dietro perche' il protocollo la
// prevede.
//
//   orizzontale   1280 attivi + 110 front porch + 40 sync + 220 back porch
//   verticale      720 attive +   5 front porch +  5 sync +  20 back porch
//
// Il conto torna esatto e vale la pena farlo:
//
//   74.250.000 / (1650 x 750) = 60,000 Hz
//
// Non 59,94, non 60,1: sessanta tondi. Se il banco misura qualcos'altro, il
// guasto sta nella PLL o nel CLKDIV, non qui.
//
// I SYNC SONO POSITIVI in questa modalita', al contrario delle vecchie
// modalita' VGA. Invertirli non da' uno schermo nero ma un'immagine spostata
// o un monitor che rifiuta il segnale dicendo "modalita' non supportata": e'
// un sintomo diverso da tutti gli altri, e per questo utile.
//
// L'USCITA E' REGISTRATA, tutta insieme. Chi disegna i pixel ha bisogno di un
// ciclo per farlo, quindi de, hsync e vsync devono arrivare al codificatore
// TMDS con lo stesso ritardo del colore. Farlo qui, in un solo stadio
// condiviso, e' l'unico modo perche' non possano scivolare l'uno rispetto
// all'altro: se fossero due stadi distinti, prima o poi qualcuno ne
// aggiungerebbe uno solo dei due.

`default_nettype none

module j20k_vtiming #(
    parameter integer H_ATT = 1280,
    parameter integer H_FP  = 110,
    parameter integer H_SY  = 40,
    parameter integer H_BP  = 220,
    parameter integer V_ATT = 720,
    parameter integer V_FP  = 5,
    parameter integer V_SY  = 5,
    parameter integer V_BP  = 20,
    parameter         H_POS = 1'b1,   // 1 = sync positivo (720p), 0 = negativo (640x480)
    parameter         V_POS = 1'b1
) (
    input  wire        clk_pix,
    input  wire        rst_pix,

    output reg  [10:0] x,             // 0..1649, posizione grezza
    output reg  [9:0]  y,             // 0..749
    output reg         de,
    output reg         hsync,
    output reg         vsync,
    output reg         vblank_inizio, // un impulso per quadro, a fine visibile
    output reg         riga_inizio,   // un impulso per riga, allineato con x==0
    output reg         quadro_inizio  // un impulso per quadro, con x==0 e y==0
);

    // GLI IMPULSI LI GENERA CHI HA LO STATO. Ricavare "inizio riga" dal
    // livello x==0 sembra equivalente e non lo e': al rilascio del reset x
    // resta zero per DUE cicli, perche' e' registrata da hc e partono
    // entrambe da zero. E' costato un quadro di troppo per accensione nella
    // build 0x50, e sarebbe ricomparso in ogni consumatore che si fosse
    // ricavato il fronte per conto suo.
    //
    // Qui l'impulso nasce da hc, che di zeri doppi non ne ha, ed esce
    // allineato con x==0 perche' anche lui passa per un registro.

    localparam integer H_TOT = H_ATT + H_FP + H_SY + H_BP;   // 1650
    localparam integer V_TOT = V_ATT + V_FP + V_SY + V_BP;   // 750

    reg [10:0] hc;
    reg [9:0]  vc;

    wire fine_riga  = (hc == H_TOT[10:0] - 11'd1);
    wire fine_quadro = fine_riga && (vc == V_TOT[9:0] - 10'd1);

    always @(posedge clk_pix) begin
        if (rst_pix) begin
            hc <= 11'd0;
            vc <= 10'd0;
            x <= 11'd0;  y <= 10'd0;
            de <= 1'b0;  hsync <= !H_POS; vsync <= !V_POS;
            vblank_inizio <= 1'b0;
            riga_inizio <= 1'b0;  quadro_inizio <= 1'b0;
        end else begin
            hc <= fine_riga ? 11'd0 : hc + 11'd1;
            if (fine_riga)
                vc <= fine_quadro ? 10'd0 : vc + 10'd1;

            // Tutto lo stesso stadio, tutto lo stesso ritardo.
            x     <= hc;
            y     <= vc;
            de    <= (hc < H_ATT[10:0]) && (vc < V_ATT[9:0]);
            hsync <= H_POS ^ !((hc >= H_ATT[10:0] + H_FP[10:0]) &&
                              (hc <  H_ATT[10:0] + H_FP[10:0] + H_SY[10:0]));
            vsync <= V_POS ^ !((vc >= V_ATT[9:0] + V_FP[9:0]) &&
                              (vc <  V_ATT[9:0] + V_FP[9:0] + V_SY[9:0]));
            vblank_inizio <= fine_riga && (vc == V_ATT[9:0] - 10'd1);
            riga_inizio   <= (hc == 11'd0);
            quadro_inizio <= (hc == 11'd0) && (vc == 10'd0);
        end
    end

endmodule

`default_nettype wire
