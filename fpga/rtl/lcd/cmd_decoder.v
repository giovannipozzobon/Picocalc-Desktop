// PicoCalc HDMI Mirror - cmd_decoder: emulazione del sottoinsieme ST7365P
//
// Consuma il flusso di byte di qspi_rx e produce scritture di pixel nella memoria del display (320 x 480) piu'
// i registri che servono al lato video (scroll, inversione, display on/off).
//
// Pacchetti: tipo 0x00 CMD (1 byte: codice comando), 0x01 DATA (N byte di
// parametri o pixel), 0x80 CTRL (0x01 = reset dello stato, memoria intatta).
// I parametri DATA proseguono sul comando corrente anche attraverso piu'
// pacchetti (il firmware spedisce un pacchetto per ogni lcd_write_data).
//
// RAMWR: cursore a (XS,YS), ogni 2 byte un pixel RGB565 MSB first, x++ e a
// fine riga x = XS, y++; oltre YE i pixel sono scartati.
//
// Pixel fuori da 320 x 480 non vengono scritti. Il lato video riceve:
//   tfa, vsam, vsp  per scroll_map; vsam = 480 - TFA - BFA se
//   USE_VSCRDEF_VSA = 0 (default, vedi nota in scroll_map.v), altrimenti il
//   VSA di VSCRDEF.

`default_nettype none

module cmd_decoder #(
    parameter USE_VSCRDEF_VSA = 0
) (
    input  wire        clk,
    input  wire        rst,

    input  wire        byte_valid,
    input  wire [7:0]  byte_data,
    input  wire        byte_first,
    input  wire        pkt_end,

    output reg         wr_valid,      // impulso: scrivi wr_data in (wr_x, wr_y)
    output reg  [8:0]  wr_x,          // 0..319
    output reg  [8:0]  wr_y,          // 0..479 (riga di memoria)
    output reg  [15:0] wr_data,

    output wire [9:0]  tfa,
    output wire [9:0]  vsam,
    output wire [9:0]  vsp,
    output reg  [7:0]  madctl,
    output reg         inv_on,
    output reg         disp_on,
    output reg         resync_pulse   // CTRL 0x01 ricevuto
);

    localparam [7:0] T_CMD = 8'h00, T_DATA = 8'h01, T_CTRL = 8'h80;

    localparam [7:0] C_SWRESET = 8'h01, C_INVOFF = 8'h20, C_INVON = 8'h21,
                     C_DISPOFF = 8'h28, C_DISPON = 8'h29, C_CASET = 8'h2A,
                     C_RASET = 8'h2B, C_RAMWR = 8'h2C, C_VSCRDEF = 8'h33,
                     C_MADCTL = 8'h36, C_VSCSAD = 8'h37;

    reg [7:0]  ptype;           // tipo del pacchetto in corso
    reg [7:0]  cmd;             // comando corrente
    reg [2:0]  pidx;            // indice del parametro
    reg [15:0] xs, xe, ys, ye;
    reg [15:0] tfa_r, vsa_r, bfa_r, vsp_r;

    // cursore RAMWR
    reg [15:0] cx, cy;
    reg        past_end;
    reg        hi_valid;
    reg [7:0]  hi_byte;

    wire [15:0] vsam_mem = 16'd480 - tfa_r - bfa_r;
    assign tfa  = tfa_r[9:0];
    assign vsp  = vsp_r[9:0];
    assign vsam = USE_VSCRDEF_VSA ? vsa_r[9:0] : vsam_mem[9:0];

    task defaults;
        begin
            xs <= 16'd0; xe <= 16'd319; ys <= 16'd0; ye <= 16'd479;
            tfa_r <= 16'd0; vsa_r <= 16'd480; bfa_r <= 16'd0; vsp_r <= 16'd0;
            madctl <= 8'h00; inv_on <= 1'b0; disp_on <= 1'b0;
            hi_valid <= 1'b0; past_end <= 1'b1;
            cmd <= 8'h00; pidx <= 3'd0;
        end
    endtask

    wire is_ramwr = (cmd == C_RAMWR);

    always @(posedge clk) begin
        wr_valid     <= 1'b0;
        resync_pulse <= 1'b0;

        if (rst) begin
            defaults;
            ptype <= 8'hFF;
            cx <= 16'd0; cy <= 16'd0;
        end else if (byte_valid) begin
            if (byte_first) begin
                ptype <= byte_data;           // il tipo non e' un dato
            end else case (ptype)

                T_CTRL: if (byte_data == 8'h01) begin
                    defaults;
                    resync_pulse <= 1'b1;
                end

                T_CMD: begin
                    cmd  <= byte_data;
                    pidx <= 3'd0;
                    case (byte_data)
                        C_SWRESET: defaults;
                        C_INVOFF:  inv_on  <= 1'b0;
                        C_INVON:   inv_on  <= 1'b1;
                        C_DISPOFF: disp_on <= 1'b0;
                        C_DISPON:  disp_on <= 1'b1;
                        C_RAMWR: begin
                            cx <= xs; cy <= ys;
                            past_end <= 1'b0;
                            hi_valid <= 1'b0;
                        end
                        default: ;
                    endcase
                end

                T_DATA: begin
                    case (cmd)
                        C_CASET: begin
                            case (pidx)
                                3'd0: xs[15:8] <= byte_data;
                                3'd1: xs[7:0]  <= byte_data;
                                3'd2: xe[15:8] <= byte_data;
                                3'd3: xe[7:0]  <= byte_data;
                                default: ;
                            endcase
                            pidx <= (pidx == 3'd7) ? pidx : pidx + 3'd1;
                        end
                        C_RASET: begin
                            case (pidx)
                                3'd0: ys[15:8] <= byte_data;
                                3'd1: ys[7:0]  <= byte_data;
                                3'd2: ye[15:8] <= byte_data;
                                3'd3: ye[7:0]  <= byte_data;
                                default: ;
                            endcase
                            pidx <= (pidx == 3'd7) ? pidx : pidx + 3'd1;
                        end
                        C_VSCRDEF: begin
                            case (pidx)
                                3'd0: tfa_r[15:8] <= byte_data;
                                3'd1: tfa_r[7:0]  <= byte_data;
                                3'd2: vsa_r[15:8] <= byte_data;
                                3'd3: vsa_r[7:0]  <= byte_data;
                                3'd4: bfa_r[15:8] <= byte_data;
                                3'd5: bfa_r[7:0]  <= byte_data;
                                default: ;
                            endcase
                            pidx <= (pidx == 3'd7) ? pidx : pidx + 3'd1;
                        end
                        C_VSCSAD: begin
                            if (pidx == 3'd0) vsp_r[15:8] <= byte_data;
                            if (pidx == 3'd1) vsp_r[7:0]  <= byte_data;
                            pidx <= (pidx == 3'd7) ? pidx : pidx + 3'd1;
                        end
                        C_MADCTL: madctl <= byte_data;
                        C_RAMWR: begin
                            if (!hi_valid) begin
                                hi_byte  <= byte_data;
                                hi_valid <= 1'b1;
                            end else begin
                                hi_valid <= 1'b0;
                                if (!past_end) begin
                                    if (cx < 16'd320 && cy < 16'd480) begin
                                        wr_valid <= 1'b1;
                                        wr_x     <= cx[8:0];
                                        wr_y     <= cy[8:0];
                                        wr_data  <= {hi_byte, byte_data};
                                    end
                                    if (cx >= xe) begin
                                        cx <= xs;
                                        if (cy >= ye) past_end <= 1'b1;
                                        else          cy <= cy + 16'd1;
                                    end else begin
                                        cx <= cx + 16'd1;
                                    end
                                end
                            end
                        end
                        default: ;       // consumato e ignorato
                    endcase
                end

                default: ;
            endcase
        end
    end

endmodule

`default_nettype wire
