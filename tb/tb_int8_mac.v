`timescale 1ns/1ps

module tb_int8_mac;
    reg clk = 0;
    reg reset = 1;
    reg clear = 0;
    reg enable = 0;
    reg signed [7:0] a = 0;
    reg signed [7:0] b = 0;
    wire signed [63:0] sum;
    reg signed [63:0] expected = 0;
    integer checks = 0;
    integer i;
    integer j;

    int8_mac dut (
        .clk(clk), .reset(reset), .clear(clear), .enable(enable),
        .a(a), .b(b), .sum(sum)
    );

    always #5 clk = ~clk;

    // Integers keep reference multiplication independent of INT8 RTL sizing.
    task step;
        input next_reset;
        input next_clear;
        input next_enable;
        input integer next_a;
        input integer next_b;
        begin
            @(negedge clk);
            reset = next_reset;
            clear = next_clear;
            enable = next_enable;
            a = next_a;
            b = next_b;
            #1;
            if (checks > 0 && sum !== expected) begin
                $display("FAIL: sum changed between clock edges");
                $fatal(1);
            end
            if (next_reset || next_clear)
                expected = 0;
            else if (next_enable)
                expected = expected + next_a * next_b;
            @(posedge clk);
            #1;
            if (sum !== expected) begin
                $display("FAIL: check=%0d a=%0d b=%0d sum=%0d expected=%0d",
                         checks, a, b, sum, expected);
                $fatal(1);
            end
            checks = checks + 1;
        end
    endtask

    initial begin
        step(1, 0, 0, 0, 0);
        // [1, -2, 3] dot [4, 5, -6] = 4 - 10 - 18 = -24.
        step(0, 0, 1, 1, 4);
        step(0, 0, 0, 127, 127);     // Stall must not consume inputs.
        step(0, 0, 1, -2, 5);
        step(0, 0, 1, 3, -6);
        if (sum !== -64'sd24) $fatal(1, "FAIL: example dot product");
        step(0, 0, 1, 0, -128);
        step(0, 1, 1, 127, 127);     // Clear discards this product.
        step(0, 0, 1, -128, -128);
        step(1, 0, 1, -128, 127);    // Reset during active accumulation.
        step(0, 0, 1, 127, 127);
        step(1, 1, 1, 127, -128);
        step(0, 0, 0, -128, -128);

        // Check every signed INT8 pair through both connected modules.
        for (i = -128; i <= 127; i = i + 1)
            for (j = -128; j <= 127; j = j + 1)
                step(0, 0, 1, i, j);

        // Distinct vectors must start with a clear edge.
        step(0, 1, 0, 0, 0);
        for (i = 0; i < 4096; i = i + 1)
            step(0, 0, 1, -128, -128);
        if (sum !== 64'sd67108864) $fatal(1, "FAIL: positive full-length vector");
        step(0, 1, 0, 0, 0);
        for (i = 0; i < 4096; i = i + 1)
            step(0, 0, 1, -128, 127);
        if (sum !== -64'sd66584576) $fatal(1, "FAIL: negative full-length vector");
        step(0, 0, 0, 99, 99);

        $display("PASS: MAC checked for %0d clock cycles, including all 65,536 INT8 pairs.", checks);
        $finish;
    end
endmodule
