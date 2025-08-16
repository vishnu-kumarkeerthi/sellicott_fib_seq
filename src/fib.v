//======================================================================
// TinyTapeout 8x8 Fixed-Point Multiplier (Shift & Add, Register-Optimized)
// Wrapper: tt_um_mult8_shiftadd
// - ui_in[7:0]  : data bus for writing A or B
// - uio_in[0]   : load_A (pulse 1 clk)
// - uio_in[1]   : load_B (pulse 1 clk)
// - uio_in[2]   : start  (pulse 1 clk)
// - uio_in[3]   : out_sel (0=low byte, 1=high byte)
// - uo_out[7:0] : result byte (gated by ena)
// - uio_out[7]  : done flag (OE enabled only on bit 7, gated by ena)
// - uio_oe[7]   : output-enable for done (others stay inputs)
// - clk         : free-running TT clock
// - rst_n       : active-low reset
// - ena         : high when this tile is selected; we gate outputs with ena
//
// Fixed-point scaling: result_out = (raw_product >> FRAC_BITS)
// Default FRAC_BITS=0 provides raw 16-bit product.
//======================================================================
`default_nettype none

module tt_um_mult8_shiftadd #(
    parameter integer FRAC_BITS = 0  // 0..8 typical; shift-right applied after multiply
) (
    input  wire [7:0] ui_in,     // dedicated inputs (data bus for A/B write)
    output wire [7:0] uo_out,    // dedicated outputs (selected result byte)
    input  wire [7:0] uio_in,    // IO (controls)
    output wire [7:0] uio_out,   // IO (done on bit 7)
    output wire [7:0] uio_oe,    // IO output enable (only bit 7 is driven)
    input  wire       ena,       // design enable
    input  wire       clk,       // clock
    input  wire       rst_n      // reset (active low)
);
    // ---------------------------
    // Control assignments
    // ---------------------------
    wire load_A  = uio_in[0];
    wire load_B  = uio_in[1];
    wire start   = uio_in[2];
    wire out_sel = uio_in[3];

    // ---------------------------
    // Operand registers
    // ---------------------------
    reg [7:0] A_reg, B_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            A_reg <= 8'd0;
            B_reg <= 8'd0;
        end else begin
            if (load_A) A_reg <= ui_in;
            if (load_B) B_reg <= ui_in;
        end
    end

    // ---------------------------
    // Multiplier core
    // ---------------------------
    wire        mul_busy;
    wire        mul_done;
    wire [15:0] mul_product;

    mul8_shiftadd_core core_i (
        .clk       (clk),
        .rst_n     (rst_n),
        .start     (start),
        .a         (A_reg),
        .b         (B_reg),
        .busy      (mul_busy),
        .done      (mul_done),
        .product   (mul_product)
    );

    // ---------------------------
    // Fixed-point scaling
    // ---------------------------
    wire [15:0] scaled_result = (FRAC_BITS == 0) ? mul_product
                                                 : (mul_product >> FRAC_BITS);

    // Output multiplexing (byte select)
    wire [7:0] result_low  = scaled_result[7:0];
    wire [7:0] result_high = scaled_result[15:8];

    // Drive outputs only when ena=1
    assign uo_out  = ena ? (out_sel ? result_high : result_low) : 8'h00;

    // Done flag on uio[7]; enable only that bit when ena=1
    assign uio_out = { {1{mul_done & ena}}, 7'b0 };
    assign uio_oe  = { {1{ena}},            7'b0 };

endmodule

//======================================================================
// Core: 8x8 Unsigned Shift-and-Add Multiplier (Iterative, 8 cycles)
// - Register-optimized: single 16b accumulator + shifting A/B
// - start pulse begins operation; 'done' pulses high for one cycle.
// - 'busy' stays high while iterating.
//======================================================================
module mul8_shiftadd_core (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start,
    input  wire [7:0] a,     // multiplicand
    input  wire [7:0] b,     // multiplier
    output reg        busy,
    output reg        done,
    output reg [15:0] product
);
    reg [7:0]  mult;          // shifting copy of multiplier (b)
    reg [15:0] mcand_ext;     // shifted multiplicand (a) extended to 16b
    reg [3:0]  count;         // iteration counter (0..8)

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy       <= 1'b0;
            done       <= 1'b0;
            product    <= 16'd0;
            mult       <= 8'd0;
            mcand_ext  <= 16'd0;
            count      <= 4'd0;
        end else begin
            done <= 1'b0; // default; pulses 1 cycle when finished

            if (start && !busy) begin
                // Load operands and initialize
                product   <= 16'd0;
                mcand_ext <= {8'd0, a};
                mult      <= b;
                count     <= 4'd8;
                busy      <= 1'b1;
            end else if (busy) begin
                // Iterative shift-and-add
                if (mult[0]) begin
                    product <= product + mcand_ext;
                end
                mcand_ext <= mcand_ext << 1;
                mult      <= mult >> 1;

                // Decrement and check completion
                if (count == 4'd1) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    count <= 4'd0;
                end else begin
                    count <= count - 1'b1;
                end
            end
        end
    end
endmodule

`default_nettype wire
