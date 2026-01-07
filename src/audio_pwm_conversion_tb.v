`timescale 1ns / 1ps

module audio_to_pwm_conversion_tb();
    reg clk, reset;
    reg [15:0] sample;
    wire led_out;
    
    audio_to_pwm_conversion dut(
        .clk(clk),
        .reset(reset),
        .sample(sample),
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
        sample = 16'd0;
        // reset cooldown
        #10;
        
        $display("Test 1, sample = 16'h4000 (positive, duty_cycle should be ~64)");
        sample = 16'h4000;  // 64 decimal
        #520; 
        $display("after full cycle sample=0x%h: led_out=%b", sample, led_out);
        
        $display("Test 2, sample = 16'hC000 (negative, duty_cycle should be ~64)");
        sample = 16'hC000;
        #300; 
        $display("at end of sim sample=0x%h: led_out=%b", sample, led_out);

        $finish;
    end
endmodule
