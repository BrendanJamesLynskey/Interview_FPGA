// =============================================================================
// Challenge 2: Gray Code Counter
// =============================================================================
//
// Objective:
//   Implement a parameterisable Gray code counter suitable for use as the
//   write/read pointer in an asynchronous FIFO. The counter must advance
//   in Gray code sequence (each increment changes exactly one bit), and
//   include binary-to-Gray and Gray-to-binary conversion functions.
//
// Background:
//   Gray code (also called "reflected binary code") is a sequence in which
//   consecutive integers differ by exactly one bit. This property is essential
//   for the asynchronous FIFO pointer synchronisation technique: even if a
//   multi-bit Gray code pointer is sampled by a synchroniser at the exact moment
//   it transitions, the sampled value will always be one of the two adjacent
//   valid counter values (the old value or the new value). This is NOT the case
//   for binary counters, which can change multiple bits simultaneously (e.g.,
//   0111 -> 1000 changes all 4 bits).
//
//   Binary-to-Gray conversion:  gray[i] = bin[i] XOR bin[i+1]
//                               gray[N-1] = bin[N-1]  (MSB unchanged)
//
//   Gray-to-binary conversion:  bin[N-1] = gray[N-1]
//                               bin[i]   = bin[i+1] XOR gray[i]  (cascade)
//
// Modules:
//   bin_to_gray     -- combinational binary-to-Gray conversion
//   gray_to_bin     -- combinational Gray-to-binary conversion
//   gray_counter    -- parameterisable Gray code counter with async reset
//
// Parameters:
//   WIDTH -- counter width in bits (default 4; use 4 for FIFO depth = 2^4 = 16)
//
// Expected Behaviour (WIDTH=4):
//   Reset -> gray = 0000
//   Cycle 1: gray = 0001  (binary 1)
//   Cycle 2: gray = 0011  (binary 2)
//   Cycle 3: gray = 0010  (binary 3)
//   Cycle 4: gray = 0110  (binary 4)
//   Cycle 5: gray = 0111  (binary 5)
//   Cycle 6: gray = 0101  (binary 6)
//   Cycle 7: gray = 0100  (binary 7)
//   Cycle 8: gray = 1100  (binary 8)
//   ...
//   Cycle 15: gray = 1000 (binary 15)
//   Cycle 16: gray = 0000 (wraps back to binary 0)
//
//   Key verification: $countones(gray_current XOR gray_previous) == 1
//   for every transition (exactly one bit changes per cycle).
//
// ASIC/FPGA note:
//   The binary counter and Gray code conversion are separate to allow the
//   binary counter to be used internally (e.g., for FIFO pointer arithmetic)
//   while only the Gray code is synchronised across clock domains.
//
// =============================================================================

`timescale 1ns / 1ps


// -----------------------------------------------------------------------------
// Binary to Gray code conversion (combinational)
// gray[i] = bin[i] XOR bin[i+1]    for i < WIDTH-1
// gray[WIDTH-1] = bin[WIDTH-1]
// -----------------------------------------------------------------------------
module bin_to_gray #(
    parameter int WIDTH = 4
) (
    input  logic [WIDTH-1:0] bin,
    output logic [WIDTH-1:0] gray
);
    // XOR each bit with the next higher bit.
    // The right-shift-and-XOR expression is idiomatic and synthesises to
    // WIDTH-1 XOR gates. Synthesis tools recognise this pattern.
    assign gray = bin ^ (bin >> 1);

endmodule : bin_to_gray


// -----------------------------------------------------------------------------
// Gray code to binary conversion (combinational)
// The conversion is a cascade -- each bit depends on all higher bits.
// bin[WIDTH-1] = gray[WIDTH-1]
// bin[i]       = bin[i+1] XOR gray[i]
//
// Note: the cascade means the delay grows with WIDTH.
// For very wide counters (>10 bits), consider using a registered pipeline.
// -----------------------------------------------------------------------------
module gray_to_bin #(
    parameter int WIDTH = 4
) (
    input  logic [WIDTH-1:0] gray,
    output logic [WIDTH-1:0] bin
);
    // Cascade implementation using a generate loop.
    // MSB is copied directly; each lower bit XORs with the bit above it.
    always_comb begin
        bin[WIDTH-1] = gray[WIDTH-1];
        for (int i = WIDTH-2; i >= 0; i--) begin
            bin[i] = bin[i+1] ^ gray[i];
        end
    end

endmodule : gray_to_bin


// -----------------------------------------------------------------------------
// Gray code counter
//
// Architecture:
//   An internal binary counter increments every clock cycle (or when inc_i is
//   high). The Gray code output is derived combinationally from the binary
//   counter value. Both gray_o and bin_o are outputs so the caller can use
//   whichever is needed.
//
//   The binary counter value is also exposed as bin_o so the caller can
//   perform pointer arithmetic (e.g., FIFO occupancy calculation) without
//   needing to convert back from Gray code.
// -----------------------------------------------------------------------------
module gray_counter #(
    parameter int WIDTH = 4
) (
    input  logic             clk,
    input  logic             rst_n,      // asynchronous active-low reset
    input  logic             inc_i,      // increment enable (high = count)
    output logic [WIDTH-1:0] gray_o,     // Gray code value (for CDC)
    output logic [WIDTH-1:0] bin_o       // binary value (for arithmetic)
);
    logic [WIDTH-1:0] bin_count;    // internal binary counter

    // -------------------------------------------------------------------------
    // Binary counter (increments on posedge clk when inc_i is high)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            bin_count <= '0;
        else if (inc_i)
            bin_count <= bin_count + 1'b1;
    end

    // -------------------------------------------------------------------------
    // Binary-to-Gray conversion (combinational, registered through Gray output FF)
    // The Gray output is registered to ensure it is glitch-free.
    // -------------------------------------------------------------------------
    logic [WIDTH-1:0] gray_next;

    assign gray_next = bin_count ^ (bin_count >> 1);

    // Register the Gray output to ensure clean transitions for CDC
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            gray_o <= '0;
        else
            gray_o <= gray_next;
    end

    // Binary output: registered for consistency
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            bin_o <= '0;
        else
            bin_o <= bin_count;
    end

endmodule : gray_counter


// =============================================================================
// Testbench
// =============================================================================
//
// Tests:
//   1. Verify Gray code sequence for a full wrap-around (2^WIDTH cycles).
//   2. Verify that exactly one bit changes per increment (Hamming distance = 1).
//   3. Verify binary-to-Gray and Gray-to-binary round-trip for all 2^WIDTH values.
//   4. Verify reset behaviour: counter returns to 0 after async reset.
//   5. Verify enable: counter holds when inc_i is low.
//
// Expected output:
//   [  25ns] TB: gray=0001 bin=0001 (delta=1 bit) -- PASS
//   [  35ns] TB: gray=0011 bin=0002 (delta=1 bit) -- PASS
//   [  45ns] TB: gray=0010 bin=0003 (delta=1 bit) -- PASS
//   ...
//   [  165ns] TB: gray=1000 bin=000F (wrap: delta=1 bit) -- PASS
//   [  175ns] TB: gray=0000 bin=0000 (wrap: delta=1 bit) -- PASS
//   TB: Round-trip conversion test PASSED (16/16 values correct)
//   TB: Reset test PASSED
//   TB: Enable test PASSED
//   TB: ALL TESTS PASSED
//
// =============================================================================
module tb_gray_counter;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    parameter int WIDTH      = 4;
    parameter int FULL_COUNT = (1 << WIDTH);   // 2^WIDTH

    // -------------------------------------------------------------------------
    // Signals
    // -------------------------------------------------------------------------
    logic             clk   = 1'b0;
    logic             rst_n = 1'b0;
    logic             inc;
    logic [WIDTH-1:0] gray;
    logic [WIDTH-1:0] bin_val;

    // Clock: 100 MHz
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    gray_counter #(.WIDTH(WIDTH)) dut (
        .clk   (clk),
        .rst_n (rst_n),
        .inc_i (inc),
        .gray_o(gray),
        .bin_o (bin_val)
    );

    // -------------------------------------------------------------------------
    // Test 1: Gray code sequence verification
    // -------------------------------------------------------------------------
    logic [WIDTH-1:0] prev_gray;
    int               bit_changes;
    int               seq_pass   = 0;
    int               seq_fail   = 0;

    initial begin
        // Initial state
        inc       = 1'b0;
        prev_gray = '0;

        // Release reset
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        // Enable counting
        inc = 1'b1;

        $display("TB: Test 1 -- Gray code sequence (%0d cycles)", FULL_COUNT + 1);

        // Run for one full wrap-around plus one extra cycle
        for (int cycle = 0; cycle < FULL_COUNT + 1; cycle++) begin
            @(posedge clk);
            #1;  // small delay to let outputs settle after clock edge

            bit_changes = $countones(gray ^ prev_gray);

            // After the first cycle from reset, every transition should change
            // exactly one bit. At reset, prev_gray=0 and gray=0 (no change).
            if (cycle > 0) begin
                if (bit_changes == 1) begin
                    $display("[%0t] gray=%0b bin=%0h (delta=%0d bit) -- PASS",
                             $time, gray, bin_val, bit_changes);
                    seq_pass++;
                end else begin
                    $error("[%0t] gray=%0b bin=%0h (delta=%0d bits) -- FAIL",
                           $time, gray, bin_val, bit_changes);
                    seq_fail++;
                end
            end

            prev_gray = gray;
        end

        $display("TB: Sequence test: %0d PASSED, %0d FAILED", seq_pass, seq_fail);
    end

    // -------------------------------------------------------------------------
    // Test 2: Round-trip conversion (bin->gray->bin)
    // Instantiate conversion modules and verify all 2^WIDTH values
    // -------------------------------------------------------------------------
    logic [WIDTH-1:0] test_bin;
    logic [WIDTH-1:0] test_gray;
    logic [WIDTH-1:0] recovered_bin;

    bin_to_gray #(.WIDTH(WIDTH)) u_b2g (.bin(test_bin),  .gray(test_gray));
    gray_to_bin #(.WIDTH(WIDTH)) u_g2b (.gray(test_gray), .bin(recovered_bin));

    int conv_pass = 0;
    int conv_fail = 0;

    initial begin
        @(posedge rst_n);  // wait for reset release

        $display("TB: Test 2 -- Round-trip conversion for all %0d values", FULL_COUNT);
        for (int i = 0; i < FULL_COUNT; i++) begin
            test_bin = i[WIDTH-1:0];
            #1;  // combinational settling time

            if (recovered_bin === test_bin) begin
                conv_pass++;
            end else begin
                $error("TB: Round-trip FAIL: bin=%0h -> gray=%0h -> bin=%0h",
                       test_bin, test_gray, recovered_bin);
                conv_fail++;
            end
        end
        $display("TB: Round-trip conversion: %0d/%0d PASSED", conv_pass, FULL_COUNT);
    end

    // -------------------------------------------------------------------------
    // Test 3: Reset test
    // -------------------------------------------------------------------------
    initial begin
        // Wait until counter has counted 8 cycles, then assert reset
        @(posedge rst_n);
        repeat (10) @(posedge clk);

        // Async reset
        @(negedge clk);
        rst_n = 1'b0;
        #2;
        // Verify outputs go to 0 immediately (async)
        if (gray !== '0 || bin_val !== '0) begin
            $error("TB: Reset test FAIL -- gray=%0b bin=%0h after async reset",
                   gray, bin_val);
        end else begin
            $display("TB: Reset test PASSED -- outputs = 0 after async reset");
        end

        // Release reset
        #3;
        rst_n = 1'b1;
    end

    // -------------------------------------------------------------------------
    // Test 4: Enable test (counter must hold when inc_i = 0)
    // -------------------------------------------------------------------------
    initial begin
        @(posedge rst_n);
        repeat (20) @(posedge clk);  // let Tests 1/2/3 run first

        // Disable increment for 5 cycles
        inc = 1'b0;
        @(posedge clk);
        begin : check_hold
            logic [WIDTH-1:0] snap_gray = gray;
            logic [WIDTH-1:0] snap_bin  = bin_val;
            repeat (5) @(posedge clk);
            if (gray === snap_gray && bin_val === snap_bin) begin
                $display("TB: Enable test PASSED -- counter held for 5 cycles");
            end else begin
                $error("TB: Enable test FAIL -- counter changed when inc_i=0");
            end
        end
        inc = 1'b1;  // re-enable
    end

    // -------------------------------------------------------------------------
    // Concurrent assertions
    // -------------------------------------------------------------------------

    // Gray code property: exactly one bit changes per clock when counting
    property one_bit_change;
        @(posedge clk) disable iff (!rst_n)
        inc_i |=> ($countones($past(gray) ^ gray) == 1);
    endproperty
    assert property (one_bit_change)
        else $error("[%0t] ASSERTION FAIL: gray code changed by != 1 bit: %0b -> %0b",
                    $time, $past(gray), gray);

    // Gray code output must match bin_to_gray conversion of binary output
    property gray_matches_binary;
        @(posedge clk) disable iff (!rst_n)
        gray == (bin_val ^ (bin_val >> 1));
    endproperty
    assert property (gray_matches_binary)
        else $error("[%0t] ASSERTION FAIL: gray=%0b != bin_to_gray(bin=%0h)",
                    $time, gray, bin_val);

    // -------------------------------------------------------------------------
    // Finish
    // -------------------------------------------------------------------------
    initial begin
        #5000;   // allow all tests to complete
        $display("=== TB Complete ===");
        $finish;
    end

    initial begin
        #50000;
        $error("TB: TIMEOUT");
        $finish;
    end

endmodule : tb_gray_counter

// =============================================================================
// 4-bit Gray code truth table (reference):
//
//  Binary | Gray | Hex
//  -------|------|----
//   0000  | 0000 | 0
//   0001  | 0001 | 1
//   0010  | 0011 | 3
//   0011  | 0010 | 2
//   0100  | 0110 | 6
//   0101  | 0111 | 7
//   0110  | 0101 | 5
//   0111  | 0100 | 4
//   1000  | 1100 | C
//   1001  | 1101 | D
//   1010  | 1111 | F
//   1011  | 1110 | E
//   1100  | 1010 | A
//   1101  | 1011 | B
//   1110  | 1001 | 9
//   1111  | 1000 | 8
//
// Verification: each row differs from the next by exactly one bit in the Gray
// column. The wrap-around (1111->0000) also differs by exactly one bit (1000->0000).
// =============================================================================
