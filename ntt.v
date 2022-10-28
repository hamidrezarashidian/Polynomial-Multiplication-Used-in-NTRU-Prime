module ntt (clk, rst, start, input_fg, addr, din, dout, valid);

    parameter P_WIDTH = 13;
    parameter Q0 = 4591;
    parameter Q1 = 7681;
    parameter Q2 = 12289;
    parameter Q3 = 15361;
    parameter Q23inv = 2562;
    parameter Q31inv = -4107;
    parameter Q12inv = 10;

    parameter Q2Q3PREFIX = 184347;
    parameter Q3Q1PREFIX = 230445;
    parameter Q1Q2PREFIX = 184359;

    parameter Q2Q3SHIFT = 10;
    parameter Q3Q1SHIFT = 9;
    parameter Q1Q2SHIFT = 9;

    parameter bit = 9; // 512 point

    localparam Q0_12 = (Q0 - 1) / 2;
    localparam Q1Q2Q3p = 34'sh197E88A01; // 1449952578049='h15197E88A01, w.o.prefix
    localparam Q1Q2Q3n = 34'sh2681775FF;

    // state
    parameter idle = 0;
    parameter ntt = 1;
    parameter point_mul = 2;
    parameter reload = 3;
    parameter intt = 4;
    parameter crt = 5;
    parameter reduce = 6;
    parameter finish = 7;

    input                clk;
    input                rst;
    input                start;
    input                input_fg;
    input       [10 : 0] addr;
    input       [12 : 0] din;
    output reg  [13 : 0] dout;
    output reg           valid;

    // dout control
    reg   [10 : 0] addr_2;

    // bram
    reg            wr_en   [0 : 2];
    reg   [10 : 0] wr_addr [0 : 2];
    reg   [10 : 0] rd_addr [0 : 2];
    reg   [41 : 0] wr_din  [0 : 2];
    wire  [41 : 0] rd_dout [0 : 2];
    wire  [41 : 0] wr_dout [0 : 2];

    // addr_gen
    wire         bank_index_rd [0 : 1];
    wire         bank_index_wr [0 : 1];
    wire [7 : 0] data_index_rd [0 : 1];
    wire [7 : 0] data_index_wr [0 : 1];
    reg  bank_index_wr_0_shift_1, bank_index_wr_0_shift_2;

    // w_addr_gen
    reg  [7 : 0] stage_bit;
    wire [7 : 0] w_addr;

    // bfu
    reg                  ntt_state; 
    reg  signed [13 : 0] in_a  [0 : 2];
    reg  signed [13 : 0] in_b  [0 : 2];
    reg  signed [18 : 0] w     [0 : 2];
    wire signed [32 : 0] bw    [0 : 2];
    wire signed [13 : 0] out_a [0 : 2];
    wire signed [13 : 0] out_b [0 : 2];

    // state, stage, counter
    reg  [2 : 0] state, next_state;
    reg  [3 : 0] stage, stage_wr;
    reg  [8 : 0] ctr;
    reg  [8 : 0] ctr_shift_7, ctr_shift_8, ctr_shift_1, ctr_shift_2;
    reg  [2 : 0] ctr_ntt;
    reg  [1 : 0] count_f, count_g;
    reg          part, part_shift, ctr_8_shift_1;
    wire         ctr_end, ctr_shift_7_end, stage_end, stage_wr_end, ntt_end, point_mul_end, reduce_end;
    reg  [1 : 0] count_f_shift_1, count_f_shift_2;
    reg  [1 : 0] count_g_shift_1, count_g_shift_2, count_g_shift_3, count_g_shift_4, count_g_shift_5;

    // reduce by x^p - x - 1
    reg  [10 : 0] red_ctr;
    reg  [10 : 0] red_ctr_1, red_ctr_2, red_ctr_3, red_ctr_4, red_ctr_5, red_ctr_6, red_ctr_7;
    reg  [10 : 0] red_ctr_m3, red_ctr_m7;
    wire [2  : 0] red_addr;
    reg signed [13 : 0] red_value;
    reg signed [13 : 0] red_value_1;
    reg signed [13 : 0] red_ld;
    reg signed [13 : 0] red_sum;
    reg signed [13 : 0] red_sum_mod;
    wire          red2_necessary, red5_necessary, red6_necessary;

    // w_7681
    reg         [8  : 0] w_addr_in;
    wire [41:0] w_dout42b ;
    wire signed [13 : 0] w_dout [0 : 2];

    reg          bank_index_rd_shift_1, bank_index_rd_shift_2;
    reg [8  : 0] wr_ctr [0 : 1];
    reg [12 : 0] din_shift_1, din_shift_2, din_shift_3;
    reg [8  : 0] w_addr_in_shift_1;

    // mod_3
    wire [2 : 0] in_addr;

    // crt
    reg  signed [13 : 0] in_b_1 [0 : 2];
    reg  signed [15 : 0] in_b_sum;
    reg  signed [32 : 0] bw_sum;
    wire signed [33 : 0] bw_sum_ALL;
    wire signed [33 : 0] q1q2q3_ALL;
    reg  signed [32 : 0] bw_sum_mod;
    wire signed [12 : 0] mod4591_out;

    // crt debug
    wire signed [13 : 0] in_b0_1;
    wire signed [13 : 0] in_b1_1;
    wire signed [13 : 0] in_b2_1;

    bram_p #(.D_SIZE(42), .Q_DEPTH(11)) bank_0 
    (clk, wr_en[0], wr_addr[0], rd_addr[0], wr_din[0], wr_dout[0], rd_dout[0]);
    bram_p #(.D_SIZE(42), .Q_DEPTH(11)) bank_1
    (clk, wr_en[1], wr_addr[1], rd_addr[1], wr_din[1], wr_dout[1], rd_dout[1]);
    bram_p #(.D_SIZE(42), .Q_DEPTH(11)) bank_2
    (clk, wr_en[2], wr_addr[2], rd_addr[2], wr_din[2], wr_dout[2], rd_dout[2]);

    addr_gen addr_rd_0 (clk, stage,    {1'b0, ctr[7 : 0]}, bank_index_rd[0], data_index_rd[0]);
    addr_gen addr_rd_1 (clk, stage,    {1'b1, ctr[7 : 0]}, bank_index_rd[1], data_index_rd[1]);
    addr_gen addr_wr_0 (clk, stage_wr, {wr_ctr[0]}, bank_index_wr[0], data_index_wr[0]);
    addr_gen addr_wr_1 (clk, stage_wr, {wr_ctr[1]}, bank_index_wr[1], data_index_wr[1]);

    w_addr_gen w_addr_gen_0 (clk, stage_bit, ctr[7 : 0], w_addr);

    bfu_7681 bfu_0 (clk, ntt_state, in_a[0], in_b[0], w[0], bw[0], out_a[0], out_b[0]);
    bfu_12289 bfu_1 (clk, ntt_state, in_a[1], in_b[1], w[1], bw[1], out_a[1], out_b[1]);
    bfu_15361 bfu_2 (clk, ntt_state, in_a[2], in_b[2], w[2], bw[2], out_a[2], out_b[2]);
    
//HRr vvvvvvv

    // w_7681 rom_w_7681 (clk, w_addr_in_shift_1, w_dout[0]);
    // w_12289 rom_w_12289 (clk, w_addr_in_shift_1, w_dout[1]);
    // w_15361 rom_w_15361 (clk, w_addr_in_shift_1, w_dout[2]);
     w42bit w_42bit (clk, w_addr_in_shift_1, w_dout42b);
     assign w_dout[0] = w_dout42b[41:28] ;
     assign w_dout[1] = w_dout42b[27:14] ;
     assign w_dout[2] = w_dout42b[13:0]  ;  
     

     
    
//HRr ^^^^^^^

    mod_3 in_addr_gen (clk, addr, input_fg, in_addr);
    mod_3 red_addr_gen (clk, red_ctr, 0, red_addr);
    mod4591S33 mod_4591 ( clk, rst, bw_sum_mod, mod4591_out);

    assign ctr_end         = (ctr[7 : 0] == 255) ? 1 : 0;
    assign ctr_shift_7_end = (ctr_shift_7[7 : 0] == 255) ? 1 : 0;
    assign stage_end       = (stage == 9) ? 1 : 0;
    assign stage_wr_end    = (stage_wr == 9) ? 1 : 0;
    assign ntt_end         = (stage_end && ctr[7 : 0] == 10) ? 1 : 0;
    // change assign ntt_end         = (stage_end && ctr[7 : 0] == 8) ? 1 : 0;
    assign point_mul_end   = (count_f == 3 && ctr_shift_7 == 511) ? 1 : 0;
    assign reload_end      = (count_f == 0 && ctr == 4) ? 1 : 0;
    assign reduce_end      = (red_ctr == 1529);

    // crt debug
    assign in_b0_1 = in_b_1[0];
    assign in_b1_1 = in_b_1[1];
    assign in_b2_1 = in_b_1[2];

    assign bw_sum_ALL = $signed({ bw_sum[24:0], 9'b0 }) + in_b_sum;
    assign q1q2q3_ALL = bw_sum[32] ? (bw_sum[31] ? $signed(0) : $signed(Q1Q2Q3p))
                                   : (bw_sum[31] ? $signed(Q1Q2Q3n) : $signed(0));

    always @(posedge clk ) begin
        in_b_1[0] <= in_b[0];
        in_b_1[1] <= in_b[1];
        in_b_1[2] <= in_b[2];

        in_b_sum <= in_b_1[0] + in_b_1[1] + in_b_1[2];
        bw_sum <= $signed({ bw[0], 1'b0 }) + $signed( bw[1] + bw[2] );
        
        bw_sum_mod <= bw_sum_ALL + q1q2q3_ALL;
        //if (bw_sum[32:31] == 2'b01) begin
        //    bw_sum_mod <= bw_sum_ALL + $signed(Q1Q2Q3n);
        //end else if (bw_sum[32:31] == 2'b10) begin
        //    bw_sum_mod <= bw_sum_ALL + $signed(Q1Q2Q3p);
        //end else begin
        //    bw_sum_mod <= bw_sum_ALL;
        //end
    end

    // dout
    //always @(posedge clk ) begin
    //    if (bank_index_wr_0_shift_2) begin
    //        //dout <= wr_dout[1][27 : 14];
    //        dout <= wr_dout[1][13 : 0];
    //    end else begin
    //        //dout <= wr_dout[0][27 : 14];
    //        dout <= wr_dout[0][13 : 0];
    //    end
    //end
    always @ (*) begin
      if(valid && addr_2 < 761) begin
        dout = wr_dout[2][13 : 0];
      end else begin
        dout = 'sd0;
      end
    end

    // bank_index_wr_0_shift_1
    always @(posedge clk ) begin
        bank_index_wr_0_shift_1 <= bank_index_wr[0];
        bank_index_wr_0_shift_2 <= bank_index_wr_0_shift_1;
    end

    // part
    always @(posedge clk ) begin
        ctr_8_shift_1 <= ctr[8];
        part <= ctr_8_shift_1;
        part_shift <= ctr_shift_7[8];
    end

    // count_f, count_g
    always @(posedge clk ) begin
        if (state == point_mul || state == reload || state == crt) begin
            if (count_g == 2 && ctr == 511) begin
                count_f <= count_f + 1;
            end else begin
                count_f <= count_f;
            end
        end else begin
            count_f <= 0;
        end
        count_f_shift_1 <= count_f;
        count_f_shift_2 <= count_f_shift_1;


        if (state == point_mul || state == reload || state == crt) begin
            if (ctr == 511) begin
                if (count_g == 2) begin
                    count_g <= 0;
                end else begin
                    count_g <= count_g + 1;
                end
            end else begin
                count_g <= count_g;
            end
        end else begin
            count_g <= 0;
        end
        count_g_shift_1 <= count_g;
        count_g_shift_2 <= count_g_shift_1;
        count_g_shift_3 <= count_g_shift_2;
        count_g_shift_4 <= count_g_shift_3;
        count_g_shift_5 <= count_g_shift_4;
    end

    // rd_addr[2]
    always @(posedge clk ) begin
        if (state == point_mul) begin
            rd_addr[2][8 : 0] <= ctr;
        end else if (state == reload) begin
            rd_addr[2][8 : 0] <= {bank_index_wr[1], data_index_wr[1]};
        end else if (state == reduce) begin
            rd_addr[2][8 : 0] <= red_ctr_m3[8:0]; 
        end else begin
            rd_addr[2][8 : 0] <= 0;
        end

        if (state == point_mul) begin
            if (ctr == 0) begin
                if (count_g == 0) begin
                    rd_addr[2][10 : 9] <= count_f;
                end else begin
                    if (rd_addr[2][10 : 9] == 0) begin
                        rd_addr[2][10 : 9] <= 1;
                    end else if (rd_addr[2][10 : 9] == 1) begin
                        rd_addr[2][10 : 9] <= 2;
                    end else begin
                        rd_addr[2][10 : 9] <= 0;
                    end
                end
            end else begin
                rd_addr[2][10 : 9] <= rd_addr[2][10 : 9];
            end
        end else if (state == reload) begin
            rd_addr[2][10 : 9] <= count_g_shift_3;
        end else if (state == reduce) begin
            rd_addr[2][10 : 9] <= red_ctr_m3[10 : 9];
        end else begin
            rd_addr[2][10 : 9] <= 0;
        end
    end

    // wr_en[2]
    always @(posedge clk ) begin
        if (state == point_mul) begin
            if (count_f == 0 && count_g == 0 && ctr < 8 /* change ctr < 6*/) begin
                wr_en[2] <= 0;
            end else begin
                wr_en[2] <= 1;
            end
        end else if (state == reduce) begin
            if (reduce_end) begin
                wr_en[2] <= 0;
            end else begin
                wr_en[2] <= |red_ctr_6;
            end
        end else begin
            wr_en[2] <= 0;
        end
    end

    // wr_addr[2]
    always @(posedge clk ) begin
        if (state == point_mul) begin
            wr_addr[2][8 : 0] <= ctr_shift_7;
        end else if(state == reduce) begin
            wr_addr[2][8 : 0] <= red_ctr_m7[8:0];
        end else if(state == finish) begin
            wr_addr[2][8 : 0] <= addr[8:0];
        end else begin
            wr_addr[2][8 : 0] <= 0;
        end        

        if (state == point_mul) begin
            if (ctr_shift_7 == 0) begin
                if (count_g == 0) begin
                    wr_addr[2][10 : 9] <= count_f;
                end else begin
                    if (wr_addr[2][10 : 9] == 0) begin
                        wr_addr[2][10 : 9] <= 1;
                    end else if (wr_addr[2][10 : 9] == 1) begin
                        wr_addr[2][10 : 9] <= 2;
                    end else begin
                        wr_addr[2][10 : 9] <= 0;
                    end
                end
            end else begin
                wr_addr[2][10 : 9] <= wr_addr[2][10 : 9];
            end
        end else if (state == reduce) begin
            wr_addr[2][10 : 9] <= red_ctr_m7[10:9];
        end else if (state == finish) begin
            wr_addr[2][10 : 9] <= addr[10:9];
        end else begin
            wr_addr[2][10 : 9] <= 0;
        end

        addr_2 <= wr_addr[2];
    end

    // wr_din[2]
    always @ (*) begin
        if(state == reduce) begin
            wr_din[2][13 : 0] = red_sum_mod;
        end else begin
            wr_din[2][13 : 0] = out_a[0];
        end
        wr_din[2][27 : 14] = out_a[1];
        wr_din[2][41 : 28] = out_a[2];
    end

    // ctr_ntt
    always @(posedge clk ) begin
        if (state == ntt || state == intt) begin
            if (ntt_end) begin
                ctr_ntt <= ctr_ntt + 1;
            end else begin
                ctr_ntt <= ctr_ntt;
            end    
        end else begin
            ctr_ntt <= 0;
        end
    end

    // w_addr_in_shift_1
    always @(posedge clk ) begin
        w_addr_in_shift_1 <= w_addr_in;
    end

    // din_shift
    always @(posedge clk ) begin
        din_shift_1 <= din;
        din_shift_2 <= din_shift_1;
        din_shift_3 <= din_shift_2;
    end

    // rd_addr
    always @(posedge clk ) begin
        if (state == point_mul || state == crt) begin
            rd_addr[0][7 : 0] <= ctr[7 : 0];
            rd_addr[1][7 : 0] <= ctr[7 : 0];
        end else begin
            if (bank_index_rd[0] == 0) begin
                rd_addr[0][7 : 0] <= data_index_rd[0];
                rd_addr[1][7 : 0] <= data_index_rd[1];
            end else begin
                rd_addr[0][7 : 0] <= data_index_rd[1];
                rd_addr[1][7 : 0] <= data_index_rd[0];
            end
        end

        if (state == point_mul) begin
            rd_addr[0][10 : 8] <= count_f;
            rd_addr[1][10 : 8] <= count_f;
        end else if (state == crt) begin
            rd_addr[0][10 : 8] <= count_g;
            rd_addr[1][10 : 8] <= count_g;  
        end else begin
            rd_addr[0][10 : 8] <= ctr_ntt;
            rd_addr[1][10 : 8] <= ctr_ntt;
        end
    end

    // wr_ctr
    always @(posedge clk ) begin
        if (state == idle) begin
            wr_ctr[0] <= addr[8 : 0];
        end else if (state == reload) begin
            wr_ctr[0] <= {ctr_shift_2[0], ctr_shift_2[1], ctr_shift_2[2], ctr_shift_2[3], ctr_shift_2[4], ctr_shift_2[5], ctr_shift_2[6], ctr_shift_2[7], ctr_shift_2[8]};
        end else if (state == finish) begin
            wr_ctr[0] <= {addr[0], addr[1], addr[2], addr[3], addr[4], addr[5], addr[6], addr[7], addr[8]};
        end else if (state == reduce) begin
            wr_ctr[0] <= {red_ctr[0], red_ctr[1], red_ctr[2], red_ctr[3], red_ctr[4], red_ctr[5], red_ctr[6], red_ctr[7], red_ctr[8]};
        end else begin
            wr_ctr[0] <= {1'b0, ctr_shift_7[7 : 0]};
        end

        if (state == reload) begin
            wr_ctr[1] <= ctr;
        end else begin
            wr_ctr[1] <= {1'b1, ctr_shift_7[7 : 0]};
        end
    end

    // wr_en
    always @(posedge clk ) begin
        if (state == idle || state == reload) begin
            if (bank_index_wr[0]) begin
                wr_en[0] <= 0;
                wr_en[1] <= 1;
            end else begin
                wr_en[0] <= 1;
                wr_en[1] <= 0;
            end
        end else if (state == ntt || state == intt) begin
            if (stage == 0 && ctr < 11 /*change 9*/) begin
                wr_en[0] <= 0;
                wr_en[1] <= 0;
            end else begin
                wr_en[0] <= 1;
                wr_en[1] <= 1;
            end
        end else if (state == crt) begin
            if (count_f == 0 && count_g == 0 && ctr < 9/* change */) begin
                wr_en[0] <= 0;
                wr_en[1] <= 0;
            end else if (!part_shift) begin
                wr_en[0] <= 1;
                wr_en[1] <= 0;
            end else begin
                wr_en[0] <= 0;
                wr_en[1] <= 1;
            end
        end else begin
            wr_en[0] <= 0;
            wr_en[1] <= 0;
        end
    end

    // wr_addr
    always @(posedge clk ) begin
        if (state == point_mul) begin
            wr_addr[0][7 : 0] <= ctr[7 : 0];
            wr_addr[1][7 : 0] <= ctr[7 : 0];
        end else if (state == reload) begin
            wr_addr[0][7 : 0] <= data_index_wr[0];
            wr_addr[1][7 : 0] <= data_index_wr[0];
        end else if (state == crt) begin
            wr_addr[0][7 : 0] <= ctr_shift_8[7 : 0];
            wr_addr[1][7 : 0] <= ctr_shift_8[7 : 0];
        end else begin
            if (bank_index_wr[0] == 0) begin
                wr_addr[0][7 : 0] <= data_index_wr[0];
                wr_addr[1][7 : 0] <= data_index_wr[1];
            end else begin
                wr_addr[0][7 : 0] <= data_index_wr[1];
                wr_addr[1][7 : 0] <= data_index_wr[0];
            end
        end  

        if (state == idle || state == finish) begin
            wr_addr[0][10 : 8] <= in_addr;
            wr_addr[1][10 : 8] <= in_addr;
        end else if (state == reduce) begin
            wr_addr[0][10 : 8] <= red_addr;
            wr_addr[1][10 : 8] <= red_addr;
        end else if(state == ntt || state == intt) begin
            wr_addr[0][10 : 8] <= ctr_ntt;
            wr_addr[1][10 : 8] <= ctr_ntt;
        end else if (state == point_mul) begin
            wr_addr[0][10 : 8] <= count_g + 3;
            wr_addr[1][10 : 8] <= count_g + 3;
        end else if (state == reload) begin
            wr_addr[0][10 : 8] <= count_g_shift_5;
            wr_addr[1][10 : 8] <= count_g_shift_5;
        end else if (state == crt) begin
            if (ctr_shift_8 == 0) begin
                wr_addr[0][10 : 8] <= count_g;
                wr_addr[1][10 : 8] <= count_g;
            end else begin
                wr_addr[0][10 : 8] <= wr_addr[0][10 : 8];
                wr_addr[1][10 : 8] <= wr_addr[1][10 : 8];
            end
        end else begin
            wr_addr[0][10 : 8] <= 0;
            wr_addr[1][10 : 8] <= 0;
        end     
    end

    // wr_din
    always @( posedge clk ) begin
        if (state == idle) begin
            wr_din[0][13 : 0] <= {din_shift_3[12], din_shift_3};
            wr_din[1][13 : 0] <= {din_shift_3[12], din_shift_3};
        end else if (state == reload) begin
            wr_din[0][13 : 0] <= rd_dout[2][13 : 0];
            wr_din[1][13 : 0] <= rd_dout[2][13 : 0];
        end else if (state == crt) begin
            wr_din[0][13 : 0] <= out_a[0];
            wr_din[1][13 : 0] <= out_a[0];
            if (count_f == 0 || (count_f == 1 && count_g == 0 && ctr < 9)) begin
                wr_din[0][13 : 0] <= out_a[0];
                wr_din[1][13 : 0] <= out_a[0];
            end else begin
                wr_din[0][13 : 0] <= mod4591_out;
                wr_din[1][13 : 0] <= mod4591_out;
            end
        end else begin
            if (bank_index_wr[0] == 0) begin
                wr_din[0][13 : 0] <= out_a[0];
                wr_din[1][13 : 0] <= out_b[0];
            end else begin
                wr_din[0][13 : 0] <= out_b[0];
                wr_din[1][13 : 0] <= out_a[0];
            end
        end

        if (state == idle) begin
            wr_din[0][27 : 14] <= {din_shift_3[12], din_shift_3};
            wr_din[1][27 : 14] <= {din_shift_3[12], din_shift_3};
        end else if (state == reload) begin
            wr_din[0][27 : 14] <= rd_dout[2][27 : 14];
            wr_din[1][27 : 14] <= rd_dout[2][27 : 14];
        end else if (state == crt) begin
            wr_din[0][27 : 14] <= out_a[1];
            wr_din[1][27 : 14] <= out_a[1];
        end else begin
            if (bank_index_wr[0] == 0) begin
                wr_din[0][27 : 14] <= out_a[1];
                wr_din[1][27 : 14] <= out_b[1];
            end else begin
                wr_din[0][27 : 14] <= out_b[1];
                wr_din[1][27 : 14] <= out_a[1];
            end
        end

        if (state == idle) begin
            wr_din[0][41 : 28] <= {din_shift_3[12], din_shift_3};
            wr_din[1][41 : 28] <= {din_shift_3[12], din_shift_3};
        end else if (state == reload) begin
            wr_din[0][41 : 28] <= rd_dout[2][41 : 28];
            wr_din[1][41 : 28] <= rd_dout[2][41 : 28];
        end else if (state == crt) begin
            wr_din[0][41 : 28] <= out_a[2];
            wr_din[1][41 : 28] <= out_a[2];
        end else begin
            if (bank_index_wr[0] == 0) begin
                wr_din[0][41 : 28] <= out_a[2];
                wr_din[1][41 : 28] <= out_b[2];
            end else begin
                wr_din[0][41 : 28] <= out_b[2];
                wr_din[1][41 : 28] <= out_a[2];
            end
        end        
    end

    // bank_index_rd_shift
    always @(posedge clk ) begin
        bank_index_rd_shift_1 <= bank_index_rd[0];
        bank_index_rd_shift_2 <= bank_index_rd_shift_1;
    end

    // ntt_state
    always @(posedge clk ) begin
        if (state == intt) begin
            ntt_state <= 1;
        end else begin
            ntt_state <= 0;
        end
    end

    // in_a, in_b
    always @(posedge clk ) begin
        if (state == point_mul || state == crt) begin
            if (!part) begin
                in_b[0] <= rd_dout[0][13 : 0];
                in_b[1] <= rd_dout[0][27 : 14];
                in_b[2] <= rd_dout[0][41 : 28];
            end else begin
                in_b[0] <= rd_dout[1][13 : 0];
                in_b[1] <= rd_dout[1][27 : 14];
                in_b[2] <= rd_dout[1][41 : 28];
            end
        end else begin
            if (bank_index_rd_shift_2 == 0) begin
                in_b[0] <= rd_dout[1][13 : 0];
                in_b[1] <= rd_dout[1][27 : 14];
                in_b[2] <= rd_dout[1][41 : 28];
            end else begin
                in_b[0] <= rd_dout[0][13 : 0];
                in_b[1] <= rd_dout[0][27 : 14];
                in_b[2] <= rd_dout[0][41 : 28];
            end
        end

        if (state == point_mul) begin
            if (count_f_shift_2 == 0) begin
                in_a[0] <= 0;
                in_a[1] <= 0;
                in_a[2] <= 0;
            end else begin
                in_a[0] <= rd_dout[2][13 : 0];
                in_a[1] <= rd_dout[2][27 : 14];
                in_a[2] <= rd_dout[2][41 : 28];
            end
        end else if (state == crt) begin
            in_a[0] <= 0;
            in_a[1] <= 0;
            in_a[2] <= 0;
        end else begin
            if (bank_index_rd_shift_2 == 0) begin
                in_a[0] <= rd_dout[0][13 : 0];
                in_a[1] <= rd_dout[0][27 : 14];
                in_a[2] <= rd_dout[0][41 : 28];
            end else begin
                in_a[0] <= rd_dout[1][13 : 0];
                in_a[1] <= rd_dout[1][27 : 14];
                in_a[2] <= rd_dout[1][41 : 28];
            end
        end
    end

    // w_addr_in, w
    always @(posedge clk ) begin
        if (state == ntt) begin
            w_addr_in <= {1'b0, w_addr};
        end else begin
            w_addr_in <= 512 - w_addr;
        end

        if (state == point_mul) begin
            if (!part) begin
                w[0] <= {{ 5{wr_dout[0][13]} }, wr_dout[0][13 : 0]};
                w[1] <= {{ 5{wr_dout[0][27]} }, wr_dout[0][27 : 14]};
                w[2] <= {{ 5{wr_dout[0][41]} }, wr_dout[0][41 : 28]};
            end else begin
                w[0] <= {{ 5{wr_dout[1][13]} }, wr_dout[1][13 : 0]};
                w[1] <= {{ 5{wr_dout[1][27]} }, wr_dout[1][27 : 14]};
                w[2] <= {{ 5{wr_dout[1][41]} }, wr_dout[1][41 : 28]};
            end
        end else if (state == crt) begin
            if (count_f_shift_2 == 0) begin
                w[0] <= Q23inv;
                w[1] <= Q31inv;
                w[2] <= Q12inv;
            end else begin
                w[0] <= Q2Q3PREFIX;
                w[1] <= Q3Q1PREFIX;
                w[2] <= Q1Q2PREFIX;
            end
        end else begin
            w[0] <= w_dout[0];
            w[1] <= w_dout[1];
            w[2] <= w_dout[2];
        end
    end

    // ctr, ctr_shift_7
    always @(posedge clk ) begin
        if (state == ntt || state == intt || state == point_mul || state == crt) begin
            if (ntt_end || point_mul_end) begin
                ctr <= 0;
            end else begin
                ctr <= ctr + 1;
            end
        end else if (state == reload) begin
            if (reload_end) begin
                ctr <= 0;
            end else begin
                ctr <= ctr + 1;
            end
        end else begin
            ctr <= 0;
        end

        //change ctr_shift_7 <= ctr - 5;
        ctr_shift_7 <= ctr - 7;
        ctr_shift_8 <= ctr_shift_7;
        ctr_shift_1 <= ctr;
        ctr_shift_2 <= ctr_shift_1;
    end

    // red_ctr
    assign red2_necessary = (red_ctr_2 > 760);
    assign red5_necessary = (red_ctr_5 > 760);
    assign red6_necessary = (red_ctr_6 > 760);

    always @( posedge clk ) begin
        if (state == crt) begin
            red_ctr <= 0;
        end else begin
            red_ctr <= red_ctr + 1;
        end

        red_ctr_1 <= red_ctr;
        red_ctr_2 <= red_ctr_1;
        red_ctr_3 <= red_ctr_2;
        red_ctr_4 <= red_ctr_3;
        red_ctr_5 <= red_ctr_4;
        red_ctr_6 <= red_ctr_5;
        red_ctr_7 <= red_ctr_6;

        red_ctr_m3 <= red_ctr_2 - (red2_necessary ? 761 : 0);
        red_ctr_m7 <= red_ctr_6 - (red6_necessary ? 761 : 0);
    end

    // red_ld, red_value, red_sum, red_sum_mod
    always @( posedge clk ) begin
        red_ld <= red5_necessary ? rd_dout[2][13:0] : 0;

        if (bank_index_wr_0_shift_2) begin
            red_value <= wr_dout[1][13 : 0];
        end else begin
            red_value <= wr_dout[0][13 : 0];
        end

        red_value_1 <= red6_necessary ? red_value : 0;

        red_sum <= red_ld + red_value + red_value_1;

        if(red_sum > Q0_12)
          red_sum_mod <= red_sum - Q0;
        else if(red_sum < -Q0_12)
          red_sum_mod <= red_sum + Q0;
        else
          red_sum_mod <= red_sum;
    end

    // stage, stage_wr
    always @(posedge clk ) begin
        if (state == ntt || state == intt) begin
            if (ntt_end) begin
                stage <= 0;
            end else if (ctr_end) begin
                stage <= stage + 1;
            end else begin
                stage <= stage;
            end
        end else begin
            stage <= 0;
        end

        if (state == ntt || state == intt) begin
            if (ntt_end) begin
                stage_wr <= 0;
            end else if (ctr_shift_7[7 : 0] == 0 && stage != 0) begin
               stage_wr <= stage_wr + 1;
            end else begin
                stage_wr <= stage_wr;
            end
        end else begin
            stage_wr <= 0;
        end        
    end

    // stage_bit
    always @(posedge clk ) begin
        if (state == ntt || state == intt) begin
            if (ntt_end) begin
                stage_bit <= 0;
            end else if (ctr_end) begin
                stage_bit[0] <= 1'b1;
                stage_bit[7 : 1] <= stage_bit[6 : 0];
            end else begin
                stage_bit <= stage_bit;
            end
        end else begin
            stage_bit <= 8'b0;
        end
    end

    // valid
    always @(posedge clk) begin
        if (state == finish) begin
            valid = 1;
        end else begin
            valid = 0;
        end
    end

    // state
	always @(posedge clk ) begin
		if(rst) begin
            state <= 0;
        end else begin
            state <= next_state;
        end
	end
	always @(*) begin
		case(state)
		idle: begin
			if(start)
				next_state = ntt;
			else
				next_state = idle;
		end
		ntt: begin
			if(ntt_end && ctr_ntt == 5)
				next_state = point_mul;
			else
				next_state = ntt;
		end
    point_mul: begin
      if (point_mul_end)
        next_state = reload;
      else
        next_state = point_mul;
    end
    reload: begin
      if (reload_end) begin
        next_state = intt;
      end else begin
        next_state = reload;
      end
    end
    intt: begin
      if(ntt_end && ctr_ntt == 2)
				next_state = crt;
			else
				next_state = intt;
      end
    crt: begin
      if(count_f == 2 && ctr == 8)
				next_state = reduce;
			else
				next_state = crt;
    end
    reduce: begin
      if(reduce_end)
        next_state = finish;
      else
        next_state = reduce;
    end
		finish: begin
			if(!start)
				next_state = finish;
			else
				next_state = idle;
		end
		default: next_state = state;
		endcase
	end

endmodule

module mod_3 (clk, addr, fg, out);

    input               clk;
    input               fg;
    input      [10 : 0] addr;
    output reg [2  : 0] out;

    reg [2 : 0] even, odd;
    reg signed [2 : 0] even_minus_odd;
    reg fg_shift_1;
    reg [1 : 0] const;

    always @(posedge clk ) begin
        fg_shift_1 <= fg;

        if (fg_shift_1) begin
            const <= 3;
        end else begin
            const <= 0;
        end

        even <= addr[0] + addr[2] + addr[4] + addr[6] + addr[8] + addr[10];
        odd  <= addr[1] + addr[3] + addr[5] + addr[7] + addr[9];
        even_minus_odd <= even[2] - even[1] + even[0] - odd[2] + odd[1] - odd[0];

        if (even_minus_odd == 3) begin
            out <= 0 + const;
        end else begin
            out <= even_minus_odd[1 : 0] - even_minus_odd[2] + const;
        end
    end

endmodule

module w_addr_gen (clk, stage_bit, ctr, w_addr);

    input              clk;
    input      [7 : 0] stage_bit;  // 0 - 8
    input      [7 : 0] ctr;        // 0 - 255
    output reg [7 : 0] w_addr;

    wire [7 : 0] w;

    assign w[0] = (stage_bit[0]) ? ctr[0] : 0;
    assign w[1] = (stage_bit[1]) ? ctr[1] : 0;
    assign w[2] = (stage_bit[2]) ? ctr[2] : 0;
    assign w[3] = (stage_bit[3]) ? ctr[3] : 0;
    assign w[4] = (stage_bit[4]) ? ctr[4] : 0;
    assign w[5] = (stage_bit[5]) ? ctr[5] : 0;
    assign w[6] = (stage_bit[6]) ? ctr[6] : 0;
    assign w[7] = (stage_bit[7]) ? ctr[7] : 0;

    always @(posedge clk ) begin
        w_addr <= {w[0], w[1], w[2], w[3], w[4], w[5], w[6], w[7]};
    end
    
endmodule

module bfu_7681 (clk, state, in_a, in_b, w, bw, out_a, out_b);

    parameter P_WIDTH = 14;
    parameter PP_WIDTH = 25;
    parameter Q = 7681;

    input                      clk;
    input                      state;
    input      signed [13 : 0] in_a;
    input      signed [13 : 0] in_b;
    input      signed [18 : 0] w;
    output reg signed [32 : 0] bw;
    output reg signed [13 : 0] out_a;
    output reg signed [13 : 0] out_b;

    wire signed [12 : 0] mod_bw;
    reg signed [14 : 0] a, b;
    reg signed [13 : 0] in_a_s1, in_a_s2, in_a_s3, in_a_s4, in_a_s5;

    reg signed [28 : 0] bwQ_0, bwQ_1, bwQ_2;
    wire signed [14  : 0] a_add_q, a_sub_q, b_add_q, b_sub_q;

    //wire signed [12 : 0] mod_bw_test;

    modmul7681s mod7681 (clk, bw, mod_bw);

    //wire test;
    //assign test = (mod_bw == mod_bw_test) ? 0 : 1;

    //assign bwQ = bw % Q;
    assign a_add_q = a + Q;
    assign a_sub_q = a - Q;
    assign b_add_q = b + Q;
    assign b_sub_q = b - Q;
    
    
    // in_a shift
    always @(posedge clk ) begin
        in_a_s1 <= in_a;
        in_a_s2 <= in_a_s1;
        in_a_s3 <= in_a_s2;
        in_a_s4 <= in_a_s3;
        in_a_s5 <= in_a_s4;
    end

    // b * w
    always @(posedge clk ) begin
        bw <= in_b * w;
        
        /*
        bwQ_0 <= bw % Q;
        bwQ_1 <= bwQ_0;
        
        if (bwQ_1 > 3840) begin
            mod_bw <= bwQ_1 - Q;
        end else if (bwQ_1 < -3840) begin
            mod_bw <= bwQ_1 + Q;
        end else begin
            mod_bw <= bwQ_1;
        end    
        */
    end

    // out_a, out_b
    always @(posedge clk ) begin
        //a <= in_a_s2 + mod_bw;
        //b <= in_a_s2 - mod_bw;

        a <= in_a_s4 + mod_bw;
        b <= in_a_s4 - mod_bw;

        if (state == 0) begin
            if (a > 3840) begin
                out_a <= a_sub_q;
            end else if (a < -3840) begin
                out_a <= a_add_q;
            end else begin
                out_a <= a;
            end
        end else begin
            if (a[0] == 0) begin
                out_a <= a[P_WIDTH : 1];
            end else if (a[P_WIDTH] == 0) begin   // a > 0
                out_a <= a_sub_q[P_WIDTH : 1];
            end else begin                        // a < 0
                out_a <= a_add_q[P_WIDTH : 1];
            end
        end


        if (state == 0) begin
            if (b > 3840) begin
                out_b <= b_sub_q;
            end else if (b < -3840) begin
                out_b <= b_add_q;
            end else begin
                out_b <= b;
            end
        end else begin
            if (b[0] == 0) begin
                out_b <= b[P_WIDTH : 1];
            end else if (b[P_WIDTH] == 0) begin   // b > 0
                out_b <= b_sub_q[P_WIDTH : 1];
            end else begin                        // b < 0
                out_b <= b_add_q[P_WIDTH : 1];
            end
        end
    end

endmodule

module bfu_12289 (clk, state, in_a, in_b, w, bw, out_a, out_b);

    parameter P_WIDTH = 14;
    parameter PP_WIDTH = 26;
    parameter Q = 12289;

    localparam HALF_Q = (Q-1)/2;

    input                                clk;
    input                                state;
    input      signed [13 : 0] in_a;
    input      signed [13 : 0] in_b;
    input      signed [18 : 0] w;
    output reg signed [32 : 0] bw;
    output reg signed [13 : 0] out_a;
    output reg signed [13 : 0] out_b;

    wire signed [13 : 0] mod_bw;
    reg signed [14 : 0] a, b;
    reg signed [13 : 0] in_a_s1, in_a_s2, in_a_s3, in_a_s4, in_a_s5;

    reg signed [28 : 0] bwQ_0, bwQ_1, bwQ_2;
    wire signed [14  : 0] a_add_q, a_sub_q, b_add_q, b_sub_q;

    mod12289s mod12289_inst (clk, 1'b0, bw, mod_bw);

    //assign bwQ = bw % Q;
    assign a_add_q = a + Q;
    assign a_sub_q = a - Q;
    assign b_add_q = b + Q;
    assign b_sub_q = b - Q;
    
    
    // in_a shift
    always @(posedge clk ) begin
        in_a_s1 <= in_a;
        in_a_s2 <= in_a_s1;
        in_a_s3 <= in_a_s2;
        in_a_s4 <= in_a_s3;
        in_a_s5 <= in_a_s4;
    end

    // b * w
    always @(posedge clk ) begin
        bw <= in_b * w;
    end

    // out_a, out_b
    always @(posedge clk ) begin
        a <= in_a_s4 + mod_bw;
        b <= in_a_s4 - mod_bw;

        if (state == 0) begin
            if (a > HALF_Q) begin
                out_a <= a_sub_q;
            end else if (a < -HALF_Q) begin
                out_a <= a_add_q;
            end else begin
                out_a <= a;
            end
        end else begin
            if (a[0] == 0) begin
                out_a <= a[P_WIDTH : 1];
            end else if (a[P_WIDTH] == 0) begin   // a > 0
                out_a <= a_sub_q[P_WIDTH : 1];
            end else begin                        // a < 0
                out_a <= a_add_q[P_WIDTH : 1];
            end
        end


        if (state == 0) begin
            if (b > HALF_Q) begin
                out_b <= b_sub_q;
            end else if (b < -HALF_Q) begin
                out_b <= b_add_q;
            end else begin
                out_b <= b;
            end
        end else begin
            if (b[0] == 0) begin
                out_b <= b[P_WIDTH : 1];
            end else if (b[P_WIDTH] == 0) begin   // b > 0
                out_b <= b_sub_q[P_WIDTH : 1];
            end else begin                        // b < 0
                out_b <= b_add_q[P_WIDTH : 1];
            end
        end
    end

endmodule

module bfu_15361 (clk, state, in_a, in_b, w, bw, out_a, out_b);

    parameter P_WIDTH = 14;
    parameter PP_WIDTH = 26;
    parameter Q = 15361;

    localparam HALF_Q = (Q-1)/2;

    input                                clk;
    input                                state;
    input      signed [13 : 0] in_a;
    input      signed [13 : 0] in_b;
    input      signed [18 : 0] w;
    output reg signed [32 : 0] bw;
    output reg signed [13 : 0] out_a;
    output reg signed [13 : 0] out_b;

    wire signed [13 : 0] mod_bw;
    reg signed [14 : 0] a, b;
    reg signed [13 : 0] in_a_s1, in_a_s2, in_a_s3, in_a_s4, in_a_s5;

    reg signed [28 : 0] bwQ_0, bwQ_1, bwQ_2;
    wire signed [14  : 0] a_add_q, a_sub_q, b_add_q, b_sub_q;

    modmul15361s mod15361_inst (clk, 1'b0, bw, mod_bw);

    //assign bwQ = bw % Q;
    assign a_add_q = a + Q;
    assign a_sub_q = a - Q;
    assign b_add_q = b + Q;
    assign b_sub_q = b - Q;
    
    
    // in_a shift
    always @(posedge clk ) begin
        in_a_s1 <= in_a;
        in_a_s2 <= in_a_s1;
        in_a_s3 <= in_a_s2;
        in_a_s4 <= in_a_s3;
        in_a_s5 <= in_a_s4;
    end

    // b * w
    always @(posedge clk ) begin
        bw <= in_b * w;
    end

    // out_a, out_b
    always @(posedge clk ) begin
        a <= in_a_s4 + mod_bw;
        b <= in_a_s4 - mod_bw;

        if (state == 0) begin
            if (a > HALF_Q) begin
                out_a <= a_sub_q;
            end else if (a < -HALF_Q) begin
                out_a <= a_add_q;
            end else begin
                out_a <= a;
            end
        end else begin
            if (a[0] == 0) begin
                out_a <= a[P_WIDTH : 1];
            end else if (a[P_WIDTH] == 0) begin   // a > 0
                out_a <= a_sub_q[P_WIDTH : 1];
            end else begin                        // a < 0
                out_a <= a_add_q[P_WIDTH : 1];
            end
        end


        if (state == 0) begin
            if (b > HALF_Q) begin
                out_b <= b_sub_q;
            end else if (b < -HALF_Q) begin
                out_b <= b_add_q;
            end else begin
                out_b <= b;
            end
        end else begin
            if (b[0] == 0) begin
                out_b <= b[P_WIDTH : 1];
            end else if (b[P_WIDTH] == 0) begin   // b > 0
                out_b <= b_sub_q[P_WIDTH : 1];
            end else begin                        // b < 0
                out_b <= b_add_q[P_WIDTH : 1];
            end
        end
    end

endmodule

module addr_gen (clk, stage, ctr, bank_index, data_index);
    
    input              clk;
    input      [3 : 0] stage;  // 0 - 8
    input      [8 : 0] ctr;    // 0 - 511
    output reg         bank_index; // 0 - 1
    output reg [7 : 0] data_index; // 0 - 255

    wire [8 : 0] bs_out;

    barrel_shifter bs (clk, ctr, stage, bs_out);

    // bank_index
    always @(posedge clk ) begin
        bank_index <= ^bs_out;
    end

    // data_index
    always @(posedge clk ) begin
        data_index <= bs_out[8 : 1];
    end

endmodule

module barrel_shifter (clk, in, shift, out);
    
    input              clk;
    input      [8 : 0] in;
    input      [3 : 0] shift;
    output reg [8 : 0] out;

    reg [8 : 0] in_s0, in_s1, in_s2;

    // shift 4
    always @(* ) begin
        if (shift[2]) begin
            in_s2 = {in[3:0], in[8:4]};
        end else begin
            in_s2 = in;
        end
    end

    // shift 2
    always @(* ) begin
        if (shift[1]) begin
            in_s1 = {in_s2[1:0], in_s2[8:2]};
        end else begin
            in_s1 = in_s2;
        end
    end

    // shift 1
    always @(* ) begin
        if (shift[0]) begin
            in_s0 = {in_s1[0], in_s1[8:1]};
        end else begin
            in_s0 = in_s1;
        end
    end

    // out
    always @(posedge clk ) begin
        if (shift[3]) begin
            out <= {in[7:0], in[8]};
        end else begin
            out <= in_s0;
        end
    end
    
endmodule
/*
module w_7681 ( clk, addr, dout);
    
    input  clk;
    input  [8 : 0] addr;
    output [13 : 0] dout;

    reg [8 : 0] a;
    (* rom_style = "block" *) reg [13 : 0] data [0 : 511];

    assign dout = data[a];

    always @(posedge clk) begin
        a <= addr;
    end

    always @(posedge clk) begin
        data[0] <= 1;
        data[1] <= 62;
        data[2] <= -3837;
        data[3] <= 217;
        data[4] <= -1908;
        data[5] <= -3081;
        data[6] <= 1003;
        data[7] <= 738;
        data[8] <= -330;
        data[9] <= 2583;
        data[10] <= -1155;
        data[11] <= -2481;
        data[12] <= -202;
        data[13] <= 2838;
        data[14] <= -707;
        data[15] <= 2252;
        data[16] <= 1366;
        data[17] <= 201;
        data[18] <= -2900;
        data[19] <= -3137;
        data[20] <= -2469;
        data[21] <= 542;
        data[22] <= 2880;
        data[23] <= 1897;
        data[24] <= 2399;
        data[25] <= 2799;
        data[26] <= -3125;
        data[27] <= -1725;
        data[28] <= 584;
        data[29] <= -2197;
        data[30] <= 2044;
        data[31] <= 3832;
        data[32] <= -527;
        data[33] <= -1950;
        data[34] <= 1996;
        data[35] <= 856;
        data[36] <= -695;
        data[37] <= 2996;
        data[38] <= 1408;
        data[39] <= 2805;
        data[40] <= -2753;
        data[41] <= -1704;
        data[42] <= 1886;
        data[43] <= 1717;
        data[44] <= -1080;
        data[45] <= 2169;
        data[46] <= -3780;
        data[47] <= 3751;
        data[48] <= 2132;
        data[49] <= 1607;
        data[50] <= -219;
        data[51] <= 1784;
        data[52] <= 3074;
        data[53] <= -1437;
        data[54] <= 3078;
        data[55] <= -1189;
        data[56] <= 3092;
        data[57] <= -321;
        data[58] <= 3141;
        data[59] <= 2717;
        data[60] <= -528;
        data[61] <= -2012;
        data[62] <= -1848;
        data[63] <= 639;
        data[64] <= 1213;
        data[65] <= -1604;
        data[66] <= 405;
        data[67] <= 2067;
        data[68] <= -2423;
        data[69] <= 3394;
        data[70] <= 3041;
        data[71] <= -3483;
        data[72] <= -878;
        data[73] <= -669;
        data[74] <= -3073;
        data[75] <= 1499;
        data[76] <= 766;
        data[77] <= 1406;
        data[78] <= 2681;
        data[79] <= -2760;
        data[80] <= -2138;
        data[81] <= -1979;
        data[82] <= 198;
        data[83] <= -3086;
        data[84] <= 693;
        data[85] <= -3120;
        data[86] <= -1415;
        data[87] <= -3239;
        data[88] <= -1112;
        data[89] <= 185;
        data[90] <= 3789;
        data[91] <= -3193;
        data[92] <= 1740;
        data[93] <= 346;
        data[94] <= -1591;
        data[95] <= 1211;
        data[96] <= -1728;
        data[97] <= 398;
        data[98] <= 1633;
        data[99] <= 1393;
        data[100] <= 1875;
        data[101] <= 1035;
        data[102] <= 2722;
        data[103] <= -218;
        data[104] <= 1846;
        data[105] <= -763;
        data[106] <= -1220;
        data[107] <= 1170;
        data[108] <= 3411;
        data[109] <= -3586;
        data[110] <= 417;
        data[111] <= 2811;
        data[112] <= -2381;
        data[113] <= -1683;
        data[114] <= 3188;
        data[115] <= -2050;
        data[116] <= 3477;
        data[117] <= 506;
        data[118] <= 648;
        data[119] <= 1771;
        data[120] <= 2268;
        data[121] <= 2358;
        data[122] <= 257;
        data[123] <= 572;
        data[124] <= -2941;
        data[125] <= 2002;
        data[126] <= 1228;
        data[127] <= -674;
        data[128] <= -3383;
        data[129] <= -2359;
        data[130] <= -319;
        data[131] <= 3265;
        data[132] <= 2724;
        data[133] <= -94;
        data[134] <= 1853;
        data[135] <= -329;
        data[136] <= 2645;
        data[137] <= 2689;
        data[138] <= -2264;
        data[139] <= -2110;
        data[140] <= -243;
        data[141] <= 296;
        data[142] <= 2990;
        data[143] <= 1036;
        data[144] <= 2784;
        data[145] <= 3626;
        data[146] <= 2063;
        data[147] <= -2671;
        data[148] <= 3380;
        data[149] <= 2173;
        data[150] <= -3532;
        data[151] <= 3765;
        data[152] <= 3000;
        data[153] <= 1656;
        data[154] <= 2819;
        data[155] <= -1885;
        data[156] <= -1655;
        data[157] <= -2757;
        data[158] <= -1952;
        data[159] <= 1872;
        data[160] <= 849;
        data[161] <= -1129;
        data[162] <= -869;
        data[163] <= -111;
        data[164] <= 799;
        data[165] <= 3452;
        data[166] <= -1044;
        data[167] <= -3280;
        data[168] <= -3654;
        data[169] <= -3799;
        data[170] <= 2573;
        data[171] <= -1775;
        data[172] <= -2516;
        data[173] <= -2372;
        data[174] <= -1125;
        data[175] <= -621;
        data[176] <= -97;
        data[177] <= 1667;
        data[178] <= 3501;
        data[179] <= 1994;
        data[180] <= 732;
        data[181] <= -702;
        data[182] <= 2562;
        data[183] <= -2457;
        data[184] <= 1286;
        data[185] <= 2922;
        data[186] <= -3180;
        data[187] <= 2546;
        data[188] <= -3449;
        data[189] <= 1230;
        data[190] <= -550;
        data[191] <= -3376;
        data[192] <= -1925;
        data[193] <= 3546;
        data[194] <= -2897;
        data[195] <= -2951;
        data[196] <= 1382;
        data[197] <= 1193;
        data[198] <= -2844;
        data[199] <= 335;
        data[200] <= -2273;
        data[201] <= -2668;
        data[202] <= 3566;
        data[203] <= -1657;
        data[204] <= -2881;
        data[205] <= -1959;
        data[206] <= 1438;
        data[207] <= -3016;
        data[208] <= -2648;
        data[209] <= -2875;
        data[210] <= -1587;
        data[211] <= 1459;
        data[212] <= -1714;
        data[213] <= 1266;
        data[214] <= 1682;
        data[215] <= -3250;
        data[216] <= -1794;
        data[217] <= -3694;
        data[218] <= 1402;
        data[219] <= 2433;
        data[220] <= -2774;
        data[221] <= -3006;
        data[222] <= -2028;
        data[223] <= -2840;
        data[224] <= 583;
        data[225] <= -2259;
        data[226] <= -1800;
        data[227] <= 3615;
        data[228] <= 1381;
        data[229] <= 1131;
        data[230] <= 993;
        data[231] <= 118;
        data[232] <= -365;
        data[233] <= 413;
        data[234] <= 2563;
        data[235] <= -2395;
        data[236] <= -2551;
        data[237] <= 3139;
        data[238] <= 2593;
        data[239] <= -535;
        data[240] <= -2446;
        data[241] <= 1968;
        data[242] <= -880;
        data[243] <= -793;
        data[244] <= -3080;
        data[245] <= 1065;
        data[246] <= -3099;
        data[247] <= -113;
        data[248] <= 675;
        data[249] <= 3445;
        data[250] <= -1478;
        data[251] <= 536;
        data[252] <= 2508;
        data[253] <= 1876;
        data[254] <= 1097;
        data[255] <= -1115;
        data[256] <= -1;
        data[257] <= -62;
        data[258] <= 3837;
        data[259] <= -217;
        data[260] <= 1908;
        data[261] <= 3081;
        data[262] <= -1003;
        data[263] <= -738;
        data[264] <= 330;
        data[265] <= -2583;
        data[266] <= 1155;
        data[267] <= 2481;
        data[268] <= 202;
        data[269] <= -2838;
        data[270] <= 707;
        data[271] <= -2252;
        data[272] <= -1366;
        data[273] <= -201;
        data[274] <= 2900;
        data[275] <= 3137;
        data[276] <= 2469;
        data[277] <= -542;
        data[278] <= -2880;
        data[279] <= -1897;
        data[280] <= -2399;
        data[281] <= -2799;
        data[282] <= 3125;
        data[283] <= 1725;
        data[284] <= -584;
        data[285] <= 2197;
        data[286] <= -2044;
        data[287] <= -3832;
        data[288] <= 527;
        data[289] <= 1950;
        data[290] <= -1996;
        data[291] <= -856;
        data[292] <= 695;
        data[293] <= -2996;
        data[294] <= -1408;
        data[295] <= -2805;
        data[296] <= 2753;
        data[297] <= 1704;
        data[298] <= -1886;
        data[299] <= -1717;
        data[300] <= 1080;
        data[301] <= -2169;
        data[302] <= 3780;
        data[303] <= -3751;
        data[304] <= -2132;
        data[305] <= -1607;
        data[306] <= 219;
        data[307] <= -1784;
        data[308] <= -3074;
        data[309] <= 1437;
        data[310] <= -3078;
        data[311] <= 1189;
        data[312] <= -3092;
        data[313] <= 321;
        data[314] <= -3141;
        data[315] <= -2717;
        data[316] <= 528;
        data[317] <= 2012;
        data[318] <= 1848;
        data[319] <= -639;
        data[320] <= -1213;
        data[321] <= 1604;
        data[322] <= -405;
        data[323] <= -2067;
        data[324] <= 2423;
        data[325] <= -3394;
        data[326] <= -3041;
        data[327] <= 3483;
        data[328] <= 878;
        data[329] <= 669;
        data[330] <= 3073;
        data[331] <= -1499;
        data[332] <= -766;
        data[333] <= -1406;
        data[334] <= -2681;
        data[335] <= 2760;
        data[336] <= 2138;
        data[337] <= 1979;
        data[338] <= -198;
        data[339] <= 3086;
        data[340] <= -693;
        data[341] <= 3120;
        data[342] <= 1415;
        data[343] <= 3239;
        data[344] <= 1112;
        data[345] <= -185;
        data[346] <= -3789;
        data[347] <= 3193;
        data[348] <= -1740;
        data[349] <= -346;
        data[350] <= 1591;
        data[351] <= -1211;
        data[352] <= 1728;
        data[353] <= -398;
        data[354] <= -1633;
        data[355] <= -1393;
        data[356] <= -1875;
        data[357] <= -1035;
        data[358] <= -2722;
        data[359] <= 218;
        data[360] <= -1846;
        data[361] <= 763;
        data[362] <= 1220;
        data[363] <= -1170;
        data[364] <= -3411;
        data[365] <= 3586;
        data[366] <= -417;
        data[367] <= -2811;
        data[368] <= 2381;
        data[369] <= 1683;
        data[370] <= -3188;
        data[371] <= 2050;
        data[372] <= -3477;
        data[373] <= -506;
        data[374] <= -648;
        data[375] <= -1771;
        data[376] <= -2268;
        data[377] <= -2358;
        data[378] <= -257;
        data[379] <= -572;
        data[380] <= 2941;
        data[381] <= -2002;
        data[382] <= -1228;
        data[383] <= 674;
        data[384] <= 3383;
        data[385] <= 2359;
        data[386] <= 319;
        data[387] <= -3265;
        data[388] <= -2724;
        data[389] <= 94;
        data[390] <= -1853;
        data[391] <= 329;
        data[392] <= -2645;
        data[393] <= -2689;
        data[394] <= 2264;
        data[395] <= 2110;
        data[396] <= 243;
        data[397] <= -296;
        data[398] <= -2990;
        data[399] <= -1036;
        data[400] <= -2784;
        data[401] <= -3626;
        data[402] <= -2063;
        data[403] <= 2671;
        data[404] <= -3380;
        data[405] <= -2173;
        data[406] <= 3532;
        data[407] <= -3765;
        data[408] <= -3000;
        data[409] <= -1656;
        data[410] <= -2819;
        data[411] <= 1885;
        data[412] <= 1655;
        data[413] <= 2757;
        data[414] <= 1952;
        data[415] <= -1872;
        data[416] <= -849;
        data[417] <= 1129;
        data[418] <= 869;
        data[419] <= 111;
        data[420] <= -799;
        data[421] <= -3452;
        data[422] <= 1044;
        data[423] <= 3280;
        data[424] <= 3654;
        data[425] <= 3799;
        data[426] <= -2573;
        data[427] <= 1775;
        data[428] <= 2516;
        data[429] <= 2372;
        data[430] <= 1125;
        data[431] <= 621;
        data[432] <= 97;
        data[433] <= -1667;
        data[434] <= -3501;
        data[435] <= -1994;
        data[436] <= -732;
        data[437] <= 702;
        data[438] <= -2562;
        data[439] <= 2457;
        data[440] <= -1286;
        data[441] <= -2922;
        data[442] <= 3180;
        data[443] <= -2546;
        data[444] <= 3449;
        data[445] <= -1230;
        data[446] <= 550;
        data[447] <= 3376;
        data[448] <= 1925;
        data[449] <= -3546;
        data[450] <= 2897;
        data[451] <= 2951;
        data[452] <= -1382;
        data[453] <= -1193;
        data[454] <= 2844;
        data[455] <= -335;
        data[456] <= 2273;
        data[457] <= 2668;
        data[458] <= -3566;
        data[459] <= 1657;
        data[460] <= 2881;
        data[461] <= 1959;
        data[462] <= -1438;
        data[463] <= 3016;
        data[464] <= 2648;
        data[465] <= 2875;
        data[466] <= 1587;
        data[467] <= -1459;
        data[468] <= 1714;
        data[469] <= -1266;
        data[470] <= -1682;
        data[471] <= 3250;
        data[472] <= 1794;
        data[473] <= 3694;
        data[474] <= -1402;
        data[475] <= -2433;
        data[476] <= 2774;
        data[477] <= 3006;
        data[478] <= 2028;
        data[479] <= 2840;
        data[480] <= -583;
        data[481] <= 2259;
        data[482] <= 1800;
        data[483] <= -3615;
        data[484] <= -1381;
        data[485] <= -1131;
        data[486] <= -993;
        data[487] <= -118;
        data[488] <= 365;
        data[489] <= -413;
        data[490] <= -2563;
        data[491] <= 2395;
        data[492] <= 2551;
        data[493] <= -3139;
        data[494] <= -2593;
        data[495] <= 535;
        data[496] <= 2446;
        data[497] <= -1968;
        data[498] <= 880;
        data[499] <= 793;
        data[500] <= 3080;
        data[501] <= -1065;
        data[502] <= 3099;
        data[503] <= 113;
        data[504] <= -675;
        data[505] <= -3445;
        data[506] <= 1478;
        data[507] <= -536;
        data[508] <= -2508;
        data[509] <= -1876;
        data[510] <= -1097;
        data[511] <= 1115;
    end

endmodule

module w_12289 ( clk, addr, dout);
    
    input  clk;
    input  [8 : 0] addr;
    output [13 : 0] dout;

    reg [8 : 0] a;
    (* rom_style = "block" *) reg [13 : 0] data [0 : 511];

    assign dout = data[a];

    always @(posedge clk) begin
        a <= addr;
    end

    always @(posedge clk) begin
        data[0] <= 1;
        data[1] <= 3;
        data[2] <= 9;
        data[3] <= 27;
        data[4] <= 81;
        data[5] <= 243;
        data[6] <= 729;
        data[7] <= 2187;
        data[8] <= -5728;
        data[9] <= -4895;
        data[10] <= -2396;
        data[11] <= 5101;
        data[12] <= 3014;
        data[13] <= -3247;
        data[14] <= 2548;
        data[15] <= -4645;
        data[16] <= -1646;
        data[17] <= -4938;
        data[18] <= -2525;
        data[19] <= 4714;
        data[20] <= 1853;
        data[21] <= 5559;
        data[22] <= 4388;
        data[23] <= 875;
        data[24] <= 2625;
        data[25] <= -4414;
        data[26] <= -953;
        data[27] <= -2859;
        data[28] <= 3712;
        data[29] <= -1153;
        data[30] <= -3459;
        data[31] <= 1912;
        data[32] <= 5736;
        data[33] <= 4919;
        data[34] <= 2468;
        data[35] <= -4885;
        data[36] <= -2366;
        data[37] <= 5191;
        data[38] <= 3284;
        data[39] <= -2437;
        data[40] <= 4978;
        data[41] <= 2645;
        data[42] <= -4354;
        data[43] <= -773;
        data[44] <= -2319;
        data[45] <= 5332;
        data[46] <= 3707;
        data[47] <= -1168;
        data[48] <= -3504;
        data[49] <= 1777;
        data[50] <= 5331;
        data[51] <= 3704;
        data[52] <= -1177;
        data[53] <= -3531;
        data[54] <= 1696;
        data[55] <= 5088;
        data[56] <= 2975;
        data[57] <= -3364;
        data[58] <= 2197;
        data[59] <= -5698;
        data[60] <= -4805;
        data[61] <= -2126;
        data[62] <= 5911;
        data[63] <= 5444;
        data[64] <= 4043;
        data[65] <= -160;
        data[66] <= -480;
        data[67] <= -1440;
        data[68] <= -4320;
        data[69] <= -671;
        data[70] <= -2013;
        data[71] <= -6039;
        data[72] <= -5828;
        data[73] <= -5195;
        data[74] <= -3296;
        data[75] <= 2401;
        data[76] <= -5086;
        data[77] <= -2969;
        data[78] <= 3382;
        data[79] <= -2143;
        data[80] <= 5860;
        data[81] <= 5291;
        data[82] <= 3584;
        data[83] <= -1537;
        data[84] <= -4611;
        data[85] <= -1544;
        data[86] <= -4632;
        data[87] <= -1607;
        data[88] <= -4821;
        data[89] <= -2174;
        data[90] <= 5767;
        data[91] <= 5012;
        data[92] <= 2747;
        data[93] <= -4048;
        data[94] <= 145;
        data[95] <= 435;
        data[96] <= 1305;
        data[97] <= 3915;
        data[98] <= -544;
        data[99] <= -1632;
        data[100] <= -4896;
        data[101] <= -2399;
        data[102] <= 5092;
        data[103] <= 2987;
        data[104] <= -3328;
        data[105] <= 2305;
        data[106] <= -5374;
        data[107] <= -3833;
        data[108] <= 790;
        data[109] <= 2370;
        data[110] <= -5179;
        data[111] <= -3248;
        data[112] <= 2545;
        data[113] <= -4654;
        data[114] <= -1673;
        data[115] <= -5019;
        data[116] <= -2768;
        data[117] <= 3985;
        data[118] <= -334;
        data[119] <= -1002;
        data[120] <= -3006;
        data[121] <= 3271;
        data[122] <= -2476;
        data[123] <= 4861;
        data[124] <= 2294;
        data[125] <= -5407;
        data[126] <= -3932;
        data[127] <= 493;
        data[128] <= 1479;
        data[129] <= 4437;
        data[130] <= 1022;
        data[131] <= 3066;
        data[132] <= -3091;
        data[133] <= 3016;
        data[134] <= -3241;
        data[135] <= 2566;
        data[136] <= -4591;
        data[137] <= -1484;
        data[138] <= -4452;
        data[139] <= -1067;
        data[140] <= -3201;
        data[141] <= 2686;
        data[142] <= -4231;
        data[143] <= -404;
        data[144] <= -1212;
        data[145] <= -3636;
        data[146] <= 1381;
        data[147] <= 4143;
        data[148] <= 140;
        data[149] <= 420;
        data[150] <= 1260;
        data[151] <= 3780;
        data[152] <= -949;
        data[153] <= -2847;
        data[154] <= 3748;
        data[155] <= -1045;
        data[156] <= -3135;
        data[157] <= 2884;
        data[158] <= -3637;
        data[159] <= 1378;
        data[160] <= 4134;
        data[161] <= 113;
        data[162] <= 339;
        data[163] <= 1017;
        data[164] <= 3051;
        data[165] <= -3136;
        data[166] <= 2881;
        data[167] <= -3646;
        data[168] <= 1351;
        data[169] <= 4053;
        data[170] <= -130;
        data[171] <= -390;
        data[172] <= -1170;
        data[173] <= -3510;
        data[174] <= 1759;
        data[175] <= 5277;
        data[176] <= 3542;
        data[177] <= -1663;
        data[178] <= -4989;
        data[179] <= -2678;
        data[180] <= 4255;
        data[181] <= 476;
        data[182] <= 1428;
        data[183] <= 4284;
        data[184] <= 563;
        data[185] <= 1689;
        data[186] <= 5067;
        data[187] <= 2912;
        data[188] <= -3553;
        data[189] <= 1630;
        data[190] <= 4890;
        data[191] <= 2381;
        data[192] <= -5146;
        data[193] <= -3149;
        data[194] <= 2842;
        data[195] <= -3763;
        data[196] <= 1000;
        data[197] <= 3000;
        data[198] <= -3289;
        data[199] <= 2422;
        data[200] <= -5023;
        data[201] <= -2780;
        data[202] <= 3949;
        data[203] <= -442;
        data[204] <= -1326;
        data[205] <= -3978;
        data[206] <= 355;
        data[207] <= 1065;
        data[208] <= 3195;
        data[209] <= -2704;
        data[210] <= 4177;
        data[211] <= 242;
        data[212] <= 726;
        data[213] <= 2178;
        data[214] <= -5755;
        data[215] <= -4976;
        data[216] <= -2639;
        data[217] <= 4372;
        data[218] <= 827;
        data[219] <= 2481;
        data[220] <= -4846;
        data[221] <= -2249;
        data[222] <= 5542;
        data[223] <= 4337;
        data[224] <= 722;
        data[225] <= 2166;
        data[226] <= -5791;
        data[227] <= -5084;
        data[228] <= -2963;
        data[229] <= 3400;
        data[230] <= -2089;
        data[231] <= 6022;
        data[232] <= 5777;
        data[233] <= 5042;
        data[234] <= 2837;
        data[235] <= -3778;
        data[236] <= 955;
        data[237] <= 2865;
        data[238] <= -3694;
        data[239] <= 1207;
        data[240] <= 3621;
        data[241] <= -1426;
        data[242] <= -4278;
        data[243] <= -545;
        data[244] <= -1635;
        data[245] <= -4905;
        data[246] <= -2426;
        data[247] <= 5011;
        data[248] <= 2744;
        data[249] <= -4057;
        data[250] <= 118;
        data[251] <= 354;
        data[252] <= 1062;
        data[253] <= 3186;
        data[254] <= -2731;
        data[255] <= 4096;
        data[256] <= -1;
        data[257] <= -3;
        data[258] <= -9;
        data[259] <= -27;
        data[260] <= -81;
        data[261] <= -243;
        data[262] <= -729;
        data[263] <= -2187;
        data[264] <= 5728;
        data[265] <= 4895;
        data[266] <= 2396;
        data[267] <= -5101;
        data[268] <= -3014;
        data[269] <= 3247;
        data[270] <= -2548;
        data[271] <= 4645;
        data[272] <= 1646;
        data[273] <= 4938;
        data[274] <= 2525;
        data[275] <= -4714;
        data[276] <= -1853;
        data[277] <= -5559;
        data[278] <= -4388;
        data[279] <= -875;
        data[280] <= -2625;
        data[281] <= 4414;
        data[282] <= 953;
        data[283] <= 2859;
        data[284] <= -3712;
        data[285] <= 1153;
        data[286] <= 3459;
        data[287] <= -1912;
        data[288] <= -5736;
        data[289] <= -4919;
        data[290] <= -2468;
        data[291] <= 4885;
        data[292] <= 2366;
        data[293] <= -5191;
        data[294] <= -3284;
        data[295] <= 2437;
        data[296] <= -4978;
        data[297] <= -2645;
        data[298] <= 4354;
        data[299] <= 773;
        data[300] <= 2319;
        data[301] <= -5332;
        data[302] <= -3707;
        data[303] <= 1168;
        data[304] <= 3504;
        data[305] <= -1777;
        data[306] <= -5331;
        data[307] <= -3704;
        data[308] <= 1177;
        data[309] <= 3531;
        data[310] <= -1696;
        data[311] <= -5088;
        data[312] <= -2975;
        data[313] <= 3364;
        data[314] <= -2197;
        data[315] <= 5698;
        data[316] <= 4805;
        data[317] <= 2126;
        data[318] <= -5911;
        data[319] <= -5444;
        data[320] <= -4043;
        data[321] <= 160;
        data[322] <= 480;
        data[323] <= 1440;
        data[324] <= 4320;
        data[325] <= 671;
        data[326] <= 2013;
        data[327] <= 6039;
        data[328] <= 5828;
        data[329] <= 5195;
        data[330] <= 3296;
        data[331] <= -2401;
        data[332] <= 5086;
        data[333] <= 2969;
        data[334] <= -3382;
        data[335] <= 2143;
        data[336] <= -5860;
        data[337] <= -5291;
        data[338] <= -3584;
        data[339] <= 1537;
        data[340] <= 4611;
        data[341] <= 1544;
        data[342] <= 4632;
        data[343] <= 1607;
        data[344] <= 4821;
        data[345] <= 2174;
        data[346] <= -5767;
        data[347] <= -5012;
        data[348] <= -2747;
        data[349] <= 4048;
        data[350] <= -145;
        data[351] <= -435;
        data[352] <= -1305;
        data[353] <= -3915;
        data[354] <= 544;
        data[355] <= 1632;
        data[356] <= 4896;
        data[357] <= 2399;
        data[358] <= -5092;
        data[359] <= -2987;
        data[360] <= 3328;
        data[361] <= -2305;
        data[362] <= 5374;
        data[363] <= 3833;
        data[364] <= -790;
        data[365] <= -2370;
        data[366] <= 5179;
        data[367] <= 3248;
        data[368] <= -2545;
        data[369] <= 4654;
        data[370] <= 1673;
        data[371] <= 5019;
        data[372] <= 2768;
        data[373] <= -3985;
        data[374] <= 334;
        data[375] <= 1002;
        data[376] <= 3006;
        data[377] <= -3271;
        data[378] <= 2476;
        data[379] <= -4861;
        data[380] <= -2294;
        data[381] <= 5407;
        data[382] <= 3932;
        data[383] <= -493;
        data[384] <= -1479;
        data[385] <= -4437;
        data[386] <= -1022;
        data[387] <= -3066;
        data[388] <= 3091;
        data[389] <= -3016;
        data[390] <= 3241;
        data[391] <= -2566;
        data[392] <= 4591;
        data[393] <= 1484;
        data[394] <= 4452;
        data[395] <= 1067;
        data[396] <= 3201;
        data[397] <= -2686;
        data[398] <= 4231;
        data[399] <= 404;
        data[400] <= 1212;
        data[401] <= 3636;
        data[402] <= -1381;
        data[403] <= -4143;
        data[404] <= -140;
        data[405] <= -420;
        data[406] <= -1260;
        data[407] <= -3780;
        data[408] <= 949;
        data[409] <= 2847;
        data[410] <= -3748;
        data[411] <= 1045;
        data[412] <= 3135;
        data[413] <= -2884;
        data[414] <= 3637;
        data[415] <= -1378;
        data[416] <= -4134;
        data[417] <= -113;
        data[418] <= -339;
        data[419] <= -1017;
        data[420] <= -3051;
        data[421] <= 3136;
        data[422] <= -2881;
        data[423] <= 3646;
        data[424] <= -1351;
        data[425] <= -4053;
        data[426] <= 130;
        data[427] <= 390;
        data[428] <= 1170;
        data[429] <= 3510;
        data[430] <= -1759;
        data[431] <= -5277;
        data[432] <= -3542;
        data[433] <= 1663;
        data[434] <= 4989;
        data[435] <= 2678;
        data[436] <= -4255;
        data[437] <= -476;
        data[438] <= -1428;
        data[439] <= -4284;
        data[440] <= -563;
        data[441] <= -1689;
        data[442] <= -5067;
        data[443] <= -2912;
        data[444] <= 3553;
        data[445] <= -1630;
        data[446] <= -4890;
        data[447] <= -2381;
        data[448] <= 5146;
        data[449] <= 3149;
        data[450] <= -2842;
        data[451] <= 3763;
        data[452] <= -1000;
        data[453] <= -3000;
        data[454] <= 3289;
        data[455] <= -2422;
        data[456] <= 5023;
        data[457] <= 2780;
        data[458] <= -3949;
        data[459] <= 442;
        data[460] <= 1326;
        data[461] <= 3978;
        data[462] <= -355;
        data[463] <= -1065;
        data[464] <= -3195;
        data[465] <= 2704;
        data[466] <= -4177;
        data[467] <= -242;
        data[468] <= -726;
        data[469] <= -2178;
        data[470] <= 5755;
        data[471] <= 4976;
        data[472] <= 2639;
        data[473] <= -4372;
        data[474] <= -827;
        data[475] <= -2481;
        data[476] <= 4846;
        data[477] <= 2249;
        data[478] <= -5542;
        data[479] <= -4337;
        data[480] <= -722;
        data[481] <= -2166;
        data[482] <= 5791;
        data[483] <= 5084;
        data[484] <= 2963;
        data[485] <= -3400;
        data[486] <= 2089;
        data[487] <= -6022;
        data[488] <= -5777;
        data[489] <= -5042;
        data[490] <= -2837;
        data[491] <= 3778;
        data[492] <= -955;
        data[493] <= -2865;
        data[494] <= 3694;
        data[495] <= -1207;
        data[496] <= -3621;
        data[497] <= 1426;
        data[498] <= 4278;
        data[499] <= 545;
        data[500] <= 1635;
        data[501] <= 4905;
        data[502] <= 2426;
        data[503] <= -5011;
        data[504] <= -2744;
        data[505] <= 4057;
        data[506] <= -118;
        data[507] <= -354;
        data[508] <= -1062;
        data[509] <= -3186;
        data[510] <= 2731;
        data[511] <= -4096;
    end

endmodule

module w_15361 ( clk, addr, dout);
    
    input  clk;
    input  [8 : 0] addr;
    output [13 : 0] dout;

    reg [8 : 0] a;
    (* rom_style = "block" *) reg [13 : 0] data [0 : 511];

    assign dout = data[a];

    always @(posedge clk) begin
        a <= addr;
    end

    always @(posedge clk) begin
        data[0] <= 1;
        data[1] <= 98;
        data[2] <= -5757;
        data[3] <= 4171;
        data[4] <= -5989;
        data[5] <= -3204;
        data[6] <= -6772;
        data[7] <= -3133;
        data[8] <= 186;
        data[9] <= 2867;
        data[10] <= 4468;
        data[11] <= -7605;
        data[12] <= 7399;
        data[13] <= 3135;
        data[14] <= 10;
        data[15] <= 980;
        data[16] <= 3874;
        data[17] <= -4373;
        data[18] <= 1554;
        data[19] <= -1318;
        data[20] <= -6276;
        data[21] <= -608;
        data[22] <= 1860;
        data[23] <= -2052;
        data[24] <= -1403;
        data[25] <= 755;
        data[26] <= -2815;
        data[27] <= 628;
        data[28] <= 100;
        data[29] <= -5561;
        data[30] <= -7343;
        data[31] <= 2353;
        data[32] <= 179;
        data[33] <= 2181;
        data[34] <= -1316;
        data[35] <= -6080;
        data[36] <= 3239;
        data[37] <= -5159;
        data[38] <= 1331;
        data[39] <= 7550;
        data[40] <= 2572;
        data[41] <= 6280;
        data[42] <= 1000;
        data[43] <= 5834;
        data[44] <= 3375;
        data[45] <= -7192;
        data[46] <= 1790;
        data[47] <= 6449;
        data[48] <= 2201;
        data[49] <= 644;
        data[50] <= 1668;
        data[51] <= -5507;
        data[52] <= -2051;
        data[53] <= -1305;
        data[54] <= -5002;
        data[55] <= 1356;
        data[56] <= -5361;
        data[57] <= -3104;
        data[58] <= 3028;
        data[59] <= 4885;
        data[60] <= 2539;
        data[61] <= 3046;
        data[62] <= 6649;
        data[63] <= 6440;
        data[64] <= 1319;
        data[65] <= 6374;
        data[66] <= -5149;
        data[67] <= 2311;
        data[68] <= -3937;
        data[69] <= -1801;
        data[70] <= -7527;
        data[71] <= -318;
        data[72] <= -442;
        data[73] <= 2767;
        data[74] <= -5332;
        data[75] <= -262;
        data[76] <= 5046;
        data[77] <= 2956;
        data[78] <= -2171;
        data[79] <= 2296;
        data[80] <= -5407;
        data[81] <= -7612;
        data[82] <= 6713;
        data[83] <= -2649;
        data[84] <= 1535;
        data[85] <= -3180;
        data[86] <= -4420;
        data[87] <= -3052;
        data[88] <= -7237;
        data[89] <= -2620;
        data[90] <= 4377;
        data[91] <= -1162;
        data[92] <= -6349;
        data[93] <= 7599;
        data[94] <= 7374;
        data[95] <= 685;
        data[96] <= 5686;
        data[97] <= 4232;
        data[98] <= -11;
        data[99] <= -1078;
        data[100] <= 1883;
        data[101] <= 202;
        data[102] <= 4435;
        data[103] <= 4522;
        data[104] <= -2313;
        data[105] <= 3741;
        data[106] <= -2046;
        data[107] <= -815;
        data[108] <= -3065;
        data[109] <= 6850;
        data[110] <= -4584;
        data[111] <= -3763;
        data[112] <= -110;
        data[113] <= 4581;
        data[114] <= 3469;
        data[115] <= 2020;
        data[116] <= -1733;
        data[117] <= -863;
        data[118] <= 7592;
        data[119] <= 6688;
        data[120] <= -5099;
        data[121] <= 7211;
        data[122] <= 72;
        data[123] <= 7056;
        data[124] <= 243;
        data[125] <= -6908;
        data[126] <= -1100;
        data[127] <= -273;
        data[128] <= 3968;
        data[129] <= 4839;
        data[130] <= -1969;
        data[131] <= 6731;
        data[132] <= -885;
        data[133] <= 5436;
        data[134] <= -4907;
        data[135] <= -4695;
        data[136] <= 720;
        data[137] <= -6245;
        data[138] <= 2430;
        data[139] <= -7636;
        data[140] <= 4361;
        data[141] <= -2730;
        data[142] <= -6403;
        data[143] <= 2307;
        data[144] <= -4329;
        data[145] <= 5866;
        data[146] <= 6511;
        data[147] <= -7084;
        data[148] <= -2987;
        data[149] <= -867;
        data[150] <= 7200;
        data[151] <= -1006;
        data[152] <= -6422;
        data[153] <= 445;
        data[154] <= -2473;
        data[155] <= 3422;
        data[156] <= -2586;
        data[157] <= -7652;
        data[158] <= 2793;
        data[159] <= -2784;
        data[160] <= 3666;
        data[161] <= 5965;
        data[162] <= 852;
        data[163] <= 6691;
        data[164] <= -4805;
        data[165] <= 5301;
        data[166] <= -2776;
        data[167] <= 4450;
        data[168] <= 5992;
        data[169] <= 3498;
        data[170] <= 4862;
        data[171] <= 285;
        data[172] <= -2792;
        data[173] <= 2882;
        data[174] <= 5938;
        data[175] <= -1794;
        data[176] <= -6841;
        data[177] <= 5466;
        data[178] <= -1967;
        data[179] <= 6927;
        data[180] <= 2962;
        data[181] <= -1583;
        data[182] <= -1524;
        data[183] <= 4258;
        data[184] <= 2537;
        data[185] <= 2850;
        data[186] <= 2802;
        data[187] <= -1902;
        data[188] <= -2064;
        data[189] <= -2579;
        data[190] <= -6966;
        data[191] <= -6784;
        data[192] <= -4309;
        data[193] <= -7535;
        data[194] <= -1102;
        data[195] <= -469;
        data[196] <= 121;
        data[197] <= -3503;
        data[198] <= -5352;
        data[199] <= -2222;
        data[200] <= -2702;
        data[201] <= -3659;
        data[202] <= -5279;
        data[203] <= 4932;
        data[204] <= 7145;
        data[205] <= -6396;
        data[206] <= 2993;
        data[207] <= 1455;
        data[208] <= 4341;
        data[209] <= -4690;
        data[210] <= 1210;
        data[211] <= -4308;
        data[212] <= -7437;
        data[213] <= -6859;
        data[214] <= 3702;
        data[215] <= -5868;
        data[216] <= -6707;
        data[217] <= 3237;
        data[218] <= -5355;
        data[219] <= -2516;
        data[220] <= -792;
        data[221] <= -811;
        data[222] <= -2673;
        data[223] <= -817;
        data[224] <= -3261;
        data[225] <= 3003;
        data[226] <= 2435;
        data[227] <= -7146;
        data[228] <= 6298;
        data[229] <= 2764;
        data[230] <= -5626;
        data[231] <= 1648;
        data[232] <= -7467;
        data[233] <= 5562;
        data[234] <= 7441;
        data[235] <= 7251;
        data[236] <= 3992;
        data[237] <= 7191;
        data[238] <= -1888;
        data[239] <= -692;
        data[240] <= -6372;
        data[241] <= 5345;
        data[242] <= 1536;
        data[243] <= -3082;
        data[244] <= 5184;
        data[245] <= 1119;
        data[246] <= 2135;
        data[247] <= -5824;
        data[248] <= -2395;
        data[249] <= -4295;
        data[250] <= -6163;
        data[251] <= -4895;
        data[252] <= -3519;
        data[253] <= -6920;
        data[254] <= -2276;
        data[255] <= 7367;
        data[256] <= -1;
        data[257] <= -98;
        data[258] <= 5757;
        data[259] <= -4171;
        data[260] <= 5989;
        data[261] <= 3204;
        data[262] <= 6772;
        data[263] <= 3133;
        data[264] <= -186;
        data[265] <= -2867;
        data[266] <= -4468;
        data[267] <= 7605;
        data[268] <= -7399;
        data[269] <= -3135;
        data[270] <= -10;
        data[271] <= -980;
        data[272] <= -3874;
        data[273] <= 4373;
        data[274] <= -1554;
        data[275] <= 1318;
        data[276] <= 6276;
        data[277] <= 608;
        data[278] <= -1860;
        data[279] <= 2052;
        data[280] <= 1403;
        data[281] <= -755;
        data[282] <= 2815;
        data[283] <= -628;
        data[284] <= -100;
        data[285] <= 5561;
        data[286] <= 7343;
        data[287] <= -2353;
        data[288] <= -179;
        data[289] <= -2181;
        data[290] <= 1316;
        data[291] <= 6080;
        data[292] <= -3239;
        data[293] <= 5159;
        data[294] <= -1331;
        data[295] <= -7550;
        data[296] <= -2572;
        data[297] <= -6280;
        data[298] <= -1000;
        data[299] <= -5834;
        data[300] <= -3375;
        data[301] <= 7192;
        data[302] <= -1790;
        data[303] <= -6449;
        data[304] <= -2201;
        data[305] <= -644;
        data[306] <= -1668;
        data[307] <= 5507;
        data[308] <= 2051;
        data[309] <= 1305;
        data[310] <= 5002;
        data[311] <= -1356;
        data[312] <= 5361;
        data[313] <= 3104;
        data[314] <= -3028;
        data[315] <= -4885;
        data[316] <= -2539;
        data[317] <= -3046;
        data[318] <= -6649;
        data[319] <= -6440;
        data[320] <= -1319;
        data[321] <= -6374;
        data[322] <= 5149;
        data[323] <= -2311;
        data[324] <= 3937;
        data[325] <= 1801;
        data[326] <= 7527;
        data[327] <= 318;
        data[328] <= 442;
        data[329] <= -2767;
        data[330] <= 5332;
        data[331] <= 262;
        data[332] <= -5046;
        data[333] <= -2956;
        data[334] <= 2171;
        data[335] <= -2296;
        data[336] <= 5407;
        data[337] <= 7612;
        data[338] <= -6713;
        data[339] <= 2649;
        data[340] <= -1535;
        data[341] <= 3180;
        data[342] <= 4420;
        data[343] <= 3052;
        data[344] <= 7237;
        data[345] <= 2620;
        data[346] <= -4377;
        data[347] <= 1162;
        data[348] <= 6349;
        data[349] <= -7599;
        data[350] <= -7374;
        data[351] <= -685;
        data[352] <= -5686;
        data[353] <= -4232;
        data[354] <= 11;
        data[355] <= 1078;
        data[356] <= -1883;
        data[357] <= -202;
        data[358] <= -4435;
        data[359] <= -4522;
        data[360] <= 2313;
        data[361] <= -3741;
        data[362] <= 2046;
        data[363] <= 815;
        data[364] <= 3065;
        data[365] <= -6850;
        data[366] <= 4584;
        data[367] <= 3763;
        data[368] <= 110;
        data[369] <= -4581;
        data[370] <= -3469;
        data[371] <= -2020;
        data[372] <= 1733;
        data[373] <= 863;
        data[374] <= -7592;
        data[375] <= -6688;
        data[376] <= 5099;
        data[377] <= -7211;
        data[378] <= -72;
        data[379] <= -7056;
        data[380] <= -243;
        data[381] <= 6908;
        data[382] <= 1100;
        data[383] <= 273;
        data[384] <= -3968;
        data[385] <= -4839;
        data[386] <= 1969;
        data[387] <= -6731;
        data[388] <= 885;
        data[389] <= -5436;
        data[390] <= 4907;
        data[391] <= 4695;
        data[392] <= -720;
        data[393] <= 6245;
        data[394] <= -2430;
        data[395] <= 7636;
        data[396] <= -4361;
        data[397] <= 2730;
        data[398] <= 6403;
        data[399] <= -2307;
        data[400] <= 4329;
        data[401] <= -5866;
        data[402] <= -6511;
        data[403] <= 7084;
        data[404] <= 2987;
        data[405] <= 867;
        data[406] <= -7200;
        data[407] <= 1006;
        data[408] <= 6422;
        data[409] <= -445;
        data[410] <= 2473;
        data[411] <= -3422;
        data[412] <= 2586;
        data[413] <= 7652;
        data[414] <= -2793;
        data[415] <= 2784;
        data[416] <= -3666;
        data[417] <= -5965;
        data[418] <= -852;
        data[419] <= -6691;
        data[420] <= 4805;
        data[421] <= -5301;
        data[422] <= 2776;
        data[423] <= -4450;
        data[424] <= -5992;
        data[425] <= -3498;
        data[426] <= -4862;
        data[427] <= -285;
        data[428] <= 2792;
        data[429] <= -2882;
        data[430] <= -5938;
        data[431] <= 1794;
        data[432] <= 6841;
        data[433] <= -5466;
        data[434] <= 1967;
        data[435] <= -6927;
        data[436] <= -2962;
        data[437] <= 1583;
        data[438] <= 1524;
        data[439] <= -4258;
        data[440] <= -2537;
        data[441] <= -2850;
        data[442] <= -2802;
        data[443] <= 1902;
        data[444] <= 2064;
        data[445] <= 2579;
        data[446] <= 6966;
        data[447] <= 6784;
        data[448] <= 4309;
        data[449] <= 7535;
        data[450] <= 1102;
        data[451] <= 469;
        data[452] <= -121;
        data[453] <= 3503;
        data[454] <= 5352;
        data[455] <= 2222;
        data[456] <= 2702;
        data[457] <= 3659;
        data[458] <= 5279;
        data[459] <= -4932;
        data[460] <= -7145;
        data[461] <= 6396;
        data[462] <= -2993;
        data[463] <= -1455;
        data[464] <= -4341;
        data[465] <= 4690;
        data[466] <= -1210;
        data[467] <= 4308;
        data[468] <= 7437;
        data[469] <= 6859;
        data[470] <= -3702;
        data[471] <= 5868;
        data[472] <= 6707;
        data[473] <= -3237;
        data[474] <= 5355;
        data[475] <= 2516;
        data[476] <= 792;
        data[477] <= 811;
        data[478] <= 2673;
        data[479] <= 817;
        data[480] <= 3261;
        data[481] <= -3003;
        data[482] <= -2435;
        data[483] <= 7146;
        data[484] <= -6298;
        data[485] <= -2764;
        data[486] <= 5626;
        data[487] <= -1648;
        data[488] <= 7467;
        data[489] <= -5562;
        data[490] <= -7441;
        data[491] <= -7251;
        data[492] <= -3992;
        data[493] <= -7191;
        data[494] <= 1888;
        data[495] <= 692;
        data[496] <= 6372;
        data[497] <= -5345;
        data[498] <= -1536;
        data[499] <= 3082;
        data[500] <= -5184;
        data[501] <= -1119;
        data[502] <= -2135;
        data[503] <= 5824;
        data[504] <= 2395;
        data[505] <= 4295;
        data[506] <= 6163;
        data[507] <= 4895;
        data[508] <= 3519;
        data[509] <= 6920;
        data[510] <= 2276;
        data[511] <= -7367;
    end

endmodule
*/


//HRr vvvvv

module w42bit (
  input                    clk,
  input             [8:0] addr,
  output reg signed [41:0] dout
) ;


//w7681 concat w12289 concat w15361  in form two's complemen
  always @ (posedge clk) begin

      case(addr)
  //              ------w7681--------w12289----------w15361-----
        'd0: dout <="000000000000010000000000000100000000000001";
        'd1: dout <="000000001111100000000000001100000001100010";
        'd2: dout <="110001000000110000000000100110100110000011";
        'd3: dout <="000000110110010000000001101101000001001011";
        'd4: dout <="111000100011000000000101000110100010011011";
        'd5: dout <="110011111101110000001111001111001101111100";
        'd6: dout <="000011111010110000101101100110010110001100";
        'd7: dout <="000010111000100010001000101111001111000011";
        'd8: dout <="111110101101101010011010000000000010111010";
        'd9: dout <="001010000101111011001110000100101100110011";
        'd10: dout <="111011011111011101101010010001000101110100";
        'd11: dout <="110110010011110100111110110110001001001011";
        'd12: dout <="111111001101100010111100011001110011100111";
        'd13: dout <="001011000101101100110101000100110000111111";
        'd14: dout <="111101001111010010011111010000000000001010";
        'd15: dout <="001000110011001011011101101100001111010100";
        'd16: dout <="000101010101101110011001001000111100100010";
        'd17: dout <="000000110010011011001011011010111011101011";
        'd18: dout <="110100101011001101100010001100011000010010";
        'd19: dout <="110011101111110100100110101011101011011010";
        'd20: dout <="110110010110110001110011110110011101111100";
        'd21: dout <="000010000111100101011011011111110110100000";
        'd22: dout <="001011010000000100010010010000011101000100";
        'd23: dout <="000111011010010000110110101111011111111100";
        'd24: dout <="001001010111110010100100000111101010000101";
        'd25: dout <="001010111011111011101100001000001011110011";
        'd26: dout <="110011110010111111000100011111010100000001";
        'd27: dout <="111001010000111101001101010100001001110100";
        'd28: dout <="000010010010000011101000000000000001100100";
        'd29: dout <="110111011010111110110111111110101001000111";
        'd30: dout <="000111111111001100100111110110001101010001";
        'd31: dout <="001110111110000001110111100000100100110001";
        'd32: dout <="111101111100010101100110100000000010110011";
        'd33: dout <="111000011000100100110011011100100010000101";
        'd34: dout <="000111110011000010011010010011101011011100";
        'd35: dout <="000011010110001011001110101110100001000000";
        'd36: dout <="111101010010011101101100001000110010100111";
        'd37: dout <="001011101101000101000100011110101111011001";
        'd38: dout <="000101100000000011001101010000010100110011";
        'd39: dout <="001010111101011101100111101101110101111110";
        'd40: dout <="110101001111110100110111001000101000001100";
        'd41: dout <="111001010110000010100101010101100010001000";
        'd42: dout <="000111010111101011101111111000001111101000";
        'd43: dout <="000110101101011111001111101101011011001010";
        'd44: dout <="111011110010001101101111000100110100101111";
        'd45: dout <="001000011110010101001101010010001111101000";
        'd46: dout <="110001001111000011100111101100011011111110";
        'd47: dout <="001110101001111110110111000001100100110001";
        'd48: dout <="001000010101001100100101000000100010011001";
        'd49: dout <="000110010001110001101111000100001010000100";
        'd50: dout <="111111001001010101001101001100011010000100";
        'd51: dout <="000110111110000011100111100010101001111101";
        'd52: dout <="001100000000101110110110011111011111111101";
        'd53: dout <="111010011000111100100011010111101011100111";
        'd54: dout <="001100000001100001101010000010110001110110";
        'd55: dout <="111011010110110100111110000000010101001100";
        'd56: dout <="001100000101000010111001111110101100001111";
        'd57: dout <="111110101111111100101101110011001111100000";
        'd58: dout <="001100010001010010001001010100101111010100";
        'd59: dout <="001010100111011010011011111001001100010101";
        'd60: dout <="111101111100001011010011101100100111101011";
        'd61: dout <="111000001001001101111011001000101111100110";
        'd62: dout <="111000110010000101110001011101100111111001";
        'd63: dout <="000010011111110101010100010001100100101000";
        'd64: dout <="000100101111010011111100101100010100100111";
        'd65: dout <="111001101111001111110110000001100011100110";
        'd66: dout <="000001100101011111100010000010101111100011";
        'd67: dout <="001000000100111110100110000000100100000111";
        'd68: dout <="110110100010011011110010000011000010011111";
        'd69: dout <="001101010000101111010110000111100011110111";
        'd70: dout <="001011111000011110000010001110001010011001";
        'd71: dout <="110010011001011010000110100111111011000010";
        'd72: dout <="111100100100101010010011110011111001000110";
        'd73: dout <="111101011000111010111011010100101011001111";
        'd74: dout <="110011111111111100110010000010101100101100";
        'd75: dout <="000101110110110010010110000111111011111010";
        'd76: dout <="000010111111101011000010001001001110110110";
        'd77: dout <="000101011111101101000110011100101110001100";
        'd78: dout <="001010011110010011010011011011011110000101";
        'd79: dout <="110101001110001101111010000100100011111000";
        'd80: dout <="110111101001100101101110010010101011100001";
        'd81: dout <="111000010001010101001010101110001001000100";
        'd82: dout <="000000110001100011100000000001101000111001";
        'd83: dout <="110011111100101110011111111111010110100111";
        'd84: dout <="000010101101011011011111110100010111111111";
        'd85: dout <="110011110100001110011111100011001110010100";
        'd86: dout <="111010011110011011011110100010111010111100";
        'd87: dout <="110011010110011110011011100111010000010100";
        'd88: dout <="111011101010001011010010101110001110111011";
        'd89: dout <="000000101110011101111000001011010111000100";
        'd90: dout <="001110110011010101101000011101000100011001";
        'd91: dout <="110011100001110100111001010011101101110110";
        'd92: dout <="000110110011000010101011101110011100110011";
        'd93: dout <="000001010110101100000011000001110110101111";
        'd94: dout <="111001110010010000001001000101110011001110";
        'd95: dout <="000100101110110000011011001100001010101101";
        'd96: dout <="111001010000000001010001100101011000110110";
        'd97: dout <="000001100011100011110100101101000010001000";
        'd98: dout <="000110011000011111011110000011111111110101";
        'd99: dout <="000101011100011110011010000011101111001010";
        'd100: dout <="000111010100111011001110000000011101011011";
        'd101: dout <="000100000010111101101010000100000011001010";
        'd102: dout <="001010101000100100111110010001000101010011";
        'd103: dout <="111111001001100010111010101101000110101010";
        'd104: dout <="000111001101101100110000000011011011110111";
        'd105: dout <="111101000001010010010000000100111010011101";
        'd106: dout <="111011001111001010110000001011100000000010";
        'd107: dout <="000100100100101100010000011111110011010001";
        'd108: dout <="001101010100110000110001011011010000000111";
        'd109: dout <="110001111111100010010100001001101011000010";
        'd110: dout <="000001101000011010111100010110111000011000";
        'd111: dout <="001010111110111100110101000011000101001101";
        'd112: dout <="110110101100110010011111000111111110010010";
        'd113: dout <="111001011011011011011101001001000111100101";
        'd114: dout <="001100011101001110010111011100110110001101";
        'd115: dout <="110111111111101011000110010100011111100100";
        'd116: dout <="001101100101011101010011000011100100111011";
        'd117: dout <="000001111110100011111001000111110010100001";
        'd118: dout <="000010100010001111101011001001110110101000";
        'd119: dout <="000110111010111111000001011001101000100000";
        'd120: dout <="001000110111001101000100001010110000010101";
        'd121: dout <="001001001101100011001100011101110000101011";
        'd122: dout <="000001000000011101100101010000000001001000";
        'd123: dout <="000010001111000100101111110101101110010000";
        'd124: dout <="110100100000110010001111011000000011110011";
        'd125: dout <="000111110100101010101110000110010100000100";
        'd126: dout <="000100110011001100001010010011101110110100";
        'd127: dout <="111101010111100000011110110111111011101111";
        'd128: dout <="110010110010010001011100011100111110000000";
        'd129: dout <="110110110010010100010101010101001011100111";
        'd130: dout <="111110110000010000111111111011100001001111";
        'd131: dout <="001100110000010010111111101001101001001011";
        'd132: dout <="001010101001001100111110110111110010001011";
        'd133: dout <="111111101000100010111100100001010100111100";
        'd134: dout <="000111001111011100110101011110110011010101";
        'd135: dout <="111110101101110010100000011010110110101001";
        'd136: dout <="001010010101011011100001000100001011010000";
        'd137: dout <="001010100000011110100011010010011110011011";
        'd138: dout <="110111001010001011101001110000100101111110";
        'd139: dout <="110111110000101110111101010110001000101100";
        'd140: dout <="111111000011011100110111111101000100001001";
        'd141: dout <="000001001010000010100111111011010101010110";
        'd142: dout <="001011101011101011110111100110011011111101";
        'd143: dout <="000100000011001111100110110000100100000011";
        'd144: dout <="001010111000001110110100010010111100010111";
        'd145: dout <="001110001010101100011100110001011011101010";
        'd146: dout <="001000000011110001010110010101100101101111";
        'd147: dout <="110101100100010100000010111110010001010100";
        'd148: dout <="001101001101000000001000110011010001010101";
        'd149: dout <="001000011111010000011010010011110010011101";
        'd150: dout <="110010001101000001001110110001110000100000";
        'd151: dout <="001110101101010011101100010011110000010010";
        'd152: dout <="001011101110001111000100101110011011101010";
        'd153: dout <="000110011110001101001110000100000110111101";
        'd154: dout <="001011000000110011101010010011011001010111";
        'd155: dout <="111000101000111110111110101100110101011110";
        'd156: dout <="111001100010011100111100000111010111100110";
        'd157: dout <="110101001110110010110100010010001000011100";
        'd158: dout <="111000011000001100011100101100101011101001";
        'd159: dout <="000111010100000001010110001011010100100000";
        'd160: dout <="000011010100010100000010011000111001010010";
        'd161: dout <="111011100101110000000111000101011101001101";
        'd162: dout <="111100100110110000010101001100001101010100";
        'd163: dout <="111111100100010000111111100101101000100011";
        'd164: dout <="000011000111110010111110101110110100111011";
        'd165: dout <="001101011111001100111100000001010010110101";
        'd166: dout <="111011111011000010110100000111010100101000";
        'd167: dout <="110011001100001100011100001001000101100010";
        'd168: dout <="110001101110100001010100011101011101101000";
        'd169: dout <="110001001010010011111101010100110110101010";
        'd170: dout <="001010000011011111110111111001001011111110";
        'd171: dout <="111001000100011111100111101000000100011101";
        'd172: dout <="110110001011001110110110111011010100011000";
        'd173: dout <="110110101111001100100100101000101101000010";
        'd174: dout <="111011100110110001101101111101011100110010";
        'd175: dout <="111101100100110101001001110111100011111110";
        'd176: dout <="111111100111110011011101011010010101000111";
        'd177: dout <="000110100000111110011000000101010101011010";
        'd178: dout <="001101101011011011001000001111100001010001";
        'd179: dout <="000111110010101101011000101001101100001111";
        'd180: dout <="000010110111000100001001111100101110010010";
        'd181: dout <="111101010000100000011101110011100111010001";
        'd182: dout <="001010000000100001011001010011101000001100";
        'd183: dout <="110110011001110100001011110001000010100010";
        'd184: dout <="000101000001100000100011001100100111101001";
        'd185: dout <="001011011010100001101001100100101100100010";
        'd186: dout <="110011100101000100111100101100101011110010";
        'd187: dout <="001001111100100010110110000011100010010010";
        'd188: dout <="110010100001111100100001111111011111110000";
        'd189: dout <="000100110011100001100101111011010111101101";
        'd190: dout <="111101110110100100110001101010010011001010";
        'd191: dout <="110010110100000010010100110110010110000000";
        'd192: dout <="111000011110111010111110011010111100101011";
        'd193: dout <="001101110110101100111011001110001010010001";
        'd194: dout <="110100101011110010110001101011101110110010";
        'd195: dout <="110100011110011100010100110111111000101011";
        'd196: dout <="000101011001100000111110100000000001111001";
        'd197: dout <="000100101010010010111011100011001001010001";
        'd198: dout <="110100111001001100110010011110101100011000";
        'd199: dout <="000001010011110010010111011011011101010010";
        'd200: dout <="110111000111111011000110000111010101110010";
        'd201: dout <="110101100101001101010010010011000110110101";
        'd202: dout <="001101111011100011110110110110101101100001";
        'd203: dout <="111001100001111111100100011001001101000100";
        'd204: dout <="110100101111111110101101001001101111101001";
        'd205: dout <="111000010110011100000111011010011100000100";
        'd206: dout <="000101100111100000010110001100101110110001";
        'd207: dout <="110100001110000001000010100100010110101111";
        'd208: dout <="110101101010000011000111101101000011110101";
        'd209: dout <="110100110001011101010111000010110110101110";
        'd210: dout <="111001110011010100000101000100010010111010";
        'd211: dout <="000101101100110000001111001010111100101100";
        'd212: dout <="111001010011100000101101011010001011110011";
        'd213: dout <="000100111100100010001000001010010100110101";
        'd214: dout <="000110100100101010011000010100111001110110";
        'd215: dout <="110011010011101011001001000010100100010100";
        'd216: dout <="111000111111101101011011000110010111001101";
        'd217: dout <="110001100100100100010001010000110010100101";
        'd218: dout <="000101011110100000110011101110101100010101";
        'd219: dout <="001001100000010010011011000111011000101100";
        'd220: dout <="110101001010101011010001001011110011101000";
        'd221: dout <="110100010000101101110011011111110011010101";
        'd222: dout <="111000000101000101011010011011010110001111";
        'd223: dout <="110100111010000100001111000111110011001111";
        'd224: dout <="000010010001110000101101001011001101000011";
        'd225: dout <="110111001011010010000111011000101110111011";
        'd226: dout <="111000111110001010010110000100100110000011";
        'd227: dout <="001110000111111011000010010010010000010110";
        'd228: dout <="000101011001011101000110110101100010011010";
        'd229: dout <="000100011010110011010100100000101011001100";
        'd230: dout <="000011111000011101111101011110101000000110";
        'd231: dout <="000000011101100101111000011000011001110000";
        'd232: dout <="111110100100110101101001000110001011010101";
        'd233: dout <="000001100111010100111011001001010110111010";
        'd234: dout <="001010000000110010110001010101110100010001";
        'd235: dout <="110110101001011100010011111001110001010011";
        'd236: dout <="110110000010010000111011101100111110011000";
        'd237: dout <="001100010000110010110011000101110000010111";
        'd238: dout <="001010001000011100011001001011100010100000";
        'd239: dout <="111101111010010001001011011111110101001100";
        'd240: dout <="110110011100100011100010010110011100011100";
        'd241: dout <="000111101100001110100110111001010011100001";
        'd242: dout <="111100100100001011110100101000011000000000";
        'd243: dout <="111100111001111111011101111111001111110110";
        'd244: dout <="110011111110001110011001110101010001000000";
        'd245: dout <="000100001010011011001101011100010001011111";
        'd246: dout <="110011111001011101101000011000100001010111";
        'd247: dout <="111111100011110100111001001110100101000000";
        'd248: dout <="000010101000110010101011100011011010100101";
        'd249: dout <="001101011101011100000010011110111100111001";
        'd250: dout <="111010001110100000000111011010011111101101";
        'd251: dout <="000010000110000000010110001010110011100001";
        'd252: dout <="001001110011000001000010011011001001000001";
        'd253: dout <="000111010101000011000111001010010011111000";
        'd254: dout <="000100010010011101010101010111011100011100";
        'd255: dout <="111011101001010100000000000001110011000111";
        'd256: dout <="111111111111111111111111111111111111111111";
        'd257: dout <="111111110000101111111111110111111110011110";
        'd258: dout <="001110111111011111111111011101011001111101";
        'd259: dout <="111111001001111111111110010110111110110101";
        'd260: dout <="000111011101001111111010111101011101100101";
        'd261: dout <="001100000010011111110000110100110010000100";
        'd262: dout <="111100000101011111010010011101101001110100";
        'd263: dout <="111101000111101101110111010100110000111101";
        'd264: dout <="000001010010100101100110000011111101000110";
        'd265: dout <="110101111010010100110001111111010011001101";
        'd266: dout <="000100100000110010010101110010111010001100";
        'd267: dout <="001001101100011011000001001101110110110101";
        'd268: dout <="000000110010101101000011101010001100011001";
        'd269: dout <="110100111010100011001010111111001111000001";
        'd270: dout <="000010110000111101100000110011111111110110";
        'd271: dout <="110111001101000100100010010111110000101100";
        'd272: dout <="111010101010100001100110111011000011011110";
        'd273: dout <="111111001101110100110100101001000100010101";
        'd274: dout <="001011010101000010011101110111100111101110";
        'd275: dout <="001100010000011011011001011000010100100110";
        'd276: dout <="001001101001011110001100001101100010000100";
        'd277: dout <="111101111000101010100100100100001001100000";
        'd278: dout <="110100110000001011101101110011100010111100";
        'd279: dout <="111000100101111111001001010100100000000100";
        'd280: dout <="110110101000011101011011111100010101111011";
        'd281: dout <="110101000100010100010011111011110100001101";
        'd282: dout <="001100001101010000111011100100101011111111";
        'd283: dout <="000110101111010010110010101111110110001100";
        'd284: dout <="111101101110001100011000000011111110011100";
        'd285: dout <="001000100101010001001000000101010110111001";
        'd286: dout <="111000000001000011011000001101110010101111";
        'd287: dout <="110001000010001110001000100011011011001111";
        'd288: dout <="000010000011111010011001100011111101001101";
        'd289: dout <="000111100111101011001100100111011101111011";
        'd290: dout <="111000001101001101100101110000010100100100";
        'd291: dout <="111100101010000100110001010101011111000000";
        'd292: dout <="000010101101110010010011111011001101011001";
        'd293: dout <="110100010011001010111011100101010000100111";
        'd294: dout <="111010100000001100110010110011101011001101";
        'd295: dout <="110101000010110010011000010110001010000010";
        'd296: dout <="001010110000011011001000111011010111110100";
        'd297: dout <="000110101010001101011010101110011101111000";
        'd298: dout <="111000101000100100010000001011110000011000";
        'd299: dout <="111001010010110000110000010110100100110110";
        'd300: dout <="000100001110000010010000111111001011010001";
        'd301: dout <="110111100001111010110010110001110000011000";
        'd302: dout <="001110110001001100011000010111100100000010";
        'd303: dout <="110001010110010001001001000010011011001111";
        'd304: dout <="110111101011000011011011000011011101100111";
        'd305: dout <="111001101110011110010000111111110101111100";
        'd306: dout <="000000110110111010110010110111100101111100";
        'd307: dout <="111001000010001100011000100001010110000011";
        'd308: dout <="110011111111100001001001100100100000000011";
        'd309: dout <="000101100111010011011100101100010100011001";
        'd310: dout <="110011111110101110010110000001001110001010";
        'd311: dout <="000100101001011011000010000011101010110100";
        'd312: dout <="110011111011001101000110000101010011110001";
        'd313: dout <="000001010000010011010010010000110000100000";
        'd314: dout <="110011101110111101110110101111010000101100";
        'd315: dout <="110101011000110101100100001010110011101011";
        'd316: dout <="000010000100000100101100010111011000010101";
        'd317: dout <="000111110111000010000100111011010000011010";
        'd318: dout <="000111001110001010001110100110011000000111";
        'd319: dout <="111101100000011010101011110010011011011000";
        'd320: dout <="111011010000111100000011010111101011011001";
        'd321: dout <="000110010001000000001010000010011100011010";
        'd322: dout <="111110011010110000011110000001010000011101";
        'd323: dout <="110111111011010001011010000011011011111001";
        'd324: dout <="001001011101110100001110000000111101100001";
        'd325: dout <="110010101111100000101001111100011100001001";
        'd326: dout <="110100000111110001111101110101110101100111";
        'd327: dout <="001101100110110101111001011100000100111110";
        'd328: dout <="000011011011100101101100010000000110111010";
        'd329: dout <="000010100111010101000100101111010100110001";
        'd330: dout <="001100000000010011001110000001010011010100";
        'd331: dout <="111010001001011101101001111100000100000110";
        'd332: dout <="111101000000100100111101111010110001001010";
        'd333: dout <="111010100000100010111001100111010001110100";
        'd334: dout <="110101100001111100101100101000100001111011";
        'd335: dout <="001010110010000010000101111111011100001000";
        'd336: dout <="001000010110101010010001110001010100011111";
        'd337: dout <="000111101110111010110101010101110110111100";
        'd338: dout <="111111001110101100100000000010010111000111";
        'd339: dout <="001100000011100001100000000100101001011001";
        'd340: dout <="111101010010110100100000001111101000000001";
        'd341: dout <="001100001100000001100000100000110001101100";
        'd342: dout <="000101100001110100100001100001000101000100";
        'd343: dout <="001100101001110001100100011100101111101100";
        'd344: dout <="000100010110000100101101010101110001000101";
        'd345: dout <="111111010001110010000111111000101000111100";
        'd346: dout <="110001001100111010010111100110111011100111";
        'd347: dout <="001100011110011011000110110000010010001010";
        'd348: dout <="111001001101001101010100010101100011001101";
        'd349: dout <="111110101001100011111101000010001001010001";
        'd350: dout <="000110001101111111110110111110001100110010";
        'd351: dout <="111011010001011111100100110111110101010011";
        'd352: dout <="000110110000001110101110011110100111001010";
        'd353: dout <="111110011100101100001011010110111101111000";
        'd354: dout <="111001100111110000100010000000000000001011";
        'd355: dout <="111010100011110001100110000000010000110110";
        'd356: dout <="111000101011010100110010000011100010100101";
        'd357: dout <="111011111101010010010101111111111100110110";
        'd358: dout <="110101010111101011000001110010111010101101";
        'd359: dout <="000000110110101101000101010110111001010110";
        'd360: dout <="111000110010100011010000000000100100001001";
        'd361: dout <="000010111110111101101111111111000101100011";
        'd362: dout <="000100110001000101001111111000011111111110";
        'd363: dout <="111011011011100011101111100100001100101111";
        'd364: dout <="110010101011011111001110101000101111111001";
        'd365: dout <="001110000000101101101011111010010100111110";
        'd366: dout <="111110010111110101000011101101000111101000";
        'd367: dout <="110101000001010011001011000000111010110011";
        'd368: dout <="001001010011011101100000111100000001101110";
        'd369: dout <="000110100100110100100010111010111000011011";
        'd370: dout <="110011100011000001101000100111001001110011";
        'd371: dout <="001000000000100100111001101111100000011100";
        'd372: dout <="110010011010110010101101000000011011000101";
        'd373: dout <="111110000001101100000110111100001101011111";
        'd374: dout <="111101011110000000010100111010001001011000";
        'd375: dout <="111001000101010000111110101010010111100000";
        'd376: dout <="110111001001000010111011111001001111101011";
        'd377: dout <="110110110010101100110011100110001111010101";
        'd378: dout <="111110111111110010011010110011111110111000";
        'd379: dout <="111101110001001011010000001110010001110000";
        'd380: dout <="001011011111011101110000101011111100001101";
        'd381: dout <="111000001011100101010001111101101011111100";
        'd382: dout <="111011001101000011110101110000010001001100";
        'd383: dout <="000010101000101111100001001100000100010001";
        'd384: dout <="001101001101111110100011100111000010000000";
        'd385: dout <="001001001101111011101010101110110100011001";
        'd386: dout <="000001001111111111000000001000011110110001";
        'd387: dout <="110011001111111101000000011010010110110101";
        'd388: dout <="110101010111000011000001001100001101110101";
        'd389: dout <="000000010111101101000011100010101011000100";
        'd390: dout <="111000110000110011001010100101001100101011";
        'd391: dout <="000001010010011101011111101001001001010111";
        'd392: dout <="110101101010110100011110111111110100110000";
        'd393: dout <="110101011111110001011100110001100001100101";
        'd394: dout <="001000110110000100010110010011011010000010";
        'd395: dout <="001000001111100001000010101101110111010100";
        'd396: dout <="000000111100110011001000000110111011110111";
        'd397: dout <="111110110110001101011000001000101010101010";
        'd398: dout <="110100010100100100001000011101100100000011";
        'd399: dout <="111011111101000000011001010011011011111101";
        'd400: dout <="110101001000000001001011110001000011101001";
        'd401: dout <="110001110101100011100011010010100100010110";
        'd402: dout <="110111111100011110101001101110011010010001";
        'd403: dout <="001010011011111011111101000101101110101100";
        'd404: dout <="110010110011001111110111010000101110101011";
        'd405: dout <="110111100000111111100101110000001101100011";
        'd406: dout <="001101110011001110110001010010001111100000";
        'd407: dout <="110001010010111100010011110000001111101110";
        'd408: dout <="110100010010000000111011010101100100010110";
        'd409: dout <="111001100010000010110001111111111001000011";
        'd410: dout <="110100111111011100010101110000100110101001";
        'd411: dout <="000111010111010001000001010111001010100010";
        'd412: dout <="000110011101110011000011111100101000011010";
        'd413: dout <="001010110001011101001011110001110111100100";
        'd414: dout <="000111101000000011100011010111010100010111";
        'd415: dout <="111000101100001110101001111000101011100000";
        'd416: dout <="111100101011111011111101101011000110101110";
        'd417: dout <="000100011010011111111000111110100010110011";
        'd418: dout <="000011011001011111101010110111110010101100";
        'd419: dout <="000000011011111111000000011110010111011101";
        'd420: dout <="111100111000011101000001010101001011000101";
        'd421: dout <="110010100001000011000100000010101101001011";
        'd422: dout <="000100000101001101001011111100101011011000";
        'd423: dout <="001100110100000011100011111010111010011110";
        'd424: dout <="001110010001101110101011100110100010011000";
        'd425: dout <="001110110101111100000010101111001001010110";
        'd426: dout <="110101111100110000001000001010110100000010";
        'd427: dout <="000110111011110000011000011011111011100011";
        'd428: dout <="001001110101000001001001001000101011101000";
        'd429: dout <="001001010001000011011011011011010010111110";
        'd430: dout <="000100011001011110010010000110100011001110";
        'd431: dout <="000010011011011010110110001100011100000010";
        'd432: dout <="000000011000011100100010101001101010111001";
        'd433: dout <="111001011111010001100111111110101010100110";
        'd434: dout <="110010010100110100110111110100011110101111";
        'd435: dout <="111000001101100010100111011010010011110001";
        'd436: dout <="111101001001001011110110000111010001101110";
        'd437: dout <="000010101111101111100010010000011000101111";
        'd438: dout <="110101111111101110100110110000010111110100";
        'd439: dout <="001001100110011011110100010010111101011110";
        'd440: dout <="111010111110101111011100110111011000010111";
        'd441: dout <="110100100101101110010110011111010011011110";
        'd442: dout <="001100011011001011000011010111010100001110";
        'd443: dout <="110110000011101101001010000000011101101110";
        'd444: dout <="001101011110010011011110000100100000010000";
        'd445: dout <="111011001100101110011010001000101000010011";
        'd446: dout <="000010001001101011001110011001101100110110";
        'd447: dout <="001101001100001101101011001101101010000000";
        'd448: dout <="000111100001010101000001101001000011010101";
        'd449: dout <="110010001001100011000100110101110101101111";
        'd450: dout <="001011010100011101001110011000010001001110";
        'd451: dout <="001011100001110011101011001100000111010101";
        'd452: dout <="111010100110101111000001100011111110000111";
        'd453: dout <="111011010101111101000100100000110110101111";
        'd454: dout <="001011000111000011001101100101010011101000";
        'd455: dout <="111110101100011101101000101000100010101110";
        'd456: dout <="001000111000010100111001111100101010001110";
        'd457: dout <="001010011011000010101101110000111001001011";
        'd458: dout <="110010000100101100001001001101010010011111";
        'd459: dout <="000110011110010000011011101010110010111100";
        'd460: dout <="001011010000010001010010111010010000010111";
        'd461: dout <="000111101001110011111000101001100011111100";
        'd462: dout <="111010011000101111101001110111010001001111";
        'd463: dout <="001011110010001110111101011111101001010001";
        'd464: dout <="001010010110001100111000010110111100001011";
        'd465: dout <="001011001110110010101001000001001001010010";
        'd466: dout <="000110001100111011111010111111101101000110";
        'd467: dout <="111010010011011111110000111001000011010100";
        'd468: dout <="000110101100101111010010101001110100001101";
        'd469: dout <="111011000011101101110111111001101011001011";
        'd470: dout <="111001011011100101100111101111000110001010";
        'd471: dout <="001100101100100100110111000001011011101100";
        'd472: dout <="000111000000100010100100111101101000110011";
        'd473: dout <="001110011011101011101110110011001101011011";
        'd474: dout <="111010100001101111001100010101010011101011";
        'd475: dout <="110110011111111101100100111100100111010100";
        'd476: dout <="001010110101100100101110111000001100011000";
        'd477: dout <="001011101111100010001100100100001100101011";
        'd478: dout <="000111111011001010100101101000101001110001";
        'd479: dout <="001011000110001011110000111100001100110001";
        'd480: dout <="111101101110011111010010111000110010111101";
        'd481: dout <="001000110100111101111000101011010001000101";
        'd482: dout <="000111000010000101101001111111011001111101";
        'd483: dout <="110001111000010100111101110001101111101010";
        'd484: dout <="111010100110110010111001001110011101100110";
        'd485: dout <="111011100101011100101011100011010100110100";
        'd486: dout <="111100000111110010000010100101010111111010";
        'd487: dout <="111111100010101010000111101011100110010000";
        'd488: dout <="000001011011011010010110111101110100101011";
        'd489: dout <="111110011000111011000100111010101001000110";
        'd490: dout <="110101111111011101001110101110001011101111";
        'd491: dout <="001001010110110011101100001010001110101101";
        'd492: dout <="001001111101111111000100010111000001101000";
        'd493: dout <="110011101111011101001100111110001111101001";
        'd494: dout <="110101110111110011100110111000011101100000";
        'd495: dout <="000010000101111110110100100100001010110100";
        'd496: dout <="001001100011101100011101101101100011100100";
        'd497: dout <="111000010100000001011001001010101100011111";
        'd498: dout <="000011011100000100001011011011101000000000";
        'd499: dout <="000011000110010000100010000100110000001010";
        'd500: dout <="001100000010000001100110001110101111000000";
        'd501: dout <="111011110101110100110010100111101110100001";
        'd502: dout <="001100000110110010010111101011011110101001";
        'd503: dout <="000000011100011011000110110101011011000000";
        'd504: dout <="111101010111011101010100100000100101011011";
        'd505: dout <="110010100010110011111101100101000011000111";
        'd506: dout <="000101110001101111111000101001100000010011";
        'd507: dout <="111101111010001111101001111001001100011111";
        'd508: dout <="110110001101001110111101101000110110111111";
        'd509: dout <="111000101011001100111000111001101100001000";
        'd510: dout <="111011101101110010101010101100100011100100";
        'd511: dout <="000100010110111100000000000010001100111001";
       
        default: dout <= 'sd0;
      endcase
    end
  

endmodule

//HRr ^^^^^







/*
module w_7681_12289_15361 (  

  input                    clk,
  input                    rst,
  input             [8:0] addr,
  output reg signed [41:0] dout
  
  );
    always @ (posedge clk) begin
    if(rst) begin
      dout <= 'sd0;
    end else begin
      case(addr)
        'd0: dout <= -'sd587;
        'd1: dout <= 'sd1620;
        'd2: dout <= 'sd1846;
        'd3: dout <= -'sd504;
        'd4: dout <= 'sd213;
        'd5: dout <= 'sd1460;
        'd6: dout <= -'sd771;
        'd7: dout <= -'sd1404;
        'd8: dout <= 'sd711;
        'd9: dout <= -'sd698;
        'd10: dout <= 'sd14;
        'd11: dout <= 'sd923;
        'd12: dout <= -'sd1469;
        'd13: dout <= -'sd2130;
        'd14: dout <= 'sd2097;
        'd15: dout <= -'sd606;
        'd16: dout <= -'sd1346;
        'd17: dout <= 'sd334;
        'd18: dout <= 'sd1357;
        'd19: dout <= -'sd1700;
        'd20: dout <= 'sd2004;
        'd21: dout <= 'sd139;
        'd22: dout <= -'sd415;
        'd23: dout <= -'sd699;
        'd24: dout <= 'sd2171;
        'd25: dout <= -'sd787;
        'd26: dout <= -'sd157;
        'd27: dout <= 'sd1864;
        'd28: dout <= 'sd756;
        'd29: dout <= -'sd665;
        'd30: dout <= 'sd929;
        'd31: dout <= -'sd750;
        'd32: dout <= -'sd2201;
        'd33: dout <= -'sd675;
        'd34: dout <= -'sd1231;
        'd35: dout <= -'sd80;
        'd36: dout <= -'sd138;
        'd37: dout <= -'sd1132;
        'd38: dout <= 'sd957;
        'd39: dout <= 'sd627;
        'd40: dout <= 'sd1125;
        'd41: dout <= -'sd385;
        'd42: dout <= 'sd2263;
        'd43: dout <= -'sd147;
        'd44: dout <= -'sd1257;
        'd45: dout <= -'sd1415;
        'd46: dout <= 'sd622;
        'd47: dout <= 'sd1415;
        'd48: dout <= 'sd1729;
        'd49: dout <= 'sd421;
        'd50: dout <= 'sd1865;
        'd51: dout <= 'sd1529;
        'd52: dout <= 'sd799;
        'd53: dout <= -'sd1637;
        'd54: dout <= -'sd178;
        'd55: dout <= -'sd627;
        'd56: dout <= 'sd1651;
        'd57: dout <= -'sd829;
        'd58: dout <= 'sd1182;
        'd59: dout <= 'sd197;
        'd60: dout <= -'sd1320;
        'd61: dout <= -'sd1533;
        'd62: dout <= 'sd1840;
        'd63: dout <= -'sd1696;
        'd64: dout <= 'sd31;
        'd65: dout <= -'sd1413;
        'd66: dout <= 'sd333;
        'd67: dout <= 'sd29;
        'd68: dout <= -'sd1181;
        'd69: dout <= 'sd1662;
        'd70: dout <= -'sd92;
        'd71: dout <= 'sd1937;
        'd72: dout <= -'sd2164;
        'd73: dout <= 'sd597;
        'd74: dout <= -'sd1997;
        'd75: dout <= -'sd786;
        'd76: dout <= -'sd1438;
        'd77: dout <= 'sd227;
        'd78: dout <= -'sd1475;
        'd79: dout <= 'sd456;
        'd80: dout <= 'sd1907;
        'd81: dout <= 'sd302;
        'd82: dout <= 'sd448;
        'd83: dout <= -'sd32;
        'd84: dout <= 'sd1486;
        'd85: dout <= 'sd2058;
        'd86: dout <= 'sd1235;
        'd87: dout <= 'sd376;
        'd88: dout <= 'sd1600;
        'd89: dout <= 'sd2061;
        'd90: dout <= 'sd1302;
        'd91: dout <= 'sd723;
        'd92: dout <= 'sd801;
        'd93: dout <= -'sd903;
        'd94: dout <= 'sd258;
        'd95: dout <= 'sd1660;
        'd96: dout <= 'sd1715;
        'd97: dout <= -'sd1178;
        'd98: dout <= -'sd1838;
        'd99: dout <= 'sd40;
        'd100: dout <= 'sd1760;
        'd101: dout <= -'sd1884;
        'd102: dout <= 'sd409;
        'd103: dout <= 'sd1385;
        'd104: dout <= -'sd1546;
        'd105: dout <= -'sd694;
        'd106: dout <= -'sd21;
        'd107: dout <= 'sd2292;
        'd108: dout <= 'sd1265;
        'd109: dout <= -'sd168;
        'd110: dout <= 'sd407;
        'd111: dout <= 'sd991;
        'd112: dout <= 'sd519;
        'd113: dout <= -'sd63;
        'd114: dout <= 'sd2182;
        'd115: dout <= -'sd1271;
        'd116: dout <= 'sd1882;
        'd117: dout <= 'sd1414;
        'd118: dout <= 'sd1204;
        'd119: dout <= 'sd374;
        'd120: dout <= -'sd565;
        'd121: dout <= 'sd1387;
        'd122: dout <= 'sd653;
        'd123: dout <= 'sd1978;
        'd124: dout <= 'sd2077;
        'd125: dout <= -'sd853;
        'd126: dout <= 'sd1796;
        'd127: dout <= -'sd977;
        'd128: dout <= -'sd27;
        'd129: dout <= -'sd101;
        'd130: dout <= 'sd1912;
        'd131: dout <= -'sd987;
        'd132: dout <= -'sd174;
        'd133: dout <= 'sd746;
        'd134: dout <= -'sd302;
        'd135: dout <= -'sd2039;
        'd136: dout <= 'sd976;
        'd137: dout <= -'sd749;
        'd138: dout <= 'sd2089;
        'd139: dout <= 'sd555;
        'd140: dout <= 'sd9;
        'd141: dout <= 'sd1368;
        'd142: dout <= 'sd1950;
        'd143: dout <= -'sd187;
        'd144: dout <= -'sd2038;
        'd145: dout <= -'sd863;
        'd146: dout <= 'sd1622;
        'd147: dout <= 'sd572;
        'd148: dout <= -'sd329;
        'd149: dout <= 'sd2026;
        'd150: dout <= -'sd904;
        'd151: dout <= -'sd1897;
        'd152: dout <= 'sd1875;
        'd153: dout <= 'sd1080;
        'd154: dout <= -'sd141;
        'd155: dout <= -'sd1710;
        'd156: dout <= 'sd2143;
        'd157: dout <= -'sd1043;
        'd158: dout <= 'sd1010;
        'd159: dout <= 'sd2021;
        'd160: dout <= -'sd195;
        'd161: dout <= 'sd1113;
        'd162: dout <= 'sd763;
        'd163: dout <= -'sd13;
        'd164: dout <= -'sd215;
        'd165: dout <= -'sd996;
        'd166: dout <= 'sd344;
        'd167: dout <= -'sd842;
        'd168: dout <= 'sd1884;
        'd169: dout <= -'sd1293;
        'd170: dout <= -'sd2277;
        'd171: dout <= -'sd1038;
        'd172: dout <= 'sd1839;
        'd173: dout <= -'sd1737;
        'd174: dout <= 'sd1590;
        'd175: dout <= 'sd64;
        'd176: dout <= -'sd953;
        'd177: dout <= -'sd1413;
        'd178: dout <= -'sd1581;
        'd179: dout <= 'sd378;
        'd180: dout <= 'sd999;
        'd181: dout <= -'sd1544;
        'd182: dout <= 'sd1285;
        'd183: dout <= 'sd138;
        'd184: dout <= 'sd1865;
        'd185: dout <= 'sd541;
        'd186: dout <= 'sd1768;
        'd187: dout <= -'sd1626;
        'd188: dout <= 'sd1742;
        'd189: dout <= 'sd100;
        'd190: dout <= -'sd2005;
        'd191: dout <= 'sd1475;
        'd192: dout <= 'sd1643;
        'd193: dout <= -'sd360;
        'd194: dout <= -'sd1697;
        'd195: dout <= -'sd894;
        'd196: dout <= -'sd1976;
        'd197: dout <= -'sd2045;
        'd198: dout <= 'sd1801;
        'd199: dout <= -'sd1017;
        'd200: dout <= 'sd212;
        'd201: dout <= 'sd1831;
        'd202: dout <= -'sd1437;
        'd203: dout <= -'sd556;
        'd204: dout <= 'sd1447;
        'd205: dout <= -'sd1697;
        'd206: dout <= -'sd332;
        'd207: dout <= -'sd1058;
        'd208: dout <= -'sd2214;
        'd209: dout <= 'sd2295;
        'd210: dout <= -'sd961;
        'd211: dout <= -'sd80;
        'd212: dout <= 'sd1703;
        'd213: dout <= 'sd1817;
        'd214: dout <= -'sd1272;
        'd215: dout <= 'sd904;
        'd216: dout <= 'sd1100;
        'd217: dout <= -'sd1959;
        'd218: dout <= 'sd507;
        'd219: dout <= 'sd1452;
        'd220: dout <= -'sd1107;
        'd221: dout <= -'sd1909;
        'd222: dout <= -'sd814;
        'd223: dout <= 'sd552;
        'd224: dout <= 'sd1469;
        'd225: dout <= 'sd1813;
        'd226: dout <= 'sd1316;
        'd227: dout <= -'sd24;
        'd228: dout <= -'sd93;
        'd229: dout <= 'sd1110;
        'd230: dout <= 'sd1328;
        'd231: dout <= 'sd2031;
        'd232: dout <= 'sd1385;
        'd233: dout <= -'sd735;
        'd234: dout <= 'sd2168;
        'd235: dout <= -'sd1936;
        'd236: dout <= -'sd1245;
        'd237: dout <= 'sd709;
        'd238: dout <= -'sd1346;
        'd239: dout <= -'sd838;
        'd240: dout <= -'sd350;
        'd241: dout <= 'sd1542;
        'd242: dout <= -'sd177;
        'd243: dout <= -'sd2113;
        'd244: dout <= -'sd1077;
        'd245: dout <= -'sd1018;
        'd246: dout <= -'sd308;
        'd247: dout <= -'sd693;
        'd248: dout <= -'sd1923;
        'd249: dout <= -'sd483;
        'd250: dout <= -'sd1446;
        'd251: dout <= 'sd1084;
        'd252: dout <= 'sd1861;
        'd253: dout <= -'sd1502;
        'd254: dout <= 'sd1210;
        'd255: dout <= -'sd494;
        'd256: dout <= -'sd339;
        'd257: dout <= -'sd6;
        'd258: dout <= 'sd1000;
        'd259: dout <= 'sd557;
        'd260: dout <= 'sd603;
        'd261: dout <= 'sd514;
        'd262: dout <= -'sd1886;
        'd263: dout <= 'sd1199;
        'd264: dout <= -'sd1023;
        'd265: dout <= -'sd1717;
        'd266: dout <= 'sd37;
        'd267: dout <= 'sd582;
        'd268: dout <= -'sd1279;
        'd269: dout <= 'sd1463;
        'd270: dout <= -'sd1487;
        'd271: dout <= -'sd1251;
        'd272: dout <= -'sd892;
        'd273: dout <= 'sd490;
        'd274: dout <= -'sd687;
        'd275: dout <= -'sd379;
        'd276: dout <= 'sd397;
        'd277: dout <= 'sd662;
        'd278: dout <= -'sd783;
        'd279: dout <= -'sd1485;
        'd280: dout <= 'sd868;
        'd281: dout <= 'sd246;
        'd282: dout <= 'sd1341;
        'd283: dout <= -'sd2060;
        'd284: dout <= 'sd239;
        'd285: dout <= 'sd1104;
        'd286: dout <= 'sd790;
        'd287: dout <= -'sd151;
        'd288: dout <= -'sd420;
        'd289: dout <= -'sd929;
        'd290: dout <= 'sd327;
        'd291: dout <= -'sd1381;
        'd292: dout <= 'sd599;
        'd293: dout <= -'sd1152;
        'd294: dout <= -'sd1538;
        'd295: dout <= 'sd671;
        'd296: dout <= 'sd1443;
        'd297: dout <= -'sd884;
        'd298: dout <= 'sd168;
        'd299: dout <= -'sd741;
        'd300: dout <= -'sd590;
        'd301: dout <= 'sd1362;
        'd302: dout <= -'sd1101;
        'd303: dout <= 'sd750;
        'd304: dout <= -'sd311;
        'd305: dout <= 'sd565;
        'd306: dout <= 'sd2150;
        'd307: dout <= 'sd63;
        'd308: dout <= -'sd961;
        'd309: dout <= 'sd608;
        'd310: dout <= 'sd1919;
        'd311: dout <= -'sd79;
        'd312: dout <= -'sd870;
        'd313: dout <= 'sd1648;
        'd314: dout <= 'sd477;
        'd315: dout <= 'sd1792;
        'd316: dout <= 'sd54;
        'd317: dout <= -'sd944;
        'd318: dout <= -'sd1856;
        'd319: dout <= 'sd230;
        'd320: dout <= -'sd1419;
        'd321: dout <= -'sd401;
        'd322: dout <= -'sd2238;
        'd323: dout <= 'sd520;
        'd324: dout <= -'sd24;
        'd325: dout <= 'sd713;
        'd326: dout <= 'sd2220;
        'd327: dout <= 'sd903;
        'd328: dout <= -'sd1849;
        'd329: dout <= -'sd1893;
        'd330: dout <= 'sd765;
        'd331: dout <= -'sd382;
        'd332: dout <= -'sd665;
        'd333: dout <= -'sd81;
        'd334: dout <= 'sd1865;
        'd335: dout <= -'sd1640;
        'd336: dout <= -'sd508;
        'd337: dout <= -'sd1928;
        'd338: dout <= 'sd1692;
        'd339: dout <= -'sd2045;
        'd340: dout <= 'sd450;
        'd341: dout <= 'sd1321;
        'd342: dout <= -'sd1068;
        'd343: dout <= -'sd336;
        'd344: dout <= 'sd855;
        'd345: dout <= 'sd2270;
        'd346: dout <= 'sd1293;
        'd347: dout <= 'sd2244;
        'd348: dout <= -'sd554;
        'd349: dout <= 'sd1325;
        'd350: dout <= -'sd783;
        'd351: dout <= 'sd1357;
        'd352: dout <= -'sd297;
        'd353: dout <= -'sd1883;
        'd354: dout <= -'sd767;
        'd355: dout <= -'sd1937;
        'd356: dout <= 'sd1664;
        'd357: dout <= 'sd214;
        'd358: dout <= 'sd1434;
        'd359: dout <= 'sd1452;
        'd360: dout <= -'sd770;
        'd361: dout <= 'sd1162;
        'd362: dout <= 'sd1078;
        'd363: dout <= 'sd1665;
        'd364: dout <= 'sd2241;
        'd365: dout <= -'sd124;
        'd366: dout <= -'sd1698;
        'd367: dout <= 'sd2035;
        'd368: dout <= 'sd1863;
        'd369: dout <= -'sd2243;
        'd370: dout <= 'sd2291;
        'd371: dout <= -'sd1580;
        'd372: dout <= 'sd1179;
        'd373: dout <= 'sd1419;
        'd374: dout <= -'sd1099;
        'd375: dout <= -'sd1364;
        'd376: dout <= 'sd1048;
        'd377: dout <= 'sd1203;
        'd378: dout <= -'sd51;
        'd379: dout <= -'sd1306;
        'd380: dout <= -'sd2265;
        'd381: dout <= 'sd2003;
        'd382: dout <= -'sd420;
        'd383: dout <= 'sd1871;
        'd384: dout <= 'sd618;
        'd385: dout <= 'sd2048;
        'd386: dout <= 'sd2173;
        'd387: dout <= 'sd1591;
        'd388: dout <= -'sd1319;
        'd389: dout <= 'sd588;
        'd390: dout <= -'sd345;
        'd391: dout <= -'sd18;
        'd392: dout <= -'sd795;
        'd393: dout <= -'sd357;
        'd394: dout <= -'sd880;
        'd395: dout <= 'sd1678;
        'd396: dout <= 'sd84;
        'd397: dout <= 'sd752;
        'd398: dout <= 'sd680;
        'd399: dout <= 'sd1333;
        'd400: dout <= 'sd1174;
        'd401: dout <= 'sd1728;
        'd402: dout <= -'sd476;
        'd403: dout <= -'sd1788;
        'd404: dout <= 'sd1840;
        'd405: dout <= -'sd789;
        'd406: dout <= 'sd1677;
        'd407: dout <= 'sd496;
        'd408: dout <= -'sd407;
        'd409: dout <= 'sd320;
        'd410: dout <= 'sd1643;
        'd411: dout <= 'sd2068;
        'd412: dout <= 'sd321;
        'd413: dout <= 'sd1543;
        'd414: dout <= 'sd98;
        'd415: dout <= -'sd832;
        'd416: dout <= -'sd278;
        'd417: dout <= -'sd2168;
        'd418: dout <= -'sd296;
        'd419: dout <= 'sd981;
        'd420: dout <= -'sd922;
        'd421: dout <= 'sd179;
        'd422: dout <= -'sd1691;
        'd423: dout <= 'sd2011;
        'd424: dout <= 'sd1512;
        'd425: dout <= 'sd1774;
        'd426: dout <= -'sd2017;
        'd427: dout <= -'sd2274;
        'd428: dout <= 'sd1428;
        'd429: dout <= -'sd1303;
        'd430: dout <= -'sd121;
        'd431: dout <= -'sd365;
        'd432: dout <= 'sd993;
        'd433: dout <= -'sd1003;
        'd434: dout <= 'sd1140;
        'd435: dout <= 'sd330;
        'd436: dout <= 'sd1739;
        'd437: dout <= 'sd559;
        'd438: dout <= -'sd1801;
        'd439: dout <= 'sd68;
        'd440: dout <= 'sd902;
        'd441: dout <= 'sd1947;
        'd442: dout <= -'sd1265;
        'd443: dout <= -'sd1681;
        'd444: dout <= 'sd2158;
        'd445: dout <= 'sd652;
        'd446: dout <= 'sd464;
        'd447: dout <= 'sd740;
        'd448: dout <= -'sd384;
        'd449: dout <= 'sd534;
        'd450: dout <= -'sd853;
        'd451: dout <= -'sd555;
        'd452: dout <= -'sd249;
        'd453: dout <= 'sd441;
        'd454: dout <= 'sd989;
        'd455: dout <= 'sd173;
        'd456: dout <= 'sd1984;
        'd457: dout <= 'sd797;
        'd458: dout <= 'sd1006;
        'd459: dout <= -'sd176;
        'd460: dout <= 'sd1607;
        'd461: dout <= 'sd417;
        'd462: dout <= -'sd956;
        'd463: dout <= 'sd334;
        'd464: dout <= -'sd2056;
        'd465: dout <= -'sd634;
        'd466: dout <= 'sd1067;
        'd467: dout <= 'sd131;
        'd468: dout <= -'sd1958;
        'd469: dout <= -'sd1480;
        'd470: dout <= -'sd2028;
        'd471: dout <= 'sd1073;
        'd472: dout <= -'sd313;
        'd473: dout <= -'sd1894;
        'd474: dout <= -'sd560;
        'd475: dout <= 'sd2202;
        'd476: dout <= 'sd415;
        'd477: dout <= -'sd1332;
        'd478: dout <= -'sd53;
        'd479: dout <= -'sd340;
        'd480: dout <= 'sd1437;
        'd481: dout <= 'sd1711;
        'd482: dout <= 'sd1863;
        'd483: dout <= -'sd1560;
        'd484: dout <= 'sd404;
        'd485: dout <= 'sd1240;
        'd486: dout <= -'sd977;
        'd487: dout <= 'sd774;
        'd488: dout <= 'sd1423;
        'd489: dout <= 'sd716;
        'd490: dout <= -'sd1573;
        'd491: dout <= -'sd2146;
        'd492: dout <= 'sd393;
        'd493: dout <= -'sd1457;
        'd494: dout <= -'sd2165;
        'd495: dout <= -'sd1956;
        'd496: dout <= -'sd1438;
        'd497: dout <= 'sd1565;
        'd498: dout <= 'sd1365;
        'd499: dout <= 'sd1968;
        'd500: dout <= -'sd814;
        'd501: dout <= -'sd956;
        'd502: dout <= -'sd1120;
        'd503: dout <= 'sd1143;
        'd504: dout <= -'sd224;
        'd505: dout <= -'sd1600;
        'd506: dout <= -'sd2194;
        'd507: dout <= -'sd800;
        'd508: dout <= 'sd689;
        'd509: dout <= 'sd1265;
        'd510: dout <= -'sd1366;
        'd511: dout <= 'sd1545;
      default: dout <= 'sd0;
      endcase
    end
  end





endmodule

*/