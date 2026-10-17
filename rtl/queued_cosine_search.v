// Fixed-dimension resident vector DB + 1000-query queue + double-buffered prefetch.
// Returns one top-K item per output handshake, in rank order, tagged by query ID.
module queued_cosine_search #(
    parameter integer DIMENSIONS=64, LANES=8, DATABASE_VECTORS=24,
    parameter integer QUERY_DEPTH=1000, TOP_K=5, MEMORY_LATENCY=2
) (
    input wire clk, reset,
    input wire database_write_valid,
    output wire database_write_ready,
    input wire [31:0] database_write_address,
    input wire [LANES*8-1:0] database_write_data,
    input wire database_commit,
    output reg database_loaded,
    input wire query_valid,
    output wire query_ready,
    input wire [LANES*8-1:0] query_data,
    input wire [31:0] query_id,
    input wire run_enable,
    output wire [31:0] queued_queries,
    output wire result_valid,
    input wire result_ready,
    output wire [31:0] result_query_id, result_rank, result_count, result_vector_id,
    output wire signed [31:0] result_score,
    output wire result_last,
    output wire [1:0] result_error,
    output reg [63:0] bank_switches, fetch_compute_overlap, normalize_compute_overlap, active_cycles,
    output wire [31:0] normalizer_inflight
);
    localparam integer WIDTH=LANES*8, CHUNKS=(DIMENSIONS+LANES-1)/LANES;
    // Explicit port width without a SystemVerilog size cast.
    localparam [15:0] VECTOR_DIMENSIONS=DIMENSIONS;
    localparam [2:0] IDLE=0, START_FETCH=1, COMMAND=2, STREAM=3, DRAIN=4, RESULT=5;
    reg [2:0] state;
    reg [31:0] active_id, completed_vectors, output_rank;
    wire queue_valid, queue_ready, queue_pop, queue_partial;
    wire [31:0] queue_id;
    wire [WIDTH-1:0] query_chunk;
    wire fetch_start_ready, db_request_valid, db_request_ready, db_response_valid, db_response_ready;
    wire [31:0] db_request_address;
    wire [WIDTH-1:0] db_response_data, fetch_data;
    wire fetch_valid, fetch_ready, fetch_last, fill_bank, read_bank;
    wire [31:0] fetch_vector, fetch_chunk;
    wire accumulator_ready, pair_ready, sums_valid, sums_ready;
    wire signed [63:0] dot_sum;
    wire [31:0] query_norm, database_norm, sums_id;
    wire normalized_valid, normalized_zero;
    wire signed [31:0] normalized_score;
    wire [31:0] normalized_id;
    wire normalized_ready=!reset && state!=IDLE && state!=RESULT;
    wire [31:0] top_count, top_id;
    wire signed [31:0] top_score;
    wire result_transfer=result_valid && result_ready;

    assign database_write_ready=!reset && !run_enable && state==IDLE && queued_queries==0 && !queue_partial && database_write_address<DATABASE_VECTORS*CHUNKS;
    assign query_ready=!reset && database_loaded && queue_ready && !database_write_valid && !database_commit;
    assign fetch_ready=!reset && state==STREAM && pair_ready;
    assign result_valid=!reset && state==RESULT;
    assign result_query_id=active_id;
    assign result_rank=output_rank;
    assign result_count=top_count;
    assign result_vector_id=top_id;
    assign result_score=top_score;
    assign result_error=top_count==0 ? 2'd2 : 2'd0;
    assign result_last=top_count==0 || output_rank==top_count-1;
    assign queue_pop=result_transfer && result_last;

    cosine_query_queue #(.WIDTH(WIDTH),.CHUNKS(CHUNKS),.DEPTH(QUERY_DEPTH)) queries (
        .clk(clk),.reset(reset),.input_valid(query_valid && database_loaded && !database_write_valid && !database_commit),.input_ready(queue_ready),
        .input_data(query_data),.input_id(query_id),.head_valid(queue_valid),.head_id(queue_id),
        .head_chunk(fetch_chunk),.head_data(query_chunk),.pop(queue_pop),.partial(queue_partial),.level(queued_queries)
    );
    cosine_database_memory #(.WIDTH(WIDTH),.WORDS(DATABASE_VECTORS*CHUNKS),.READ_LATENCY(MEMORY_LATENCY)) storage (
        .clk(clk),.reset(reset),.write_valid(database_write_valid && database_write_ready),
        .write_address(database_write_address),.write_data(database_write_data),
        .request_valid(db_request_valid),.request_ready(db_request_ready),.request_address(db_request_address),
        .response_valid(db_response_valid),.response_ready(db_response_ready),.response_data(db_response_data)
    );
    cosine_db_ping_pong #(.WIDTH(WIDTH),.CHUNKS(CHUNKS),.VECTORS(DATABASE_VECTORS)) prefetch (
        .clk(clk),.reset(reset),.start_valid(!reset && state==START_FETCH),.start_ready(fetch_start_ready),
        .request_valid(db_request_valid),.request_ready(db_request_ready),.request_address(db_request_address),
        .response_valid(db_response_valid),.response_ready(db_response_ready),.response_data(db_response_data),
        .output_valid(fetch_valid),.output_ready(fetch_ready),.output_data(fetch_data),
        .output_vector(fetch_vector),.output_chunk(fetch_chunk),.output_last(fetch_last),
        .filling_bank(fill_bank),.consuming_bank(read_bank)
    );
    int8_cosine_accumulator #(.LANES(LANES)) accumulator (
        .clk(clk),.reset(reset),.command_valid(!reset && state==COMMAND && fetch_valid),.command_ready(accumulator_ready),
        .dimensions(VECTOR_DIMENSIONS),.vector_id(fetch_vector),.pair_valid(fetch_valid && state==STREAM),
        .pair_ready(pair_ready),.query_data(query_chunk),.database_data(fetch_data),
        .sums_valid(sums_valid),.sums_ready(sums_ready),.dot_sum(dot_sum),
        .query_norm(query_norm),.database_norm(database_norm),.output_id(sums_id)
    );
    cosine_normalizer_pipeline normalization (
        .clk(clk),.reset(reset),.input_valid(sums_valid),.input_ready(sums_ready),
        .dot_sum(dot_sum),.query_norm(query_norm),.database_norm(database_norm),.input_id(sums_id),
        .output_valid(normalized_valid),.output_ready(normalized_ready),.score(normalized_score),
        .zero_norm(normalized_zero),.output_id(normalized_id),.inflight(normalizer_inflight)
    );
    cosine_topk #(.K(TOP_K)) topk (
        .clk(clk),.reset(reset),.clear(state==START_FETCH),
        .candidate_valid(normalized_valid && normalized_ready && !normalized_zero),
        .candidate_score(normalized_score),.candidate_id(normalized_id),.read_rank(output_rank),
        .count(top_count),.read_score(top_score),.read_id(top_id)
    );
    always @(posedge clk) begin
        if(reset) begin
            state<=IDLE; active_id<=0; completed_vectors<=0; output_rank<=0;
            database_loaded<=0; active_cycles<=0; bank_switches<=0; fetch_compute_overlap<=0; normalize_compute_overlap<=0;
        end else begin
            if(state!=IDLE) active_cycles<=active_cycles+1;
            if(database_write_valid && database_write_ready) database_loaded<=0;
            else if(database_commit && !run_enable && state==IDLE && queued_queries==0 && !queue_partial) database_loaded<=1;
            if(fetch_valid && fetch_ready && fetch_last) bank_switches<=bank_switches+1;
            if(db_response_valid && db_response_ready && fetch_valid && fetch_ready && fill_bank!=read_bank)
                fetch_compute_overlap<=fetch_compute_overlap+1;
            if(fetch_valid && fetch_ready && normalizer_inflight!=0)
                normalize_compute_overlap<=normalize_compute_overlap+1;
            if(normalized_valid && normalized_ready) begin
                completed_vectors<=completed_vectors+1;
                if(completed_vectors==DATABASE_VECTORS-1) begin state<=RESULT; output_rank<=0; end
            end
            case(state)
                IDLE: if(run_enable && database_loaded && queue_valid) begin
                    active_id<=queue_id; completed_vectors<=0; output_rank<=0; state<=START_FETCH;
                end
                START_FETCH: if(fetch_start_ready) state<=COMMAND;
                COMMAND: if(fetch_valid && accumulator_ready) state<=STREAM;
                STREAM: if(fetch_valid && fetch_ready && fetch_last)
                    state<=fetch_vector==DATABASE_VECTORS-1 ? DRAIN : COMMAND;
                DRAIN: begin end
                RESULT: if(result_transfer) begin
                    if(result_last) state<=IDLE;
                    else output_rank<=output_rank+1;
                end
                default: state<=IDLE;
            endcase
        end
    end
endmodule
