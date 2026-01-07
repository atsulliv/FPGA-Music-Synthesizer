module wave_display (
    input clk,
    input reset,
    input [10:0] x,  // [0..1279]
    input [9:0]  y,  // [0..1023]
    input valid,
    input [7:0] read_value, // from RAM, what we read
    // New EWD inputs
    input [7:0] read_value_v1,
    input [7:0] read_value_v2,
    input [7:0] read_value_v3,
    input v1_active,
    input v2_active,
    input v3_active,
    input read_index,   // comes in from prev module
    output wire [8:0] read_address,
    output wire valid_pixel,        // what verifies blkout or not
    output wire [7:0] r,
    output wire [7:0] g,
    output wire [7:0] b     // rgb now assigned a variable value
);

    // Break up wave display into pipeline to prevent timing violations
    // Stage 0
    wire [2:0] x_top = x[10:8];
    reg x_encoded;
    always @(*) begin
        case (x_top)
            3'b001: x_encoded = 1'b0;
            3'b010: x_encoded = 1'b1;
            default: x_encoded = 1'b0;
        endcase
    end

    assign read_address = {read_index, x_encoded, x[7:1]};

    wire x_valid = (x_top == 3'b001) || (x_top == 3'b010);
    wire y_valid = (y[9] == 1'b0);
    wire x_gt_edge = (x >= 11'b001_00000010);
    wire valid_pixel_s0 = x_valid && y_valid && x_gt_edge;

    // Stage 1
    wire [8:0] prev_read_addr;
    dffr #(9) addr_reg (.clk(clk), .r(reset), .d(read_address), .q(prev_read_addr));

    wire addr_changed = (read_address != prev_read_addr);

    // Adjust values
    wire [7:0] read_value_adj_s1 = (read_value >> 1) + 8'd32;
    wire [7:0] read_value_v1_adj_s1 = (read_value_v1 >> 1) + 8'd32;
    wire [7:0] read_value_v2_adj_s1 = (read_value_v2 >> 1) + 8'd32;
    wire [7:0] read_value_v3_adj_s1 = (read_value_v3 >> 1) + 8'd32;

    // Previous values
    wire [7:0] prev_read_value, prev_read_value_v1, prev_read_value_v2, prev_read_value_v3;
    dffre #(8) prev_val (.clk(clk), .r(reset), .en(addr_changed), .d(read_value_adj_s1), .q(prev_read_value));
    dffre #(8) prev_v1 (.clk(clk), .r(reset), .en(addr_changed), .d(read_value_v1_adj_s1), .q(prev_read_value_v1));
    dffre #(8) prev_v2 (.clk(clk), .r(reset), .en(addr_changed), .d(read_value_v2_adj_s1), .q(prev_read_value_v2));
    dffre #(8) prev_v3 (.clk(clk), .r(reset), .en(addr_changed), .d(read_value_v3_adj_s1), .q(prev_read_value_v3));

    // Previous active
    wire prev_v1_active, prev_v2_active, prev_v3_active;
    dffre #(1) prev_a1 (.clk(clk), .r(reset), .en(addr_changed), .d(v1_active), .q(prev_v1_active));
    dffre #(1) prev_a2 (.clk(clk), .r(reset), .en(addr_changed), .d(v2_active), .q(prev_v2_active));
    dffre #(1) prev_a3 (.clk(clk), .r(reset), .en(addr_changed), .d(v3_active), .q(prev_v3_active));

    // Pipeline control signals
    wire [7:0] y_rest_s1;
    wire valid_pixel_s1, valid_s1;
    dffr #(8) y_reg (.clk(clk), .r(reset), .d(y[8:1]), .q(y_rest_s1));
    dffr #(1) vp_reg (.clk(clk), .r(reset), .d(valid_pixel_s0), .q(valid_pixel_s1));
    dffr #(1) v_reg (.clk(clk), .r(reset), .d(valid), .q(valid_s1));

    // Stage 2 (comparisons)
    // Register adjusted values for comparison
    wire [7:0] curr_val, curr_v1, curr_v2, curr_v3;
    dffr #(8) curr_reg (.clk(clk), .r(reset), .d(read_value_adj_s1), .q(curr_val));
    dffr #(8) curr_v1_reg (.clk(clk), .r(reset), .d(read_value_v1_adj_s1), .q(curr_v1));
    dffr #(8) curr_v2_reg (.clk(clk), .r(reset), .d(read_value_v2_adj_s1), .q(curr_v2));
    dffr #(8) curr_v3_reg (.clk(clk), .r(reset), .d(read_value_v3_adj_s1), .q(curr_v3));

    // Pipeline y/control signals again
    wire [7:0] y_rest_s2;
    wire valid_pixel_s2, valid_s2;
    wire v1_act_s2, v2_act_s2, v3_act_s2;
    wire prev_v1_act_s2, prev_v2_act_s2, prev_v3_act_s2;
    
    dffr #(8) y_reg2 (.clk(clk), .r(reset), .d(y_rest_s1), .q(y_rest_s2));
    dffr #(1) vp_reg2 (.clk(clk), .r(reset), .d(valid_pixel_s1), .q(valid_pixel_s2));
    dffr #(1) v_reg2 (.clk(clk), .r(reset), .d(valid_s1), .q(valid_s2));
    dffr #(1) a1_reg (.clk(clk), .r(reset), .d(v1_active), .q(v1_act_s2));
    dffr #(1) a2_reg (.clk(clk), .r(reset), .d(v2_active), .q(v2_act_s2));
    dffr #(1) a3_reg (.clk(clk), .r(reset), .d(v3_active), .q(v3_act_s2));
    dffr #(1) pa1_reg (.clk(clk), .r(reset), .d(prev_v1_active), .q(prev_v1_act_s2));
    dffr #(1) pa2_reg (.clk(clk), .r(reset), .d(prev_v2_active), .q(prev_v2_act_s2));
    dffr #(1) pa3_reg (.clk(clk), .r(reset), .d(prev_v3_active), .q(prev_v3_act_s2));

    // Min/max for combined
    wire [7:0] min_val = (curr_val < prev_read_value) ? curr_val : prev_read_value;
    wire [7:0] max_val = (curr_val > prev_read_value) ? curr_val : prev_read_value;
    wire between = (y_rest_s2 <= max_val) && (y_rest_s2 >= min_val);

    // Min/max for voice 1
    wire [7:0] min_v1 = (curr_v1 < prev_read_value_v1) ? curr_v1 : prev_read_value_v1;
    wire [7:0] max_v1 = (curr_v1 > prev_read_value_v1) ? curr_v1 : prev_read_value_v1;
    wire between_v1 = (y_rest_s2 <= max_v1) && (y_rest_s2 >= min_v1);

    // Min/max for voice 2
    wire [7:0] min_v2 = (curr_v2 < prev_read_value_v2) ? curr_v2 : prev_read_value_v2;
    wire [7:0] max_v2 = (curr_v2 > prev_read_value_v2) ? curr_v2 : prev_read_value_v2;
    wire between_v2 = (y_rest_s2 <= max_v2) && (y_rest_s2 >= min_v2);

    // Min/max for voice 3
    wire [7:0] min_v3 = (curr_v3 < prev_read_value_v3) ? curr_v3 : prev_read_value_v3;
    wire [7:0] max_v3 = (curr_v3 > prev_read_value_v3) ? curr_v3 : prev_read_value_v3;
    wire between_v3 = (y_rest_s2 <= max_v3) && (y_rest_s2 >= min_v3);

    // Select signals
    wire sel = valid_pixel_s2 && valid_s2 && between;
    wire sel_v1 = valid_pixel_s2 && valid_s2 && between_v1 && (v1_act_s2 || prev_v1_act_s2);
    wire sel_v2 = valid_pixel_s2 && valid_s2 && between_v2 && (v2_act_s2 || prev_v2_act_s2);
    wire sel_v3 = valid_pixel_s2 && valid_s2 && between_v3 && (v3_act_s2 || prev_v3_act_s2);

    // Stage 3 (color o/p)
    wire [23:0] color_out = 
        sel    ? 24'hFFFFFF :
        sel_v1 ? 24'hFF0000 :
        sel_v2 ? 24'h00FF00 :
        sel_v3 ? 24'h0000FF :
                 24'h000000;

    wire [23:0] color_out_reg;
    wire valid_pixel_s3;
    dffr #(24) color_reg (.clk(clk), .r(reset), .d(color_out), .q(color_out_reg));
    dffr #(1) vp_reg3 (.clk(clk), .r(reset), .d(valid_pixel_s2), .q(valid_pixel_s3));

    assign valid_pixel = valid_pixel_s3;
    assign r = color_out_reg[23:16];
    assign g = color_out_reg[15:8];
    assign b = color_out_reg[7:0];

endmodule