`timescale 1ns/1ps

module tb_int8_multiplier;

    reg  signed [7:0] a;
    reg  signed [7:0] b;
    wire signed [15:0] product;

    // Connect the circuit we are testing.
    int8_multiplier dut (
        .a(a),
        .b(b),
        .product(product)
    );

    // Integer variables for trying every input combination.
    integer i;
    integer j;
    integer expected;

    initial begin
        for (i = -128; i <= 127; i = i + 1) begin
            for (j = -128; j <= 127; j = j + 1) begin
                a = i;
                b = j;

                #1;  // Allow the simulated output to settle.
                expected = i * j;

                if (product !== expected) begin
                    $display(
                        "FAIL: a=%0d b=%0d product=%0d expected=%0d",
                        a, b, product, expected
                    );
                    $fatal(1);
                end
            end
        end

        $display("PASS: all 65,536 input combinations checked.");
        $finish;
    end

endmodule