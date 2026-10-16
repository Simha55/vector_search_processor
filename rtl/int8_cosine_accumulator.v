// Vector accumulation stage. Independent of the normalizer; tagged totals queue
// into its pipeline while the next database vector starts accumulating.
module int8_cosine_accumulator #(
    parameter integer LANES=8
) (
    input wire clk, reset,
    input wire command_valid,
    output wire command_ready,
    input wire [15:0] dimensions,
    input wire [31:0] vector_id,
    input wire pair_valid,
    output wire pair_ready,
    input wire [LANES*8-1:0] query_data, database_data,
    output wire sums_valid,
    input wire sums_ready,
    output reg signed [63:0] dot_sum,
    output reg [31:0] query_norm, database_norm,
    output reg [31:0] output_id
);
    localparam integer LEAVES=1 << $clog2(LANES), LEVELS=$clog2(LEAVES);
    localparam [2:0] IDLE=0, CLEAR=1, RUN=2, REDUCE=3, OUTPUT=4;
    reg [2:0] state;
    reg [15:0] saved_dimensions;
    reg [31:0] processed, reduction_wait;
    wire signed [63:0] dot_tree [1:2*LEAVES-1];
    wire signed [63:0] query_tree [1:2*LEAVES-1];
    wire signed [63:0] database_tree [1:2*LEAVES-1];
    assign command_ready=!reset && state==IDLE;
    assign pair_ready=!reset && state==RUN;
    assign sums_valid=!reset && state==OUTPUT;
    genvar n;
    generate
        for(n=0;n<LEAVES;n=n+1) begin: lanes
            if(n<LANES) begin: active
                wire signed [7:0] q=query_data[8*n +:8];
                wire signed [7:0] d=database_data[8*n +:8];
                wire consume=pair_valid && pair_ready && processed+n<saved_dimensions;
                int8_mac p(.clk(clk),.reset(reset),.clear(state==CLEAR),.enable(consume),.a(q),.b(d),.sum(dot_tree[LEAVES+n]));
                int8_mac qs(.clk(clk),.reset(reset),.clear(state==CLEAR),.enable(consume),.a(q),.b(q),.sum(query_tree[LEAVES+n]));
                int8_mac ds(.clk(clk),.reset(reset),.clear(state==CLEAR),.enable(consume),.a(d),.b(d),.sum(database_tree[LEAVES+n]));
            end else begin: padding
                assign dot_tree[LEAVES+n]=0;
                assign query_tree[LEAVES+n]=0;
                assign database_tree[LEAVES+n]=0;
            end
        end
        for(n=1;n<LEAVES;n=n+1) begin: tree
            reg signed [63:0] p,q,d;
            always @(posedge clk) if(state==REDUCE) begin
                p<=dot_tree[2*n]+dot_tree[2*n+1];
                q<=query_tree[2*n]+query_tree[2*n+1];
                d<=database_tree[2*n]+database_tree[2*n+1];
            end
            assign dot_tree[n]=p;
            assign query_tree[n]=q;
            assign database_tree[n]=d;
        end
    endgenerate
    always @(posedge clk) begin
        if(reset) begin
            state<=IDLE; processed<=0; saved_dimensions<=0; reduction_wait<=0;
            dot_sum<=0; query_norm<=0; database_norm<=0; output_id<=0;
        end else case(state)
            IDLE: if(command_valid && command_ready) begin
                saved_dimensions<=dimensions; output_id<=vector_id;
                processed<=0; state<=CLEAR;
            end
            CLEAR: state<=RUN;
            RUN: if(pair_valid && pair_ready) begin
                processed<=processed+LANES;
                if(processed+LANES>=saved_dimensions) begin state<=REDUCE; reduction_wait<=0; end
            end
            REDUCE: if(reduction_wait==LEVELS) begin
                dot_sum<=dot_tree[1]; query_norm<=query_tree[1]; database_norm<=database_tree[1];
                state<=OUTPUT;
            end else reduction_wait<=reduction_wait+1;
            OUTPUT: if(sums_valid && sums_ready) state<=IDLE;
            default: state<=IDLE;
        endcase
    end
endmodule
