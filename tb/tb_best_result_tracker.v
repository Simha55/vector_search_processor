`timescale 1ns/1ps

module tb_best_result_tracker;
    reg clk = 0;
    reg reset = 1;
    reg clear = 0;
    reg enable = 0;
    reg signed [63:0] candidate_score = 0;
    reg [31:0] candidate_id = 0;
    wire best_valid;
    wire signed [63:0] best_score;
    wire [31:0] best_id;
    reg previous_valid;
    reg signed [63:0] previous_score;
    reg [31:0] previous_id;
    integer checks = 0;

    localparam signed [63:0] MIN_SCORE = 64'sh8000000000000000;
    localparam signed [63:0] MAX_SCORE = 64'sh7fffffffffffffff;

    best_result_tracker dut (
        .clk(clk), .reset(reset), .clear(clear), .enable(enable),
        .candidate_score(candidate_score), .candidate_id(candidate_id),
        .best_valid(best_valid), .best_score(best_score), .best_id(best_id)
    );

    always #5 clk = ~clk;
    initial begin
        #10000;
        $fatal(1, "FAIL: simulation timeout");
    end

    // Expected results are specified explicitly for each directed scenario.
    task step;
        input next_reset;
        input next_clear;
        input next_enable;
        input signed [63:0] next_score;
        input [31:0] next_id;
        input expected_valid;
        input signed [63:0] expected_score;
        input [31:0] expected_id;
        begin
            @(negedge clk);
            previous_valid = best_valid;
            previous_score = best_score;
            previous_id = best_id;
            reset = next_reset;
            clear = next_clear;
            enable = next_enable;
            candidate_score = next_score;
            candidate_id = next_id;
            #1;
            if (best_valid !== previous_valid || best_score !== previous_score || best_id !== previous_id)
                $fatal(1, "FAIL: outputs changed without a rising edge");
            @(posedge clk);
            #1;
            if (best_valid !== expected_valid || best_score !== expected_score || best_id !== expected_id) begin
                $display("FAIL: check=%0d valid=%b score=%0d id=%0d expected_valid=%b expected_score=%0d expected_id=%0d",
                         checks, best_valid, best_score, best_id, expected_valid, expected_score, expected_id);
                $fatal(1);
            end
            checks = checks + 1;
        end
    endtask

    initial begin
        step(1, 0, 0, 0, 0, 0, 0, 0);
        step(0, 0, 0, MAX_SCORE, 1, 0, 0, 0); // Disabled candidate, no result yet.
        step(0, 0, 1, -30, 5, 1, -30, 5);    // First negative score must win.
        step(0, 0, 1, -40, 0, 1, -30, 5);    // Lower ID cannot beat lower score.
        step(0, 0, 1, -10, 9, 1, -10, 9);
        step(0, 0, 1, -10, 12, 1, -10, 9);   // Tie with larger ID loses.
        step(0, 0, 1, -10, 3, 1, -10, 3);    // Tie with smaller ID wins.
        step(0, 0, 1, -10, 3, 1, -10, 3);    // Identical candidate.
        step(0, 0, 0, MAX_SCORE, 0, 1, -10, 3);
        step(0, 0, 1, 0, 99, 1, 0, 99);
        step(0, 0, 1, 20, 7, 1, 20, 7);
        step(0, 0, 1, MIN_SCORE, 0, 1, 20, 7);
        step(0, 0, 1, MAX_SCORE, 8, 1, MAX_SCORE, 8);
        step(0, 0, 1, MAX_SCORE, 2, 1, MAX_SCORE, 2);
        step(0, 1, 1, MAX_SCORE, 1, 0, 0, 0); // Clear discards candidate.
        step(0, 0, 0, 50, 1, 0, 0, 0);       // Empty search stays invalid.
        step(0, 0, 1, MIN_SCORE, 32'hffffffff, 1, MIN_SCORE, 32'hffffffff);
        step(0, 0, 1, MIN_SCORE, 32'h80000000, 1, MIN_SCORE, 32'h80000000);
        step(0, 0, 1, MIN_SCORE, 32'h7fffffff, 1, MIN_SCORE, 32'h7fffffff);
        step(0, 0, 1, MIN_SCORE, 32'hffffffff, 1, MIN_SCORE, 32'h7fffffff);
        step(0, 0, 1, MIN_SCORE, 0, 1, MIN_SCORE, 0);
        step(0, 1, 0, 0, 0, 0, 0, 0);
        step(0, 0, 1, -100, 42, 1, -100, 42); // New search, no stale winner.
        step(1, 0, 1, MAX_SCORE, 1, 0, 0, 0); // Reset during active search.
        step(0, 0, 1, 7, 8, 1, 7, 8);
        step(1, 1, 1, MAX_SCORE, 1, 0, 0, 0);
        step(0, 0, 1, 0, 0, 1, 0, 0);
        step(0, 0, 1, -1, 0, 1, 0, 0);

        $display("PASS: best-result tracker checked for %0d clock cycles.", checks);
        $finish;
    end
endmodule
