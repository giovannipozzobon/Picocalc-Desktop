// PicoCalc HDMI Mirror - lettore di righe (dominio clk_sys)
//
// Tiene nei due banchi del buffer di riga la riga sorgente `show` (quella che
// il video sta mostrando) e la successiva, leggendole dalla SDRAM con la porta
// DMA di j20k_sdram: 20 burst da 8 word = 160 word = 320 pixel. La riga di
// memoria si ricava da `show` con scroll_map. `show` arriva dal dominio pixel
// in codice Gray (cambia di 1 alla volta) e si sincronizza con due flip-flop.
//
// Quando il video passa a show+1 legge dal banco che il lettore aveva gia'
// riempito, e il banco appena liberato si ricarica con show+2: il lettore ha
// due righe video (circa 44 us) per farlo.

`default_nettype none

module fb_read (
    input  wire        clk,
    input  wire        rst,

    input  wire [8:0]  show_gray,       // asincrono: dominio pixel
    input  wire [9:0]  tfa,             // asincroni: dominio QSPI (quasi statici)
    input  wire [9:0]  vsam,
    input  wire [9:0]  vsp,

    output reg         dma_req,
    output reg  [22:0] dma_addr,
    input  wire        dma_acc,
    input  wire        dma_valid,
    input  wire [31:0] dma_rdata,

    output reg         lb_we,
    output reg  [8:0]  lb_waddr,
    output reg  [31:0] lb_wdata
);

    // ---- sincronizzatori ----
    reg [8:0] sg1, sg2;
    reg [9:0] tfa1, tfa2, vsam1, vsam2, vsp1, vsp2;
    always @(posedge clk) begin
        sg1 <= show_gray; sg2 <= sg1;
        tfa1 <= tfa;   tfa2 <= tfa1;
        vsam1 <= vsam; vsam2 <= vsam1;
        vsp1 <= vsp;   vsp2 <= vsp1;
    end
    // Gray -> binario
    reg [8:0] show;
    integer i;
    always @* begin
        show[8] = sg2[8];
        for (i = 7; i >= 0; i = i - 1) show[i] = show[i+1] ^ sg2[i];
    end

    // ---- stato dei banchi ----
    reg        valid0, valid1;
    reg [8:0]  tag0, tag1;

    wire [8:0] show1 = show + 9'd1;
    wire       va = show[0]  ? valid1 : valid0;
    wire [8:0] ta = show[0]  ? tag1   : tag0;
    wire       vb = show1[0] ? valid1 : valid0;
    wire [8:0] tb = show1[0] ? tag1   : tag0;
    wire ld_a = va && (ta == show);
    wire ld_b = vb && (tb == show1);

    wire need_a = !ld_a;
    wire need_b = ld_a && !ld_b && (show1 <= 9'd319);

    // ---- scroll_map: riga sorgente -> riga di memoria ----
    reg  [9:0] v_in;
    wire [9:0] row;
    scroll_map u_map (.clk(clk), .v(v_in), .tfa(tfa2), .vsam(vsam2), .vsp(vsp2), .row(row));

    localparam S_IDLE = 3'd0, S_MAP = 3'd1, S_BASE = 3'd2, S_RUN = 3'd3;
    reg [2:0]  st;
    reg [1:0]  wait_c;
    reg [8:0]  cur_t;
    reg        cur_b;
    reg [22:0] base;
    reg [4:0]  burst;
    reg [7:0]  wcnt;
    reg        req_done;       // tutti i 20 burst accettati

    always @(posedge clk) begin
        lb_we <= 1'b0;
        if (rst) begin
            st <= S_IDLE; dma_req <= 1'b0; valid0 <= 1'b0; valid1 <= 1'b0;
            tag0 <= 9'd0; tag1 <= 9'd0;
        end else case (st)
            S_IDLE: begin
                if (need_a || need_b) begin
                    cur_t <= need_a ? show : show1;
                    cur_b <= need_a ? show[0] : show1[0];
                    v_in  <= {1'b0, need_a ? show : show1};
                    wait_c <= 2'd0;
                    if (need_a ? show[0] : show1[0]) valid1 <= 1'b0; else valid0 <= 1'b0;
                    st <= S_MAP;
                end
            end
            S_MAP: begin                    // scroll_map ha 1 ciclo di latenza
                wait_c <= wait_c + 2'd1;
                if (wait_c == 2'd1) st <= S_BASE;
            end
            S_BASE: begin
                base     <= ({13'd0, row} << 9) + ({13'd0, row} << 7);   // riga * 640 byte
                dma_addr <= ({13'd0, row} << 9) + ({13'd0, row} << 7);
                dma_req  <= 1'b1;
                burst    <= 5'd0;
                wcnt     <= 8'd0;
                req_done <= 1'b0;
                st       <= S_RUN;
            end
            S_RUN: begin
                if (dma_acc && dma_req) begin
                    if (burst == 5'd19) begin
                        dma_req  <= 1'b0;
                        req_done <= 1'b1;
                    end else begin
                        burst    <= burst + 5'd1;
                        dma_addr <= dma_addr + 23'd32;
                    end
                end
                if (dma_valid) begin
                    lb_we    <= 1'b1;
                    lb_waddr <= {cur_b, wcnt};
                    lb_wdata <= dma_rdata;
                    wcnt     <= wcnt + 8'd1;
                    if (wcnt == 8'd159) begin
                        if (cur_b) begin valid1 <= 1'b1; tag1 <= cur_t; end
                        else       begin valid0 <= 1'b1; tag0 <= cur_t; end
                        st <= S_IDLE;
                    end
                end
            end
            default: st <= S_IDLE;
        endcase
    end

endmodule

`default_nettype wire
