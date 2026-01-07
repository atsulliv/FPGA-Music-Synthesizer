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
    assign next_state = (load_new_advance)
                        ? duration_to_load : state - 1;

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
    assign next_n1state = (load_new_note1)
                        ? duration_to_load : n1state - 1;
    assign voice1_ready = (n1state == 6'b0);

    // BEGIN DYNAMICS IMPL.
    wire [5:0] n1_duration;
    dffre #(.WIDTH(6)) note1_duration_dffre (
        .clk(clk), .r(reset),
        .en(load_new_note1),
        .d(duration_to_load),
        .q(n1_duration)
    );

    // set up timer
    wire [5:0] n1_elapsed = n1_duration - n1state;
    // set up time in which we are in attack
    parameter ATTACK_BEATS = 6'd4;

    // generate the envelope for voice 1 that will be multiplied
    wire [7:0] envelope1;
    wire [8:0] envelope1_temp = (n1_elapsed << 6);  // temporary wire to have 9 bits, holding 256
    wire in_attack1 = (n1_elapsed < ATTACK_BEATS);

    assign envelope1 = voice1_ready ? 8'd0 :      // Silent when done
                in_attack1 ? ((envelope1_temp > 9'd255) ? 8'd255 : envelope1_temp[7:0]) :  // Linear attack (0->64->128->192)
                (8'd255 >> (n1_elapsed >> 2));    // Decay by div4 each time

    // voice 1 pipelined envelope input
    wire [7:0] envelope1_pipe;
    dffr #(.WIDTH(8)) v1_env_pipe (
        .clk(clk), .r(reset),
        .d(envelope1),
        .q(envelope1_pipe)
    );

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

    sine_reader sine_read1(
        .clk(clk), .reset(reset),
        .step_size(step_size1),
        .generate_next(play_enable && generate_next_sample),
        .sample_ready(new_sample_ready1),
        .sample(sample_out1)
    );

    sine_reader sine_read1_h1(
        .clk(clk), .reset(reset),
        .step_size(step_size1_h1),
        .generate_next(play_enable && generate_next_sample),
        .sample_ready(new_sample_ready1_h1),
        .sample(sample_out1_h1)
    );

    sine_reader sine_read1_h2(
        .clk(clk), .reset(reset),
        .step_size(step_size1_h2),
        .generate_next(play_enable && generate_next_sample),
        .sample_ready(new_sample_ready1_h2),
        .sample(sample_out1_h2)
    );

    sine_reader sine_read1_h3(
        .clk(clk), .reset(reset),
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

    // our sample_out is now multiplied by an envelope we defined
    wire signed [23:0] shaped_sample1_d = ($signed(sample_out1_reg) * $signed({1'b0, envelope1_pipe})); // 
    wire signed [23:0] shaped_sample1_h1_d  = ($signed(sample_out1_h1_reg) * $signed({1'b0, envelope1_pipe})); // 
    wire signed [23:0] shaped_sample1_h2_d  = ($signed(sample_out1_h2_reg) * $signed({1'b0, envelope1_pipe})); //
    wire signed [23:0] shaped_sample1_h3_d  = ($signed(sample_out1_h3_reg) * $signed({1'b0, envelope1_pipe})); // 

    wire signed [23:0] shaped_sample1, shaped_sample1_h1, shaped_sample1_h2, shaped_sample1_h3;

    dffr #(.WIDTH(24)) v1_shaped_fund_pipe (
        .clk(clk), .r(reset),
        .d(shaped_sample1_d), 
        .q(shaped_sample1)
    );
    dffr #(.WIDTH(24)) v1_shaped_h1_pipe (
        .clk(clk), .r(reset),
        .d(shaped_sample1_h1_d), 
        .q(shaped_sample1_h1)
    );
    dffr #(.WIDTH(24)) v1_shaped_h2_pipe (
        .clk(clk), .r(reset),
        .d(shaped_sample1_h2_d), 
        .q(shaped_sample1_h2)
    );
    dffr #(.WIDTH(24)) v1_shaped_h3_pipe (
        .clk(clk), .r(reset),
        .d(shaped_sample1_h3_d), 
        .q(shaped_sample1_h3)
    );

    wire signed [23:0] shaped_sample1_2, shaped_sample1_h1_2, shaped_sample1_h2_2, shaped_sample1_h3_2;
    
    // two stages as suggested by DSP block
    dffr #(.WIDTH(24)) v1_shaped_fund_pipe2 (
        .clk(clk), .r(reset),
        .d(shaped_sample1),
        .q(shaped_sample1_2)
    );

    dffr #(.WIDTH(24)) v1_shaped_fund_pipe2 (
        .clk(clk), .r(reset),
        .d(shaped_sample1_h1),
        .q(shaped_sample1_h1_2)
    );

    dffr #(.WIDTH(24)) v1_shaped_fund_pipe2 (
        .clk(clk), .r(reset),
        .d(shaped_sample1_h2),
        .q(shaped_sample1_h2_2)
    );

    dffr #(.WIDTH(24)) v1_shaped_fund_pipe2 (
        .clk(clk), .r(reset),
        .d(shaped_sample1_h3),
        .q(shaped_sample1_h3_2)
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

    // BEGIN DYNAMICS IMPL.
    wire [5:0] n2_duration;
    dffre #(.WIDTH(6)) note2_duration_dffre (
        .clk(clk), .r(reset),
        .en(load_new_note2),
        .d(duration_to_load),
        .q(n2_duration)
    );

    // set up timer
    wire [5:0] n2_elapsed = n2_duration - n2state;

    // generate the envelope for voice 1 that will be multiplied
    wire [7:0] envelope2;
    wire [8:0] envelope2_temp = (n2_elapsed << 6);  // temporary wire to have 9 bits, holding 256
    wire in_attack2 = (n2_elapsed < ATTACK_BEATS);

    assign envelope2 = voice2_ready ? 8'd0 :      // Silent when done
                in_attack2 ? ((envelope2_temp > 9'd255) ? 8'd255 : envelope2_temp[7:0]) :  // Linear attack (0->64->128->192->256)
                (8'd255 >> (n2_elapsed >> 2));    // Decay by div4 each time

    // voice 2 pipelined envelope input
    wire [7:0] envelope2_pipe;
    dffr #(.WIDTH(8)) v2_env_pipe (
        .clk(clk), .r(reset),
        .d(envelope2),
        .q(envelope2_pipe)
    );

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

    sine_reader sine_read2(
        .clk(clk), .reset(reset),
        .step_size(step_size2),
        .generate_next(play_enable && generate_next_sample),
        .sample_ready(new_sample_ready2),
        .sample(sample_out2)
    );

    sine_reader sine_read2_h1(
        .clk(clk), .reset(reset),
        .step_size(step_size2_h1),
        .generate_next(play_enable && generate_next_sample),
        .sample_ready(new_sample_ready2_h1),
        .sample(sample_out2_h1)
    );

    sine_reader sine_read2_h2(
        .clk(clk), .reset(reset),
        .step_size(step_size2_h2),
        .generate_next(play_enable && generate_next_sample),
        .sample_ready(new_sample_ready2_h2),
        .sample(sample_out2_h2)
    );

    sine_reader sine_read2_h3(
        .clk(clk), .reset(reset),
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

    // our sample_out is now multiplied by an envelope we defined
    wire signed [23:0] shaped_sample2_d = ($signed(sample_out2_reg) * $signed({1'b0, envelope2_pipe})); // 
    wire signed [23:0] shaped_sample2_h1_d  = ($signed(sample_out2_h1_reg) * $signed({1'b0, envelope2_pipe})); // 
    wire signed [23:0] shaped_sample2_h2_d  = ($signed(sample_out2_h2_reg) * $signed({1'b0, envelope2_pipe})); // 
    wire signed [23:0] shaped_sample2_h3_d  = ($signed(sample_out2_h3_reg) * $signed({1'b0, envelope2_pipe})); // 

    wire signed [23:0] shaped_sample2, shaped_sample2_h1, shaped_sample2_h2, shaped_sample2_h3;

    dffr #(.WIDTH(24)) v2_shaped_fund_pipe (
        .clk(clk), .r(reset),
        .d(shaped_sample2_d), 
        .q(shaped_sample2)
    );
    dffr #(.WIDTH(24)) v2_shaped_h1_pipe (
        .clk(clk), .r(reset),
        .d(shaped_sample2_h1_d), 
        .q(shaped_sample2_h1)
    );
    dffr #(.WIDTH(24)) v2_shaped_h2_pipe (
        .clk(clk), .r(reset),
        .d(shaped_sample2_h2_d), 
        .q(shaped_sample2_h2)
    );
    dffr #(.WIDTH(24)) v2_shaped_h3_pipe (
        .clk(clk), .r(reset),
        .d(shaped_sample2_h3_d), 
        .q(shaped_sample2_h3)
    );

    wire signed [23:0] shaped_sample2_2, shaped_sample2_h1_2, shaped_sample2_h2_2, shaped_sample2_h3_2;
    
    // two stages as suggested by DSP block
    dffr #(.WIDTH(24)) v2_shaped_fund_pipe2 (
        .clk(clk), .r(reset),
        .d(shaped_sample2),
        .q(shaped_sample2_2)
    );

    dffr #(.WIDTH(24)) v2_shaped_fund_pipe2 (
        .clk(clk), .r(reset),
        .d(shaped_sample2_h1),
        .q(shaped_sample2_h1_2)
    );

    dffr #(.WIDTH(24)) v2_shaped_fund_pipe2 (
        .clk(clk), .r(reset),
        .d(shaped_sample2_h2),
        .q(shaped_sample2_h2_2)
    );

    dffr #(.WIDTH(24)) v2_shaped_fund_pipe2 (
        .clk(clk), .r(reset),
        .d(shaped_sample2_h3),
        .q(shaped_sample2_h3_2)
    );


    // Voice 3
    // 3) Timer:
    wire [5:0] n3state, next_n3state;
    dffre #(.WIDTH(6)) note3_reg (
        .clk(clk), .r(reset),
        .en(((beat && !voice3_ready) || load_new_note3) && play_enable),
        .d(next_n3state),
        .q(n3state)
    );
    assign next_n3state = (load_new_note3)
                        ? duration_to_load : n3state - 1;
    assign voice3_ready = (n3state == 6'b0);

    // BEGIN DYNAMICS IMPL.
    wire [5:0] n3_duration;
    dffre #(.WIDTH(6)) note3_duration_dffre (
        .clk(clk), .r(reset),
        .en(load_new_note3),
        .d(duration_to_load),
        .q(n3_duration)
    );

    // set up timer
    wire [5:0] n3_elapsed = n3_duration - n3state;

    // generate the envelope for voice 1 that will be multiplied
    wire [7:0] envelope3;
    wire [8:0] envelope3_temp = (n3_elapsed << 6);  // temporary wire to have 9 bits, holding 256
    wire in_attack3 = (n3_elapsed < ATTACK_BEATS);

    assign envelope3 = voice3_ready ? 8'd0 :      // Silent when done
                in_attack3 ? ((envelope3_temp > 9'd255) ? 8'd255 : envelope3_temp[7:0]) :  // Linear attack (0->64->128->192)
                (8'd255 >> (n3_elapsed >> 2));    // Decay by div4 each time

    // voice 3 pipelined envelope input
    wire [7:0] envelope3_pipe;
    dffr #(.WIDTH(8)) v3_env_pipe (
        .clk(clk), .r(reset),
        .d(envelope3),
        .q(envelope3_pipe)
    );

    // 3) freq_rom and sine_reader datapath:
    wire [19:0] step_size3;
    wire [5:0] freq_rom_in3;
    wire [15:0] sample_out3;
    wire new_sample_ready3;

    dffre #(.WIDTH(6)) freq_reg3 (
        .clk(clk), .r(reset),
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

    sine_reader sine_read3(
        .clk(clk), .reset(reset),
        .step_size(step_size3),
        .generate_next(play_enable && generate_next_sample),
        .sample_ready(new_sample_ready3),
        .sample(sample_out3)
    );

    sine_reader sine_read3_h1(
        .clk(clk), .reset(reset),
        .step_size(step_size3_h1),
        .generate_next(play_enable && generate_next_sample),
        .sample_ready(new_sample_ready3_h1),
        .sample(sample_out3_h1)
    );

    sine_reader sine_read3_h2(
        .clk(clk), .reset(reset),
        .step_size(step_size3_h2),
        .generate_next(play_enable && generate_next_sample),
        .sample_ready(new_sample_ready3_h2),
        .sample(sample_out3_h2)
    );

    sine_reader sine_read3_h3(
        .clk(clk), .reset(reset),
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

    // our sample_out is now multiplied by an envelope we defined
    wire signed [23:0] shaped_sample3_d = ($signed(sample_out3_reg) * $signed({1'b0, envelope3_pipe}));        // 
    wire signed [23:0] shaped_sample3_h1_d  = ($signed(sample_out3_h1_reg) * $signed({1'b0, envelope3_pipe})); 
    wire signed [23:0] shaped_sample3_h2_d  = ($signed(sample_out3_h2_reg) * $signed({1'b0, envelope3_pipe})); // 
    wire signed [23:0] shaped_sample3_h3_d  = ($signed(sample_out3_h3_reg) * $signed({1'b0, envelope3_pipe})); // 

    wire signed [23:0] shaped_sample3, shaped_sample3_h1, shaped_sample3_h2, shaped_sample3_h3;

    dffr #(.WIDTH(24)) v3_shaped_fund_pipe (
        .clk(clk), .r(reset),
        .d(shaped_sample3_d), 
        .q(shaped_sample3)
    );
    dffr #(.WIDTH(24)) v3_shaped_h1_pipe (
        .clk(clk), .r(reset),
        .d(shaped_sample3_h1_d), 
        .q(shaped_sample3_h1)
    );
    dffr #(.WIDTH(24)) v3_shaped_h2_pipe (
        .clk(clk), .r(reset),
        .d(shaped_sample3_h2_d), 
        .q(shaped_sample3_h2)
    );
    dffr #(.WIDTH(24)) v3_shaped_h3_pipe (
        .clk(clk), .r(reset),
        .d(shaped_sample3_h3_d), 
        .q(shaped_sample3_h3)
    );

    wire signed [23:0] shaped_sample3_2, shaped_sample3_h1_2, shaped_sample3_h2_2, shaped_sample3_h3_2;

    // two stages as suggested by DSP block
    dffr #(.WIDTH(24)) v3_shaped_fund_pipe2 (
        .clk(clk), .r(reset),
        .d(shaped_sample3),
        .q(shaped_sample3_2)
    );

    dffr #(.WIDTH(24)) v3_shaped_fund_pipe2 (
        .clk(clk), .r(reset),
        .d(shaped_sample3_h1),
        .q(shaped_sample3_h1_2)
    );

    dffr #(.WIDTH(24)) v3_shaped_fund_pipe2 (
        .clk(clk), .r(reset),
        .d(shaped_sample3_h2),
        .q(shaped_sample3_h2_2)
    );

    dffr #(.WIDTH(24)) v3_shaped_fund_pipe2 (
        .clk(clk), .r(reset),
        .d(shaped_sample3_h3),
        .q(shaped_sample3_h3_2)
    );

    //------

    wire voice1_ready_pipe1, voice1_ready_pipe2, voice1_ready_pipe3;
    wire voice2_ready_pipe1, voice2_ready_pipe2, voice2_ready_pipe3;
    wire voice3_ready_pipe1, voice3_ready_pipe2, voice3_ready_pipe3;

    dffr #(.WIDTH(1)) v1_ready_pipe1 (.clk(clk), .r(reset), .d(voice1_ready), .q(voice1_ready_pipe1));
    dffr #(.WIDTH(1)) v1_ready_pipe2 (.clk(clk), .r(reset), .d(voice1_ready_pipe1), .q(voice1_ready_pipe2));
    dffr #(.WIDTH(1)) v1_ready_pipe3 (.clk(clk), .r(reset), .d(voice1_ready_pipe2), .q(voice1_ready_pipe3));

    dffr #(.WIDTH(1)) v2_ready_pipe1 (.clk(clk), .r(reset), .d(voice2_ready), .q(voice2_ready_pipe1));
    dffr #(.WIDTH(1)) v2_ready_pipe2 (.clk(clk), .r(reset), .d(voice2_ready_pipe1), .q(voice2_ready_pipe2));
    dffr #(.WIDTH(1)) v2_ready_pipe3 (.clk(clk), .r(reset), .d(voice2_ready_pipe2), .q(voice2_ready_pipe3));

    dffr #(.WIDTH(1)) v3_ready_pipe1 (.clk(clk), .r(reset), .d(voice3_ready), .q(voice3_ready_pipe1));
    dffr #(.WIDTH(1)) v3_ready_pipe2 (.clk(clk), .r(reset), .d(voice3_ready_pipe1), .q(voice3_ready_pipe2));
    dffr #(.WIDTH(1)) v3_ready_pipe3 (.clk(clk), .r(reset), .d(voice3_ready_pipe2), .q(voice3_ready_pipe3));

    // we need to regularize by a factor of 256 because we set max volume at 256 (DYNAMICS)
    // Updated Output Logic
    // Gate samples - only include if voice is actively playing
    // Sum up weighted harmonics (up to 3)
    wire signed [17:0] gated_sample1 = voice1_ready_pipe3 ? 18'sd0 : ((shaped_sample1_2 >>> 8) + ((shaped_sample1_h1_2 >>> 8) >>> 4) + ((shaped_sample1_h2_2 >>> 8) >>> 1) + ((shaped_sample1_h3_2 >>> 8) >>> 4));
    wire signed [17:0] gated_sample2 = voice2_ready_pipe3 ? 18'sd0 : ((shaped_sample2_2 >>> 8) + ((shaped_sample2_h1_2 >>> 8) >>> 4) + ((shaped_sample2_h2_2 >>> 8) >>> 1) + ((shaped_sample2_h3_2 >>> 8) >>> 4));
    wire signed [17:0] gated_sample3 = voice3_ready_pipe3 ? 18'sd0 : ((shaped_sample3_2 >>> 8) + ((shaped_sample3_h1_2 >>> 8) >>> 4) + ((shaped_sample3_h2_2 >>> 8) >>> 1) + ((shaped_sample3_h3_2 >>> 8) >>> 4));
    
    wire [1:0] active_count = !voice1_ready_pipe3 + !voice2_ready_pipe3 + !voice3_ready_pipe3;
    wire signed [19:0] sample_sum = gated_sample1 + gated_sample2 + gated_sample3;
    
    reg signed [19:0] temp_sample_out;
    
    always @(*) begin
        case(active_count)
            2'd3: temp_sample_out = (sample_sum >>> 3) + (sample_sum >>> 5); // div 6, adjusted for adding harmonics
            2'd2: temp_sample_out = (sample_sum >>> 2); // div 4
            2'd1: temp_sample_out = (sample_sum >>> 1); // div 2
            default: temp_sample_out = 20'd0;
        endcase
    end

    // pipeline sample_ready signals to align with extra flip flop delay
    wire new_sample_ready_pipeline, new_sample_ready_pipeline1, new_sample_ready_pipeline2;
    assign new_sample_ready_pipeline = (new_sample_ready1 && new_sample_ready2 && new_sample_ready3);

    dffr #(.WIDTH(1)) ready_pipe0 (
        .clk(clk), .r(reset),
        .d(new_sample_ready_pipeline),
        .q(new_sample_ready_pipeline1)
    );

    dffr #(.WIDTH(1)) ready_pipe1 (
        .clk(clk), .r(reset),
        .d(new_sample_ready_pipeline1),
        .q(new_sample_ready_pipeline2) 
    );

    dffr #(.WIDTH(1)) ready_pipe2 (
        .clk(clk), .r(reset),
        .d(new_sample_ready_pipeline2),
        .q(new_sample_ready)
    );

    assign sample_out = temp_sample_out[15:0];
    
endmodule