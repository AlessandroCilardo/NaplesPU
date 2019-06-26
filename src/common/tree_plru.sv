`timescale 1ns / 1ps
/*
 * Permette di ottenere la way LRU per un determinato set (interfaccia read_en + read_set).
 * L'uscita della way LRU avviene nello stesso colpo di clock.
 * 
 * L'accesso per poter ottenere la linea di cache meno utilizzata è arricchita di un'altra funzionalità:
 * settando le linee read_valids, è possibile ottenere le linee che non sono utilizzate.
 * Settare read_valids a tutti 1 per disabilitare la funzionalità.
 * 
 * Per aggiornare una way ad essere la MRU, utilizzare l'interfaccia update_xxx. L'effettivo aggiornamento
 * avviene internamente il colpo di clock successivo.
 * 
 * Per ogni interfaccia, i segnali devono essere inseriti tutti nello stesso colpo di clock
 */


module tree_plru #(

        parameter NUM_SETS        = 32,
        parameter NUM_WAYS        = 4, // Must be 1, 2, 4, or 8
        parameter SET_INDEX_WIDTH = $clog2(NUM_SETS),
        parameter WAY_INDEX_WIDTH = $clog2(NUM_WAYS)

    )(
        input                                  clk,

        input  logic                           read_en,
        input  logic [SET_INDEX_WIDTH - 1 : 0] read_set,
        input  logic [NUM_WAYS - 1 : 0]        read_valids,

        input  logic                           update_en,
        input  logic [SET_INDEX_WIDTH - 1 : 0] update_set,
        input  logic [WAY_INDEX_WIDTH - 1 : 0] update_way,

        output logic [WAY_INDEX_WIDTH - 1 : 0] read_way

    );


    logic [$clog2(NUM_WAYS) - 1 : 0] empty_way_idx; 
    logic                            there_is_empty_way;

    priority_encoder_npu #(
        .INPUT_WIDTH (NUM_WAYS)
    )
    u_priority_encoder (
        .decode( ~read_valids       ),
        .encode( empty_way_idx      ),
        .valid ( there_is_empty_way )
    );

    //--------------------------------------------------------------------------------------------------------------------------------------------------
    // --
    //--------------------------------------------------------------------------------------------------------------------------------------------------

    localparam LRU_FLAG_BITS =
    NUM_WAYS == 1 ? 1 :
    NUM_WAYS == 2 ? 1 :
    NUM_WAYS == 4 ? 3 :
    7; // NUM_WAYS = 8



    logic [LRU_FLAG_BITS - 1 : 0]    read_flags;
    logic [LRU_FLAG_BITS - 1 : 0]    update_flags_next;
    logic [LRU_FLAG_BITS - 1 : 0]    update_flags;

    logic [WAY_INDEX_WIDTH - 1 : 0]  lru_way;

    memory_bank_async_2r1w #(
        .SIZE      ( NUM_SETS      ),
        .COL_WIDTH ( LRU_FLAG_BITS ),
        .NB_COL    ( 1             )
    )
    u_memory_bank_async_2r1w (
        .clock        ( clk               ),
        .read1_enable ( read_en           ), //Word-wide asynchronous read enable
        .read1_address( read_set          ),
        .read2_enable ( update_en         ), //Word-wide asynchronous read enable
        .read2_address( update_set        ),
        .write_enable ( update_en         ), //Byte-wide synchronous write enable
        .write_address( update_set        ),
        .write_data   ( update_flags_next ),
        .read1_data   ( read_flags        ),
        .read2_data   ( update_flags      )
    );

    generate
        case (NUM_WAYS)

            1:
            begin
                assign lru_way              = 0;
                assign update_flags_next    = 0;

            end


            2:
            begin
                assign lru_way              = !update_flags[0];
                assign update_flags_next[0] = !update_way;
            end


            4:
            begin

                always_comb
                begin
                    casex (read_flags)
                        3'b00?: lru_way  = 0;
                        3'b10?: lru_way  = 1;
                        3'b?10: lru_way  = 2;
                        3'b?11: lru_way  = 3;
                        default: lru_way = '0;
                    endcase
                end

                always_comb
                begin
                    case (update_way)
                        2'd0: update_flags_next    = {2'b11, update_flags[0]};
                        2'd1: update_flags_next    = {2'b01, update_flags[0]};
                        2'd2: update_flags_next    = {update_flags[2], 2'b01};
                        2'd3: update_flags_next    = {update_flags[2], 2'b00};
                        default: update_flags_next = '0;
                    endcase
                end

            end

            8:
            begin
                always_comb
                begin
                    casex (read_flags)
                        7'b00?0???: lru_way = 0;
                        7'b10?0???: lru_way = 1;
                        7'b?100???: lru_way = 2;
                        7'b?110???: lru_way = 3;
                        7'b???100?: lru_way = 4;
                        7'b???110?: lru_way = 5;
                        7'b???1?10: lru_way = 6;
                        7'b???1?11: lru_way = 7;
                        default: lru_way    = '0;
                    endcase
                end

                always_comb
                begin
                    case (update_way)
                        3'd0: update_flags_next    = {2'b11, update_flags[5], 1'b1, update_flags[2:0]};
                        3'd1: update_flags_next    = {2'b01, update_flags[5], 1'b1, update_flags[2:0]};
                        3'd2: update_flags_next    = {update_flags[6], 3'b011, update_flags[2:0]};
                        3'd3: update_flags_next    = {update_flags[6], 3'b001, update_flags[2:0]};
                        3'd4: update_flags_next    = {update_flags[6:4], 3'b011, update_flags[0]};
                        3'd5: update_flags_next    = {update_flags[6:4], 3'b010, update_flags[0]};
                        3'd6: update_flags_next    = {update_flags[6:4], 2'b00, update_flags[1], 1'b1};
                        3'd7: update_flags_next    = {update_flags[6:4], 2'b00, update_flags[1], 1'b0};
                        default: update_flags_next = '0;
                    endcase
                end


            end

            default:
            begin
                initial
                begin
                    $display("%m invalid number of ways");
                    $finish;
                end
            end

        endcase
    endgenerate



    //--------------------------------------------------------------------------------------------------------------------------------------------------
    // --
    //--------------------------------------------------------------------------------------------------------------------------------------------------

    assign read_way          = there_is_empty_way ? empty_way_idx : lru_way;



endmodule
