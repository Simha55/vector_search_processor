// Host-loaded packed vector storage, followed by a latency-configurable read pipeline.
// The caller freezes host writes before starting searches. Memory is not reset.
module cosine_database_memory #(
    parameter integer WIDTH=64, WORDS=192, READ_LATENCY=2
) (
    input wire clk, reset,
    input wire write_valid,
    input wire [31:0] write_address,
    input wire [WIDTH-1:0] write_data,
    input wire request_valid,
    output wire request_ready,
    input wire [31:0] request_address,
    output wire response_valid,
    input wire response_ready,
    output wire [WIDTH-1:0] response_data
);
    reg [WIDTH-1:0] memory [0:WORDS-1];
    reg [READ_LATENCY-1:0] valid;
    reg [WIDTH-1:0] pipeline [0:READ_LATENCY-1];
    wire advance = !valid[READ_LATENCY-1] || response_ready;
    assign request_ready = !reset && advance;
    assign response_valid = !reset && valid[READ_LATENCY-1];
    assign response_data = response_valid ? pipeline[READ_LATENCY-1] : {WIDTH{1'b0}};
    integer stage;
    always @(posedge clk) begin
        if (!reset && write_valid && write_address<WORDS) memory[write_address]<=write_data;
        if (reset) valid<=0;
        else if (advance) begin
            valid[0]<=request_valid && request_address<WORDS;
            if (request_valid && request_address<WORDS) pipeline[0]<=memory[request_address];
            for (stage=1;stage<READ_LATENCY;stage=stage+1) begin
                valid[stage]<=valid[stage-1];
                pipeline[stage]<=pipeline[stage-1];
            end
        end
    end
endmodule
