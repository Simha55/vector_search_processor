module int8_multiplier (
    input  wire signed [7:0] a,
    input  wire signed [7:0] b,
    output wire signed [15:0] product
);

    assign product = a * b;

endmodule