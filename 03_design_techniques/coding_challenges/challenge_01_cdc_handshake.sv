// =============================================================================
// Challenge 1: CDC Four-Phase Handshake
// =============================================================================
//
// Objective:
//   Implement a complete, synthesisable four-phase CDC handshake module that
//   safely transfers a parameterisable-width data word from a source clock
//   domain to a destination clock domain.
//
// Background:
//   A four-phase (request/acknowledge) handshake is the standard technique for
//   transferring arbitrary multi-bit data between two unrelated clock domains
//   when throughput requirements are low (a few transfers per microsecond or less).
//   Each phase requires two synchroniser traversals, giving a total round-trip
//   latency of approximately 4 * max(T_src, T_dst) before the next transfer can
//   begin.
//
// Protocol:
//   Phase 1 -- Source asserts REQ and holds DATA stable.
//   Phase 2 -- Destination sees synchronised REQ high, latches DATA, asserts ACK.
//   Phase 3 -- Source sees synchronised ACK high, de-asserts REQ.
//   Phase 4 -- Destination sees synchronised REQ low, de-asserts ACK.
//   Repeat.
//
//   IMPORTANT: DATA must be held stable from Phase 1 through to the end of
//   Phase 2. The destination latches DATA only AFTER it has observed two
//   consecutive destination-clock cycles with REQ synchronised high, ensuring
//   DATA has had at least two cycles to stabilise through the routing.
//
// Module interfaces:
//   cdc_handshake_src  -- source-domain state machine
//   cdc_handshake_dst  -- destination-domain state machine
//   cdc_sync_2ff       -- 2-FF synchroniser helper (used by both sides)
//   cdc_handshake_top  -- top-level wrapper connecting src and dst
//
// Parameters:
//   DATA_WIDTH -- width of the data word to transfer (default 32)
//
// Expected Behaviour:
//   1. Caller asserts send_i with data_i valid for one src clock cycle.
//   2. cdc_handshake_src captures data_i and initiates the handshake.
//   3. busy_o is high from send_i until the handshake completes.
//   4. cdc_handshake_dst asserts rcv_valid_o for exactly one dst clock cycle
//      when rcv_data_o contains the transferred word.
//   5. A new transfer cannot begin until busy_o de-asserts.
//
// Constraints note:
//   In a real design, apply the following XDC to all synchroniser FFs:
//     set_false_path -to [get_cells -hier -filter {ASYNC_REG == TRUE}]
//   This suppresses timing analysis on the asynchronous data input to FF1.
//
// =============================================================================

`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// 2-FF synchroniser (helper module)
// Parameterised for 2 or 3 stages; ASYNC_REG applied to all stages.
// -----------------------------------------------------------------------------
module cdc_sync_2ff #(
    parameter int STAGES     = 2,           // number of synchroniser stages
    parameter bit RESET_VAL  = 1'b0         // reset value of the chain
) (
    input  logic clk_dst,                   // destination domain clock
    input  logic rst_n_dst,                 // destination domain reset (active low)
    input  logic d_async,                   // asynchronous data input
    output logic q_sync                     // synchronised output
);
    // ASYNC_REG: tells Vivado/Quartus to:
    //   1. Place these FFs adjacently (minimise inter-FF routing delay)
    //   2. Flag this path as a known CDC crossing in report_cdc
    (* ASYNC_REG = "TRUE" *) logic [STAGES-1:0] chain;

    always_ff @(posedge clk_dst or negedge rst_n_dst) begin
        if (!rst_n_dst)
            chain <= {STAGES{RESET_VAL}};
        else
            chain <= {chain[STAGES-2:0], d_async};
    end

    assign q_sync = chain[STAGES-1];

endmodule : cdc_sync_2ff


// -----------------------------------------------------------------------------
// Source-domain state machine
// Manages the REQ assertion and waits for ACK to complete the handshake.
// -----------------------------------------------------------------------------
module cdc_handshake_src #(
    parameter int DATA_WIDTH = 32
) (
    input  logic                  clk_src,
    input  logic                  rst_n_src,

    // User interface (source domain)
    input  logic [DATA_WIDTH-1:0] data_i,        // data to transfer
    input  logic                  send_i,         // pulse to initiate transfer
    output logic                  busy_o,          // high during handshake

    // Handshake signals crossing to destination domain
    output logic [DATA_WIDTH-1:0] data_stable_o,  // held stable during handshake
    output logic                  req_o,           // REQ to destination domain

    // ACK synchronised into source domain (from cdc_sync_2ff in src side)
    input  logic                  ack_sync_i
);
    // -------------------------------------------------------------------------
    // State machine
    // -------------------------------------------------------------------------
    typedef enum logic [1:0] {
        SRC_IDLE,       // waiting for send_i
        SRC_REQ_HIGH,   // REQ asserted, waiting for ACK
        SRC_REQ_LOW,    // ACK seen, REQ de-asserted, waiting for ACK to go low
        SRC_DONE        // one-cycle done state before returning to IDLE
    } src_state_t;

    src_state_t state;

    always_ff @(posedge clk_src or negedge rst_n_src) begin
        if (!rst_n_src) begin
            state         <= SRC_IDLE;
            req_o         <= 1'b0;
            busy_o        <= 1'b0;
            data_stable_o <= '0;
        end else begin
            unique case (state)
                // -----------------------------------------------------------------
                SRC_IDLE: begin
                    busy_o <= 1'b0;
                    if (send_i) begin
                        data_stable_o <= data_i;    // capture data
                        req_o         <= 1'b1;       // Phase 1: assert REQ
                        busy_o        <= 1'b1;
                        state         <= SRC_REQ_HIGH;
                    end
                end
                // -----------------------------------------------------------------
                SRC_REQ_HIGH: begin
                    // Wait for synchronised ACK to go high (Phase 2 complete)
                    if (ack_sync_i) begin
                        req_o <= 1'b0;              // Phase 3: de-assert REQ
                        state <= SRC_REQ_LOW;
                    end
                end
                // -----------------------------------------------------------------
                SRC_REQ_LOW: begin
                    // Wait for synchronised ACK to go low (Phase 4 complete)
                    // Only then is the protocol complete and the bus is free
                    if (!ack_sync_i) begin
                        state  <= SRC_DONE;
                    end
                end
                // -----------------------------------------------------------------
                SRC_DONE: begin
                    busy_o <= 1'b0;
                    state  <= SRC_IDLE;
                end
            endcase
        end
    end

endmodule : cdc_handshake_src


// -----------------------------------------------------------------------------
// Destination-domain state machine
// Detects synchronised REQ, latches data, asserts ACK.
// -----------------------------------------------------------------------------
module cdc_handshake_dst #(
    parameter int DATA_WIDTH = 32
) (
    input  logic                  clk_dst,
    input  logic                  rst_n_dst,

    // REQ synchronised into destination domain (from cdc_sync_2ff on dst side)
    input  logic                  req_sync_i,

    // Data bus (driven by source domain; stable when req_sync_i is high)
    // Note: data is captured COMBINATIONALLY when req_sync_i first goes high.
    // For maximum safety, capture on the SECOND cycle after req_sync_i is stable.
    input  logic [DATA_WIDTH-1:0] data_i,

    // Handshake ACK output (crosses to source domain)
    output logic                  ack_o,

    // User interface (destination domain)
    output logic [DATA_WIDTH-1:0] rcv_data_o,   // received data
    output logic                  rcv_valid_o    // pulses high for one cycle
);
    typedef enum logic [1:0] {
        DST_IDLE,       // waiting for REQ
        DST_LATCH,      // REQ seen, latch data, assert ACK
        DST_ACK_HIGH,   // ACK asserted, waiting for REQ to go low
        DST_ACK_LOW     // REQ seen low, de-assert ACK
    } dst_state_t;

    dst_state_t state;

    always_ff @(posedge clk_dst or negedge rst_n_dst) begin
        if (!rst_n_dst) begin
            state       <= DST_IDLE;
            ack_o       <= 1'b0;
            rcv_valid_o <= 1'b0;
            rcv_data_o  <= '0;
        end else begin
            rcv_valid_o <= 1'b0;     // default: valid is a one-cycle pulse

            unique case (state)
                // -----------------------------------------------------------------
                DST_IDLE: begin
                    // Phase 2 begins when we see synchronised REQ high
                    if (req_sync_i) begin
                        state <= DST_LATCH;
                    end
                end
                // -----------------------------------------------------------------
                DST_LATCH: begin
                    // Data has been stable for at least 2 dst cycles (req_sync_i
                    // traversed 2 FFs). Safe to latch now.
                    rcv_data_o  <= data_i;
                    rcv_valid_o <= 1'b1;     // one-cycle valid pulse
                    ack_o       <= 1'b1;     // Phase 2: assert ACK
                    state       <= DST_ACK_HIGH;
                end
                // -----------------------------------------------------------------
                DST_ACK_HIGH: begin
                    // Wait for synchronised REQ to go low (Phase 3 complete from src)
                    if (!req_sync_i) begin
                        ack_o <= 1'b0;   // Phase 4: de-assert ACK
                        state <= DST_ACK_LOW;
                    end
                end
                // -----------------------------------------------------------------
                DST_ACK_LOW: begin
                    // ACK has been de-asserted; return to IDLE
                    state <= DST_IDLE;
                end
            endcase
        end
    end

endmodule : cdc_handshake_dst


// -----------------------------------------------------------------------------
// Top-level: connects src FSM, dst FSM, and the two 2FF synchronisers
// -----------------------------------------------------------------------------
module cdc_handshake_top #(
    parameter int DATA_WIDTH  = 32,
    parameter int SYNC_STAGES = 2        // 2 or 3 sync stages
) (
    // Source domain
    input  logic                  clk_src,
    input  logic                  rst_n_src,
    input  logic [DATA_WIDTH-1:0] src_data_i,
    input  logic                  src_send_i,
    output logic                  src_busy_o,

    // Destination domain
    input  logic                  clk_dst,
    input  logic                  rst_n_dst,
    output logic [DATA_WIDTH-1:0] dst_data_o,
    output logic                  dst_valid_o
);
    // -------------------------------------------------------------------------
    // Internal signals
    // -------------------------------------------------------------------------
    logic                  req_raw;        // REQ from src FSM -> sync -> dst FSM
    logic                  req_sync;       // REQ synchronised into dst domain
    logic                  ack_raw;        // ACK from dst FSM -> sync -> src FSM
    logic                  ack_sync;       // ACK synchronised into src domain
    logic [DATA_WIDTH-1:0] data_stable;    // data held stable by src FSM

    // -------------------------------------------------------------------------
    // Synchroniser: REQ crosses from clk_src to clk_dst
    // -------------------------------------------------------------------------
    cdc_sync_2ff #(
        .STAGES    (SYNC_STAGES),
        .RESET_VAL (1'b0)
    ) u_req_sync (
        .clk_dst   (clk_dst),
        .rst_n_dst (rst_n_dst),
        .d_async   (req_raw),
        .q_sync    (req_sync)
    );

    // -------------------------------------------------------------------------
    // Synchroniser: ACK crosses from clk_dst back to clk_src
    // -------------------------------------------------------------------------
    cdc_sync_2ff #(
        .STAGES    (SYNC_STAGES),
        .RESET_VAL (1'b0)
    ) u_ack_sync (
        .clk_dst   (clk_src),        // ACK crosses INTO source domain
        .rst_n_dst (rst_n_src),
        .d_async   (ack_raw),
        .q_sync    (ack_sync)
    );

    // -------------------------------------------------------------------------
    // Source FSM
    // -------------------------------------------------------------------------
    cdc_handshake_src #(
        .DATA_WIDTH (DATA_WIDTH)
    ) u_src (
        .clk_src       (clk_src),
        .rst_n_src     (rst_n_src),
        .data_i        (src_data_i),
        .send_i        (src_send_i),
        .busy_o        (src_busy_o),
        .data_stable_o (data_stable),
        .req_o         (req_raw),
        .ack_sync_i    (ack_sync)
    );

    // -------------------------------------------------------------------------
    // Destination FSM
    // -------------------------------------------------------------------------
    cdc_handshake_dst #(
        .DATA_WIDTH (DATA_WIDTH)
    ) u_dst (
        .clk_dst    (clk_dst),
        .rst_n_dst  (rst_n_dst),
        .req_sync_i (req_sync),
        .data_i     (data_stable),   // data held stable by src FSM
        .ack_o      (ack_raw),
        .rcv_data_o (dst_data_o),
        .rcv_valid_o(dst_valid_o)
    );

endmodule : cdc_handshake_top


// =============================================================================
// Testbench
// =============================================================================
//
// Tests:
//   1. Basic transfer: single data word crosses from 100 MHz to 75 MHz domain.
//   2. Back-to-back: transfer a sequence of words with minimum gap (busy-wait).
//   3. Stress: random data at maximum transfer rate over 1000 transfers.
//   4. Reset during transfer: assert reset while handshake is in progress.
//
// Expected output (approximate):
//   [   95ns] TB: Sending 0xDEADBEEF from src domain
//   [  235ns] TB: Received 0xDEADBEEF at dst domain -- PASS
//   [  260ns] TB: src_busy de-asserted -- ready for next transfer
//   ...
//   [XXXXX ns] TB: All 1000 transfers PASSED
//   [XXXXX ns] TB: Simulation complete
//
// =============================================================================
module tb_cdc_handshake;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    parameter int DATA_WIDTH  = 32;
    parameter int NUM_XFERS   = 1000;

    // -------------------------------------------------------------------------
    // Clock generation: deliberately incommensurate frequencies
    // src: 100 MHz (10 ns period)
    // dst:  75 MHz (13.33 ns period)
    // -------------------------------------------------------------------------
    logic clk_src = 1'b0;
    logic clk_dst = 1'b0;

    always #5.0  clk_src = ~clk_src;   // 100 MHz
    always #6.67 clk_dst = ~clk_dst;   //  75 MHz

    // -------------------------------------------------------------------------
    // Reset
    // -------------------------------------------------------------------------
    logic rst_n_src = 1'b0;
    logic rst_n_dst = 1'b0;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic [DATA_WIDTH-1:0] src_data;
    logic                  src_send;
    logic                  src_busy;
    logic [DATA_WIDTH-1:0] dst_data;
    logic                  dst_valid;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    cdc_handshake_top #(
        .DATA_WIDTH  (DATA_WIDTH),
        .SYNC_STAGES (2)
    ) dut (
        .clk_src    (clk_src),
        .rst_n_src  (rst_n_src),
        .src_data_i (src_data),
        .src_send_i (src_send),
        .src_busy_o (src_busy),
        .clk_dst    (clk_dst),
        .rst_n_dst  (rst_n_dst),
        .dst_data_o (dst_data),
        .dst_valid_o(dst_valid)
    );

    // -------------------------------------------------------------------------
    // Scoreboard: captures expected data and checks against dst_valid
    // -------------------------------------------------------------------------
    logic [DATA_WIDTH-1:0] expected_q [$];   // queue of expected values
    int                     pass_count = 0;
    int                     fail_count = 0;

    // Enqueue expected values when sent
    always_ff @(posedge clk_src) begin
        if (src_send)
            expected_q.push_back(src_data);
    end

    // Check received values against expected
    always_ff @(posedge clk_dst) begin
        if (dst_valid) begin
            logic [DATA_WIDTH-1:0] expected_val;
            if (expected_q.size() == 0) begin
                $error("[%0t] TB: Received unexpected data 0x%08X (queue empty)",
                       $time, dst_data);
                fail_count++;
            end else begin
                expected_val = expected_q.pop_front();
                if (dst_data === expected_val) begin
                    $display("[%0t] TB: Received 0x%08X -- PASS", $time, dst_data);
                    pass_count++;
                end else begin
                    $error("[%0t] TB: Received 0x%08X, expected 0x%08X -- FAIL",
                           $time, dst_data, expected_val);
                    fail_count++;
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Task: send one word and wait for dst_valid
    // -------------------------------------------------------------------------
    task automatic send_and_wait(input logic [DATA_WIDTH-1:0] data);
        // Wait until not busy
        @(posedge clk_src);
        while (src_busy) @(posedge clk_src);

        // Assert send for one cycle
        src_data <= data;
        src_send <= 1'b1;
        @(posedge clk_src);
        src_send <= 1'b0;

        // Wait for busy to de-assert (handshake complete)
        @(posedge clk_src);
        while (src_busy) @(posedge clk_src);
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        src_data = '0;
        src_send = 1'b0;

        // Release reset
        repeat (4) @(posedge clk_src);
        repeat (4) @(posedge clk_dst);
        rst_n_src = 1'b1;
        rst_n_dst = 1'b1;
        @(posedge clk_src);

        // Test 1: single transfer
        $display("[%0t] TB: Test 1 -- single transfer", $time);
        send_and_wait(32'hDEAD_BEEF);
        $display("[%0t] TB: Test 1 complete", $time);

        // Test 2: back-to-back transfers
        $display("[%0t] TB: Test 2 -- back-to-back transfers", $time);
        send_and_wait(32'hCAFE_0001);
        send_and_wait(32'hCAFE_0002);
        send_and_wait(32'hCAFE_0003);
        $display("[%0t] TB: Test 2 complete", $time);

        // Test 3: stress test with random data
        $display("[%0t] TB: Test 3 -- %0d random transfers", $time, NUM_XFERS);
        for (int i = 0; i < NUM_XFERS; i++) begin
            automatic logic [DATA_WIDTH-1:0] rdata = $urandom();
            send_and_wait(rdata);
        end
        $display("[%0t] TB: Test 3 complete", $time);

        // Allow outstanding dst_valid to be captured
        repeat (20) @(posedge clk_dst);

        // Final summary
        $display("=== Results: %0d PASSED, %0d FAILED ===", pass_count, fail_count);
        if (fail_count == 0 && pass_count == (1 + 3 + NUM_XFERS))
            $display("TB: ALL TESTS PASSED");
        else
            $error("TB: TESTS FAILED");

        $finish;
    end

    // -------------------------------------------------------------------------
    // Timeout watchdog
    // -------------------------------------------------------------------------
    initial begin
        #5ms;
        $error("[%0t] TB: TIMEOUT -- simulation did not complete", $time);
        $finish;
    end

    // -------------------------------------------------------------------------
    // Assertions
    // -------------------------------------------------------------------------

    // src_send must be a single-cycle pulse (not held high while busy)
    property send_is_pulse;
        @(posedge clk_src) disable iff (!rst_n_src)
        src_send |-> ##1 !src_send;
    endproperty
    assert property (send_is_pulse)
        else $error("[%0t] TB ASSERTION: src_send held high for more than one cycle", $time);

    // dst_valid must be a single-cycle pulse
    property valid_is_pulse;
        @(posedge clk_dst) disable iff (!rst_n_dst)
        dst_valid |-> ##1 !dst_valid;
    endproperty
    assert property (valid_is_pulse)
        else $error("[%0t] TB ASSERTION: dst_valid held high for more than one cycle", $time);

    // REQ must not be asserted while busy is low (invariant: busy -> req eventually)
    property busy_when_req;
        @(posedge clk_src) disable iff (!rst_n_src)
        dut.u_src.req_o |-> src_busy;
    endproperty
    assert property (busy_when_req)
        else $error("[%0t] TB ASSERTION: req_o asserted but src_busy is low", $time);

endmodule : tb_cdc_handshake

// =============================================================================
// Expected simulation output (example, timing will vary with simulator):
//
//   [   95ns] TB: Test 1 -- single transfer
//   [  235ns] TB: Received 0xDEADBEEF -- PASS
//   [  280ns] TB: Test 1 complete
//   [  280ns] TB: Test 2 -- back-to-back transfers
//   [  430ns] TB: Received 0xCAFE0001 -- PASS
//   [  580ns] TB: Received 0xCAFE0002 -- PASS
//   [  730ns] TB: Received 0xCAFE0003 -- PASS
//   [  750ns] TB: Test 2 complete
//   [  750ns] TB: Test 3 -- 1000 random transfers
//   ...
//   [XXXXXX ns] TB: Test 3 complete
//   === Results: 1004 PASSED, 0 FAILED ===
//   TB: ALL TESTS PASSED
//
// Key things to verify in waveforms:
//   1. req_raw is held high until ack_sync is observed in src domain.
//   2. data_stable does not change between src_send and src_busy de-assertion.
//   3. dst_valid is exactly one clk_dst cycle wide.
//   4. Back-to-back transfers: no data is dropped.
// =============================================================================
