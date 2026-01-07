//
//  music_player module
//
//  This music_player module connects up the MCU, song_reader, note_player,
//  beat_generator, and codec_conditioner. It provides an output that indicates
//  a new sample (new_sample_generated) which will be used in lab 5.
//

module music_player(
    // Standard system clock and reset
    input clk,
    input reset,

    // Our debounced and one-pulsed button inputs.
    input play_button,
    input next_button,

    // The raw new_frame signal from the ac97_if codec.
    input new_frame,

    // This output must go high for one cycle when a new sample is generated.
    output wire new_sample_generated,

    // Our final output sample to the codec. This needs to be synced to
    // new_frame.
    output wire [15:0] sample_out_l,
    output wire [15:0] sample_out_r,
    output wire [15:0] sample_out, // we still want this for display

    // New outputs for enhanced display
    output wire [15:0] voice1_sample,
    output wire [15:0] voice2_sample,
    output wire [15:0] voice3_sample,
    output wire voice1_active,
    output wire voice2_active,
    output wire voice3_active
);
    // The BEAT_COUNT is parameterized so you can reduce this in simulation.
    // If you reduce this to 100 your simulation will be 10x faster.
    parameter BEAT_COUNT = 1000;


//
//  ****************************************************************************
//      Master Control Unit
//  ****************************************************************************
//   The reset_player output from the MCU is run only to the song_reader because
//   we don't need to reset any state in the note_player. If we do it may make
//   a pop when it resets the output sample.
//
 
    wire play;
    wire reset_player;
    wire [1:0] current_song;
    wire song_done;
    mcu mcu(
        .clk(clk),
        .reset(reset),
        .play_button(play_button),
        .next_button(next_button),
        .play(play),
        .reset_player(reset_player),
        .song(current_song),
        .song_done(song_done)
    );

//
//  ****************************************************************************
//      Song Reader (UPDATED TO ACCOUNT FOR CHORDS LOGIC CHANGES)
//  ****************************************************************************
//
    wire [5:0] note_to_play;
    wire [5:0] duration_for_note;
    wire advance_done, voice1_done, voice2_done, voice3_done;
    wire new_advance, new_note1, new_note2, new_note3;
    song_reader song_reader(
        .clk(clk),
        .reset(reset | reset_player),
        .play(play),
        .song(current_song),
        .note(note_to_play),
        .duration(duration_for_note),
        .song_done(song_done),
    // Updated note_done logic for chords
        .advance_done(advance_done),
        .voice1_done(voice1_done),
        .voice2_done(voice2_done),
        .voice3_done(voice3_done),
    // Updated new_note logic for chords
        .new_advance(new_advance),
        .new_note1(new_note1),
        .new_note2(new_note2),
        .new_note3(new_note3)
    );

//   
//  ************************************************************************
//      Note Player (UPDATED TO ACCOUNT FOR CHORDS/STEREO LOGIC CHANGES)
//  ************************************************************************
//  
    wire beat;
    wire generate_next_sample, generate_next_sample0;
    wire [15:0] note_sample_l, note_sample_l0;
    wire [15:0] note_sample_r, note_sample_r0;
    wire [15:0] note_sample, note_sample_0;
    wire note_sample_ready, note_sample_ready0;

    // Wires for display samples
    wire [15:0] voice1_sample_raw, voice2_sample_raw, voice3_sample_raw;

    // Get voice ready signals
    wire voice1_ready_internal, voice2_ready_internal, voice3_ready_internal;

    // These pipeline registers were added to decrease the length of the critical path!
    dffr pipeline_ff_gen_next_sample (.clk(clk), .r(reset), .d(generate_next_sample0), .q(generate_next_sample));
    dffr #(.WIDTH(16)) pipeline_ff_note_sample_l (.clk(clk), .r(reset), .d(note_sample_l0), .q(note_sample_l));
    dffr #(.WIDTH(16)) pipeline_ff_note_sample_r (.clk(clk), .r(reset), .d(note_sample_r0), .q(note_sample_r));
    dffr #(.WIDTH(16)) pipeline_ff_note_sample (.clk(clk), .r(reset), .d(note_sample_0), .q(note_sample));
    dffr pipeline_ff_new_sample_ready (.clk(clk), .r(reset), .d(note_sample_ready0), .q(note_sample_ready));

    note_player note_player(
        .clk(clk),
        .reset(reset),
        .play_enable(play),
        .note_to_load(note_to_play),
        .duration_to_load(duration_for_note),
        .beat(beat),
        .generate_next_sample(generate_next_sample),
        .sample_out_l(note_sample_l0),
        .sample_out_r(note_sample_r0),
        .sample_out(note_sample_0),
        .new_sample_ready(note_sample_ready0),
    // Updated load_new_note logic for chords
        .load_new_advance(new_advance),
        .load_new_note1(new_note1),
        .load_new_note2(new_note2),
        .load_new_note3(new_note3),
    // Updated done_with_note logic for chords
        .done_with_advance(advance_done),
        .voice1_ready(voice1_done),
        .voice2_ready(voice2_done),
        .voice3_ready(voice3_done),
    // Updated samples out for enhanced display
        .sample_out1_display(voice1_sample_raw),
        .sample_out2_display(voice2_sample_raw),
        .sample_out3_display(voice3_sample_raw)
    );

    // Pipeline individual sample outputs to match main sample delays
    dffr #(.WIDTH(16)) pipeline_voice1_sample (.clk(clk), .r(reset), .d(voice1_sample_raw), .q(voice1_sample));
    dffr #(.WIDTH(16)) pipeline_voice2_sample (.clk(clk), .r(reset), .d(voice2_sample_raw), .q(voice2_sample));
    dffr #(.WIDTH(16)) pipeline_voice3_sample (.clk(clk), .r(reset), .d(voice3_sample_raw), .q(voice3_sample));

    // Active signals for individual sample outputs
    wire voice1_active_raw = !voice1_done && play;
    wire voice2_active_raw = !voice2_done && play;
    wire voice3_active_raw = !voice3_done && play;
    dffr pipeline_v1_active (.clk(clk), .r(reset), .d(voice1_active_raw), .q(voice1_active));
    dffr pipeline_v2_active (.clk(clk), .r(reset), .d(voice2_active_raw), .q(voice2_active));
    dffr pipeline_v3_active (.clk(clk), .r(reset), .d(voice3_active_raw), .q(voice3_active));


   
//   
//  ****************************************************************************
//      Beat Generator
//  ****************************************************************************
//  By default this will divide the generate_next_sample signal (48kHz from the
//  codec's new_frame input) down by 1000, to 48Hz. If you change the BEAT_COUNT
//  parameter when instantiating this you can change it for simulation.
//  
    beat_generator #(.WIDTH(10), .STOP(BEAT_COUNT)) beat_generator(
        .clk(clk),
        .reset(reset),
        .en(generate_next_sample),
        .beat(beat)
    );

//  
//  ****************************************************************************
//      Codec Conditioner (updated for stereo logic changes) 
//  ****************************************************************************
//  
    wire new_sample_generated0;
    wire [15:0] sample_out_l0; 
    wire [15:0] sample_out_r0;
    wire [15:0] sample_out_0;

    dffr pipeline_ff_nsg (.clk(clk), .r(reset), .d(new_sample_generated0), .q(new_sample_generated));
    dffr #(.WIDTH(16)) pipeline_ff_sample_out_l (.clk(clk), .r(reset), .d(sample_out_l0), .q(sample_out_l));
    dffr #(.WIDTH(16)) pipeline_ff_sample_out_r (.clk(clk), .r(reset), .d(sample_out_r0), .q(sample_out_r));
    dffr #(.WIDTH(16)) pipeline_ff_sample_out (.clk(clk), .r(reset), .d(sample_out_0), .q(sample_out));
    //assign sample_out = sample_out0;

    assign new_sample_generated0 = generate_next_sample;
    codec_conditioner codec_conditioner_l(
        .clk(clk),
        .reset(reset),
        .new_sample_in(note_sample_l),
        .latch_new_sample_in(note_sample_ready),
        .generate_next_sample(), // unconnected
        .new_frame(new_frame),
        .valid_sample(sample_out_l0)
    );

    codec_conditioner codec_conditioner_r(
        .clk(clk),
        .reset(reset),
        .new_sample_in(note_sample_r),
        .latch_new_sample_in(note_sample_ready),
        .generate_next_sample(), // unconnected
        .new_frame(new_frame),
        .valid_sample(sample_out_r0)
    );

    codec_conditioner codec_conditioner(
        .clk(clk),
        .reset(reset),
        .new_sample_in(note_sample),
        .latch_new_sample_in(note_sample_ready),
        .generate_next_sample(generate_next_sample0), // driver of conditioner
        .new_frame(new_frame),
        .valid_sample(sample_out_0)
    );

endmodule