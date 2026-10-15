`timescale 1ns/1ps

module tb_int8_dot_product;
    reg clk = 0;
    reg reset = 1;
    reg command_valid = 0;
    wire command_ready;
    reg [15:0] dimensions = 0;
    reg pair_valid = 0;
    wire pair_ready;
    reg signed [7:0] a = 0;
    reg signed [7:0] b = 0;
    wire result_valid;
    reg result_ready = 0;
    wire signed [63:0] score;
    reg signed [63:0] expected;
    integer cycles = 0;
    integer vectors = 0;
    integer k;

    int8_dot_product dut (
        .clk(clk), .reset(reset),
        .command_valid(command_valid), .command_ready(command_ready),
        .dimensions(dimensions), .pair_valid(pair_valid), .pair_ready(pair_ready),
        .a(a), .b(b), .result_valid(result_valid), .result_ready(result_ready),
        .score(score)
    );

    always #5 clk = ~clk;
    always @(posedge clk) cycles = cycles + 1;
    initial begin
        #2000000;
        $fatal(1, "FAIL: simulation timeout");
    end

    task tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task start_vector;
        input integer length;
        begin
            @(negedge clk);
            if (command_ready !== 1'b1) $fatal(1, "FAIL: command not ready");
            command_valid = 1;
            dimensions = length;
            pair_valid = 1; // Early pair must not be accepted in IDLE/CLEAR.
            a = 127;
            b = 127;
            tick;
            if (command_ready !== 0 || pair_ready !== 0 || result_valid !== 0)
                $fatal(1, "FAIL: clear phase");
            @(negedge clk);
            command_valid = 0;
            dimensions = 0; // Accepted dimensions must have been latched.
            tick;
            expected = 0;
            if (score !== 0) $fatal(1, "FAIL: initial clear");
            if (length == 0) begin
                if (result_valid !== 1 || pair_ready !== 0)
                    $fatal(1, "FAIL: zero-dimensional result");
            end else if (pair_ready !== 1 || result_valid !== 0)
                $fatal(1, "FAIL: run phase");
        end
    endtask

    task send_pair;
        input integer av;
        input integer bv;
        input integer last;
        begin
            @(negedge clk);
            if (pair_ready !== 1) $fatal(1, "FAIL: pair not ready");
            pair_valid = 1;
            a = av;
            b = bv;
            expected = expected + av * bv;
            tick;
            if (score !== expected) $fatal(1, "FAIL: score mismatch");
            if (last) begin
                if (result_valid !== 1 || pair_ready !== 0)
                    $fatal(1, "FAIL: completion after last pair");
            end else if (result_valid !== 0 || pair_ready !== 1)
                $fatal(1, "FAIL: premature completion");
        end
    endtask

    task pause_input;
        begin
            @(negedge clk);
            pair_valid = 0;
            a = -128;
            b = -128;
            command_valid = 1; // Busy commands must not overwrite the length.
            dimensions = 1;
            tick;
            if (command_ready !== 0 || pair_ready !== 1 || result_valid !== 0 || score !== expected)
                $fatal(1, "FAIL: input pause or busy command");
            @(negedge clk);
            command_valid = 0;
        end
    endtask

    task finish_vector;
        begin
            // Hold a valid extra pair and a busy command during result stalls.
            repeat (3) begin
                @(negedge clk);
                pair_valid = 1;
                a = 127;
                b = 127;
                command_valid = 1;
                dimensions = 1;
                tick;
                if (result_valid !== 1 || pair_ready !== 0 || command_ready !== 0 || score !== expected)
                    $fatal(1, "FAIL: result backpressure");
            end
            @(negedge clk);
            command_valid = 0;
            pair_valid = 0;
            result_ready = 1;
            tick;
            if (result_valid !== 0 || command_ready !== 1 || pair_ready !== 0)
                $fatal(1, "FAIL: result acceptance");
            @(negedge clk);
            result_ready = 0;
            vectors = vectors + 1;
        end
    endtask

    task reset_engine;
        begin
            @(negedge clk);
            reset = 1;
            #1;
            if (command_ready !== 0 || pair_ready !== 0 || result_valid !== 0)
                $fatal(1, "FAIL: reset handshake gating");
            tick;
            if (score !== 0) $fatal(1, "FAIL: reset sum");
            @(negedge clk);
            command_valid = 0;
            pair_valid = 0;
            result_ready = 0;
            reset = 0;
            tick;
            if (command_ready !== 1 || pair_ready !== 0 || result_valid !== 0)
                $fatal(1, "FAIL: reset recovery");
        end
    endtask

    initial begin
        reset_engine;
        start_vector(3);
        send_pair(1, 4, 0);
        pause_input;
        send_pair(-2, 5, 0);
        send_pair(3, -6, 1);
        if (score !== -64'sd24) $fatal(1, "FAIL: known dot product");
        finish_vector;

        start_vector(0);
        finish_vector;
        start_vector(1);
        send_pair(-128, 127, 1);
        finish_vector;
        start_vector(6);
        for (k = 0; k < 6; k = k + 1) begin
            pause_input;
            send_pair(k - 3, 2, k == 5);
        end
        finish_vector;
        start_vector(4096);
        for (k = 0; k < 4096; k = k + 1)
            send_pair(-128, -128, k == 4095);
        if (score !== 64'sd67108864) $fatal(1, "FAIL: full-length score");
        finish_vector;
        start_vector(257);
        for (k = 0; k < 257; k = k + 1) begin
            if (k % 7 == 0) pause_input;
            send_pair(((k * 73) % 256) - 128, ((k * 31) % 256) - 128, k == 256);
        end
        finish_vector;

        // Reset aborts a partially accumulated vector.
        start_vector(3);
        send_pair(5, 6, 0);
        reset_engine;
        // Reset drops an unconsumed result.
        start_vector(1);
        send_pair(7, 8, 1);
        reset_engine;
        // Reset during CLEAR must abort the accepted command.
        @(negedge clk);
        command_valid = 1;
        dimensions = 10;
        tick;
        reset_engine;
        start_vector(1);
        send_pair(-128, -128, 1);
        finish_vector;

        // A receiver already ready when the final pair arrives still gets
        // one valid result cycle; it cannot consume the result prematurely.
        start_vector(1);
        result_ready = 1;
        send_pair(2, 3, 1);
        tick;
        if (command_ready !== 1 || result_valid !== 0)
            $fatal(1, "FAIL: immediately ready receiver");
        vectors = vectors + 1;

        $display("PASS: dot product checked %0d completed vectors over %0d clock cycles, including stalls and reset recovery.", vectors, cycles);
        $finish;
    end
endmodule
