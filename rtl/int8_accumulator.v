module int8_accumulator (
    input  wire clk,
    input  wire reset,
    input  wire clear,
    input  wire enable,
    input  wire signed [15:0] product,
    output reg  signed [63:0] sum
);

    wire signed [63:0] extended_product;
    assign extended_product = {{48{product[15]}}, product};

    always @(posedge clk) begin
        if (reset)
            sum <= 64'sd0;
        else if (clear)
            sum <= 64'sd0;
        else if (enable)
            sum <= sum + extended_product;
    end

endmodule
