module int8_search_controller #(
    parameter integer MAX_ELEMENTS = 4096,
    parameter integer ADDRESS_WIDTH = (MAX_ELEMENTS <= 1) ? 1 : $clog2(MAX_ELEMENTS)
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
    output wire [31:0] result_id,
    output wire buffer_write_enable,
    output wire [ADDRESS_WIDTH-1:0] buffer_write_address,
    output wire signed [7:0] buffer_write_data,
    output wire buffer_read_enable,
    output wire [ADDRESS_WIDTH-1:0] buffer_read_address,
    input wire buffer_read_valid,
    input wire signed [7:0] buffer_read_data,
    output wire dot_command_valid,
    input wire dot_command_ready,
    output wire [15:0] dot_dimensions,
    output wire dot_pair_valid,
    input wire dot_pair_ready,
    output wire signed [7:0] dot_a,
    output wire signed [7:0] dot_b,
    input wire dot_result_valid,
    output wire dot_result_ready,
    input wire signed [63:0] dot_score,
    output wire tracker_clear,
    output wire tracker_enable,
    output wire signed [63:0] tracker_candidate_score,
    output wire [31:0] tracker_candidate_id,
    input wire tracker_best_valid,
    input wire signed [63:0] tracker_best_score,
    input wire [31:0] tracker_best_id
);

    localparam [3:0] IDLE = 4'd0, VALIDATE = 4'd1, LOAD_QUERY = 4'd2,
                     DOT_COMMAND = 4'd3, RECEIVE_ELEMENT = 4'd4,
                     READ_QUERY = 4'd5, WAIT_QUERY = 4'd6, SEND_PAIR = 4'd7,
                     WAIT_SCORE = 4'd8, RESULT = 4'd9;
    localparam [1:0] ERROR_NONE = 2'd0, ERROR_DIMENSIONS = 2'd1,
                     ERROR_EMPTY_DATABASE = 2'd2;

    reg [3:0] state;
    reg [15:0] saved_dimensions;
    reg [31:0] saved_vector_count;
    reg [15:0] element_index;
    reg [31:0] vector_index;
    reg signed [7:0] saved_database_element;
    reg signed [7:0] saved_query_element;
    reg [1:0] error_code;

    assign command_ready = !reset && (state == IDLE);
    assign query_ready = !reset && (state == LOAD_QUERY);
    assign database_ready = !reset && (state == RECEIVE_ELEMENT);
    assign result_valid = !reset && (state == RESULT);
    assign result_error = error_code;
    assign result_found = (error_code == ERROR_NONE) && tracker_best_valid;
    assign result_score = tracker_best_score;
    assign result_id = tracker_best_id;

    assign buffer_write_enable = query_valid && query_ready;
    assign buffer_write_address = element_index[ADDRESS_WIDTH-1:0];
    assign buffer_write_data = query_data;
    assign buffer_read_enable = !reset && (state == READ_QUERY);
    assign buffer_read_address = element_index[ADDRESS_WIDTH-1:0];

    assign dot_command_valid = !reset && (state == DOT_COMMAND);
    assign dot_dimensions = saved_dimensions;
    assign dot_pair_valid = !reset && (state == SEND_PAIR);
    assign dot_a = saved_query_element;
    assign dot_b = saved_database_element;
    assign dot_result_ready = !reset && (state == WAIT_SCORE);

    assign tracker_clear = !reset && (state == VALIDATE);
    assign tracker_enable = dot_result_valid && dot_result_ready;
    assign tracker_candidate_score = dot_score;
    assign tracker_candidate_id = vector_index;

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            saved_dimensions <= 16'd0;
            saved_vector_count <= 32'd0;
            element_index <= 16'd0;
            vector_index <= 32'd0;
            saved_database_element <= 8'sd0;
            saved_query_element <= 8'sd0;
            error_code <= ERROR_NONE;
        end else begin
            case (state)
                IDLE: begin
                    if (command_valid && command_ready) begin
                        saved_dimensions <= dimensions;
                        saved_vector_count <= vector_count;
                        element_index <= 16'd0;
                        vector_index <= 32'd0;
                        error_code <= ERROR_NONE;
                        state <= VALIDATE;
                    end
                end
                VALIDATE: begin
                    // Validate the full length BEFORE narrowing it to an address.
                    if ((saved_dimensions == 16'd0) || (saved_dimensions > MAX_ELEMENTS)) begin
                        error_code <= ERROR_DIMENSIONS;
                        state <= RESULT;
                    end else if (saved_vector_count == 32'd0) begin
                        error_code <= ERROR_EMPTY_DATABASE;
                        state <= RESULT;
                    end else
                        state <= LOAD_QUERY;
                end
                LOAD_QUERY: begin
                    if (query_valid && query_ready) begin
                        if (element_index == saved_dimensions - 16'd1) begin
                            element_index <= 16'd0;
                            state <= DOT_COMMAND;
                        end else
                            element_index <= element_index + 16'd1;
                    end
                end
                DOT_COMMAND: begin
                    if (dot_command_valid && dot_command_ready)
                        state <= RECEIVE_ELEMENT;
                end
                RECEIVE_ELEMENT: begin
                    if (database_valid && database_ready) begin
                        saved_database_element <= database_data;
                        state <= READ_QUERY;
                    end
                end
                READ_QUERY: state <= WAIT_QUERY;
                WAIT_QUERY: begin
                    if (buffer_read_valid) begin
                        saved_query_element <= buffer_read_data;
                        state <= SEND_PAIR;
                    end
                end
                SEND_PAIR: begin
                    if (dot_pair_valid && dot_pair_ready) begin
                        if (element_index == saved_dimensions - 16'd1)
                            state <= WAIT_SCORE;
                        else begin
                            element_index <= element_index + 16'd1;
                            state <= RECEIVE_ELEMENT;
                        end
                    end
                end
                WAIT_SCORE: begin
                    if (dot_result_valid && dot_result_ready) begin
                        // Tracker stores this score on the SAME edge.
                        if (vector_index == saved_vector_count - 32'd1)
                            state <= RESULT;
                        else begin
                            vector_index <= vector_index + 32'd1;
                            element_index <= 16'd0;
                            state <= DOT_COMMAND;
                        end
                    end
                end
                RESULT: begin
                    if (result_valid && result_ready)
                        state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end

endmodule
