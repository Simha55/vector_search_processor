`timescale 1ns/1ps

module tb_int8_search_controller;
    parameter integer MAX_ELEMENTS = 5;
    localparam integer ADDRESS_WIDTH = (MAX_ELEMENTS <= 1) ? 1 : $clog2(MAX_ELEMENTS);
    reg clk = 0;
    reg reset = 0;
    reg command_valid = 0;
    wire command_ready;
    reg [15:0] dimensions = 0;
    reg [31:0] vector_count = 0;
    reg query_valid = 0;
    wire query_ready;
    reg signed [7:0] query_data = 0;
    reg database_valid = 0;
    wire database_ready;
    reg signed [7:0] database_data = 0;
    wire result_valid;
    reg result_ready = 0;
    wire [1:0] result_error;
    wire result_found;
    wire signed [63:0] result_score;
    wire [31:0] result_id;
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
    integer searches = 0;
    integer i;
    integer v;
    integer av;
    integer bv;
    reg signed [63:0] expected;
    reg signed [63:0] vector_score;
    reg [31:0] expected_id;

    int8_search_controller #(.MAX_ELEMENTS(MAX_ELEMENTS)) dut (
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
    int8_query_buffer #(.MAX_ELEMENTS(MAX_ELEMENTS)) query_buffer (
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

    always #5 clk = ~clk;
    initial begin
        #10000000;
        $fatal(1, "FAIL: simulation timeout");
    end
    task tick;
        begin @(posedge clk); #1; end
    endtask

    task reset_engine;
        begin
            @(negedge clk);
            reset = 1;
            command_valid = 0;
            query_valid = 0;
            database_valid = 0;
            result_ready = 0;
            #1;
            if (command_ready !== 0 || query_ready !== 0 || database_ready !== 0 || result_valid !== 0)
                $fatal(1, "FAIL: reset gating");
            tick;
            @(negedge clk); reset = 0;
            tick;
            if (command_ready !== 1 || result_valid !== 0)
                $fatal(1, "FAIL: reset recovery");
        end
    endtask

    task command;
        input integer length;
        input integer count;
        begin
            @(negedge clk);
            if (command_ready !== 1) $fatal(1, "FAIL: command unavailable");
            dimensions = length;
            vector_count = count;
            command_valid = 1;
            tick;
            @(negedge clk);
            command_valid = 0;
            dimensions = 0;
            vector_count = 0; // Commands must be latched.
        end
    endtask

    task query_element;
        input integer value;
        begin
            @(negedge clk);
            query_valid = 1;
            query_data = value;
            while (!query_ready) @(negedge clk);
            tick;
            @(negedge clk); query_valid = 0;
        end
    endtask

    task database_element;
        input integer value;
        begin
            @(negedge clk);
            database_valid = 1;
            database_data = value;
            while (!database_ready) @(negedge clk);
            tick;
            @(negedge clk); database_valid = 0;
        end
    endtask

    task receive_result;
        input [1:0] error;
        input signed [63:0] wanted_score;
        input [31:0] wanted_id;
        begin
            wait (result_valid === 1'b1);
            #1;
            repeat (3) begin
                @(negedge clk);
                // Extra inputs and commands must be blocked while result waits.
                query_valid = 1;
                database_valid = 1;
                command_valid = 1;
                query_data = 99;
                database_data = 99;
                dimensions = 1;
                vector_count = 1;
                tick;
                if (result_valid !== 1 || result_error !== error ||
                    command_ready !== 0 || query_ready !== 0 || database_ready !== 0)
                    $fatal(1, "FAIL: result control/backpressure");
                if (error == 0) begin
                    if (result_found !== 1 || result_score !== wanted_score || result_id !== wanted_id) begin
                        $display("FAIL: score=%0d id=%0d expected_score=%0d expected_id=%0d",
                                 result_score, result_id, wanted_score, wanted_id);
                        $fatal(1);
                    end
                end else if (result_found !== 0 || tracker_best_valid !== 0)
                    $fatal(1, "FAIL: invalid command retained winner");
            end
            @(negedge clk);
            query_valid = 0;
            database_valid = 0;
            command_valid = 0;
            result_ready = 1;
            tick;
            if (result_valid !== 0 || command_ready !== 1)
                $fatal(1, "FAIL: result consumption");
            @(negedge clk); result_ready = 0;
            searches = searches + 1;
        end
    endtask

    task run_search;
        input integer length;
        input integer count;
        input integer mode;
        begin
            command(length, count);
            for (i = 0; i < length; i = i + 1) begin
                if (mode == 0) av = 1;
                else if (mode == 1) av = -128;
                else av = ((i * 73) % 256) - 128;
                query_element(av);
                if (i % 3 == 0) tick; // Query pauses.
            end
            for (v = 0; v < count; v = v + 1) begin
                vector_score = 0;
                for (i = 0; i < length; i = i + 1) begin
                    if (mode == 0) begin
                        av = 1;
                        // All negative, with vectors 1 and 2 tied for best.
                        if (v == 0) bv = -5; else bv = -2;
                    end else if (mode == 1) begin
                        av = -128;
                        if (v == 0) bv = 127; else bv = -128;
                    end else begin
                        av = ((i * 73) % 256) - 128;
                        bv = ((i * 31 + v * 19) % 256) - 128;
                    end
                    vector_score = vector_score + av * bv;
                    database_element(bv);
                    if (i % 7 == 0) repeat (2) tick; // Database pauses.
                end
                // Ascending IDs mean retaining the earlier vector resolves ties.
                if (v == 0 || vector_score > expected) begin
                    expected = vector_score;
                    expected_id = v;
                end
            end
            receive_result(0, expected, expected_id);
        end
    endtask

    initial begin
        reset_engine;
        run_search(1, 1, 2);
        run_search(MAX_ELEMENTS, 3, 0);
        run_search(MAX_ELEMENTS, 2, 1);
        run_search(MAX_ELEMENTS, 4, 2);
        command(0, 3); receive_result(1, 0, 0);
        command(MAX_ELEMENTS+1, 2); receive_result(1, 0, 0);
        command(1, 0); receive_result(2, 0, 0);
        command(0, 0); receive_result(1, 0, 0); // Dimension error has priority.
        // Abort partially loaded query.
        command(MAX_ELEMENTS, 2);
        query_element(12);
        reset_engine;
        // Abort database processing, with a query read/pair in flight.
        command(1, 2);
        query_element(3);
        database_element(7);
        reset_engine;
        // Drop an unconsumed final result.
        command(1, 1);
        query_element(2);
        database_element(4);
        wait (result_valid === 1'b1);
        reset_engine;
        // Reloading must recover correctly after aborted work.
        run_search(1, 2, 1);
        $display("PASS: search controller capacity=%0d checked %0d searches plus reset recovery.", MAX_ELEMENTS, searches);
        $finish;
    end
endmodule
