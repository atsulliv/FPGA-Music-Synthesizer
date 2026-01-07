// audio_to_pwm_conversion.v

module audio_to_pwm_conversion(
    input clk,
    input reset,
    input [15:0] sample, // signed 16-bit audio sample from the note_player
    output led_out // PWM output
);

    // logic that changes output sample to magnitude
    wire signed [15:0] sample_signed;
    wire [15:0] sample_abs_val;
    wire [7:0] duty_cycle;
    assign sample_signed = sample;
    
    // dealing with case of if sample is negative at MSB.
    assign sample_abs_val = sample_signed[15] ? -sample_signed : sample_signed;
    
    // since we have 255 levels, we are taking the 8 MSBs
    assign duty_cycle = sample_abs_val[15:8];
    
    // instantiate FSM for PWM ctrl
    pwm_led pwm(
        .clk(clk),
        .reset(reset),
        .duty_cycle(duty_cycle),
        .led_out(led_out)
    );

endmodule