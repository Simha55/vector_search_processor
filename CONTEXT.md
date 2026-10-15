# Original project handoff

Historical context supplied by the user. See PROGRESS.md for verified current status.

Copy the following into Codex. It captures the project context, decisions, current code, and how you want to work.

---

## Project: Verilog vector-search accelerator

I am learning computer architecture and Verilog. Help me build this project incrementally, explaining the hardware clearly.

### Goal

Build a synthesizable vector-search accelerator that:

1. Receives a query vector.
2. Compares it against database vectors.
3. Calculates each vector’s dot product with the query.
4. Returns the highest score and its vector ID.

For unit-normalized vectors, the dot product equals cosine similarity. **Software will handle normalization initially.**

This is a dedicated accelerator controlled by an FSM, rather than a CPU fetching instructions.

### How I want you to teach and implement

- **Give me only one module at a time.**
- Explain every line, its inputs, outputs, widths, signedness, and behavior.
- Answer my questions before advancing to another module.
- Start with the simplest working integer version.
- Add floating-point support and performance improvements later.
- Keep track of completed modules, tests, decisions, and my questions.
- Distinguish synthesizable hardware from simulation-only testbench code.
- Never claim a test passed unless it actually ran successfully.
- Keep explanations beginner-friendly, with concrete numeric examples.
- Maintain a project progress/context file so I can return to ChatGPT afterward to design an improved version.

### Planned overall features

These describe the intended direction; **do not implement everything immediately**.

| Feature | Plan |
|---|---|
| Search | Exact dot-product search |
| Result | Top-1 vector ID and score |
| Equal scores | Smaller vector ID wins |
| Vector length | Runtime configurable |
| Query capacity | Parameterized; proposed maximum is 4,096 elements |
| Database size | Runtime configurable |
| Database storage | External data streamed into the accelerator |
| Query storage | Internal buffer, loaded once per search |
| Arithmetic lanes | Eventually four parallel lanes |
| Formats | INT8 first; IEEE FP32 later |
| Format selection | One format per search, shared by query and database |
| INT8 product | Signed 16-bit |
| INT8 accumulation | Proposed signed 64-bit |
| FP32 arithmetic | Separate rounded multiplication and addition |
| FP32 rounding | Round-to-nearest, ties-to-even |
| Tools | Icarus Verilog, GTKWave; cocotb later |

For FP32, we proposed reusing **Berkeley HardFloat** rather than implementing floating-point arithmetic with Verilog `real`. That dependency has **not been integrated or verified**.

### Planned interfaces

Eventually use:

- Command input: format, dimensions, database vector count.
- Query stream.
- Database stream.
- Result output.

Streams use `valid` and `ready`. A transfer happens at a clock edge only when both are high.

The proposed query/database transfer is 128 bits, containing four 32-bit slots:

| Slot | Bits |
|---|---|
| 0 | `[31:0]` |
| 1 | `[63:32]` |
| 2 | `[95:64]` |
| 3 | `[127:96]` |

FP32 uses all 32 bits of each slot. INT8 uses the lowest eight bits as a signed integer; the upper bits are ignored.

This simplifies the interface but wastes INT8 bandwidth. Packed INT8 can be a later improvement.

For dimensions not divisible by four, ignore unused slots in the last transfer. For example, a six-element vector uses four slots, then two.

### Four-lane dot-product plan

Lane assignments:

```text
Lane 0: elements 0, 4, 8, ...
Lane 1: elements 1, 5, 9, ...
Lane 2: elements 2, 6, 10, ...
Lane 3: elements 3, 7, 11, ...
```

Each lane accumulates its products. Initially, the conceptual final reduction is:

```text
score = (A0 + A1) + (A2 + A3)
```

Example:

```text
Query:    [1, 2, 3, 4, 5, 6, 7, 8]
Database: [2, 2, 2, 2, 2, 2, 2, 2]

Lane sums: [12, 16, 20, 24]
Score: (12 + 16) + (20 + 24) = 72
```

FP32 reference tests must reproduce the implemented multiplication, accumulation, and reduction order because rounding depends on order.

### Control and performance discussion

The original simple FSM proposal was:

```text
IDLE
LOAD_QUERY
RECEIVE_CHUNK
MULTIPLY
ACCUMULATE
REDUCE
COMPARE
RESULT
```

I questioned this because serial phases leave multipliers idle.

We clarified:

- Four lanes provide simultaneous arithmetic.
- Pipelining allows different chunks to occupy different stages simultaneously.
- A future performance target is **four element pairs accepted per cycle** during sustained processing.
- The FSM should coordinate the overall search while pipeline stages work concurrently.
- This target depends on memory bandwidth, arithmetic throughput, and scheduling; it has not been achieved.

FP32 accumulation has a feedback dependency:

```text
next_sum = previous_sum + product
```

A pipelined adder cannot update the same accumulator every cycle if the previous result is still unavailable. Possible future solutions include multiple independent accumulators or interleaving vectors.

If we introduce additional accumulators, we must define their reduction order and update the reference model accordingly.

**For now, prioritize a simple correct implementation.**

### Planned corner cases

Eventually handle:

- Zero dimensions.
- Dimensions exceeding query capacity.
- Empty database.
- Partial final chunks.
- Negative scores, including all-negative databases.
- Equal scores.
- Input pauses and output backpressure.
- Reset during an active search.

Initialize the best result from the first completed vector so all-negative scores work correctly.

For future FP32 support, the proposed policy is:

- Reject NaN and infinity inputs.
- Support finite values, including subnormals.
- Report overflow or invalid arithmetic.
- Allow ordinary rounding.
- Treat equal positive/negative zero scores consistently.

These policies still need concrete interface definitions.

## Current implementation: Module 1 only

The first module is a combinational signed INT8 multiplier:

**`rtl/int8_multiplier.v`**

```verilog
module int8_multiplier (
    input  wire signed [7:0] a,
    input  wire signed [7:0] b,
    output wire signed [15:0] product
);

    assign product = a * b;

endmodule
```

Behavior:

- `a` and `b` range from −128 through 127.
- The 16-bit signed output preserves the complete product.
- No clock or reset: this module has no storage.
- `assign` describes continuously driven combinational multiplication.
- Synthesis chooses suitable multiplication logic or a hardware multiplier resource.
- Pipeline registers and an accumulator have not been implemented.

## Current testbench

A Verilog testbench was provided to exhaustively check all 65,536 input pairs.

**`tb_int8_multiplier.v`**

```verilog
`timescale 1ns/1ps

module tb_int8_multiplier;

    reg  signed [7:0] a;
    reg  signed [7:0] b;
    wire signed [15:0] product;

    int8_multiplier dut (
        .a(a),
        .b(b),
        .product(product)
    );

    integer i;
    integer j;
    integer expected;

    initial begin
        for (i = -128; i <= 127; i = i + 1) begin
            for (j = -128; j <= 127; j = j + 1) begin
                a = i;
                b = j;

                #1;
                expected = i * j;

                if (product !== expected) begin
                    $display(
                        "FAIL: a=%0d b=%0d product=%0d expected=%0d",
                        a, b, product, expected
                    );
                    $fatal(1);
                end
            end
        end

        $display("PASS: all 65,536 input combinations checked.");
        $finish;
    end

endmodule
```

Commands, when both files are in the current directory:

```bash
iverilog -g2012 -s tb_int8_multiplier -o multiplier_test \
  int8_multiplier.v tb_int8_multiplier.v

vvp multiplier_test
```

**No successful simulation output has been reported in the conversation. Inspect existing files and run the test before marking this module verified.**

## Questions already discussed

1. **Why use `reg` for testbench inputs and `wire` for the output?**  
   Traditional Verilog procedural assignments inside `initial` require variables such as `reg`. A `wire` carries a value driven by the connected module.

2. **Does `reg` always imply a hardware register?**  
   No. Its use determines the hardware. Testbench variables are simulation-only; complete combinational procedural logic can describe combinational circuits; clocked assignments usually infer flip-flops.

3. **Why does Verilog have `integer`?**  
   It supports hardware descriptions and simulation programs. Verilog `integer` is a signed 32-bit variable, useful for testbench loops and reference arithmetic. Synthesizable uses may infer hardware.

4. **How are floating-point binary points maintained?**  
   The point is implied by the format. Integer significand multiplication adds the input fractional-bit counts. The exponent supplies the overall power-of-two scale.

5. **Why can FP32 represent 16,777,218 but not 16,777,217 exactly?**  
   FP32 has 24 significant binary bits. At exponent 24, adjacent representable values are two apart. The missing units bit requires an additional fraction position.

6. **Do GPUs also pipeline?**  
   Yes. They combine arithmetic pipelines, parallel lanes, and scheduling of independent work. Dependencies still constrain accumulation.

## What to do next

Inspect the workspace, establish the project files, and run the exhaustive multiplier test. Explain any corrections.

Then wait for my questions or request to continue. The likely next hardware module is an integer accumulator, but **do not implement it until I ask**.

Maintain an accurate progress record that I can bring back to ChatGPT for the next design iteration.

---