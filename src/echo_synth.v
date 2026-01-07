`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Stanford EE108
// Engineer: Joseph Shull
// 
// Create Date: 12/02/2025 10:55:15 PM
// Design Name: final project
// Module Name: echo_synth
// Description: 
//
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module echo_synth #(parameter WIDTH = 16       // note_sample is 16 bits wide
    )(
    input [15:0] note_sample_in,
    input note_sample_ready, // 48kHz validation signal
    input rst,
    input profile,
    output [15:0] note_sample_out
    );
    
    wire signed [15:0] note_sample_in_half = $signed(note_sample_in) >>> 1; // this is nessecary to prevent clipping as we can assume that we will have 100% input
    
    // ECHO 1  (100ms) --------------------------------------------------------------------------------------------
    localparam DELAY_1 = 4800;  // 0.1s of 48kHz validation signal
    reg [15:0] note_sample_echo1;
    localparam addr_width_1 = $clog2(DELAY_1);  // Calculate address width
    reg [WIDTH-1:0] mem1 [0:DELAY_1-1]; // declares an array of registers, each element is a vector of [0:DELAY_1-1]
    reg [addr_width_1-1:0] addr1;   // Address pointer
    always @(posedge note_sample_ready) begin
        if (rst) begin
            addr1 <= 0;
            note_sample_echo1 <= 0;
        end 
        else begin
            note_sample_echo1 <= mem1[addr1];   // Read old data
            mem1[addr1] <= note_sample_in_half; // Write new data
            addr1 <= addr1 + 1'b1;  // Increment circular pointer
        end
    end
    wire signed [15:0] note_sample_echo1_wire;
    assign note_sample_echo1_wire = $signed(note_sample_echo1);
    
    // ECHO 2  (200ms) --------------------------------------------------------------------------------------------
    localparam DELAY_2 = 9600;  // 0.2s of 48kHz validation signal
    reg [15:0] note_sample_echo2;
    localparam addr_width_2 = $clog2(DELAY_2);  // Calculate address width
    reg [WIDTH-1:0] mem2 [0:DELAY_2-1]; // declares an array of registers, each element is a vector of [0:DELAY_1-1]
    reg [addr_width_2-1:0] addr2;   // Address pointer
    always @(posedge note_sample_ready) begin
        if (rst) begin
            addr2 <= 0;
            note_sample_echo2 <= 0;
        end 
        else begin
            note_sample_echo2 <= mem2[addr2];   // Read old data
            mem2[addr2] <= note_sample_in_half; // Write new data
            addr2 <= addr2 + 1'b1;  // Increment circular pointer
        end
    end
    wire signed [15:0] note_sample_echo2_wire;
    assign note_sample_echo2_wire = $signed(note_sample_echo2);
    
    // ECHO 3  (400ms) --------------------------------------------------------------------------------------------
    localparam DELAY_3 = 19200;  // 0.4s of 48kHz validation signal
    reg [15:0] note_sample_echo3;
    localparam addr_width_3 = $clog2(DELAY_3);  // Calculate address width
    reg [WIDTH-1:0] mem3 [0:DELAY_3-1]; // declares an array of registers, each element is a vector of [0:DELAY_1-1]
    reg [addr_width_3-1:0] addr3;   // Address pointer
    always @(posedge note_sample_ready) begin
        if (rst) begin
            addr3 <= 0;
            note_sample_echo3 <= 0;
        end 
        else begin
            note_sample_echo3 <= mem3[addr3];   // Read old data
            mem3[addr3] <= note_sample_in_half; // Write new data
            addr3 <= addr3 + 1'b1;  // Increment circular pointer
        end
    end
    wire signed [15:0] note_sample_echo3_wire;
    assign note_sample_echo3_wire = $signed(note_sample_echo3);
    
    // ECHO 4  (500ms) --------------------------------------------------------------------------------------------
    localparam DELAY_4 = 24000;  // 0.4s of 48kHz validation signal
    reg [15:0] note_sample_echo4;
    localparam addr_width_4 = $clog2(DELAY_4);  // Calculate address width
    reg [WIDTH-1:0] mem4 [0:DELAY_4-1]; // declares an array of registers, each element is a vector of [0:DELAY_1-1]
    reg [addr_width_4-1:0] addr4;   // Address pointer
    always @(posedge note_sample_ready) begin
        if (rst) begin
            addr4 <= 0;
            note_sample_echo4 <= 0;
        end 
        else begin
            note_sample_echo4 <= mem4[addr4];   // Read old data
            mem4[addr4] <= note_sample_in_half; // Write new data
            addr4 <= addr4 + 1'b1;  // Increment circular pointer
        end
    end
    wire signed [15:0] note_sample_echo4_wire;
    assign note_sample_echo4_wire = $signed(note_sample_echo4);
    
//    // make a wire that carries: 0.6 * note_sample_echo4_wire for use in voice 3
//    // To accomplish this we use fixed point operation as descirbed on pg. 238-242 of Dally & Harting
//    wire [15:0] note_sample_echo4_wire_0dot6;
//    localparam signed [15:0] GAIN = 16'sd19660;  // 0.6 in Q1.15 format
//    wire signed [31:0] mult = note_sample_echo4_wire * GAIN;
//    assign note_sample_echo4_wire_0dot6 = mult[30:15]; // Take the upper 16 bits (proper Q1.15 scaling)
   
    // attenuation and synthesis ----------------------------------------------------------------------------------
    reg signed [15:0] temp_note_sample_out;
    always @(*) begin
        case(profile)
            2'b00: temp_note_sample_out = (note_sample_in_half) + (note_sample_echo1_wire >>> 3) + (note_sample_echo2_wire >>> 4);
            2'b01: temp_note_sample_out = (note_sample_in_half) + (note_sample_echo3_wire >>> 3) + (note_sample_echo4_wire >>> 4);
            2'b10: temp_note_sample_out = note_sample_in_half + (note_sample_echo3_wire >>> 2);    // test of delay
            2'b11: temp_note_sample_out = note_sample_in_half;
            default: temp_note_sample_out = 18'd0;
        endcase
    end
    assign note_sample_out = temp_note_sample_out;
    
endmodule
