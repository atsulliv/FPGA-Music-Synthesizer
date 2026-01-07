module note_player(
    // Exact same logic as solution code
    input clk,
    input reset,
    input play_enable,  // When high we play, when low we don't
    input [5:0] note_to_load,  // The note to play
    input [5:0] duration_to_load,  // The duration of the note to play
    input beat,  // This is our 1/48th second beat
    input generate_next_sample,  // Tells us when the codec wants a new sample

    // Changed logic with same output form as solution code
    output [15:0] sample_out,  // Our sample output
    output new_sample_ready,  // Tells the codec when we've got a sample

    // new inputs
    input load_new_advance, // Tells us when we have a new advance duration to load
    input load_new_note1, // Tells us when to load a new note in the Voice 1 path
    input load_new_note2, // Tells us when to load a new note in the Voice 2 path
    input load_new_note3, // Tells us when to load a new note in the Voice 3 path

    // new outputs
    output done_with_advance, // When we are done with the advance this stays high
    output voice1_ready, // When we are done with the 1st note this stays high
    output voice2_ready, // When we are done with the 2nd note this stays high
    output voice3_ready // When we are done with the 3rd note this stays high


);
    wire [5:0] state, next_state;
    dffre #(.WIDTH(6)) state_reg (
        .clk(clk), .r(reset),
        // allow FF to propagate next_state only when we see a beat while actively 
        // decrementing or when we load a new advance duration
        .en(((beat && !done_with_advance) || load_new_advance) && play_enable),
        .d(next_state),
        .q(state)
    );
    assign next_state = (load_new_advance) ? duration_to_load : state - 1;
    assign done_with_advance = (state == 6'b0);

    // Add logic for individual voices
    // Voice 1 (+ its harmonics)
    // 1) Timer:
    wire [5:0] n1state, next_n1state;
    dffre #(.WIDTH(6)) note1_reg (
        .clk(clk), .r(reset),
        .en(((beat && !voice1_ready) || load_new_note1) && play_enable),
        .d(next_n1state),
        .q(n1state)
    );
    assign next_n1state = (load_new_note1) ? duration_to_load : n1state - 1;
    assign voice1_ready = (n1state == 6'b0);

    // (DYNAMICS) time counter
    wire [5:0] n1_elapsed, n1_elapsed_next;
    assign n1_elapsed_next = load_new_note1 ? 6'd0 : 
                            (beat && !voice1_ready) ? (n1_elapsed + 6'd1) : 
                            n1_elapsed;

    dffre #(.WIDTH(6)) note1_counter_ff (
        .clk(clk), .r(reset),
        .en((beat && !voice1_ready) || load_new_note1),
        .d(n1_elapsed_next),
        .q(n1_elapsed)
    );

    wire [5:0] current_note1;
    dffre #(.WIDTH(6)) note1_value_reg (
        .clk(clk), .r(reset),
        .en(load_new_note1),
        .d(note_to_load),
        .q(current_note1)
    );

    // identify when we are at rest (when note is 0)
    wire is_rest1 = (current_note1 == 6'd0);

    parameter ATTACK_BEATS = 6'd4;
    // envelope logic.
    wire [7:0] envelope1;
    wire in_attack1 = (n1_elapsed <= ATTACK_BEATS);

    // decay
    wire [5:0] decay_elapsed = n1_elapsed - ATTACK_BEATS;
    reg [7:0] decay_value; // what decay should be

    // discretized exponential decay using only shifts.
    always @(*) begin
        if (decay_elapsed < 6'd2) decay_value = 8'd255;      // Exact match
        else if (decay_elapsed < 6'd4) decay_value = 8'd224; // ~192 in default
        else if (decay_elapsed < 6'd6) decay_value = 8'd192; // Exact match
        else if (decay_elapsed < 6'd8) decay_value = 8'd160; // ~128 in default
        else if (decay_elapsed < 6'd10) decay_value = 8'd128; // Exact match
        else if (decay_elapsed < 6'd12) decay_value = 8'd96;  // ~64 in default
        else if (decay_elapsed < 6'd14) decay_value = 8'd64;  // Exact match
        else if (decay_elapsed < 6'd18) decay_value = 8'd32;  // ~16 in default
        else if (decay_elapsed < 6'd22) decay_value = 8'd16;  // ~8 in default
        else if (decay_elapsed < 6'd26) decay_value = 8'd8;   // ~4 in default
        else if (decay_elapsed < 6'd30) decay_value = 8'd4;   // ~2 in default
        else decay_value = 8'd2;
    end

    assign envelope1 = (is_rest1) ? 8'd0 : // if in rest, envelope should be at 0
                       in_attack1 ? ((n1_elapsed == ATTACK_BEATS) ? 8'd255 : (8'd16 + (n1_elapsed << 5))) : // if in attack, envelope should shift with elapsed time (n1_elapsed == ATTACK_BEATS) ?  : (8'd64 + (n1_elapsed << 4))
                       decay_value; // if in decay, we need to shift down.

    // 1) freq_rom and sine_reader datapath:
    wire [19:0] step_size1;
    wire [5:0] freq_rom_in1;
    wire [15:0] sample_out1;
    wire new_sample_ready1;

    dffre #(.WIDTH(6)) freq_reg1 (
        .clk(clk), .r(reset),
        .en(load_new_note1),
        .d(note_to_load),
        .q(freq_rom_in1)
    );

    frequency_rom freq_rom1(
        .clk(clk),
        .addr(freq_rom_in1),
        .dout(step_size1)
    );

    // create new branches with harmonics, instantiate multiple sine_readers
    wire [19:0] step_size1_h1 = step_size1 << 1;              // x2
    wire [19:0] step_size1_h2 = (step_size1 << 1) + step_size1; // x3
    wire [19:0] step_size1_h3 = step_size1 << 2;              // x4
    
    // new sample_outs
    wire [15:0] sample_out1_h1, sample_out1_h2, sample_out1_h3;
    wire new_sample_ready1_h1, new_sample_ready1_h2, new_sample_ready1_h3;

    wire sine_reset1 = reset || load_new_note1;

    sine_reader sine_read1(
        .clk(clk), .reset(sine_reset1),
        .step_size(step_size1),
        .generate_next(play_enable && generate_next_sample),
        .sample_ready(new_sample_ready1),
        .sample(sample_out1)
    );

    sine_reader sine_read1_h1(
        .clk(clk), .reset(sine_reset1),
        .step_size(step_size1_h1),
        .generate_next(play_enable && generate_next_sample),
        .sample_ready(new_sample_ready1_h1),
        .sample(sample_out1_h1)
    );

    sine_reader sine_read1_h2(
        .clk(clk), .reset(sine_reset1),
        .step_size(step_size1_h2),
        .generate_next(play_enable && generate_next_sample),
        .sample_ready(new_sample_ready1_h2),
        .sample(sample_out1_h2)
    );

    sine_reader sine_read1_h3(
        .clk(clk), .reset(sine_reset1),
        .step_size(step_size1_h3),
        .generate_next(play_enable && generate_next_sample),
        .sample_ready(new_sample_ready1_h3),
        .sample(sample_out1_h3)
    );

    // fix for timing violations, pipelined with another series of flip flops, voice 1
    wire signed [15:0] sample_out1_reg, sample_out1_h1_reg, sample_out1_h2_reg, sample_out1_h3_reg;

    dffr #(.WIDTH(16)) v1_fund_pipe (
        .clk(clk), .r(reset),
        .d(sample_out1),
        .q(sample_out1_reg)
    );

    dffr #(.WIDTH(16)) v1_h1_pipe (
        .clk(clk), .r(reset),
        .d(sample_out1_h1),
        .q(sample_out1_h1_reg)
    );

    dffr #(.WIDTH(16)) v1_h2_pipe (
        .clk(clk), .r(reset),
        .d(sample_out1_h2),
        .q(sample_out1_h2_reg)
    );

    dffr #(.WIDTH(16)) v1_h3_pipe (
        .clk(clk), .r(reset),
        .d(sample_out1_h3),
        .q(sample_out1_h3_reg)
    );

    // (DYNAMICS) always logic for dynamics -- shift and add method (instead of using DSP block)
    // voice 1
    reg signed [15:0] shaped_sample1_next, shaped_sample1_h1_next, shaped_sample1_h2_next, shaped_sample1_h3_next;
    always @(*) begin
        // apply envelope directly
        case(envelope1)
            8'd0:   begin 
                shaped_sample1_next = 16'sd0;
                shaped_sample1_h1_next = 16'sd0;
                shaped_sample1_h2_next = 16'sd0;
                shaped_sample1_h3_next = 16'sd0;
            end
            8'd64: begin
                shaped_sample1_next = sample_out1_reg >>> 2;
                shaped_sample1_h1_next = sample_out1_h1_reg >>> 2;
                shaped_sample1_h2_next = sample_out1_h2_reg >>> 2;
                shaped_sample1_h3_next = sample_out1_h3_reg >>> 2;
            end
            8'd128: begin
                shaped_sample1_next = sample_out1_reg >>> 1;
                shaped_sample1_h1_next = sample_out1_h1_reg >>> 1;
                shaped_sample1_h2_next = sample_out1_h2_reg >>> 1;
                shaped_sample1_h3_next = sample_out1_h3_reg >>> 1;
            end
            8'd192: begin
                shaped_sample1_next = (sample_out1_reg >>> 1) + (sample_out1_reg >>> 2);
                shaped_sample1_h1_next = (sample_out1_h1_reg >>> 1) + (sample_out1_h1_reg >>> 2);
                shaped_sample1_h2_next = (sample_out1_h2_reg >>> 1) + (sample_out1_h2_reg >>> 2);
                shaped_sample1_h3_next = (sample_out1_h3_reg >>> 1) + (sample_out1_h3_reg >>> 2);
            end
            8'd255: begin
                shaped_sample1_next = sample_out1_reg;
                shaped_sample1_h1_next = sample_out1_h1_reg;
                shaped_sample1_h2_next = sample_out1_h2_reg;
                shaped_sample1_h3_next = sample_out1_h3_reg;
            end
            default: begin
                // For other values, approximate
                if (envelope1 < 8'd32) begin
                    shaped_sample1_next = sample_out1_reg >>> 4;
                    shaped_sample1_h1_next = sample_out1_h1_reg >>> 4;
                    shaped_sample1_h2_next = sample_out1_h2_reg >>> 4;
                    shaped_sample1_h3_next = sample_out1_h3_reg >>> 4;
                end else if (envelope1 < 8'd96) begin
                    shaped_sample1_next = sample_out1_reg >>> 2;
                    shaped_sample1_h1_next = sample_out1_h1_reg >>> 2;
                    shaped_sample1_h2_next = sample_out1_h2_reg >>> 2;
                    shaped_sample1_h3_next = sample_out1_h3_reg >>> 2;
                end else if (envelope1 < 8'd160) begin
                    shaped_sample1_next = sample_out1_reg >>> 1;
                    shaped_sample1_h1_next = sample_out1_h1_reg >>> 1;
                    shaped_sample1_h2_next = sample_out1_h2_reg >>> 1;
                    shaped_sample1_h3_next = sample_out1_h3_reg >>> 1;
                end else begin
                    shaped_sample1_next = (sample_out1_reg >>> 1) + (sample_out1_reg >>> 2);
                    shaped_sample1_h1_next = (sample_out1_h1_reg >>> 1) + (sample_out1_h1_reg >>> 2);
                    shaped_sample1_h2_next = (sample_out1_h2_reg >>> 1) + (sample_out1_h2_reg >>> 2);
                    shaped_sample1_h3_next = (sample_out1_h3_reg >>> 1) + (sample_out1_h3_reg >>> 2);
                end
            end
        endcase
    end

    wire signed [15:0] shaped_sample1, shaped_sample1_h1, shaped_sample1_h2, shaped_sample1_h3;

    dffr #(.WIDTH(16)) shaped_sample1_fund_pipe (
        .clk(clk), .r(reset),
        .d(shaped_sample1_next),
        .q(shaped_sample1)
    );
    
    dffr #(.WIDTH(16)) shaped_sample1_h1_pipe (
        .clk(clk), .r(reset),
        .d(shaped_sample1_h1_next),
        .q(shaped_sample1_h1)
    );

    dffr #(.WIDTH(16)) shaped_sample1_h2_pipe (
        .clk(clk), .r(reset),
        .d(shaped_sample1_h2_next),
        .q(shaped_sample1_h2)
    );

    dffr #(.WIDTH(16)) shaped_sample1_h3_pipe (
        .clk(clk), .r(reset),
        .d(shaped_sample1_h3_next),
        .q(shaped_sample1_h3)
    );

    // Voice 2
    // 2) Timer:
    wire [5:0] n2state, next_n2state;
    dffre #(.WIDTH(6)) note2_reg (
        .clk(clk), .r(reset),
        .en(((beat && !voice2_ready) || load_new_note2) && play_enable),
        .d(next_n2state),
        .q(n2state)
    );
    assign next_n2state = (load_new_note2)
                        ? duration_to_load : n2state - 1;
    assign voice2_ready = (n2state == 6'b0);

    // (DYNAMICS) time counter, voice 2
    wire [5:0] n2_elapsed, n2_elapsed_next;
    assign n2_elapsed_next = load_new_note2 ? 6'd0 : 
                            (beat && !voice2_ready) ? (n2_elapsed + 6'd1) : 
                            n2_elapsed;

    dffre #(.WIDTH(6)) note2_counter_ff (
        .clk(clk), .r(reset),
        .en((beat && !voice2_ready) || load_new_note2),
        .d(n2_elapsed_next),
        .q(n2_elapsed)
    );

    wire [5:0] current_note2;
    dffre #(.WIDTH(6)) note2_value_reg (
        .clk(clk), .r(reset),
        .en(load_new_note2),
        .d(note_to_load),
        .q(current_note2)
    );

    // identify when we are at rest (when note is 0)
    wire is_rest2 = (current_note2 == 6'd0);

    // envelope logic.
    wire [7:0] envelope2;
    wire in_attack2 = (n2_elapsed <= ATTACK_BEATS);

    // decay
    wire [5:0] decay_elapsed_2 = n2_elapsed - ATTACK_BEATS;
    reg [7:0] decay_value_2; // what decay should be

    // discretized exponential decay using only shifts.
    always @(*) begin
        if (decay_elapsed_2 < 6'd2) decay_value_2 = 8'd255;      // Exact match
        else if (decay_elapsed_2 < 6'd4) decay_value_2 = 8'd224; // ~192 in default
        else if (decay_elapsed_2 < 6'd6) decay_value_2 = 8'd192; // Exact match
        else if (decay_elapsed_2 < 6'd8) decay_value_2 = 8'd160; // ~128 in default
        else if (decay_elapsed_2 < 6'd10) decay_value_2 = 8'd128; // Exact match
        else if (decay_elapsed_2 < 6'd12) decay_value_2 = 8'd96;  // ~64 in default
        else if (decay_elapsed_2 < 6'd14) decay_value_2 = 8'd64;  // Exact match
        else if (decay_elapsed_2 < 6'd18) decay_value_2 = 8'd32;  // ~16 in default
        else if (decay_elapsed_2 < 6'd22) decay_value_2 = 8'd16;  // ~8 in default
        else if (decay_elapsed_2 < 6'd26) decay_value_2 = 8'd8;   // ~4 in default
        else if (decay_elapsed_2 < 6'd30) decay_value_2 = 8'd4;   // ~2 in default
        else decay_value_2 = 8'd2;
    end

    assign envelope2 = (is_rest2) ? 8'd0 : // if in rest, envelope should be at 0
                       in_attack2 ? ((n2_elapsed == ATTACK_BEATS) ? 8'd255 : (8'd16 + (n2_elapsed << 5))) : // if in attack, envelope should shift with elapsed time )
                       decay_value_2; // if in decay, we need to shift down.

    // 2) freq_rom and sine_reader datapath:
    wire [19:0] step_size2;
    wire [5:0] freq_rom_in2;
    wire [15:0] sample_out2;
    wire new_sample_ready2;

    dffre #(.WIDTH(6)) freq_reg2 (
        .clk(clk), .r(reset),
        .en(load_new_note2),
        .d(note_to_load),
        .q(freq_rom_in2)
    );

    frequency_rom freq_rom2(
        .clk(clk),
        .addr(freq_rom_in2),
        .dout(step_size2)
    );

    // voice 2 harmonics
    wire [19:0] step_size2_h1 = step_size2 << 1;              // x2
    wire [19:0] step_size2_h2 = (step_size2 << 1) + step_size2; // x3
    wire [19:0] step_size2_h3 = step_size2 << 2;              // x4

    wire [15:0] sample_out2_h1, sample_out2_h2, sample_out2_h3;
    wire new_sample_ready2_h1, new_sample_ready2_h2, new_sample_ready2_h3;

    wire sine_reset2 = reset || load_new_note2;

    sine_reader sine_read2(
        .clk(clk), .reset(sine_reset2),
        .step_size(step_size2),
        .generate_next(play_enable && generate_next_sample),
        .sample_ready(new_sample_ready2),
        .sample(sample_out2)
    );

    sine_reader sine_read2_h1(
        .clk(clk), .reset(sine_reset2),
        .step_size(step_size2_h1),
        .generate_next(play_enable && generate_next_sample),
        .sample_ready(new_sample_ready2_h1),
        .sample(sample_out2_h1)
    );

    sine_reader sine_read2_h2(
        .clk(clk), .reset(sine_reset2),
        .step_size(step_size2_h2),
        .generate_next(play_enable && generate_next_sample),
        .sample_ready(new_sample_ready2_h2),
        .sample(sample_out2_h2)
    );

    sine_reader sine_read2_h3(
        .clk(clk), .reset(sine_reset2),
        .step_size(step_size2_h3),
        .generate_next(play_enable && generate_next_sample),
        .sample_ready(new_sample_ready2_h3),
        .sample(sample_out2_h3)
    );

    // fix for timing violations, pipelined with another series of flip flops, voice 2
    wire signed [15:0] sample_out2_reg, sample_out2_h1_reg, sample_out2_h2_reg, sample_out2_h3_reg;

    dffr #(.WIDTH(16)) v2_fund_pipe (
        .clk(clk), .r(reset),
        .d(sample_out2),
        .q(sample_out2_reg)
    );

    dffr #(.WIDTH(16)) v2_h1_pipe (
        .clk(clk), .r(reset),
        .d(sample_out2_h1),
        .q(sample_out2_h1_reg)
    );

    dffr #(.WIDTH(16)) v2_h2_pipe (
        .clk(clk), .r(reset),
        .d(sample_out2_h2),
        .q(sample_out2_h2_reg)
    );

    dffr #(.WIDTH(16)) v2_h3_pipe (
        .clk(clk), .r(reset),
        .d(sample_out2_h3),
        .q(sample_out2_h3_reg)
    );

    // (DYNAMICS) always logic for dynamics -- shift and add method (instead of using DSP block), voice 2
    // voice 2
    reg signed [15:0] shaped_sample2_next, shaped_sample2_h1_next, shaped_sample2_h2_next, shaped_sample2_h3_next;
    always @(*) begin
        // apply envelope directly
        case(envelope2)
            8'd0: begin 
                shaped_sample2_next = 16'sd0;
                shaped_sample2_h1_next = 16'sd0;
                shaped_sample2_h2_next = 16'sd0;
                shaped_sample2_h3_next = 16'sd0;
            end
            8'd64: begin
                shaped_sample2_next = sample_out2_reg >>> 2;
                shaped_sample2_h1_next = sample_out2_h1_reg >>> 2;
                shaped_sample2_h2_next = sample_out2_h2_reg >>> 2;
                shaped_sample2_h3_next = sample_out2_h3_reg >>> 2;
            end
            8'd128: begin
                shaped_sample2_next = sample_out2_reg >>> 1;
                shaped_sample2_h1_next = sample_out2_h1_reg >>> 1;
                shaped_sample2_h2_next = sample_out2_h2_reg >>> 1;
                shaped_sample2_h3_next = sample_out2_h3_reg >>> 1;
            end
            8'd192: begin
                shaped_sample2_next = (sample_out2_reg >>> 1) + (sample_out2_reg >>> 2);
                shaped_sample2_h1_next = (sample_out2_h1_reg >>> 1) + (sample_out2_h1_reg >>> 2);
                shaped_sample2_h2_next = (sample_out2_h2_reg >>> 1) + (sample_out2_h2_reg >>> 2);
                shaped_sample2_h3_next = (sample_out2_h3_reg >>> 1) + (sample_out2_h3_reg >>> 2);
            end
            8'd255: begin
                shaped_sample2_next = sample_out2_reg;
                shaped_sample2_h1_next = sample_out2_h1_reg;
                shaped_sample2_h2_next = sample_out2_h2_reg;
                shaped_sample2_h3_next = sample_out2_h3_reg;
            end
            default: begin
                // for other values, approximate
                if (envelope2 < 8'd32) begin
                    shaped_sample2_next = sample_out2_reg >>> 4;
                    shaped_sample2_h1_next = sample_out2_h1_reg >>> 4;
                    shaped_sample2_h2_next = sample_out2_h2_reg >>> 4;
                    shaped_sample2_h3_next = sample_out2_h3_reg >>> 4;
                end else if (envelope2 < 8'd96) begin
                    shaped_sample2_next = sample_out2_reg >>> 2;
                    shaped_sample2_h1_next = sample_out2_h1_reg >>> 2;
                    shaped_sample2_h2_next = sample_out2_h2_reg >>> 2;
                    shaped_sample2_h3_next = sample_out2_h3_reg >>> 2;
                end else if (envelope2 < 8'd160) begin
                    shaped_sample2_next = sample_out2_reg >>> 1;
                    shaped_sample2_h1_next = sample_out2_h1_reg >>> 1;
                    shaped_sample2_h2_next = sample_out2_h2_reg >>> 1;
                    shaped_sample2_h3_next = sample_out2_h3_reg >>> 1;
                end else begin
                    shaped_sample2_next = (sample_out2_reg >>> 1) + (sample_out2_reg >>> 2);
                    shaped_sample2_h1_next = (sample_out2_h1_reg >>> 1) + (sample_out2_h1_reg >>> 2);
                    shaped_sample2_h2_next = (sample_out2_h2_reg >>> 1) + (sample_out2_h2_reg >>> 2);
                    shaped_sample2_h3_next = (sample_out2_h3_reg >>> 1) + (sample_out2_h3_reg >>> 2);
                end
            end
        endcase
    end

    wire signed [15:0] shaped_sample2, shaped_sample2_h1, shaped_sample2_h2, shaped_sample2_h3;

    dffr #(.WIDTH(16)) shaped_sample2_fund_pipe (
        .clk(clk), .r(reset),
        .d(shaped_sample2_next),
        .q(shaped_sample2)
    );

    dffr #(.WIDTH(16)) shaped_sample2_h1_pipe (
        .clk(clk), .r(reset),
        .d(shaped_sample2_h1_next),
        .q(shaped_sample2_h1)
    );

    dffr #(.WIDTH(16)) shaped_sample2_h2_pipe (
        .clk(clk), .r(reset),
        .d(shaped_sample2_h2_next),
        .q(shaped_sample2_h2)
    );

    dffr #(.WIDTH(16)) shaped_sample2_h3_pipe (
        .clk(clk), .r(reset),
        .d(shaped_sample2_h3_next),
        .q(shaped_sample2_h3)
    );

    // Voice 3
    // 3) Timer:
    wire [5:0] n3state, next_n3state;
    dffre #(.WIDTH(6)) note3_reg (
        .clk(clk),
        .r(reset),
        .en(((beat && !voice3_ready) || load_new_note3) && play_enable),
        .d(next_n3state),
        .q(n3state)
    );
    assign next_n3state = (load_new_note3)
                        ? duration_to_load : n3state - 1;
    assign voice3_ready = (n3state == 6'b0);


    // (DYNAMICS) time counter
    wire [5:0] n3_elapsed, n3_elapsed_next;
    assign n3_elapsed_next = load_new_note3 ? 6'd0 : 
                            (beat && !voice3_ready) ? (n3_elapsed + 6'd1) : 
                            n3_elapsed;

    dffre #(.WIDTH(6)) note3_counter_ff (
        .clk(clk), .r(reset),
        .en((beat && !voice3_ready) || load_new_note3),
        .d(n3_elapsed_next),
        .q(n3_elapsed)
    );

    wire [5:0] current_note3;
    dffre #(.WIDTH(6)) note3_value_reg (
        .clk(clk), .r(reset),
        .en(load_new_note3),
        .d(note_to_load),
        .q(current_note3)
    );

    // identify when we are at rest (when note is 0)
    wire is_rest3 = (current_note3 == 6'd0);

    // envelope logic.
    wire [7:0] envelope3;
    wire in_attack3 = (n3_elapsed <= ATTACK_BEATS);

    // decay
    wire [5:0] decay_elapsed_3 = n3_elapsed - ATTACK_BEATS;
    reg [7:0] decay_value_3; // what decay should be

    // discretized exponential decay using only shifts.
    always @(*) begin
        if (decay_elapsed_3 < 6'd2) decay_value_3 = 8'd255;      // Exact match
        else if (decay_elapsed_3 < 6'd4) decay_value_3 = 8'd224; // ~192 in default
        else if (decay_elapsed_3 < 6'd6) decay_value_3 = 8'd192; // Exact match
        else if (decay_elapsed_3 < 6'd8) decay_value_3 = 8'd160; // ~128 in default
        else if (decay_elapsed_3 < 6'd10) decay_value_3 = 8'd128; // Exact match
        else if (decay_elapsed_3 < 6'd12) decay_value_3 = 8'd96;  // ~64 in default
        else if (decay_elapsed_3 < 6'd14) decay_value_3 = 8'd64;  // Exact match
        else if (decay_elapsed_3 < 6'd18) decay_value_3 = 8'd32;  // ~16 in default
        else if (decay_elapsed_3 < 6'd22) decay_value_3 = 8'd16;  // ~8 in default
        else if (decay_elapsed_3 < 6'd26) decay_value_3 = 8'd8;   // ~4 in default
        else if (decay_elapsed_3 < 6'd30) decay_value_3 = 8'd4;   // ~2 in default
        else decay_value_3 = 8'd2;
    end

    assign envelope3 = (is_rest3) ? 8'd0 : // if in rest, envelope should be at 0
                       in_attack3 ? ((n3_elapsed == ATTACK_BEATS) ? 8'd255 : (8'd16 + (n3_elapsed << 5))) : // if in attack, envelope should shift with elapsed time (n3_elapsed == ATTACK_BEATS) ? (8'd64 + (n3_elapsed << 4))
                       decay_value_3; // if in decay, we need to shift down.

    // 3) freq_rom and sine_reader datapath:
    wire [19:0] step_size3;
    wire [5:0] freq_rom_in3;
    wire [15:0] sample_out3;
    wire new_sample_ready3;

    dffre #(.WIDTH(6)) freq_reg3 (
        .clk(clk),
        .r(reset),
        .en(load_new_note3),
        .d(note_to_load),
        .q(freq_rom_in3)
    );

    frequency_rom freq_rom3(
        .clk(clk),
        .addr(freq_rom_in3),
        .dout(step_size3)
    );

    // voice 3 harmonics
    wire [19:0] step_size3_h1 = step_size3 << 1;              // x2
    wire [19:0] step_size3_h2 = (step_size3 << 1) + step_size3; // x3
    wire [19:0] step_size3_h3 = step_size3 << 2;              // x4

    wire [15:0] sample_out3_h1, sample_out3_h2, sample_out3_h3;
    wire new_sample_ready3_h1, new_sample_ready3_h2, new_sample_ready3_h3;

    wire sine_reset3 = reset || load_new_note3;

    sine_reader sine_read3(
        .clk(clk),
        .reset(sine_reset3),
        .step_size(step_size3),
        .generate_next(play_enable && generate_next_sample),
        .sample_ready(new_sample_ready3),
        .sample(sample_out3)
    );

    sine_reader sine_read3_h1(
        .clk(clk),
        .reset(sine_reset3),
        .step_size(step_size3_h1),
        .generate_next(play_enable && generate_next_sample),
        .sample_ready(new_sample_ready3_h1),
        .sample(sample_out3_h1)
    );

    sine_reader sine_read3_h2(
        .clk(clk),
        .reset(sine_reset3),
        .step_size(step_size3_h2),
        .generate_next(play_enable && generate_next_sample),
        .sample_ready(new_sample_ready3_h2),
        .sample(sample_out3_h2)
    );

    sine_reader sine_read3_h3(
        .clk(clk),
        .reset(sine_reset3),
        .step_size(step_size3_h3),
        .generate_next(play_enable && generate_next_sample),
        .sample_ready(new_sample_ready3_h3),
        .sample(sample_out3_h3)
    );

    // fix for timing violations, pipelined with another series of flip flops, voice 3
    wire signed [15:0] sample_out3_reg, sample_out3_h1_reg, sample_out3_h2_reg, sample_out3_h3_reg;

    dffr #(.WIDTH(16)) v3_fund_pipe (
        .clk(clk), .r(reset),
        .d(sample_out3),
        .q(sample_out3_reg)
    );

    dffr #(.WIDTH(16)) v3_h1_pipe (
        .clk(clk), .r(reset),
        .d(sample_out3_h1),
        .q(sample_out3_h1_reg)
    );

    dffr #(.WIDTH(16)) v3_h2_pipe (
        .clk(clk), .r(reset),
        .d(sample_out3_h2),
        .q(sample_out3_h2_reg)
    );

    dffr #(.WIDTH(16)) v3_h3_pipe (
        .clk(clk), .r(reset),
        .d(sample_out3_h3),
        .q(sample_out3_h3_reg)
    );

    // (DYNAMICS) always logic for dynamics -- shift and add method (instead of using DSP block), voice 2
    // voice 2
    reg signed [15:0] shaped_sample3_next, shaped_sample3_h1_next, shaped_sample3_h2_next, shaped_sample3_h3_next;
    always @(*) begin
        // apply envelope directly
        case(envelope3)
            8'd0: begin 
                shaped_sample3_next = 16'sd0;
                shaped_sample3_h1_next = 16'sd0;
                shaped_sample3_h2_next = 16'sd0;
                shaped_sample3_h3_next = 16'sd0;
            end
            8'd64: begin
                shaped_sample3_next = sample_out3_reg >>> 2;
                shaped_sample3_h1_next = sample_out3_h1_reg >>> 2;
                shaped_sample3_h2_next = sample_out3_h2_reg >>> 2;
                shaped_sample3_h3_next = sample_out3_h3_reg >>> 2;
            end
            8'd128: begin
                shaped_sample3_next = sample_out3_reg >>> 1;
                shaped_sample3_h1_next = sample_out3_h1_reg >>> 1;
                shaped_sample3_h2_next = sample_out3_h2_reg >>> 1;
                shaped_sample3_h3_next = sample_out3_h3_reg >>> 1;
            end
            8'd192: begin
                shaped_sample3_next = (sample_out3_reg >>> 1) + (sample_out3_reg >>> 2);
                shaped_sample3_h1_next = (sample_out3_h1_reg >>> 1) + (sample_out3_h1_reg >>> 2);
                shaped_sample3_h2_next = (sample_out3_h2_reg >>> 1) + (sample_out3_h2_reg >>> 2);
                shaped_sample3_h3_next = (sample_out3_h3_reg >>> 1) + (sample_out3_h3_reg >>> 2);
            end
            8'd255: begin
                shaped_sample3_next = sample_out3_reg;
                shaped_sample3_h1_next = sample_out3_h1_reg;
                shaped_sample3_h2_next = sample_out3_h2_reg;
                shaped_sample3_h3_next = sample_out3_h3_reg;
            end
            default: begin
                // for other values, approximate
                if (envelope3 < 8'd32) begin
                    shaped_sample3_next = sample_out3_reg >>> 4;
                    shaped_sample3_h1_next = sample_out3_h1_reg >>> 4;
                    shaped_sample3_h2_next = sample_out3_h2_reg >>> 4;
                    shaped_sample3_h3_next = sample_out3_h3_reg >>> 4;
                end else if (envelope3 < 8'd96) begin
                    shaped_sample3_next = sample_out3_reg >>> 2;
                    shaped_sample3_h1_next = sample_out3_h1_reg >>> 2;
                    shaped_sample3_h2_next = sample_out3_h2_reg >>> 2;
                    shaped_sample3_h3_next = sample_out3_h3_reg >>> 2;
                end else if (envelope3 < 8'd160) begin
                    shaped_sample3_next = sample_out3_reg >>> 1;
                    shaped_sample3_h1_next = sample_out3_h1_reg >>> 1;
                    shaped_sample3_h2_next = sample_out3_h2_reg >>> 1;
                    shaped_sample3_h3_next = sample_out3_h3_reg >>> 1;
                end else begin
                    shaped_sample3_next = (sample_out3_reg >>> 1) + (sample_out3_reg >>> 2);
                    shaped_sample3_h1_next = (sample_out3_h1_reg >>> 1) + (sample_out3_h1_reg >>> 2);
                    shaped_sample3_h2_next = (sample_out3_h2_reg >>> 1) + (sample_out3_h2_reg >>> 2);
                    shaped_sample3_h3_next = (sample_out3_h3_reg >>> 1) + (sample_out3_h3_reg >>> 2);
                end
            end
        endcase
    end

    wire signed [15:0] shaped_sample3, shaped_sample3_h1, shaped_sample3_h2, shaped_sample3_h3;

    // pipeline ff after shaped sample
    dffr #(.WIDTH(16)) shaped_sample3_fund_pipe (
        .clk(clk), .r(reset),
        .d(shaped_sample3_next),
        .q(shaped_sample3)
    );

    dffr #(.WIDTH(16)) shaped_sample3_h1_pipe (
        .clk(clk), .r(reset),
        .d(shaped_sample3_h1_next),
        .q(shaped_sample3_h1)
    );

    dffr #(.WIDTH(16)) shaped_sample3_h2_pipe (
        .clk(clk), .r(reset),
        .d(shaped_sample3_h2_next),
        .q(shaped_sample3_h2)
    );

    dffr #(.WIDTH(16)) shaped_sample3_h3_pipe (
        .clk(clk), .r(reset),
        .d(shaped_sample3_h3_next),
        .q(shaped_sample3_h3)
    );

    // Updated Output Logic
    // Gate samples - only include if voice is actively playing
    // Sum up weighted harmonics (up to 3)
    wire signed [17:0] gated_sample1 = voice1_ready ? 18'sd0 : (($signed(shaped_sample1) >>> 1) + ($signed(shaped_sample1_h1) >>> 2) + ($signed(shaped_sample1_h2) >>> 1) + ($signed(shaped_sample1_h3) >>> 2));
    wire signed [17:0] gated_sample2 = voice2_ready ? 18'sd0 : (($signed(shaped_sample2) >>> 1) + ($signed(shaped_sample2_h1) >>> 2) + ($signed(shaped_sample2_h2) >>> 1) + ($signed(shaped_sample2_h3) >>> 2));
    wire signed [17:0] gated_sample3 = voice3_ready ? 18'sd0 : (($signed(shaped_sample3) >>> 1) + ($signed(shaped_sample3_h1) >>> 2) + ($signed(shaped_sample3_h2) >>> 1) + ($signed(shaped_sample3_h3) >>> 2));
    
    wire [1:0] active_count = !voice1_ready + !voice2_ready + !voice3_ready;
    wire signed [19:0] sample_sum = gated_sample1 + gated_sample2 + gated_sample3;
    
    reg signed [19:0] temp_sample_out;
    
    always @(*) begin
        case(active_count)
            2'd3: temp_sample_out = (sample_sum >>> 3); // div 9, adjusted for adding harmonics
            2'd2: temp_sample_out = (sample_sum >>> 2); // div 6
            2'd1: temp_sample_out = (sample_sum >>> 1); // div 4
            default: temp_sample_out = 20'd0;
        endcase
    end

    // pipeline sample_ready signals to align with extra flip flop delay
    wire new_sample_ready_pipeline;
    assign new_sample_ready_pipeline = (new_sample_ready1 && new_sample_ready2 && new_sample_ready3);

    dffr #(.WIDTH(1)) ready_pipe (
        .clk(clk),
        .r(reset),
        .d(new_sample_ready_pipeline),
        .q(new_sample_ready)
    );

    assign sample_out = play_enable ? temp_sample_out[15:0] : 16'sd0;
endmodule