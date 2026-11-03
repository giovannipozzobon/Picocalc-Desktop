// J20K — encoder TMDS 8b/10b, sezione 5.4.4 di HDMI 1.4 / DVI 1.0
//
// Due stadi, e fanno due lavori diversi:
//
//   8 -> 9   minimizza le TRANSIZIONI. Si sceglie XOR o XNOR secondo quanti
//            uno ci sono nel byte, e il nono bit dice quale dei due si e'
//            usato. E' la M di TMDS, ed e' cio' su cui il ricevitore recupera
//            il clock: un simbolo che sfarfalla troppo non si aggancia.
//
//   9 -> 10  bilancia la CORRENTE CONTINUA. Il decimo bit dice se il payload
//            e' stato invertito, e un contatore di disparita' decide quando
//            conviene invertire. Senza, il collegamento accumulerebbe uno
//            sbilanciamento e l'accoppiamento capacitivo lo perderebbe.
//
// DURANTE IL BLANKING non si codifica niente: si mandano quattro simboli
// fissi che portano hsync e vsync, ed e' anche l'unico momento in cui il
// contatore di disparita' si azzera. I quattro valori sono ELENCATI nel
// documento, non calcolati, e stanno scritti qui sotto tali e quali.
//
// COME SI VERIFICA. tools/test_tmds.py contiene due implementazioni
// indipendenti — una nella forma del documento, una nella forma di questo
// circuito — e le confronta su tutti i 256 byte per ogni valore di bias. Piu'
// tre proprieta' da cui il circuito dipende e che il documento non enuncia:
// che bias non esca dai cinque bit con segno, che non vada alla deriva su
// duecentomila simboli, e che nessun simbolo di dati coincida con uno di
// controllo. Confrontare due copie della stessa idea non proverebbe niente:
// le due forme si somigliano poco apposta.
//
// Qui uno sbaglio non ha sintomi intermedi. O il monitor aggancia, o resta
// nero, e da un nero non si deduce niente: e' il motivo per cui questo pezzo
// e' stato verificato prima di sintetizzarlo, e non dopo.

`default_nettype none

module j20k_tmds (
    input  wire       clk_pix,
    input  wire       rst_pix,          // sincrono, attivo alto
    input  wire [7:0] dato,
    input  wire [1:0] ctrl,             // {vsync, hsync}, solo nel blanking
    input  wire       de,
    output reg  [9:0] tmds
);

    // Da "dato" a "tmds" a STADI, non tutto in un colpo: conteggio + sette
    // XOR/XNOR incatenati (qm dipende da qm[i-1], un bit alla volta) +
    // secondo conteggio + l'addizione nel contatore bias fanno 14-15 livelli
    // logici, troppi per un solo ciclo a 74,25MHz (report di sintesi: slack
    // -0,21..-0,70ns su u_hdmi/enc_rosso/bias_3/bias_4). STESSO principio
    // delle pipeline in j20k_spr.v e rpt_seriale.v: un registro di mezzo,
    // allo stadio naturale fra "quale codifica" (qm, dipende solo da dato) e
    // "quanto sbilancia" (dipende da qm).
    //
    // de/ctrl VIAGGIANO CON qm, non restano dal vivo: senza, lo stadio 2
    // leggerebbe il blanking del pixel SUCCESSIVO invece di quello a cui qm
    // si riferisce, spostando il confine del blanking di un pixel rispetto
    // al colore vero - l'unico genere di sbaglio per cui questo modulo
    // avverte "niente sintomi intermedi, o aggancia o resta nero". L'intero
    // canale (tutti e tre: blu/verde/rosso usano lo stesso modulo) si sposta
    // di UN ciclo pixel in piu' rispetto a prima: invisibile a valle, non
    // c'e' niente con cui debba restare allineato in fase.

    // ------------------------------------------------------- 8 bit -> 9 bit
    // La funzione sta PRIMA di chi la usa: Verilog lo pretende, e il messaggio
    // che si prende sbagliando ordine non lo dice.
    function [3:0] quanti_uni(input [7:0] d);
        quanti_uni = d[0] + d[1] + d[2] + d[3] + d[4] + d[5] + d[6] + d[7];
    endfunction

    reg [3:0] uni;
    reg       xnor_scelto;

    always @(*) begin
        uni = quanti_uni(dato);
        // Piu' della meta' a uno, oppure meta' esatta con il bit 0 a zero:
        // la regola sceglie la codifica che produrra' meno transizioni.
        xnor_scelto = (uni > 4'd4) || ((uni == 4'd4) && (dato[0] == 1'b0));
    end

    integer i;
    reg [8:0] qm;

    always @(*) begin
        qm[0] = dato[0];
        for (i = 0; i < 7; i = i + 1)
            qm[i+1] = xnor_scelto ? (qm[i] ~^ dato[i+1])
                                  : (qm[i]  ^ dato[i+1]);
        qm[8] = xnor_scelto ? 1'b0 : 1'b1;
    end

    // ---------------------------------------------------- registro di stadio
    reg [8:0] qm_p;
    reg [1:0] ctrl_p;
    reg       de_p;

    always @(posedge clk_pix) begin
        qm_p   <= qm;
        ctrl_p <= ctrl;
        de_p   <= de;
    end

    // -------------------------------------------- disparita' di questo simbolo
    reg signed [4:0] uni_qm, zeri_qm, squilibrio;

    always @(*) begin
        uni_qm     = qm_p[0] + qm_p[1] + qm_p[2] + qm_p[3]
                   + qm_p[4] + qm_p[5] + qm_p[6] + qm_p[7];
        zeri_qm    = 5'sd8 - uni_qm;
        squilibrio = uni_qm - zeri_qm;          // da -8 a +8
    end

    // ------------------------------------------------------- 9 bit -> 10 bit
    // bias accumula la disparita'. Cinque bit con segno bastano: la prova in
    // tools/test_tmds.py non lo vede mai superare 8 in valore assoluto su
    // duecentomila simboli, contro un tetto di 15.
    reg signed [4:0] bias;

    always @(posedge clk_pix) begin
        if (rst_pix || !de_p) begin
            bias <= 5'sd0;
            case (ctrl_p)
                2'b00: tmds <= 10'b1101010100;
                2'b01: tmds <= 10'b0010101011;
                2'b10: tmds <= 10'b0101010100;
                2'b11: tmds <= 10'b1010101011;
            endcase
        end else if (bias == 5'sd0 || squilibrio == 5'sd0) begin
            // Nessuna preferenza da nessuna delle due parti: decide il nono
            // bit, e la disparita' del simbolo va tutta nel bias.
            if (qm_p[8] == 1'b0) begin
                tmds <= {2'b10, ~qm_p[7:0]};
                bias <= bias - squilibrio;
            end else begin
                tmds <= {2'b01,  qm_p[7:0]};
                bias <= bias + squilibrio;
            end
        end else if ((bias > 5'sd0 && squilibrio > 5'sd0) ||
                     (bias < 5'sd0 && squilibrio < 5'sd0)) begin
            // Bias e simbolo tirano dalla stessa parte: si inverte il payload
            // per tirare dall'altra.
            tmds <= {1'b1, qm_p[8], ~qm_p[7:0]};
            bias <= bias + (qm_p[8] ? 5'sd2 : 5'sd0) - squilibrio;
        end else begin
            tmds <= {1'b0, qm_p[8],  qm_p[7:0]};
            bias <= bias - (qm_p[8] ? 5'sd0 : 5'sd2) + squilibrio;
        end
    end

    // I due literal con segno non sono pignoleria. Scritti come
    // concatenazione — {3'b0, qm[8], 1'b0} — sarebbero SENZA segno, e in
    // Verilog basta un operando senza segno perche' tutta l'espressione lo
    // diventi, bias e squilibrio compresi. Il risultato tornerebbe lo stesso
    // per via dell'aritmetica modulo 32, ma per coincidenza, e una coincidenza
    // e' esattamente cio' che si rompe quando qualcuno allarga un registro.

endmodule

`default_nettype wire
