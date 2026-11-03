// J20K — controller di memoria multi-porta
//
// Prototipo a tre porte (task #138: aggiunta blt_*, letto/scrittura a
// grana singola per il Blitter, stesso meccanismo della porta CPU — vedi
// il commento sulla porta 2 piu' sotto). Il primo passo verso il controller definitivo.
// Sostituisce il controller di riferimento, che era ottimizzato per la
// latenza e ne pagava il prezzo in portata: ogni accesso un ciclo completo
// con auto-precharge, 5 cicli per quattro byte, 48,6 MB/s di tetto.
//
// Le tre scelte che lo definiscono, e il perché.
//
// PRIORITÀ ALLA CPU. È l'unico consumatore sensibile alla latenza, e chiede
// circa 15 MB/s su oltre 200 disponibili: non può affamare nessuno. I motori
// DMA leggono in anticipo dentro buffer di riga e la latenza non la sentono.
// Passa per primo chi soffre di più ad aspettare — che è il contrario di
// quello che verrebbe istintivo, cioè dare la precedenza al video.
//
// BURST DA 8 WORD per la porta DMA, ma CONCATENABILI. Burst più lunghi
// darebbero più banda e costerebbero alla CPU una latenza che cresce in
// fretta: 256 word sono 32 cicli di bus del 68000 buttati via. La
// concatenazione dà la stessa banda senza quel prezzo, perché la catena si
// spezza appena la CPU chiede: 8 word restano l'unità di attesa, ma non sono
// più l'unità di avvio.
//
// (Qui c'era scritto che tutti i consumatori sommati chiedono il 31% del
// picco. Era sbagliato: il 31% di 243 fa 75 MB/s, meno del solo framebuffer
// del modo 4, che ne chiede 110,6. Il conto vero sta in
// controller_memoria.md §4-decies.)
//
// RIGA APERTA. La riga non si richiude dopo l'accesso: il controller ricorda
// quale riga e' aperta in ciascun banco e, se la richiesta successiva cade
// nella stessa, salta ACTIVATE. E' quello che fa divergere il sequenziale
// dallo sparso, e ne vale la pena: il modo video piu' esigente chiede 110,6
// MB/s, l'86% di quanto dava il controller a riga chiusa.
//
// REFRESH INTERNO. Il controller di riferimento lo delegava a chi lo usava,
// ed è una porta aperta sugli errori: basta dimenticarsene e la memoria perde
// i dati in modo silenzioso e intermittente. Qui è affare del controller.
//
// Mappatura degli indirizzi: il BANCO sta nei bit alti.
//   addr[9:2]   colonna   256 word = 1 KB per riga
//   addr[20:10] riga      2048 righe
//   addr[22:21] banco     una regione contigua da 2 MB ciascuno
//
// Non e' la disposizione ovvia. Quella ovvia mette il banco nei bit bassi
// perche' pagine consecutive cadano su banchi diversi, che e' cio' che serve
// all'interleaving fra accessi vicini. Ma qui l'interleaving che conta non e'
// quello fra due letture consecutive del video: e' quello fra il VIDEO e la
// CPU, che sono due flussi lontanissimi fra loro.
//
// Con il banco nei bit alti, framebuffer e codice stanno in banchi diversi per
// costruzione, e non si sfrattano mai le righe a vicenda. E il sequenziale non
// ci perde niente: la riga resta lunga 1 KB in entrambe le mappe, quindi i
// cambi di riga sono gli stessi — 1023 su 32768 burst contro 1020.

`default_nettype none

module j20k_sdram #(
    parameter FREQ  = 60_750_000,
    parameter BURST = 8            // word per burst della porta DMA
) (
    input  wire        clk,
    input  wire        clk_sdram,   // sfasato di 180°
    input  wire        rst_n,

    // ---- porta 0: CPU. Accesso singolo a 32 bit, priorità alta ----------
    input  wire        cpu_req,     // livello: voglio un accesso
    input  wire        cpu_we,      // 1 = scrittura
    input  wire [22:0] cpu_addr,    // indirizzo a byte
    input  wire [31:0] cpu_wdata,
    input  wire [3:0]  cpu_ben,     // byte da scrivere, attivi alti
    output reg  [31:0] cpu_rdata,
    output reg         cpu_acc,     // impulso: richiesta accettata
    output reg         cpu_ack,     // impulso: conclusa, dato valido se lettura
    output reg         cpu_da_buf,  // impulso: servita dal buffer, non dalla memoria

    // ---- porta 1: DMA. Burst di lettura ---------------------------------
    input  wire        dma_req,     // livello: voglio un burst
    input  wire [22:0] dma_addr,    // allineato a BURST*4 byte
    output reg  [31:0] dma_rdata,       // il dato buono
    output reg  [31:0] dma_rdata_tardi,  // mezzo ciclo dopo, solo diagnostica
    output reg         dma_acc,     // impulso: richiesta accettata
    output reg         dma_valid,   // un impulso per word
    output reg         dma_done,    // burst concluso

    // ---- porta 2: Blitter. Accesso singolo, lettura O scrittura ---------
    //
    // NON e' un terzo cliente di dma_req/dma_addr (quella resta un burst
    // fisso da 8 word pensato per righe video sequenziali, e resta cosi',
    // invariata, per non rimettere in discussione una macchina a stati gia'
    // verificata su hardware). Il Blitter chiede accessi a grana singola,
    // spesso non sequenziali (moduli, tre sorgenti a disallineamenti
    // diversi) — lo stesso identico bisogno che ha gia' la porta CPU. Qui
    // si riusa quel meccanismo (S_CPU/S_BLT condividono addr_lat/wdata_lat/
    // ben_lat/we_lat/t0/att_act, sono mutuamente esclusivi per costruzione)
    // invece di bufferizzare accessi parziali dentro j20k_blt.v.
    //
    // Priorita': sotto la CPU e sotto il burst video/sprite (vedi S_IDLE) —
    // il Blitter non ruba mai un ciclo a display o refresh, sulla falsariga
    // del bit DMAF_BLITHOG=0 di Amiga (cede il passo, non lo pretende).
    input  wire        blt_req,     // livello: voglio un accesso
    input  wire        blt_we,      // 1 = scrittura
    input  wire [22:0] blt_addr,    // indirizzo a byte
    input  wire [31:0] blt_wdata,
    input  wire [3:0]  blt_ben,     // byte da scrivere, attivi alti
    output reg  [31:0] blt_rdata,
    output reg         blt_acc,     // impulso: richiesta accettata
    output reg         blt_ack,     // impulso: conclusa, dato valido se lettura

    output reg         busy,        // il controller sta servendo qualcuno

    // ---- SDRAM ----------------------------------------------------------
    inout  wire [31:0] SDRAM_DQ,
    output reg  [10:0] SDRAM_A,
    output reg  [1:0]  SDRAM_BA,
    output wire        SDRAM_nCS,
    output reg         SDRAM_nWE,
    output reg         SDRAM_nRAS,
    output reg         SDRAM_nCAS,
    output wire        SDRAM_CLK,
    output wire        SDRAM_CKE,
    output reg  [3:0]  SDRAM_DQM
);

    // Tempi validati sull'hardware a 60,75 MHz nella verifica 3.
    localparam [3:0] CAS   = 4'd2;
    localparam [3:0] T_RP  = 4'd1;
    localparam [3:0] T_RCD = 4'd1;
    localparam [3:0] T_RC  = 4'd4;
    localparam [3:0] T_WR  = 4'd2;
    localparam [3:0] T_MRD = 4'd2;

    localparam [10:0] MODE_REG = {4'b0, CAS[2:0], 1'b0, 3'b000}; // BL=1, sequenziale

    // comandi: {nRAS, nCAS, nWE}
    localparam CMD_MODE   = 3'b000, CMD_REFRESH = 3'b001,
               CMD_PRE    = 3'b010, CMD_ACT     = 3'b011,
               CMD_WRITE  = 3'b100, CMD_READ    = 3'b101,
               CMD_NOP    = 3'b111;

    assign SDRAM_CLK = clk_sdram;
    assign SDRAM_CKE = 1'b1;
    assign SDRAM_nCS = 1'b0;

    reg        dq_oe;
    reg [31:0] dq_out;
    assign SDRAM_DQ = dq_oe ? dq_out : 32'bz;
    wire [31:0] dq_in = SDRAM_DQ;

    // Il dato si cattura sul fronte di DISCESA, non su quello di salita.
    //
    // Misurato: sul fronte di salita 29.875 word sbagliate su 524.288, sul
    // fronte di discesa zero. La finestra del dato si chiude prima del fronte
    // di salita, che cade proprio sulla transizione verso la word successiva.
    //
    // Il fronte di salita resta catturato lo stesso, come misura del margine
    // che rimane: se un domani tornasse a zero errori vorrebbe dire che la
    // finestra si e' spostata, e conviene saperlo prima che si sposti troppo.
    reg [31:0] dq_neg;
    always @(negedge clk) dq_neg <= dq_in;

    // scomposizione dell'indirizzo
    function [7:0]  col_of;  input [22:0] a; col_of  = a[9:2];   endfunction
    function [1:0]  bank_of; input [22:0] a; bank_of = a[22:21]; endfunction
    function [10:0] row_of;  input [22:0] a; row_of  = a[20:10]; endfunction

    // ------------------------------------------------------------ refresh
    // Interno: 4096 refresh ogni 64 ms, cioè uno ogni 15,6 µs. Si sta larghi
    // a 15 µs. Il contatore accumula le richieste arretrate, così un burst
    // lungo non fa perdere un refresh, lo rimanda soltanto.
    localparam REF_INTERVAL = FREQ / 1_000_000 * 15;

    reg [15:0] ref_timer;
    reg [3:0]  ref_debito;        // refresh dovuti e non ancora eseguiti

    // -------------------------------------------------------- macchina a stati
    localparam S_INIT = 3'd0, S_CONFIG = 3'd1, S_IDLE = 3'd2,
               S_CPU  = 3'd3, S_DMA    = 3'd4, S_REF  = 3'd5,
               S_BLT  = 3'd6;

    reg [2:0]  st;
    reg [4:0]  ctr;               // cicli dall'inizio dell'operazione
    reg [22:0] addr_lat;
    reg [31:0] wdata_lat;
    reg [3:0]  ben_lat;
    reg        we_lat;

    reg [14:0] init_cnt;          // attesa di 200 µs all'accensione

    // ------------------------------------------------- politica a riga aperta
    //
    // Il controller non richiude piu' la riga dopo ogni accesso. Tiene memoria
    // di quale riga e' aperta in ciascuno dei quattro banchi, e quando la
    // richiesta successiva cade nella stessa riga salta ACTIVATE del tutto.
    //
    // Tre casi, e l'unica cosa che cambia fra loro e' quando parte il primo
    // comando READ o WRITE:
    //
    //   riga gia' aperta        nessun preambolo         t0 = 0
    //   banco chiuso            ACTIVATE                 t0 = T_RCD
    //   riga sbagliata aperta   PRECHARGE poi ACTIVATE   t0 = T_RP + T_RCD
    //
    // Tutto il resto della sequenza scorre agganciato a t0. Non servono stati
    // nuovi e i tre casi non possono divergere per sbaglio, perche' sono lo
    // stesso codice con un'origine diversa.
    //
    // Sparisce anche l'attesa in coda: senza auto-precharge non c'e' piu' un
    // T_RP da aspettare dopo l'ultimo dato prima di liberare il controller.
    reg [3:0]  riga_valida;       // un bit per banco: c'e' una riga aperta?
    reg [10:0] riga_di [0:3];     // e quale
    reg [4:0]  t0;                // ciclo del primo comando
    reg        att_act;           // ACTIVATE ancora da emettere (caso miss)

    wire [1:0]  cpu_bk  = bank_of(cpu_addr);
    wire [10:0] cpu_rw  = row_of(cpu_addr);
    wire        cpu_hit = riga_valida[cpu_bk] && (riga_di[cpu_bk] == cpu_rw);
    wire        cpu_mis = riga_valida[cpu_bk] && (riga_di[cpu_bk] != cpu_rw);

    wire [1:0]  dma_bk  = bank_of(dma_addr);
    wire [10:0] dma_rw  = row_of(dma_addr);
    wire        dma_hit = riga_valida[dma_bk] && (riga_di[dma_bk] == dma_rw);
    wire        dma_mis = riga_valida[dma_bk] && (riga_di[dma_bk] != dma_rw);

    wire [1:0]  blt_bk  = bank_of(blt_addr);
    wire [10:0] blt_rw  = row_of(blt_addr);
    wire        blt_hit = riga_valida[blt_bk] && (riga_di[blt_bk] == blt_rw);
    wire        blt_mis = riga_valida[blt_bk] && (riga_di[blt_bk] != blt_rw);

    // ---------------------------------------- buffer di lettura della CPU
    //
    // Il 68000 ha il bus dati a 16 bit, la memoria e' a 32. Due letture
    // consecutive di codice cadono quindi nella stessa word, e la seconda non
    // ha bisogno di toccare la memoria: basta tenere l'ultima word letta.
    //
    // Non e' un'ottimizzazione di comodo. Sotto carico misto ogni accesso
    // della CPU costa 9,9 cicli al DMA, perche' lo sospende e gli fa
    // ricaricare la pipeline. Dimezzare gli accessi dimezza quel danno, ed e'
    // il modo piu' economico di farlo: una word, un'etichetta, un bit.
    //
    // Il colpo si serve in qualunque stato, senza passare da S_IDLE e senza
    // spezzare la catena del DMA. E' questo che lo rende quasi gratuito.
    reg [20:0] cpu_tag;       // addr[22:2] della word in buffer
    reg        cpu_tag_ok;
    reg [31:0] cpu_buf;

    wire cpu_colpo = cpu_tag_ok && !cpu_we && (cpu_addr[22:2] == cpu_tag);

    // ------------------------------------------------ concatenazione dei burst
    //
    // Un burst da 8 word costava 12 cicli: 8 di dati, 3 di riempimento della
    // pipeline CAS, 1 di ritorno in S_IDLE. I 4 di troppo sono un costo di
    // AVVIO, non di accesso, e si ripagavano a ogni burst anche quando il
    // burst precedente stava sulla stessa riga.
    //
    // Qui il flusso di comandi READ non si ferma piu' fra un burst e il
    // successivo: quando i comandi del burst corrente sono esauriti e la
    // richiesta seguente cade su una riga gia' aperta, viene accettata subito
    // e i suoi READ partono nello stesso ciclo. I dati escono continui.
    //
    // Il banco non ha dovuto cambiare per questo: teneva gia' dma_req alto e
    // presentava dma_addr della richiesta successiva appena quella corrente
    // era accettata. La richiesta seguente era gia' li' da guardare.
    //
    // La catena si spezza quando la CPU chiede o quando il refresh e' dovuto.
    // E' quello che tiene il conto della latenza: la CPU aspetta al piu' il
    // resto del burst in corso, 11 cicli, cioe' 1,4 cicli di bus del 68000.
    // ------------------------------------------- intreccio della porta CPU
    //
    // Durante un flusso concatenato il bus dei comandi e' pieno: un READ per
    // ciclo, una word per ciclo. Non ci sono fessure libere da regalare alla
    // CPU. Ma una fessura si puo' RUBARE, e costa un ciclo di dati invece dei
    // 9,9 che costava sospendere tutto e ricaricare la pipeline.
    //
    //   riga della CPU gia' aperta   READ                        1 ciclo
    //   banco chiuso                 ACTIVATE, READ              2 cicli
    //   riga sbagliata               PRECHARGE, ACTIVATE, READ   3 cicli
    //
    // I ritardi fra quei comandi si rispettano da soli: fra uno e l'altro
    // passa un ciclo di comandi del DMA, e T_RP e T_RCD valgono un ciclo.
    //
    // Due condizioni. La CPU deve stare su un BANCO DIVERSO da quello che il
    // DMA sta riversando, altrimenti il suo PRECHARGE chiuderebbe la riga del
    // DMA: e' per questo che il banco e' passato nei bit alti. E deve essere
    // una LETTURA, perche' una scrittura metterebbe dati sul bus DQ mentre ci
    // stanno passando quelli letti dal DMA. Fuori da questi due casi si torna
    // a sospendere, come prima.
    reg  [1:0] bk_dma;       // banco che il DMA sta riversando
    reg  [1:0] cpu_seq;      // 0 nulla, 1 tocca ACTIVATE, 2 tocca READ
    reg  [1:0] cpu_bk_l;     // banco, riga e colonna della CPU, agganciati
    reg  [10:0] cpu_rw_l;
    reg  [7:0] cpu_col_l;
    reg  [20:0] cpu_tag_l;
    reg        cpu_volo;     // c'e' una lettura CPU intrecciata in corso

    reg  [5:0] cmd_left;     // READ ancora da emettere per il burst accettato
    reg  [7:0] col_ptr;      // prossima colonna
    reg  [CAS:0] pipe;       // ritardo comando -> dato, CAS+1 stadi
    reg  [CAS:0] pipe_cpu;   // lo stesso, per il dato della CPU
    reg  [3:0] word_cnt;     // word consegnate nel burst corrente
    reg        avviato;      // il preambolo e' finito, i comandi possono uscire

    // La CPU si puo' intrecciare se legge e sta su un altro banco.
    wire cpu_intrec  = cpu_req && !cpu_colpo && !cpu_we && (cpu_bk != bk_dma);
    wire cpu_vuole   = cpu_intrec && !cpu_volo && (cpu_seq == 2'd0)
                       && !att_act;
    wire cpu_prende  = (cpu_seq != 2'd0) || cpu_vuole;
    // il ciclo in cui esce il READ della CPU: da li' partono i CAS+1 di attesa
    wire cpu_legge   = (st == S_DMA) &&
                       ((cpu_seq == 2'd2) || (cpu_vuole && cpu_hit));

    // Ne' un colpo nel buffer ne' una lettura intrecciata spezzano la catena:
    // il primo non tocca la memoria, la seconda ruba una fessura e basta.
    wire concatena   = dma_req && dma_hit && (ref_debito == 4'd0)
                       && (!cpu_req || cpu_colpo || cpu_intrec);
    wire dma_catena  = (cmd_left == 6'd0) && concatena;
    wire dma_emette  = (st == S_DMA) && (avviato || (ctr == t0)) && !cpu_prende &&
                       ((cmd_left != 6'd0) || dma_catena);
    wire [7:0] dma_col = (cmd_left != 6'd0) ? col_ptr : col_of(dma_addr);

    // Il dato si campiona CAS+1 cicli dopo il comando READ, non CAS. Il
    // comando e' assegnato con assegnazione non bloccante, quindi compare sui
    // piedini nel ciclo DOPO quello in cui lo si scrive, e solo da li' partono
    // i cicli di latenza CAS. Ed e' catturato sul fronte di DISCESA: vedi il
    // commento su dq_neg piu' sopra.

    always @(posedge clk) begin
        {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_NOP;
        cpu_acc    <= 1'b0;
        cpu_ack    <= 1'b0;
        cpu_da_buf <= 1'b0;
        dma_acc   <= 1'b0;
        dma_valid <= 1'b0;
        dma_done  <= 1'b0;
        blt_acc   <= 1'b0;
        blt_ack   <= 1'b0;

        if (!rst_n) begin
            st        <= S_INIT;
            ctr       <= 5'd0;
            init_cnt  <= 15'd0;
            ref_timer <= 16'd0;
            ref_debito<= 4'd0;
            dq_oe     <= 1'b0;
            busy      <= 1'b1;
            SDRAM_DQM <= 4'b1111;
            riga_valida <= 4'b0000;   // S_CONFIG chiude tutti i banchi
            att_act     <= 1'b0;
            t0          <= 5'd0;
            cpu_tag_ok  <= 1'b0;
            bk_dma      <= 2'd0;
            cpu_seq     <= 2'd0;
            cpu_volo    <= 1'b0;
            pipe_cpu    <= {(CAS+1){1'b0}};
            cmd_left    <= 6'd0;
            col_ptr     <= 8'd0;
            pipe        <= {(CAS+1){1'b0}};
            word_cnt    <= 4'd0;
            avviato     <= 1'b0;
        end else begin
            // orologio del refresh, indipendente da tutto il resto
            if (ref_timer >= REF_INTERVAL[15:0]) begin
                ref_timer <= 16'd0;
                if (ref_debito != 4'hF) ref_debito <= ref_debito + 4'd1;
            end else begin
                ref_timer <= ref_timer + 16'd1;
            end

            ctr <= ctr + 5'd1;

            // La lettura intrecciata della CPU torna CAS+1 cicli dopo il suo
            // comando, in mezzo ai dati del DMA. La pipeline la porta su un
            // secondo binario: e' tutto quello che serve per non confonderla.
            pipe_cpu <= {pipe_cpu[CAS-1:0], cpu_legge};
            if (pipe_cpu[CAS]) begin
                cpu_rdata  <= dq_neg;
                cpu_buf    <= dq_neg;
                cpu_tag    <= cpu_tag_l;
                cpu_tag_ok <= 1'b1;
                cpu_ack    <= 1'b1;
                cpu_volo   <= 1'b0;
            end

            // ACTIVATE rimandato. Nel caso di riga sbagliata il PRECHARGE e'
            // partito in S_IDLE e l'ACTIVATE tocca T_RP cicli dopo, dentro lo
            // stato di accesso.
            //
            // Sta PRIMA del case, quindi il case puo' sovrascriverne il
            // comando. Con il solo DMA non poteva succedere - quando att_act e'
            // alto t0 vale T_RP+T_RCD, e il primo READ e' sempre piu' in la' -
            // ma la CPU intrecciata ruba fessure a qualunque ciclo, compreso
            // questo. E il danno non sarebbe l'ACTIVATE perso: sarebbe che
            // riga_valida viene alzata lo stesso, e il controller crede aperta
            // una riga che non e' mai stata attivata.
            //
            // Per questo cpu_vuole richiede !att_act: la fessura di questo
            // ciclo e' gia' prenotata.
            if (att_act && (st == S_CPU || st == S_DMA || st == S_BLT) && ctr == T_RP - 4'd1) begin
                {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_ACT;
                SDRAM_A <= row_of(addr_lat);
                riga_valida[bank_of(addr_lat)] <= 1'b1;
                riga_di[bank_of(addr_lat)]     <= row_of(addr_lat);
                att_act <= 1'b0;
            end

            // Colpo nel buffer: si risponde subito, in qualunque stato, senza
            // toccare la memoria e senza disturbare il burst in corso.
            if (cpu_req && cpu_colpo && st != S_INIT && st != S_CONFIG) begin
                cpu_rdata  <= cpu_buf;
                cpu_acc    <= 1'b1;
                cpu_ack    <= 1'b1;
                cpu_da_buf <= 1'b1;
            end

            case (st)

            // 200 µs di attesa all'accensione, come vuole la SDRAM
            S_INIT: begin
                if (init_cnt >= FREQ/1000*200/1000) begin
                    st  <= S_CONFIG;
                    ctr <= 5'd0;
                end else begin
                    init_cnt <= init_cnt + 15'd1;
                end
            end

            // precharge di tutti i banchi, due refresh, registro di modo
            S_CONFIG: begin
                case (ctr)
                    5'd0: begin
                        {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_PRE;
                        SDRAM_A[10] <= 1'b1;          // tutti i banchi
                    end
                    T_RP:            {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_REFRESH;
                    T_RP+T_RC:       {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_REFRESH;
                    T_RP+T_RC+T_RC: begin
                        {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_MODE;
                        SDRAM_A  <= MODE_REG;
                        SDRAM_BA <= 2'b00;
                    end
                    T_RP+T_RC+T_RC+T_MRD: begin
                        st   <= S_IDLE;
                        busy <= 1'b0;
                    end
                    default: ;
                endcase
            end

            // Arbitraggio. L'ordine è la politica: prima la CPU, che è
            // l'unica a soffrire l'attesa; poi il refresh, che non può
            // aspettare all'infinito; infine il DMA, che legge in anticipo.
            S_IDLE: begin
                ctr  <= 5'd0;
                busy <= 1'b0;
                if (cpu_req && !cpu_colpo) begin
                    addr_lat  <= cpu_addr;
                    wdata_lat <= cpu_wdata;
                    ben_lat   <= cpu_ben;
                    we_lat    <= cpu_we;
                    if (cpu_we) cpu_tag_ok <= 1'b0;
                    SDRAM_BA  <= cpu_bk;
                    st        <= S_CPU;
                    busy      <= 1'b1;
                    cpu_acc   <= 1'b1;
                    if (cpu_hit) begin
                        t0 <= 5'd0;  att_act <= 1'b0;
                    end else if (cpu_mis) begin
                        {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_PRE;
                        SDRAM_A <= 11'd0;            // A10=0: solo questo banco
                        t0 <= T_RP + T_RCD;  att_act <= 1'b1;
                    end else begin
                        {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_ACT;
                        SDRAM_A <= cpu_rw;
                        riga_valida[cpu_bk] <= 1'b1;
                        riga_di[cpu_bk]     <= cpu_rw;
                        t0 <= T_RCD;  att_act <= 1'b0;
                    end
                end else if (ref_debito != 4'd0) begin
                    // AUTO_REFRESH vuole tutti i banchi chiusi. Con la riga
                    // aperta non lo sono piu' da soli: va chiuso qui.
                    {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_PRE;
                    SDRAM_A     <= 11'b100_0000_0000;   // A10=1: tutti i banchi
                    riga_valida <= 4'b0000;
                    ref_debito  <= ref_debito - 4'd1;
                    st          <= S_REF;
                    busy        <= 1'b1;
                end else if (dma_req) begin
                    addr_lat  <= dma_addr;
                    SDRAM_BA  <= dma_bk;
                    st        <= S_DMA;
                    busy      <= 1'b1;
                    dma_acc   <= 1'b1;
                    cmd_left  <= BURST;
                    col_ptr   <= col_of(dma_addr);
                    bk_dma    <= dma_bk;
                    word_cnt  <= 4'd0;
                    pipe      <= {(CAS+1){1'b0}};
                    if (dma_hit) begin
                        t0 <= 5'd0;  att_act <= 1'b0;  avviato <= 1'b1;
                    end else if (dma_mis) begin
                        {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_PRE;
                        SDRAM_A <= 11'd0;
                        t0 <= T_RP + T_RCD;  att_act <= 1'b1;  avviato <= 1'b0;
                    end else begin
                        {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_ACT;
                        SDRAM_A <= dma_rw;
                        riga_valida[dma_bk] <= 1'b1;
                        riga_di[dma_bk]     <= dma_rw;
                        t0 <= T_RCD;  att_act <= 1'b0;  avviato <= 1'b0;
                    end
                end else if (blt_req) begin
                    // ultima priorita': dopo CPU, refresh e burst video/
                    // sprite. Stesso schema esatto di cpu_hit/cpu_mis sopra,
                    // solo sul banco/riga del Blitter.
                    addr_lat  <= blt_addr;
                    wdata_lat <= blt_wdata;
                    ben_lat   <= blt_ben;
                    we_lat    <= blt_we;
                    SDRAM_BA  <= blt_bk;
                    st        <= S_BLT;
                    busy      <= 1'b1;
                    blt_acc   <= 1'b1;
                    if (blt_hit) begin
                        t0 <= 5'd0;  att_act <= 1'b0;
                    end else if (blt_mis) begin
                        {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_PRE;
                        SDRAM_A <= 11'd0;
                        t0 <= T_RP + T_RCD;  att_act <= 1'b1;
                    end else begin
                        {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_ACT;
                        SDRAM_A <= blt_rw;
                        riga_valida[blt_bk] <= 1'b1;
                        riga_di[blt_bk]     <= blt_rw;
                        t0 <= T_RCD;  att_act <= 1'b0;
                    end
                end
            end

            // accesso singolo della CPU. A10 resta a zero: la riga non si
            // chiude piu' da sola, e la prossima richiesta la trova aperta.
            S_CPU: begin
                if (ctr == t0) begin
                    {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= we_lat ? CMD_WRITE : CMD_READ;
                    SDRAM_A   <= {1'b0, 2'b00, col_of(addr_lat)};
                    SDRAM_DQM <= we_lat ? ~ben_lat : 4'b0000;
                    if (we_lat) begin
                        dq_out <= wdata_lat;
                        dq_oe  <= 1'b1;
                    end
                end
                if (ctr == t0 + 5'd1) dq_oe <= 1'b0;

                if (!we_lat && ctr == t0 + CAS + 5'd1) begin
                    cpu_rdata  <= dq_neg;
                    cpu_buf    <= dq_neg;
                    cpu_tag    <= addr_lat[22:2];
                    cpu_tag_ok <= 1'b1;
                end

                // In scrittura basta rispettare T_WR: il PRECHARGE non c'e'
                // piu' qui, e quando servira' sara' almeno tre cicli dopo.
                if (ctr == (we_lat ? (t0 + T_WR) : (t0 + CAS + 5'd1))) begin
                    cpu_ack <= 1'b1;
                    st      <= S_IDLE;
                end
            end

            // accesso singolo del Blitter: stesso schema esatto di S_CPU,
            // stessi registri agganciati (addr_lat/wdata_lat/ben_lat/
            // we_lat/t0) — mutuamente esclusivi con S_CPU per costruzione,
            // quindi nessun conflitto nel riusarli.
            S_BLT: begin
                if (ctr == t0) begin
                    {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= we_lat ? CMD_WRITE : CMD_READ;
                    SDRAM_A   <= {1'b0, 2'b00, col_of(addr_lat)};
                    SDRAM_DQM <= we_lat ? ~ben_lat : 4'b0000;
                    if (we_lat) begin
                        dq_out <= wdata_lat;
                        dq_oe  <= 1'b1;
                    end
                end
                if (ctr == t0 + 5'd1) dq_oe <= 1'b0;

                if (!we_lat && ctr == t0 + CAS + 5'd1) begin
                    blt_rdata <= dq_neg;
                end

                if (ctr == (we_lat ? (t0 + T_WR) : (t0 + CAS + 5'd1))) begin
                    blt_ack <= 1'b1;
                    st      <= S_IDLE;
                end
            end

            // Burst di lettura concatenabili. Il flusso di comandi non si ferma
            // fra un burst e il successivo se questo cade su una riga aperta,
            // e la CPU puo' rubare una fessura senza fermarlo.
            S_DMA: begin
                pipe <= {pipe[CAS-1:0], dma_emette};

                // ---- fessura rubata dalla CPU: ha la precedenza ----
                if (cpu_seq == 2'd1) begin
                    {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_ACT;
                    SDRAM_BA <= cpu_bk_l;
                    SDRAM_A  <= cpu_rw_l;
                    riga_valida[cpu_bk_l] <= 1'b1;
                    riga_di[cpu_bk_l]     <= cpu_rw_l;
                    cpu_seq <= 2'd2;
                end else if (cpu_seq == 2'd2) begin
                    {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_READ;
                    SDRAM_BA  <= cpu_bk_l;
                    SDRAM_A   <= {1'b0, 2'b00, cpu_col_l};
                    SDRAM_DQM <= 4'b0000;
                    cpu_seq   <= 2'd0;
                end else if (cpu_vuole) begin
                    cpu_acc   <= 1'b1;
                    cpu_volo  <= 1'b1;
                    cpu_bk_l  <= cpu_bk;
                    cpu_rw_l  <= cpu_rw;
                    cpu_col_l <= col_of(cpu_addr);
                    cpu_tag_l <= cpu_addr[22:2];
                    SDRAM_BA  <= cpu_bk;
                    if (cpu_hit) begin
                        {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_READ;
                        SDRAM_A   <= {1'b0, 2'b00, col_of(cpu_addr)};
                        SDRAM_DQM <= 4'b0000;
                        cpu_seq   <= 2'd0;
                    end else if (cpu_mis) begin
                        {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_PRE;
                        SDRAM_A <= 11'd0;           // A10=0: solo questo banco
                        cpu_seq <= 2'd1;
                    end else begin
                        {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_ACT;
                        SDRAM_A <= cpu_rw;
                        riga_valida[cpu_bk] <= 1'b1;
                        riga_di[cpu_bk]     <= cpu_rw;
                        cpu_seq <= 2'd2;
                    end

                // ---- altrimenti il flusso del DMA ----
                end else if (dma_emette) begin
                    {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_READ;
                    SDRAM_BA  <= bk_dma;      // la CPU puo' averlo cambiato
                    SDRAM_A   <= {1'b0, 2'b00, dma_col};
                    SDRAM_DQM <= 4'b0000;
                    col_ptr   <= dma_col + 8'd1;
                    avviato   <= 1'b1;
                    if (dma_catena) begin
                        // aggancio: il burst successivo parte senza un ciclo
                        // di pausa, e il suo primo READ e' questo qui
                        SDRAM_BA <= dma_bk;
                        bk_dma   <= dma_bk;
                        addr_lat <= dma_addr;
                        dma_acc  <= 1'b1;
                        cmd_left <= BURST - 1;
                    end else begin
                        cmd_left <= cmd_left - 6'd1;
                    end
                end

                // ---- lato dati, CAS+1 cicli piu' tardi ----
                if (pipe[CAS]) begin
                    dma_rdata       <= dq_neg;
                    dma_rdata_tardi <= dq_in;
                    dma_valid       <= 1'b1;
                    if (word_cnt == BURST - 1) begin
                        word_cnt <= 4'd0;
                        dma_done <= 1'b1;
                    end else begin
                        word_cnt <= word_cnt + 4'd1;
                    end
                end

                // Uscita. Va controllata a OGNI ciclo, non all'arrivo
                // dell'ultimo dato del DMA: la lettura intrecciata della CPU
                // puo' concludersi dopo, e in quel caso non arriverebbe piu'
                // nessun impulso a far rivalutare la condizione. E' esattamente
                // cosi' che questa macchina si e' piantata la prima volta.
                if (cmd_left == 6'd0 && !concatena && !dma_emette
                    && !cpu_prende && cpu_seq == 2'd0
                    && pipe     == {(CAS+1){1'b0}}
                    && pipe_cpu == {(CAS+1){1'b0}})
                    st <= S_IDLE;
            end

            // PRECHARGE di tutti i banchi emesso in S_IDLE, poi il refresh
            S_REF: begin
                if (ctr == T_RP - 4'd1)
                    {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_REFRESH;
                if (ctr == T_RP + T_RC) st <= S_IDLE;
            end

            default: st <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
