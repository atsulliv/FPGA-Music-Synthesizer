`define SONG_WIDTH 7 // changed from 5b to 7b
`define ADDTL_ARG_WIDTH 4 // 1b for adv/note, 3b for metadata
`define NOTE_WIDTH 6
`define DURATION_WIDTH 6

// ----------------------------------------------
// Define State Assignments
// ----------------------------------------------
`define SWIDTH_SR 3
`define PAUSED             3'b000
`define RETRIEVE_DATA      3'b001
`define NEW_DATA_READY     3'b010
`define NEW_ADVANCE_READY  3'b011
`define NEW_NOTE_READY     3'b100
`define WAIT               3'b101
`define INCREMENT_ADDRESS  3'b110


module song_reader(
    // Exact same logic as solution code
    input clk,
    input reset,
    input play,
    input [1:0] song,
    output wire [5:0] note,
    output wire [5:0] duration,
    output wire song_done,

    // New Inputs
    input advance_done,
    input voice1_done,
    input voice2_done,
    input voice3_done,

    // New Outputs
    output wire new_advance,
    output wire new_note1,
    output wire new_note2,
    output wire new_note3


);
    wire [`SONG_WIDTH-1:0] curr_data_num, next_data_num;
    wire [`ADDTL_ARG_WIDTH + `NOTE_WIDTH + `DURATION_WIDTH - 1:0] rom_data_out;
    wire [`SONG_WIDTH + 1:0] rom_addr = {song, curr_data_num};

    wire [`SWIDTH_SR-1:0] state;
    reg  [`SWIDTH_SR-1:0] next;

    // For identifying when we reach the end of a song
    wire overflow;

    dffr #(`SONG_WIDTH) data_counter (
        .clk(clk),
        .r(reset),
        .d(next_data_num),
        .q(curr_data_num)
    );
    dffr #(`SWIDTH_SR) fsm (
        .clk(clk),
        .r(reset),
        .d(next),
        .q(state)
    );

    song_rom rom(.clk(clk), .addr(rom_addr), .dout(rom_data_out));

    // For identifying whether we load an advance or a note
    // *** 1 corresponds to an advance, 0 to a note
    wire data_msb = rom_data_out[15];

    always @(*) begin
        case (state)
            `PAUSED:            next = play ? `RETRIEVE_DATA : `PAUSED;
            `RETRIEVE_DATA:     next = play ? `NEW_DATA_READY : `PAUSED;
            `NEW_DATA_READY:    next = !play ? `PAUSED :
                                        (data_msb ? `NEW_ADVANCE_READY : `NEW_NOTE_READY);
            `NEW_ADVANCE_READY: next = play ? `WAIT : `PAUSED;
            `WAIT:              next = !play ? `PAUSED :
                                        (advance_done ? `INCREMENT_ADDRESS : `WAIT);
            `NEW_NOTE_READY:    next = play ? `INCREMENT_ADDRESS : `PAUSED;
            `INCREMENT_ADDRESS: next = (play && !overflow) ? `RETRIEVE_DATA : `PAUSED;
            default:            next = `PAUSED;
        endcase
    end

    // Determine which pipeline to load note to
    // Track which voices have been assigned since last advance
    wire [2:0] voices_used, next_voices_used;
    reg [2:0] temp_voice;


    // Reset voices_used when we process an advance, otherwise accumulate
    assign next_voices_used = (state == `NEW_ADVANCE_READY) ? 3'b000 :
                              (state == `NEW_NOTE_READY)    ? (voices_used | temp_voice) :
                                                               voices_used;

    dffr #(.WIDTH(3)) voices_used_reg (
        .clk(clk),
        .r(reset),
        .d(next_voices_used),
        .q(voices_used)
    );

    // Voices that are both idle (done) AND not yet used since last advance
    wire [2:0] voices_available = {voice3_done, voice2_done, voice1_done} & ~voices_used;
    
    // Select first available voice (priority: voice1 > voice2 > voice3)
    always @(*) begin
        casex(voices_available)
            3'bxx1:     temp_voice = 3'b001;  // Voice 1 available
            3'bx10:     temp_voice = 3'b010;  // Voice 2 available  
            3'b100:     temp_voice = 3'b100;  // Voice 3 available
            default:    temp_voice = 3'b000;  // None available
        endcase
    end

    assign {new_note3, new_note2, new_note1} = 
        (state == `NEW_NOTE_READY) ? temp_voice : 3'b000;

    assign {overflow, next_data_num} =
        (state == `INCREMENT_ADDRESS) ? {1'b0, curr_data_num} + 1
                                      : {1'b0, curr_data_num};
    assign new_advance = (state == `NEW_ADVANCE_READY);
    assign {note, duration} = {rom_data_out[14:9], rom_data_out[8:3]};
    assign song_done = overflow;
    
endmodule