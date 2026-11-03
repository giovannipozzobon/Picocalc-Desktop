// PicoCalc HDMI Mirror - uscita video: finestra 640x640 (scala 2x) a 720p
//
// Finestra a x = 320, y = 40; ogni pixel e ogni riga sorgente sono ripetuti
// due volte; fuori finestra nero. Legge il buffer di riga (due banchi: la riga
// sorgente sl sta nel banco sl[0]) e pubblica in codice Gray la riga sorgente
// corrente (`show_gray`) per il lettore della SDRAM. Convertitore RGB565 ->
// RGB888 per replica dei bit alti; inversione (vedi INVON_NORMAL) e display-off applicati qui.
//
// x, y, de, hsync, vsync arrivano da j20k_vtiming, tutti nello stesso stadio:
// qui hsync/vsync/de sono ritardati di un ciclo, quello della lettura BSRAM.

`default_nettype none

module mirror_video #(
    // Il pannello IPS del PicoCalc mostra i colori giusti solo con INVON
    // (lcd_init lo manda sempre): la memoria contiene i colori veri. Quindi
    // con INVON = 1 l'HDMI mostra la memoria com'e', con INVON = 0 la inverte.
    parameter         INVON_NORMAL = 1'b1,
    parameter integer WIN_X = 320,
    parameter integer WIN_Y = 40
) (
    input  wire        clk_pix,
    input  wire [10:0] x,
    input  wire [9:0]  y,
    input  wire        de,
    input  wire        hsync,
    input  wire        vsync,

    input  wire        inv_on,         // asincroni: dominio QSPI (quasi statici)
    input  wire        disp_on,

    output reg  [8:0]  show_gray,
    output wire [8:0]  lb_raddr,
    input  wire [31:0] lb_rdata,

    output wire [7:0]  rosso,
    output wire [7:0]  verde,
    output wire [7:0]  blu,
    output reg         de_o,
    output reg         hsync_o,
    output reg         vsync_o
);

    wire in_win = (x >= WIN_X) && (x < WIN_X + 640) && (y >= WIN_Y) && (y < WIN_Y + 640);
    wire [9:0] wx = x - WIN_X;
    wire [9:0] wy = y - WIN_Y;
    wire [8:0] px = wx[9:1];           // 0..319
    wire [8:0] sl = wy[9:1];           // 0..319

    assign lb_raddr = {sl[0], px[8:1]};

    reg        half_d, win_d;
    reg [1:0]  inv_s, disp_s;
    always @(posedge clk_pix) begin
        half_d  <= px[0];
        win_d   <= in_win;
        de_o    <= de;
        hsync_o <= hsync;
        vsync_o <= vsync;
        inv_s   <= {inv_s[0], inv_on};
        disp_s  <= {disp_s[0], disp_on};
    end

    // riga sorgente mostrata: 0 sopra la finestra, 319 sotto
    wire [9:0] dy = y - WIN_Y;
    wire [8:0] show_bin = (y < WIN_Y) ? 9'd0 : (y >= WIN_Y + 640) ? 9'd319 : dy[9:1];
    always @(posedge clk_pix) show_gray <= (show_bin >> 1) ^ show_bin;

    wire [15:0] p = half_d ? lb_rdata[31:16] : lb_rdata[15:0];
    wire [7:0]  r8 = {p[15:11], p[15:13]};
    wire [7:0]  g8 = {p[10:5],  p[10:9]};
    wire [7:0]  b8 = {p[4:0],   p[4:2]};
    wire        show_px = win_d && disp_s[1];
    wire [7:0]  m   = (inv_s[1] == INVON_NORMAL) ? 8'h00 : 8'hFF;

    assign rosso = show_px ? (r8 ^ m) : 8'h00;
    assign verde = show_px ? (g8 ^ m) : 8'h00;
    assign blu   = show_px ? (b8 ^ m) : 8'h00;

endmodule

`default_nettype wire
