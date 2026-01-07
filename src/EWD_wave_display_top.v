module wave_display_top(
    input clk,
    input reset,
    input new_sample,
    input [15:0] sample,
    // New inputs for EWD
    input [15:0] sample_voice1,
    input [15:0] sample_voice2,
    input [15:0] sample_voice3,
    input voice1_active,
    input voice2_active,
    input voice3_active,
    // original ip/op below
    input [10:0] x,  // [0..1279]
    input [9:0]  y,  // [0..1023]     
    input valid,
    input vsync,
    output [7:0] r,
    output [7:0] g,
    output [7:0] b
);

    wire [7:0] read_sample, write_sample;
    wire [8:0] read_address, write_address;
    wire read_index;
    wire write_en;
    wire wave_display_idle = ~vsync;

    wave_capture wc(
        .clk(clk),
        .reset(reset),
        .new_sample_ready(new_sample),
        .new_sample_in(sample),
        .write_address(write_address),
        .write_enable(write_en),
        .write_sample(write_sample),
        .wave_display_idle(wave_display_idle),
        .read_index(read_index)
    );
    
    ram_1w2r #(.WIDTH(8), .DEPTH(9)) sample_ram(
        .clka(clk),
        .clkb(clk),
        .wea(write_en),
        .addra(write_address),
        .dina(write_sample),
        .douta(),
        .addrb(read_address),
        .doutb(read_sample)
    );
 
    // Additional RAMs/RAM logic for individual voice waveforms
    wire [7:0] write_sample_v1 = sample_voice1[15:8] + 8'd128;
    wire [7:0] write_sample_v2 = sample_voice2[15:8] + 8'd128;
    wire [7:0] write_sample_v3 = sample_voice3[15:8] + 8'd128;
    
    wire [7:0] read_sample_v1, read_sample_v2, read_sample_v3;
    wire read_v1_active, read_v2_active, read_v3_active;

    // Voice 1 RAM
    ram_1w2r #(.WIDTH(8), .DEPTH(9)) ram_v1(
        .clka(clk),
        .clkb(clk),
        .wea(write_en),
        .addra(write_address),
        .dina(write_sample_v1),
        .douta(),
        .addrb(read_address),
        .doutb(read_sample_v1)
    );

    // Voice 2 RAM
    ram_1w2r #(.WIDTH(8), .DEPTH(9)) ram_v2(
        .clka(clk),
        .clkb(clk),
        .wea(write_en),
        .addra(write_address),
        .dina(write_sample_v2),
        .douta(),
        .addrb(read_address),
        .doutb(read_sample_v2)
    );

    // Voice 3 RAM
    ram_1w2r #(.WIDTH(8), .DEPTH(9)) ram_v3(
        .clka(clk),
        .clkb(clk),
        .wea(write_en),
        .addra(write_address),
        .dina(write_sample_v3),
        .douta(),
        .addrb(read_address),
        .doutb(read_sample_v3)
    );

    // Voice Active RAM (All 3 in single 3-bit RAM)
        // Voice 1 RAM
    ram_1w2r #(.WIDTH(3), .DEPTH(9)) ram_active(
        .clka(clk),
        .clkb(clk),
        .wea(write_en),
        .addra(write_address),
        .dina({voice3_active, voice2_active, voice1_active}),
        .douta(),
        .addrb(read_address),
        .doutb({read_v3_active, read_v2_active, read_v1_active})
    );



    wire valid_pixel;
    wire [7:0] wd_r, wd_g, wd_b;
    wave_display wd(
        .clk(clk),
        .reset(reset),
        .x(x),
        .y(y),
        .valid(valid),
        .read_address(read_address),
        .read_value(read_sample),
        // New EWD args
        .read_value_v1(read_sample_v1),
        .read_value_v2(read_sample_v2),
        .read_value_v3(read_sample_v3),
        .v1_active(read_v1_active),
        .v2_active(read_v2_active),
        .v3_active(read_v3_active),
        // End of new args
        .read_index(read_index),
        .valid_pixel(valid_pixel),
        .r(wd_r), .g(wd_g), .b(wd_b)
    );

    assign {r, g, b} = valid_pixel ? {wd_r, wd_g, wd_b} : {3{8'b0}};

endmodule
