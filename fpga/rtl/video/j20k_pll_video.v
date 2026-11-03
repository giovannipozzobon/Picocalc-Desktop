// J20K — PLL del dominio pixel: 371,25 MHz seriale e 74,25 MHz pixel
//
// L'HDMI 720p60 chiede un pixel clock di 74,25 MHz esatti e un seriale TMDS
// cinque volte tanto, 371,25 MHz. Questi due numeri non sono negoziabili: li
// fissa lo standard, non il progetto (docs/architettura_clock.md §2).
//
// Il 27 MHz del quarzo e' stato scelto da Sipeed proprio per questo:
//
//   371,25 = 27 x 55 / 4      IDIV = 4, FBDIV = 55
//   VCO    = 371,25 x 2 = 742,5 MHz, dentro il range del dispositivo
//   pixel  = 371,25 / 5 = 74,25 MHz, da un CLKDIV dedicato
//
// I registri del Gowin vogliono i valori DIMINUITI DI UNO: IDIV_SEL = 3,
// FBDIV_SEL = 54. E' la stessa convenzione del PLL di sistema, ed e' la prima
// cosa da guardare quando la frequenza esce diversa da quella attesa.
//
// PIXEL E SERIALE DALLA STESSA PLL, e non e' un dettaglio: l'OSER10 vuole
// PCLK e FCLK in relazione di fase fissa, e prenderli da due PLL diverse
// significherebbe una relazione non controllata fra i due, cioe' un
// serializzatore che sbaglia la finestra di campionamento in modo diverso a
// ogni accensione. Il CLKDIV divide il seriale invece di generare il pixel
// per conto suo, ed e' quello che rende la relazione garantita per
// costruzione.
//
// IL DOMINIO DI SISTEMA RESTA A 60,75 MHz e da un'ALTRA PLL. La scelta e'
// gia' argomentata in docs/architettura_clock.md §3: far girare la CPU a
// 74,25 MHz lascerebbe tre punti e mezzo di margine su fx68k, che non
// sopravvivono all'aggiunta di un solo blocco. Il GW2AR-18 ha due rPLL e
// questa e' la seconda.

`default_nettype none

module j20k_pll_video #(
    // 720p : IDIV_SEL=3 FBDIV_SEL=54 ODIV_SEL=2  -> 371,25 / 74,25 MHz
    // 480p : IDIV_SEL=2 FBDIV_SEL=13 ODIV_SEL=4  -> 126,00 / 25,20 MHz (27x14/3)
    parameter integer IDIV_SEL  = 3,
    parameter integer FBDIV_SEL = 54,
    parameter integer ODIV_SEL  = 2
) (
    input  wire sys_clk,        // 27 MHz dal quarzo
    output wire clk_pix,        // 74,25 MHz
    output wire clk_5x,         // 371,25 MHz, per l'OSER10
    output wire clk_d3,         // CLKOUTD3 = clk_5x / 3 = 123,75 MHz (720p): dominio QSPI
    output wire locked
);

    wire clk_5x_int, pll_lock;

    rPLL pll_video (
        .CLKOUT  (clk_5x_int),
        .LOCK    (pll_lock),
        .CLKOUTP (),
        .CLKOUTD (),
        .CLKOUTD3(clk_d3),
        .RESET   (1'b0),
        .RESET_P (1'b0),
        .CLKIN   (sys_clk),
        .CLKFB   (1'b0),
        .FBDSEL  (6'b000000),
        .IDSEL   (6'b000000),
        .ODSEL   (6'b000000),
        .PSDA    (4'b0000),
        .DUTYDA  (4'b0000),
        .FDLY    (4'b0000)
    );

    defparam pll_video.DEVICE           = "GW2AR-18C";
    defparam pll_video.FCLKIN           = "27";
    defparam pll_video.DYN_IDIV_SEL     = "false";
    defparam pll_video.IDIV_SEL         = IDIV_SEL;
    defparam pll_video.DYN_FBDIV_SEL    = "false";
    defparam pll_video.FBDIV_SEL        = FBDIV_SEL;
    defparam pll_video.DYN_ODIV_SEL     = "false";
    defparam pll_video.ODIV_SEL         = ODIV_SEL;
    defparam pll_video.PSDA_SEL         = "0000";   // nessuno sfasamento
    defparam pll_video.DYN_DA_EN        = "false";
    defparam pll_video.DUTYDA_SEL       = "1000";
    defparam pll_video.CLKOUT_FT_DIR    = 1'b1;
    defparam pll_video.CLKOUTP_FT_DIR   = 1'b1;
    defparam pll_video.CLKOUT_DLY_STEP  = 0;
    defparam pll_video.CLKOUTP_DLY_STEP = 0;
    defparam pll_video.CLKFB_SEL        = "internal";
    defparam pll_video.CLKOUT_BYPASS    = "false";
    defparam pll_video.CLKOUTP_BYPASS   = "false";
    defparam pll_video.CLKOUTD_BYPASS   = "false";
    defparam pll_video.DYN_SDIV_SEL     = 2;
    defparam pll_video.CLKOUTD_SRC      = "CLKOUT";
    defparam pll_video.CLKOUTD3_SRC     = "CLKOUT";

    // Il divisore per cinque. RESETN e' tenuto basso finche' la PLL non
    // aggancia: un divisore avviato su un clock che sta ancora cercando la
    // frequenza parte con una fase qualsiasi.
    CLKDIV u_clkdiv (
        .CLKOUT (clk_pix),
        .HCLKIN (clk_5x_int),
        .RESETN (pll_lock),
        .CALIB  (1'b0)
    );
    defparam u_clkdiv.DIV_MODE = "5";
    defparam u_clkdiv.GSREN    = "false";

    assign clk_5x = clk_5x_int;
    assign locked = pll_lock;

endmodule

`default_nettype wire
