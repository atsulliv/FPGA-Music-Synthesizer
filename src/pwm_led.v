// pwm_led.v

module pwm_led(
    input clk,
    input reset,
    input [7:0] duty_cycle, // 0 = off, 255 = full brightness
    output led_out // PWM output to LED
);

    // declare FSM states
    `define OFF 1'b0
    `define ON  1'b1
    
    // declare state registers
    wire state, next_state;
    wire led_out_next;
    
    // declare counter
    wire [7:0] counter, counter_next;
    
    // begin counter logic
    assign counter_next = counter + 8'd1;  // wrap at 256 (number of levels)
    dffr #(.WIDTH(8)) counter_reg (
        .clk(clk),
        .r(reset),
        .d(counter_next),
        .q(counter)
    );
    
    // state logic
    reg next_state_comb;
    reg led_out_comb;

    // instantiate state reg
    dffr #(.WIDTH(1)) state_reg (
        .clk(clk),
        .r(reset),
        .d(next_state),
        .q(state)
    );
    
    always @(*) begin
        case (state)
            `OFF: begin
                led_out_comb = 1'b0;
                // if counter is at zero and the duty cycle is greater than 0, goto ON
                if (counter == 8'd0 && duty_cycle > 8'd0)
                    next_state_comb = ON;
                else
                    next_state_comb = OFF; // otherwise stay off
            end
            `ON: begin
                led_out_comb = 1'b1;
                // turn off when counter reaches the cycle
                if (counter >= duty_cycle)
                    next_state_comb = OFF;
                else
                    next_state_comb = ON;
            end
            default: begin
                next_state_comb = OFF;
                led_out_comb = 1'b0;
            end
        endcase
    end
    
    assign next_state = next_state_comb;
    assign led_out_next = led_out_comb;

    // assign led_out with ff
    dffr #(.WIDTH(1)) output_reg (
        .clk(clk),
        .r(reset),
        .d(led_out_next),
        .q(led_out)
    );

endmodule