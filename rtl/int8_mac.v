module int8_mac (
    input  wire clk,
    input  wire reset,
    input  wire clear,
    input  wire enable,
    input  wire signed [7:0] a,
    input  wire signed [7:0] b,
    output wire signed [63:0] sum
);

    wire signed [15:0] product;

    int8_multiplier multiplier (
        .a(a),
        .b(b),
        .product(product)
    );

    int8_accumulator accumulator (
        .clk(clk),
        .reset(reset),
        .clear(clear),
        .enable(enable),
        .product(product),
        .sum(sum)
    );

endmodule
