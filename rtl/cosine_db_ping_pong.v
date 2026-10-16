// Two vector-sized banks: fill one while the consumer drains the other.
// Memory responses must be in request order. One vector occupies one bank.
module cosine_db_ping_pong #(
    parameter integer WIDTH=64, CHUNKS=8, VECTORS=24
) (
    input wire clk, reset,
    input wire start_valid,
    output wire start_ready,
    output wire request_valid,
    input wire request_ready,
    output wire [31:0] request_address,
    input wire response_valid,
    output wire response_ready,
    input wire [WIDTH-1:0] response_data,
    output wire output_valid,
    input wire output_ready,
    output wire [WIDTH-1:0] output_data,
    output wire [31:0] output_vector,
    output wire [31:0] output_chunk,
    output wire output_last,
    output wire filling_bank,
    output wire consuming_bank
);
    reg [WIDTH-1:0] banks [0:2*CHUNKS-1];
    reg [31:0] bank_vector [0:1];
    reg [1:0] full;
    reg active, write_bank, read_bank;
    reg [31:0] fill_vector, issued, received, read_chunk;
    wire can_fill = active && fill_vector<VECTORS && !full[write_bank];
    assign start_ready = !reset && !active;
    assign request_valid = !reset && can_fill && issued<CHUNKS;
    assign request_address = fill_vector*CHUNKS+issued;
    assign response_ready = !reset && can_fill && received<CHUNKS;
    assign output_valid = !reset && active && full[read_bank];
    assign output_data = output_valid ? banks[read_bank*CHUNKS+read_chunk] : {WIDTH{1'b0}};
    assign output_vector = output_valid ? bank_vector[read_bank] : 32'd0;
    assign output_chunk = read_chunk;
    assign output_last = read_chunk==CHUNKS-1;
    assign filling_bank = write_bank;
    assign consuming_bank = read_bank;
    always @(posedge clk) begin
        if (reset) begin
            full<=0; active<=0; write_bank<=0; read_bank<=0;
            fill_vector<=0; issued<=0; received<=0; read_chunk<=0;
        end else if (start_valid && start_ready) begin
            full<=0; active<=1; write_bank<=0; read_bank<=0;
            fill_vector<=0; issued<=0; received<=0; read_chunk<=0;
        end else begin
            if (request_valid && request_ready) issued<=issued+1;
            if (response_valid && response_ready) begin
                banks[write_bank*CHUNKS+received]<=response_data;
                if (received==CHUNKS-1) begin
                    full[write_bank]<=1;
                    bank_vector[write_bank]<=fill_vector;
                    write_bank<=!write_bank;
                    fill_vector<=fill_vector+1;
                    issued<=0; received<=0;
                end else received<=received+1;
            end
            if (output_valid && output_ready) begin
                if (output_last) begin
                    full[read_bank]<=0;
                    read_chunk<=0; read_bank<=!read_bank;
                    if (bank_vector[read_bank]==VECTORS-1) active<=0;
                end else read_chunk<=read_chunk+1;
            end
        end
    end
endmodule
