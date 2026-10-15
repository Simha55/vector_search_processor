module int8_query_buffer #(
    parameter integer MAX_ELEMENTS = 4096,
    parameter integer ADDRESS_WIDTH = (MAX_ELEMENTS <= 1) ? 1 : $clog2(MAX_ELEMENTS)
) (
    input  wire clk,
    input  wire reset,
    input  wire write_enable,
    input  wire [ADDRESS_WIDTH-1:0] write_address,
    input  wire signed [7:0] write_data,
    input  wire read_enable,
    input  wire [ADDRESS_WIDTH-1:0] read_address,
    output reg signed [7:0] read_data,
    output reg read_valid
);

    reg signed [7:0] memory [0:MAX_ELEMENTS-1];

    always @(posedge clk) begin
        if (reset) begin
            read_data <= 8'sd0;
            read_valid <= 1'b0;
        end else begin
            read_valid <= 1'b0;

            if (write_enable && (write_address < MAX_ELEMENTS))
                memory[write_address] <= write_data;

            if (read_enable && (read_address < MAX_ELEMENTS)) begin
                read_data <= memory[read_address];
                read_valid <= 1'b1;
            end
        end
    end

endmodule
