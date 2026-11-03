// PicoCalc HDMI Mirror - PLL di sistema: 27 MHz x 4 = 108 MHz
//
// sys_clk deve essere >= 4x SCK (qspi_rx campiona SCK in sys_clk): 108 MHz
// regge SCK fino a 25 MHz con margine (4,3x) e fino a 40 MHz al limite (2,7x).
// Registri Gowin diminuiti di uno: IDIV_SEL=0 (IDIV 1), FBDIV_SEL=3 (FBDIV 4),
// VCO = 108 x 8 = 864 MHz.

`default_nettype none

module pm_pll_sys (
    input  wire clkin,       // 27 MHz
    output wire clk_sys,     // 108 MHz
    output wire lock
);

    rPLL rpll_inst (
        .CLKOUT  (clk_sys),
        .LOCK    (lock),
        .CLKOUTP (),
        .CLKOUTD (),
        .CLKOUTD3(),
        .RESET   (1'b0),
        .RESET_P (1'b0),
        .CLKIN   (clkin),
        .CLKFB   (1'b0),
        .FBDSEL  (6'b000000),
        .IDSEL   (6'b000000),
        .ODSEL   (6'b000000),
        .PSDA    (4'b0000),
        .DUTYDA  (4'b0000),
        .FDLY    (4'b0000)
    );

    defparam rpll_inst.DEVICE           = "GW2AR-18C";
    defparam rpll_inst.FCLKIN           = "27";
    defparam rpll_inst.DYN_IDIV_SEL     = "false";
    defparam rpll_inst.IDIV_SEL         = 0;
    defparam rpll_inst.DYN_FBDIV_SEL    = "false";
    defparam rpll_inst.FBDIV_SEL        = 3;
    defparam rpll_inst.DYN_ODIV_SEL     = "false";
    defparam rpll_inst.ODIV_SEL         = 8;
    defparam rpll_inst.PSDA_SEL         = "0000";
    defparam rpll_inst.DYN_DA_EN        = "false";
    defparam rpll_inst.DUTYDA_SEL       = "1000";
    defparam rpll_inst.CLKOUT_FT_DIR    = 1'b1;
    defparam rpll_inst.CLKOUTP_FT_DIR   = 1'b1;
    defparam rpll_inst.CLKOUT_DLY_STEP  = 0;
    defparam rpll_inst.CLKOUTP_DLY_STEP = 0;
    defparam rpll_inst.CLKFB_SEL        = "internal";
    defparam rpll_inst.CLKOUT_BYPASS    = "false";
    defparam rpll_inst.CLKOUTP_BYPASS   = "false";
    defparam rpll_inst.CLKOUTD_BYPASS   = "false";
    defparam rpll_inst.DYN_SDIV_SEL     = 2;
    defparam rpll_inst.CLKOUTD_SRC      = "CLKOUT";
    defparam rpll_inst.CLKOUTD3_SRC     = "CLKOUT";

endmodule

`default_nettype wire
