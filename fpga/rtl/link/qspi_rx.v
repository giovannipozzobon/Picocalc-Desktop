// PicoCalc HDMI Mirror - ricevitore QSPI unidirezionale Pico -> FPGA
//
// Il Pico cambia D[3:0] sul
// fronte di discesa di SCK, la FPGA campiona sul fronte di salita. Ogni byte
// viaggia in due cicli: prima il nibble alto, poi il basso. SCK fermo basso
// con CS_N alto. Un pacchetto e' delimitato da CS_N basso -> alto.
//
// Tutto gira in sys_clk (>= 4x SCK): SCK, CS_N e D sono sincronizzati con 2
// flip-flop, il fronte di salita di SCK e' rilevato sul segnale sincronizzato
// e D e' letto allo stesso stadio, cosi' tutte le linee hanno lo stesso
// ritardo e il campionamento resta coerente.
//
// FILT: filtro anti-glitch su SCK e CS_N. Un livello e' accettato solo dopo FILT
// campioni consecutivi uguali (FILT=1: nessun filtro). Serve a ignorare il
// ringing di cavi lunghi senza resistenze serie; l'impulso piu' corto di SCK
// (mezzo periodo) deve durare almeno FILT cicli di sys_clk: con 108 MHz e
// FILT=3 SCK arriva a circa 15 MHz, con FILT=1 a 25 MHz (il mirror usa FILT=2: 25 MHz con resistenze serie da 47 ohm). I dati sono ritardati
// dello stesso numero di cicli di SCK, quindi il campionamento non cambia.
//
// Uscite (sys_clk):
//   byte_valid  impulso di un ciclo, un byte completo disponibile
//   byte_data   il byte
//   byte_first  il byte e' il primo del pacchetto (il tipo)
//   pkt_end     impulso di un ciclo al rilascio di CS_N (fine pacchetto)
//   pkt_odd     con pkt_end: il pacchetto aveva un numero dispari di nibble
//               (errore di linea: l'ultimo nibble e' scartato)

`default_nettype none

module qspi_rx #(
    parameter integer FILT = 1          // 1..8
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       qspi_sck,
    input  wire       qspi_csn,
    input  wire [3:0] qspi_d,

    output reg        byte_valid,
    output reg  [7:0] byte_data,
    output reg        byte_first,
    output reg        pkt_end,
    output reg        pkt_odd
);

    reg [1:0] sck_s, csn_s;
    reg [3:0] d_s0, d_s1;
    reg [7:0] sck_h, csn_h;
    reg       sck_f, csn_f;
    reg       sck_q, csn_q;
    reg [3:0] dd [0:8];                 // d_s1 ritardato di 1..9 cicli
    integer   k;

    wire [7:0] fmask = (8'd1 << FILT) - 8'd1;

    always @(posedge clk) begin
        sck_s <= {sck_s[0], qspi_sck};
        csn_s <= {csn_s[0], qspi_csn};
        d_s0  <= qspi_d;
        d_s1  <= d_s0;
        sck_h <= {sck_h[6:0], sck_s[1]};
        csn_h <= {csn_h[6:0], csn_s[1]};
        if ((sck_h & fmask) == fmask)      sck_f <= 1'b1;
        else if ((sck_h & fmask) == 8'd0)  sck_f <= 1'b0;
        if ((csn_h & fmask) == fmask)      csn_f <= 1'b1;
        else if ((csn_h & fmask) == 8'd0)  csn_f <= 1'b0;
        sck_q <= sck_f;
        csn_q <= csn_f;
        dd[0] <= d_s1;
        for (k = 1; k < 9; k = k + 1) dd[k] <= dd[k-1];
    end

    wire sck_rise = sck_f & ~sck_q;
    wire csn_fall = ~csn_f & csn_q;
    wire csn_rise =  csn_f & ~csn_q;
    wire active   = ~csn_f;

    // f ha FILT+1 cicli di ritardo rispetto a sck_s[1]: i dati hanno lo stesso.
    wire [3:0] d_a = dd[FILT];
    reg       phase;      // 0 = atteso nibble alto, 1 = atteso nibble basso
    reg [3:0] hi;
    reg       first_pending;

    always @(posedge clk) begin
        byte_valid <= 1'b0;
        pkt_end    <= 1'b0;
        pkt_odd    <= 1'b0;
        if (rst) begin
            phase <= 1'b0;
            first_pending <= 1'b1;
        end else begin
            if (csn_fall) begin
                phase <= 1'b0;
                first_pending <= 1'b1;
            end
            if (active && sck_rise) begin
                if (!phase) begin
                    hi    <= d_a;
                    phase <= 1'b1;
                end else begin
                    byte_data  <= {hi, d_a};
                    byte_valid <= 1'b1;
                    byte_first <= first_pending;
                    first_pending <= 1'b0;
                    phase <= 1'b0;
                end
            end
            if (csn_rise) begin
                pkt_end <= 1'b1;
                pkt_odd <= phase;
                phase   <= 1'b0;
            end
        end
    end

endmodule

`default_nettype wire
