// J20K — PLL del dominio di sistema
//
// 27 MHz dal quarzo  ->  60,75 MHz  (27 × 9/4)
//                    ->  60,75 MHz sfasati di 180°, per la SDRAM
//
// Il calcolo:
//   fCLKOUT = fCLKIN × FBDIV / IDIV = 27 × 9 / 4 = 60,75 MHz
//   IDIV_SEL  = IDIV  − 1 = 3
//   FBDIV_SEL = FBDIV − 1 = 8
//   fVCO = fCLKOUT × ODIV = 60,75 × 16 = 972 MHz
//
// PSDA_SEL sfasa CLKOUTP in sedicesimi di periodo: "1000" = 8/16 = 180°,
// che è lo sfasamento richiesto dal controller SDRAM sul percorso di
// scrittura.
//
// ---------------------------------------------------------------------------
// DA VERIFICARE
//
// Se il place & route rifiuta questi parametri, il sospetto numero uno è
// ODIV_SEL: il VCO deve cadere nel range del dispositivo, e la scelta
// alternativa è 8, che porta il VCO a 486 MHz. Entrambi i valori sono
// aritmeticamente corretti; solo il datasheet dice quale è ammesso.
//
// Il secondo sospetto è DEVICE, che va scritto esattamente come lo scrive
// il generatore IP di Gowin per questo chip.
//
// C'è comunque una rete di sicurezza: se il PLL producesse una frequenza
// diversa da 60,75 MHz, la UART del banco di prova andrebbe fuori baud rate
// e stamperebbe caratteri illeggibili. Un clock sbagliato non passa
// inosservato.
// ---------------------------------------------------------------------------

`default_nettype none

module pm_pll_sdram (
    input  wire clkin,       // 27 MHz dal quarzo
    output wire clk_sys,     // 60,75 MHz
    output wire clk_sdram,   // 60,75 MHz sfasati di 180°
    output wire lock
);

    wire clkoutd_o;
    wire clkoutd3_o;
    wire gnd = 1'b0;

    rPLL rpll_inst (
        .CLKOUT   (clk_sys),
        .LOCK     (lock),
        .CLKOUTP  (clk_sdram),
        .CLKOUTD  (clkoutd_o),
        .CLKOUTD3 (clkoutd3_o),
        .RESET    (gnd),
        .RESET_P  (gnd),
        .CLKIN    (clkin),
        .CLKFB    (gnd),
        .FBDSEL   ({gnd,gnd,gnd,gnd,gnd,gnd}),
        .IDSEL    ({gnd,gnd,gnd,gnd,gnd,gnd}),
        .ODSEL    ({gnd,gnd,gnd,gnd,gnd,gnd}),
        .PSDA     ({gnd,gnd,gnd,gnd}),
        .DUTYDA   ({gnd,gnd,gnd,gnd}),
        .FDLY     ({gnd,gnd,gnd,gnd})
    );

    defparam rpll_inst.FCLKIN           = "27";
    defparam rpll_inst.DYN_IDIV_SEL     = "false";
    defparam rpll_inst.IDIV_SEL         = 3;        // IDIV  = 4
    defparam rpll_inst.DYN_FBDIV_SEL    = "false";
    defparam rpll_inst.FBDIV_SEL        = 8;        // FBDIV = 9
    defparam rpll_inst.DYN_ODIV_SEL     = "false";
    defparam rpll_inst.ODIV_SEL         = 16;       // VCO = 972 MHz
    // ---------------------------------------------------------------------
    // DYN_DA_EN deve restare "false", ed e' il parametro piu' insidioso dei
    // ventidue.
    //
    // A "true" la fase e il duty cycle di CLKOUTP NON vengono piu' dai
    // parametri PSDA_SEL e DUTYDA_SEL, ma dalle porte di ingresso PSDA[3:0]
    // e DUTYDA[3:0]. Se quelle sono legate a zero — come in ogni file
    // generato da Gowin, dove CLKOUTP di solito non si usa — il duty cycle
    // vale 1/16 x (DUTYDA - PSDA) = 0. Cioe' CLKOUTP non e' un clock lento o
    // sfasato male: NON ESISTE.
    //
    // Il resto del progetto continua a funzionare, perche' gira su CLKOUT.
    // A restare senza clock e' solo la SDRAM, che quindi non si inizializza,
    // non risponde, e lascia il bus dati in aria: letto tutto a uno.
    // ---------------------------------------------------------------------
    defparam rpll_inst.PSDA_SEL         = "1000";   // 8/16 di periodo = 180°
    defparam rpll_inst.DYN_DA_EN        = "false";  // usa i parametri, non le porte
    defparam rpll_inst.DUTYDA_SEL       = "1000";   // 50% di duty cycle
    defparam rpll_inst.CLKOUT_FT_DIR    = 1'b1;
    defparam rpll_inst.CLKOUTP_FT_DIR   = 1'b1;
    defparam rpll_inst.CLKOUT_DLY_STEP  = 0;
    defparam rpll_inst.CLKOUTP_DLY_STEP = 0;
    defparam rpll_inst.CLKFB_SEL        = "internal";
    defparam rpll_inst.CLKOUT_BYPASS    = "false";
    defparam rpll_inst.CLKOUTP_BYPASS   = "false";
    defparam rpll_inst.CLKOUTD_BYPASS   = "false";
    defparam rpll_inst.DYN_SDIV_SEL     = 10;
    defparam rpll_inst.CLKOUTD_SRC      = "CLKOUT";
    defparam rpll_inst.CLKOUTD3_SRC     = "CLKOUT";
    defparam rpll_inst.DEVICE           = "GW2AR-18C";

endmodule

`default_nettype wire
