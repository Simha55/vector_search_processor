// Fixed-dimension complete-query FIFO. Partial input packets are not visible.
module cosine_query_queue #(
    parameter integer WIDTH=64, CHUNKS=8, DEPTH=1000
) (
    input wire clk, reset,
    input wire input_valid,
    output wire input_ready,
    input wire [WIDTH-1:0] input_data,
    input wire [31:0] input_id,
    output wire head_valid,
    output wire [31:0] head_id,
    input wire [31:0] head_chunk,
    output wire [WIDTH-1:0] head_data,
    input wire pop,
    output wire partial,
    output reg [31:0] level
);
    reg [WIDTH-1:0] data [0:DEPTH*CHUNKS-1];
    reg [31:0] ids [0:DEPTH-1];
    reg [31:0] write_slot, read_slot, write_chunk;
    wire write = input_valid && input_ready;
    wire complete = write && write_chunk==CHUNKS-1;
    wire remove = pop && head_valid;
    assign partial = write_chunk!=0;
    assign input_ready = !reset && level<DEPTH;
    assign head_valid = !reset && level!=0;
    assign head_id = head_valid ? ids[read_slot] : 32'd0;
    assign head_data = head_valid && head_chunk<CHUNKS ? data[read_slot*CHUNKS+head_chunk] : {WIDTH{1'b0}};
    always @(posedge clk) begin
        if (reset) begin
            write_slot<=0; read_slot<=0; write_chunk<=0; level<=0;
        end else begin
            if (write) begin
                data[write_slot*CHUNKS+write_chunk] <= input_data;
                if (write_chunk==0) ids[write_slot]<=input_id;
                if (complete) begin
                    write_chunk<=0;
                    write_slot <= write_slot==DEPTH-1 ? 0 : write_slot+1;
                end else write_chunk<=write_chunk+1;
            end
            if (remove) read_slot <= read_slot==DEPTH-1 ? 0 : read_slot+1;
            case ({complete,remove})
                2'b10: level<=level+1;
                2'b01: level<=level-1;
                default: level<=level;
            endcase
        end
    end
endmodule
