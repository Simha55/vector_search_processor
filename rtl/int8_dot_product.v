module int8_dot_product (
    input  wire clk,
    input  wire reset,
    input  wire command_valid,
    output wire command_ready,
    input  wire [15:0] dimensions,
    input  wire pair_valid,
    output wire pair_ready,
    input  wire signed [7:0] a,
    input  wire signed [7:0] b,
    output wire result_valid,
    input  wire result_ready,
    output wire signed [63:0] score
);

    localparam [1:0] IDLE = 2'd0;
    localparam [1:0] CLEAR = 2'd1;
    localparam [1:0] RUN = 2'd2;
    localparam [1:0] RESULT = 2'd3;

    reg [1:0] state;
    reg [15:0] remaining;
    wire clear_sum;
    wire accept_pair;

    assign command_ready = !reset && (state == IDLE);
    assign pair_ready = !reset && (state == RUN);
    assign result_valid = !reset && (state == RESULT);
    assign clear_sum = (state == CLEAR);
    assign accept_pair = pair_valid && pair_ready;

    int8_mac mac (
        .clk(clk),
        .reset(reset),
        .clear(clear_sum),
        .enable(accept_pair),
        .a(a),
        .b(b),
        .sum(score)
    );

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            remaining <= 16'd0;
        end else begin
            case (state)
                IDLE: begin
                    if (command_valid && command_ready) begin
                        remaining <= dimensions;
                        state <= CLEAR;
                    end
                end
                CLEAR: begin
                    if (remaining == 16'd0)
                        state <= RESULT;
                    else
                        state <= RUN;
                end
                RUN: begin
                    if (accept_pair) begin
                        remaining <= remaining - 16'd1;
                        if (remaining == 16'd1)
                            state <= RESULT;
                    end
                end
                RESULT: begin
                    if (result_valid && result_ready)
                        state <= IDLE;
                end
                default: begin
                    state <= IDLE;
                    remaining <= 16'd0;
                end
            endcase
        end
    end

endmodule
