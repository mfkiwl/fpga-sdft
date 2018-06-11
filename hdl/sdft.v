`default_nettype none
module sdft
#(
    parameter data_width = 8, 
    parameter freq_bins = 16,
    parameter FILE_REAL = "hdl/twiddle_real.list",
    parameter FILE_IMAJ = "hdl/twiddle_imag.list"
)
(
    input wire                              clk,
    input wire signed [data_width-1:0]      sample,
    output wire                             ready,
    input wire                              start
);


    // width of addr needed to address the frequency bins
    localparam bin_addr_w = $clog2(freq_bins);

    // register for the twiddle factor ROM
    reg [bin_addr_w:0] tw_addr;

    // register for sample index
    reg [bin_addr_w-1:0] sample_index;

    // twiddle factor ROM
    wire signed [data_width-1:0] twid_real;
    wire signed [data_width-1:0] twid_imag;
    twiddle_rom #(.addr_w(bin_addr_w), .data_w(data_width)) twiddle_rom_0(.clk(clk), .addr(tw_addr), .dout_real(twid_real), .dout_imag(twid_imag));

    // complex mult
    /*
    wire signed [data_width*2-1:0] complex_mult_out_real;
    wire signed [data_width*2-1:0] complex_mult_out_imag;

    wire signed [data_width:0] complex_mult_in_a_real; // one extra bit for handling subtraction of delta
    wire signed [data_width:0] complex_mult_in_a_imag;

    complex_mult #(.data_in_w(data_width+1), .data_out_w(data_width*2)) complex_mult_0(.a_real(complex_mult_in_a_real), .a_imag(complex_mult_in_a_imag), .b_real(twid_real), .b_imag(twid_imag), .out_real(complex_mult_out_real), .out_imag(complex_mult_out_imag));

*/
    // frequency bins RAM - double width to handle multiply
    reg signed [data_width*2-1:0] frequency_bins_real [freq_bins-1:0];
    reg signed [data_width*2-1:0] frequency_bins_imag [freq_bins-1:0];

    // sample storage
    reg signed [data_width-1:0] samples [freq_bins-1:0];

    // delta storage (1 more than data_width to handle subtraction)
    reg signed [data_width:0] delta;

    integer j;
    initial begin
        tw_addr = 0;
        sample_index = 0;
        delta = 0;
        for(j = 0; j < freq_bins; j = j + 1)  begin
            samples[j] = 0;
            frequency_bins_real[j] = 0;
            frequency_bins_imag[j] = 0;
        end
    end

    localparam STATE_WAIT           = 0;
    localparam STATE_START          = 1;
    localparam STATE_LOAD_ROM       = 2;
    localparam STATE_WAIT_ROM       = 3;
    localparam STATE_CALC           = 4;
    localparam STATE_FINISH         = 5;

    reg [3:0] state = STATE_START;
/*
    assign complex_mult_in_a_real = frequency_bins_real[tw_addr] + delta;
    assign complex_mult_in_a_imag = frequency_bins_imag[tw_addr]; // imag component
*/
    assign ready = state == STATE_WAIT ? 1'b1 : 1'b0;

    always@(posedge clk) begin
        case(state)
            STATE_WAIT: begin
                if(start)
                    state <= STATE_START;
            end 

            STATE_START: begin
                // get delta: newest - oldest
                delta <= sample - samples[sample_index];
                // store new sample
                samples[sample_index] <= sample;
                tw_addr <= 0;
                state <= STATE_CALC;
            end

            STATE_LOAD_ROM: begin // 2
                tw_addr <= tw_addr + 1; 
                if(tw_addr == freq_bins -1) begin
                    tw_addr <= 0;
                    state <= STATE_FINISH;
                end else
                    state <= STATE_WAIT_ROM;
            end
            STATE_WAIT_ROM: begin // 3
                state <= STATE_CALC;
            end
            STATE_CALC: begin // 4
                //freqs[i] =  (freqs[i] + delta) * coeffs[i]
//                frequency_bins_real[tw_addr] <= complex_mult_out_real >>> 7;
//                frequency_bins_imag[tw_addr] <= complex_mult_out_imag >>> 7;
//                frequency_bins_real[tw_addr] <= ((frequency_bins_real[tw_addr] + delta) * twid_real + (frequency_bins_imag[tw_addr] * twid_imag)) >>> 7;
 //               frequency_bins_imag[tw_addr] <= ((frequency_bins_imag[tw_addr]) * twid_imag + (frequency_bins_imag[tw_addr] * twid_real)) >>> 7;
              // delta is only real, so can skip adding it to the imag parts
                frequency_bins_real[tw_addr] <= ((frequency_bins_real[tw_addr] + delta) * twid_real - (frequency_bins_imag[tw_addr] * twid_imag)) >>> 7;
                frequency_bins_imag[tw_addr] <= ((frequency_bins_real[tw_addr] + delta) * twid_imag + (frequency_bins_imag[tw_addr] * twid_real)) >>> 7;



                state <= STATE_LOAD_ROM;
            end

            STATE_FINISH: begin
                // increment sample index (same as rotating)
                sample_index <= sample_index + 1;
                // reset index if it wraps
                if(sample_index == freq_bins)
                    sample_index <= 0;
                state <= STATE_WAIT;
            end 

        endcase
    end


endmodule

