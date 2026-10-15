`timescale 1ns/1ps

module tb_int8_query_buffer;
    parameter integer MAX_ELEMENTS = 5;
    localparam integer ADDRESS_WIDTH = (MAX_ELEMENTS <= 1) ? 1 : $clog2(MAX_ELEMENTS);
    reg clk = 0;
    reg reset = 1;
    reg write_enable = 0;
    reg [ADDRESS_WIDTH-1:0] write_address = 0;
    reg signed [7:0] write_data = 0;
    reg read_enable = 0;
    reg [ADDRESS_WIDTH-1:0] read_address = 0;
    wire signed [7:0] read_data;
    wire read_valid;
    reg signed [7:0] previous_data;
    reg previous_valid;
    integer checks = 0;
    integer i;
    integer held_data;

    int8_query_buffer #(.MAX_ELEMENTS(MAX_ELEMENTS)) dut (
        .clk(clk), .reset(reset),
        .write_enable(write_enable), .write_address(write_address), .write_data(write_data),
        .read_enable(read_enable), .read_address(read_address),
        .read_data(read_data), .read_valid(read_valid)
    );

    always #5 clk = ~clk;
    initial begin
        #1000000;
        $fatal(1, "FAIL: simulation timeout");
    end

    task step;
        input next_reset;
        input next_write;
        input integer next_write_address;
        input integer next_write_data;
        input next_read;
        input integer next_read_address;
        input expected_valid;
        input signed [7:0] expected_data;
        begin
            @(negedge clk);
            previous_data = read_data;
            previous_valid = read_valid;
            reset = next_reset;
            write_enable = next_write;
            write_address = next_write_address;
            write_data = next_write_data;
            read_enable = next_read;
            read_address = next_read_address;
            #1;
            if (read_data !== previous_data || read_valid !== previous_valid)
                $fatal(1, "FAIL: outputs changed before a rising edge");
            @(posedge clk);
            #1;
            if (read_valid !== expected_valid || read_data !== expected_data) begin
                $display("FAIL: capacity=%0d check=%0d valid=%b data=%0d expected_valid=%b expected_data=%0d",
                         MAX_ELEMENTS, checks, read_valid, read_data, expected_valid, expected_data);
                $fatal(1);
            end
            checks = checks + 1;
        end
    endtask

    initial begin
        step(1, 0, 0, 0, 0, 0, 0, 0);
        // Initialize every location. Never read unwritten memory.
        for (i = 0; i < MAX_ELEMENTS; i = i + 1)
            step(0, 1, i, ((i * 73) % 256) - 128, 0, 0, 0, 0);
        // Consecutive read requests check every location and signed pattern.
        for (i = 0; i < MAX_ELEMENTS; i = i + 1)
            step(0, 0, 0, 0, 1, i, 1, ((i * 73) % 256) - 128);
        held_data = read_data;
        step(0, 0, 0, 127, 0, 0, 0, held_data);
        step(0, 0, 0, 127, 1, 0, 1, -128); // Disabled write has no effect.
        // Same-address read/write returns OLD data; next read sees new data.
        step(0, 1, 0, 127, 1, 0, 1, -128);
        step(0, 0, 0, 0, 1, 0, 1, 127);
        step(0, 1, 0, -1, 0, 0, 0, 127);
        step(0, 0, 0, 0, 1, 0, 1, -1);
        if (MAX_ELEMENTS > 1) begin
            step(0, 1, MAX_ELEMENTS-1, 42, 1, 0, 1, -1);
            step(0, 0, 0, 0, 1, MAX_ELEMENTS-1, 1, 42);
        end
        held_data = read_data;
        // Non-power-of-two capacities have representable invalid addresses.
        if (MAX_ELEMENTS < (2 ** ADDRESS_WIDTH)) begin
            step(0, 1, MAX_ELEMENTS, 99, 1, MAX_ELEMENTS, 0, held_data);
            step(0, 0, 0, 0, 1, 0, 1, -1); // Invalid write must not corrupt address 0.
        end
        // Reset suppresses both operations but preserves stored query data.
        step(1, 1, 0, 77, 1, 0, 0, 0);
        step(0, 0, 0, 0, 1, 0, 1, -1);
        step(0, 0, 0, 0, 0, 0, 0, -1);

        $display("PASS: query buffer capacity=%0d checked for %0d clock cycles.", MAX_ELEMENTS, checks);
        $finish;
    end
endmodule
