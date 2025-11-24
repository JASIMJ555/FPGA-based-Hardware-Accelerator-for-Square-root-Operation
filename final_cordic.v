`timescale 1ns/1ps
// ================================================================
// MODULE 1: CORDIC Stage (The Building Block)
// ================================================================
module cordic_stage_vectoring #(
    parameter DATA_WIDTH = 18,
    parameter ANGLE_WIDTH = 16,
    parameter STAGE_NUM = 0
)(
    input  wire clk,
    input  wire rst_n,
    input  wire signed [DATA_WIDTH-1:0] x_i,
    input  wire signed [DATA_WIDTH-1:0] y_i,
    input  wire signed [ANGLE_WIDTH-1:0] z_i,
    input  wire signed [ANGLE_WIDTH-1:0] arctan_val,
    output reg  signed [DATA_WIDTH-1:0] x_o,
    output reg  signed [DATA_WIDTH-1:0] y_o,
    output reg  signed [ANGLE_WIDTH-1:0] z_o
);

    reg signed [DATA_WIDTH-1:0] x_next, y_next;
    reg signed [ANGLE_WIDTH-1:0] z_next;
    wire d_direction;

    // Vectoring mode: decide direction based on sign of y_i to drive it to zero
    assign d_direction = (y_i[DATA_WIDTH-1] == 1); // 1 if y is negative, 0 if positive

    // Combinational logic to calculate the next state
    always @(*) begin
        if (d_direction == 1) begin // y_i is negative, rotate Counter-Clockwise
            x_next = x_i - (y_i >>> STAGE_NUM);
            y_next = y_i + (x_i >>> STAGE_NUM);
            z_next = z_i - arctan_val;
        end else begin // y_i is positive, rotate Clockwise
            x_next = x_i + (y_i >>> STAGE_NUM);
            y_next = y_i - (x_i >>> STAGE_NUM);
            z_next = z_i + arctan_val;
        end
    end

    // Registered outputs for the pipeline stage
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_o <= 0;
            y_o <= 0;
            z_o <= 0;
        end else begin
            x_o <= x_next;
            y_o <= y_next;
            z_o <= z_next;
        end
    end
endmodule


// ================================================================
// MODULE 2: CORDIC Pipeline (The Core Engine with Accuracy Correction)
// ================================================================
module cordic_sqrt_pipelined(
    input  wire clk,
    input  wire rst_n,
    input  wire start,
    input  wire signed [17:0] x_in,
    input  wire signed [17:0] y_in,
    output reg  signed [17:0] sqrt_out,
    output reg  done
);

    parameter DATA_WIDTH  = 18;
    parameter ANGLE_WIDTH = 16;
    parameter NUM_STAGES  = 12;

    wire signed [DATA_WIDTH-1:0] x_pipe [0:NUM_STAGES];
    wire signed [DATA_WIDTH-1:0] y_pipe [0:NUM_STAGES];
    wire signed [ANGLE_WIDTH-1:0] z_pipe [0:NUM_STAGES];

    // Synthesizable Look-Up Table using a function
    function signed [ANGLE_WIDTH-1:0] get_arctan_val (input integer stage_num);
        case(stage_num)
            0:  get_arctan_val = 16'h2D00;
            1:  get_arctan_val = 16'h1A92;
            2:  get_arctan_val = 16'h0E09;
            3:  get_arctan_val = 16'h0722;
            4:  get_arctan_val = 16'h0395;
            5:  get_arctan_val = 16'h01CA;
            6:  get_arctan_val = 16'h00E5;
            7:  get_arctan_val = 16'h0073;
            8:  get_arctan_val = 16'h0039;
            9:  get_arctan_val = 16'h001D;
            10: get_arctan_val = 16'h000E;
            11: get_arctan_val = 16'h0007;
            default: get_arctan_val = 16'h0000;
        endcase
    endfunction

    // Pre-processing: Take absolute values for vectoring
    assign x_pipe[0] = (x_in[DATA_WIDTH-1]) ? -x_in : x_in;
    assign y_pipe[0] = (y_in[DATA_WIDTH-1]) ? -y_in : y_in;
    assign z_pipe[0] = 0;

    // Generate pipeline stages
    genvar i;
    generate
        for (i = 0; i < NUM_STAGES; i = i + 1) begin : stage_gen
            cordic_stage_vectoring #(.STAGE_NUM(i)) stage (
                .clk(clk),
                .rst_n(rst_n),
                .x_i(x_pipe[i]),
                .y_i(y_pipe[i]),
                .z_i(z_pipe[i]),
                .x_o(x_pipe[i+1]),
                .y_o(y_pipe[i+1]),
                .z_o(z_pipe[i+1]),
                .arctan_val(get_arctan_val(i))
            );
        end
    endgenerate

    // Post-processing: Remove CORDIC gain and apply accuracy correction
    wire signed [DATA_WIDTH-1:0] raw_output = x_pipe[NUM_STAGES];
    wire signed [DATA_WIDTH-1:0] scaled_result_temp;
    wire signed [DATA_WIDTH-1:0] intermediate_result;
    wire signed [DATA_WIDTH-1:0] final_scaled_result;

    assign scaled_result_temp = (raw_output >>> 1) + (raw_output >>> 3) - (raw_output >>> 6) - (raw_output >>> 9);
    assign intermediate_result = scaled_result_temp - (scaled_result_temp >>> 12);
    assign final_scaled_result = intermediate_result - (intermediate_result >>> 9); // Final accuracy correction

    // Done signal generation
    reg [NUM_STAGES:0] start_delay_pipe;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sqrt_out <= 0;
            done <= 0;
            start_delay_pipe <= 0;
        end else begin
            sqrt_out <= final_scaled_result;
            start_delay_pipe <= {start_delay_pipe[NUM_STAGES-1:0], start};
            done <= start_delay_pipe[NUM_STAGES];
        end
    end
endmodule


// ================================================================
// MODULE 3: Top Level with Auto-Reset (NO BUTTON NEEDED)
// ================================================================
module cordic_sqrt_top_no_reset(
    input wire clk
);

    // Power-On Reset Circuit
    reg [4:0] reset_counter = 5'b11111;
    wire rst_n;

    always @(posedge clk) begin
        if (|reset_counter) begin
            reset_counter <= reset_counter - 1;
        end
    end

    assign rst_n = (reset_counter == 0); // rst_n high only when counter finishes

    // Internal signals for connecting the components
    wire start;
    wire signed [17:0] x_in;
    wire signed [17:0] y_in;
    wire signed [17:0] sqrt_out;
    wire done;

    // Instantiate the CORDIC engine
    cordic_sqrt_pipelined dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .x_in(x_in),
        .y_in(y_in),
        .sqrt_out(sqrt_out),
        .done(done)
    );

    // Instantiate VIO (Virtual Input/Output)
    vio_0 vio_inst (
        .clk(clk),
        .probe_in0(sqrt_out),
        .probe_in1(done),
        .probe_out0(start),
        .probe_out1(x_in),
        .probe_out2(y_in)
    );

    // Instantiate ILA (Integrated Logic Analyzer)
    ila_0 ila_inst (
        .clk(clk),
        .probe0(start),
        .probe1(rst_n),
        .probe2(x_in),
        .probe3(y_in),
        .probe4(sqrt_out),
        .probe5(done)
    );
endmodule
