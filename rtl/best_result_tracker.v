module best_result_tracker (
    input  wire clk,
    input  wire reset,
    input  wire clear,
    input  wire enable,
    input  wire signed [63:0] candidate_score,
    input  wire [31:0] candidate_id,
    output reg best_valid,
    output reg signed [63:0] best_score,
    output reg [31:0] best_id
);

    always @(posedge clk) begin
        if (reset) begin
            best_valid <= 1'b0;
            best_score <= 64'sd0;
            best_id <= 32'd0;
        end else if (clear) begin
            best_valid <= 1'b0;
            best_score <= 64'sd0;
            best_id <= 32'd0;
        end else if (enable) begin
            if (!best_valid ||
                (candidate_score > best_score) ||
                ((candidate_score == best_score) && (candidate_id < best_id))) begin
                best_valid <= 1'b1;
                best_score <= candidate_score;
                best_id <= candidate_id;
            end
        end
    end

endmodule
