`timescale 1ns / 1ps

module pwm_led_tb();
    reg clk, reset;
    reg [7:0] duty_cycle;
    wire led_out;

    pwm_led dut(
        .clk(clk),
        .reset(reset),
        .duty_cycle(duty_cycle),
        .led_out(led_out)
    );

    // clk and reset
    initial begin
        clk = 1'b0;
        reset = 1'b1;
        repeat (4) #1 clk = ~clk;
        reset = 1'b0;
        forever #1 clk = ~clk;
    end

    // Tests
    initial begin
        
        // initialize input
        duty_cycle = 8'd0;

        // Reset cooldown
        #30;
        
        $display("Test 1, duty_cycle = 0 (LED should stay OFF)");
        duty_cycle = 8'd0;
        #10; // Wait for one full counter cycle (256 clocks)
        $display("duty_cycle=0: led_out=%b", led_out);

        $display("Test 2, duty_cycle = 128 (50%%)");
        duty_cycle = 8'd128;
        #500; 
        $display("After 500ns with duty_cycle=128: led_out=%b", led_out);
    end
    
    endmodule
