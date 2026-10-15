`timescale 1ns/1ps

module tb_int8_accumulator;
    reg clk = 0;
    reg reset;
    reg clear;
    reg enable;
    reg signed [15:0] product;
    wire signed [63:0] sum;
    integer checks = 0;
    integer i;
    reg signed [63:0] expected;

    int8_accumulator dut (
        .clk(clk), .reset(reset), .clear(clear), .enable(enable),
        .product(product), .sum(sum)
    );

    always #5 clk = ~clk;

    // Drive on the falling edge, then check after rising-edge updates settle.
    task step;
        input next_reset;
        input next_clear;
        input next_enable;
        input signed [15:0] next_product;
        input signed [63:0] expected_sum;
        begin
            @(negedge clk);
            reset = next_reset;
            clear = next_clear;
            enable = next_enable;
            product = next_product;
            // Even asserted reset/clear must wait for a rising edge.
            #1;
            if (checks > 0 && sum !== expected) begin
                $display("FAIL: sum changed between clock edges");
                $fatal(1);
            end
            @(posedge clk);
            #1;
            if (sum !== expected_sum) begin
                $display("FAIL: check=%0d reset=%b clear=%b enable=%b product=%0d sum=%0d expected=%0d",
                         checks, reset, clear, enable, product, sum, expected_sum);
                $fatal(1);
            end
            expected = expected_sum;
            checks = checks + 1;
        end
    endtask

    initial begin
        reset = 1;
        clear = 0;
        enable = 0;
        product = 0;
        expected = 0;

        step(1, 0, 0, 0, 0);
        step(0, 0, 1, 6, 6);
        step(0, 0, 1, -8, -2);
        step(0, 0, 1, 10, 8);
        step(0, 0, 0, 123, 8);       // Disabled input is ignored.
        step(0, 0, 1, 0, 8);
        step(0, 1, 1, 99, 0);        // Clear takes priority over enable.
        step(0, 0, 1, -32768, -32768);
        step(0, 0, 1, 32767, -1);
        step(0, 0, 1, -1, -2);
        step(1, 0, 1, 100, 0);       // Reset discards an active sum/input.
        step(0, 0, 1, 7, 7);
        step(1, 1, 1, -100, 0);      // Simultaneous reset, clear, enable.
        step(0, 0, 0, -32768, 0);

        // 4096 maximum positive INT8 products: (-128) * (-128).
        for (i = 0; i < 4096; i = i + 1)
            step(0, 0, 1, 16384, (i + 1) * 64'sd16384);
        step(0, 1, 0, 0, 0);
        // 4096 most-negative INT8 products: (-128) * 127.
        for (i = 0; i < 4096; i = i + 1)
            step(0, 0, 1, -16256, (i + 1) * -64'sd16256);
        step(0, 1, 0, 0, 0);

        // Deterministic varied inputs, stalls, clears, and resets.
        for (i = 0; i < 1024; i = i + 1) begin
            @(negedge clk);
            reset = (i % 127 == 0);
            clear = (i % 53 == 0);
            enable = (i % 5 != 0);
            product = ((i * 7919) % 65536) - 32768;
            if (reset || clear)
                expected = 0;
            else if (enable)
                expected = expected + $signed(product);
            @(posedge clk);
            #1;
            if (sum !== expected) begin
                $display("FAIL: varied sequence index=%0d sum=%0d expected=%0d", i, sum, expected);
                $fatal(1);
            end
            checks = checks + 1;
        end

        $display("PASS: accumulator checked for %0d clock cycles.", checks);
        $finish;
    end
endmodule
