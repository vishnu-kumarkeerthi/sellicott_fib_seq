`timescale 1ns/1ps
`default_nettype none

module tb_tt_um_mult8_shiftadd;
    // DUT ports
    logic [7:0] ui_in;
    wire  [7:0] uo_out;
    logic [7:0] uio_in;
    wire  [7:0] uio_out;
    wire  [7:0] uio_oe;
    logic       ena;
    logic       clk;
    logic       rst_n;

    // Instantiate DUT (FRAC_BITS=0 => raw 16b product)
    tt_um_mult8_shiftadd #(.FRAC_BITS(0)) dut (
        .ui_in   (ui_in),
        .uo_out  (uo_out),
        .uio_in  (uio_in),
        .uio_out (uio_out),
        .uio_oe  (uio_oe),
        .ena     (ena),
        .clk     (clk),
        .rst_n   (rst_n)
    );

    // Clock: 100 MHz
    initial clk = 0;
    always #5 clk = ~clk;

    // Helpers
    task automatic pulse(input int bit_idx);
        begin
            uio_in[bit_idx] = 1'b1;
            @(posedge clk);
            uio_in[bit_idx] = 1'b0;
            @(posedge clk);
        end
    endtask

    task automatic write_A(input logic [7:0] val);
        begin
            ui_in = val;
            pulse(0); // load_A
        end
    endtask

    task automatic write_B(input logic [7:0] val);
        begin
            ui_in = val;
            pulse(1); // load_B
        end
    endtask

    task automatic start_mul();
        begin
            pulse(2); // start
        end
    endtask

    function automatic [15:0] read_result();
        logic [7:0] lo, hi;
        begin
            uio_in[3] = 1'b0; // out_sel = low
            @(posedge clk);
            lo = uo_out;

            uio_in[3] = 1'b1; // out_sel = high
            @(posedge clk);
            hi = uo_out;

            read_result = {hi, lo};
        end
    endfunction

    task automatic do_test(input logic [7:0] a, input logic [7:0] b);
        logic [15:0] expect, got;
        begin
            write_A(a);
            write_B(b);
            start_mul();

            // Wait for done (uio_out[7]) — allow a generous timeout
            int timeout = 0;
            while (uio_out[7] !== 1'b1) begin
                @(posedge clk);
                timeout++;
                if (timeout > 50) begin
                    $fatal(1, "Timeout waiting for done (A=%0d, B=%0d)", a, b);
                end
            end

            got     = read_result();
            expect  = a * b; // FRAC_BITS=0 in this bench

            if (got !== expect) begin
                $display("FAIL: A=%0d (0x%02h)  B=%0d (0x%02h)  expect=0x%04h  got=0x%04h",
                         a, a, b, b, expect, got);
                $fatal(1);
            end else begin
                $display("PASS: A=%0d (0x%02h)  B=%0d (0x%02h)  result=0x%04h",
                         a, a, b, b, got);
            end
        end
    endtask

    // Stimulus
    initial begin
        // Defaults
        ui_in  = 8'h00;
        uio_in = 8'h00;
        ena    = 1'b0;
        rst_n  = 1'b0;

        // Reset
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        ena   = 1'b1; // act like our tile is selected

        // Small delay after enabling
        repeat (2) @(posedge clk);

        // Test vectors
        do_test(8'h00, 8'h00);   // 0 * 0 = 0x0000
        do_test(8'h01, 8'hFF);   // 1 * 255 = 0x00FF
        do_test(8'hAA, 8'h0F);   // 170 * 15  = 2550 = 0x09F6
        do_test(8'h7F, 8'h80);   // 127 * 128 = 16256 = 0x3F80
        do_test(8'hFF, 8'hFF);   // 255 * 255 = 65025 = 0xFE01

        $display("All tests passed.");
        $finish;
    end

endmodule

`default_nettype wire
