module int8_vector_search #(
    parameter integer MAX_ELEMENTS = 4096
) (
    input wire clk,
    input wire reset,
    input wire command_valid,
    output wire command_ready,
    input wire [15:0] dimensions,
    input wire [31:0] vector_count,
    input wire query_valid,
    output wire query_ready,
    input wire signed [7:0] query_data,
    input wire database_valid,
    output wire database_ready,
    input wire signed [7:0] database_data,
    output wire result_valid,
    input wire result_ready,
    output wire [1:0] result_error,
    output wire result_found,
    output wire signed [63:0] result_score,
    output wire [31:0] result_id
);

    localparam integer ADDRESS_WIDTH = (MAX_ELEMENTS <= 1) ? 1 : $clog2(MAX_ELEMENTS);

    wire buffer_write_enable;
    wire [ADDRESS_WIDTH-1:0] buffer_write_address;
    wire signed [7:0] buffer_write_data;
    wire buffer_read_enable;
    wire [ADDRESS_WIDTH-1:0] buffer_read_address;
    wire buffer_read_valid;
    wire signed [7:0] buffer_read_data;
    wire dot_command_valid;
    wire dot_command_ready;
    wire [15:0] dot_dimensions;
    wire dot_pair_valid;
    wire dot_pair_ready;
    wire signed [7:0] dot_a;
    wire signed [7:0] dot_b;
    wire dot_result_valid;
    wire dot_result_ready;
    wire signed [63:0] dot_score;
    wire tracker_clear;
    wire tracker_enable;
    wire signed [63:0] tracker_candidate_score;
    wire [31:0] tracker_candidate_id;
    wire tracker_best_valid;
    wire signed [63:0] tracker_best_score;
    wire [31:0] tracker_best_id;

    int8_search_controller #(.MAX_ELEMENTS(MAX_ELEMENTS), .ADDRESS_WIDTH(ADDRESS_WIDTH)) controller (
        .clk(clk),
        .reset(reset),
        .command_valid(command_valid),
        .command_ready(command_ready),
        .dimensions(dimensions),
        .vector_count(vector_count),
        .query_valid(query_valid),
        .query_ready(query_ready),
        .query_data(query_data),
        .database_valid(database_valid),
        .database_ready(database_ready),
        .database_data(database_data),
        .result_valid(result_valid),
        .result_ready(result_ready),
        .result_error(result_error),
        .result_found(result_found),
        .result_score(result_score),
        .result_id(result_id),
        .buffer_write_enable(buffer_write_enable),
        .buffer_write_address(buffer_write_address),
        .buffer_write_data(buffer_write_data),
        .buffer_read_enable(buffer_read_enable),
        .buffer_read_address(buffer_read_address),
        .buffer_read_valid(buffer_read_valid),
        .buffer_read_data(buffer_read_data),
        .dot_command_valid(dot_command_valid),
        .dot_command_ready(dot_command_ready),
        .dot_dimensions(dot_dimensions),
        .dot_pair_valid(dot_pair_valid),
        .dot_pair_ready(dot_pair_ready),
        .dot_a(dot_a),
        .dot_b(dot_b),
        .dot_result_valid(dot_result_valid),
        .dot_result_ready(dot_result_ready),
        .dot_score(dot_score),
        .tracker_clear(tracker_clear),
        .tracker_enable(tracker_enable),
        .tracker_candidate_score(tracker_candidate_score),
        .tracker_candidate_id(tracker_candidate_id),
        .tracker_best_valid(tracker_best_valid),
        .tracker_best_score(tracker_best_score),
        .tracker_best_id(tracker_best_id)
    );
    int8_query_buffer #(.MAX_ELEMENTS(MAX_ELEMENTS), .ADDRESS_WIDTH(ADDRESS_WIDTH)) query_buffer (
        .clk(clk), .reset(reset), .write_enable(buffer_write_enable),
        .write_address(buffer_write_address), .write_data(buffer_write_data),
        .read_enable(buffer_read_enable), .read_address(buffer_read_address),
        .read_valid(buffer_read_valid), .read_data(buffer_read_data)
    );
    int8_dot_product dot_product (
        .clk(clk), .reset(reset), .command_valid(dot_command_valid),
        .command_ready(dot_command_ready), .dimensions(dot_dimensions),
        .pair_valid(dot_pair_valid), .pair_ready(dot_pair_ready), .a(dot_a), .b(dot_b),
        .result_valid(dot_result_valid), .result_ready(dot_result_ready), .score(dot_score)
    );
    best_result_tracker tracker (
        .clk(clk), .reset(reset), .clear(tracker_clear), .enable(tracker_enable),
        .candidate_score(tracker_candidate_score), .candidate_id(tracker_candidate_id),
        .best_valid(tracker_best_valid), .best_score(tracker_best_score), .best_id(tracker_best_id)
    );

endmodule
