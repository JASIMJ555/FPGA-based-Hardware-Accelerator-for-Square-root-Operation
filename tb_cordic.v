`timescale 1ns/1ps
module cordic_tb;

reg clk = 0;
always #5 clk = ~clk; // 100 MHz clock

reg rst_n = 0;
reg start = 0;
reg signed [17:0] x_in = 0;
reg signed [17:0] y_in = 0;
wire signed [17:0] sqrt_out;
wire done;

// Instantiate the DUT
cordic_sqrt_pipelined dut (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .x_in(x_in),
    .y_in(y_in),
    .sqrt_out(sqrt_out),
    .done(done)
);

initial begin
    // Reset
    rst_n = 0;
    #50;
    rst_n = 1;
    #20;

    // Test 1
    apply_inputs(300, 400);
    // Test 2
    apply_inputs(1000, 0);
    // Test 3
    apply_inputs(1000, 1000);
    // Test 4
    apply_inputs(-359, 510);
    // Test 5
    apply_inputs(0, 0);

    #100;
    $display("Simulation completed.");
    $finish;
end

task apply_inputs(input signed [17:0] tx, input signed [17:0] ty);
    begin
        x_in = tx;
        y_in = ty;
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;
        wait(done == 1);
        @(posedge clk);
        $display("x=%d  y=%d  ->  sqrt_out=%d", x_in, y_in, sqrt_out);
        #20;
    end
endtask

endmodule
