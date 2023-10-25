`define ss_done 1'b0
`define ss_idle 1'b1
`define AP_INIT 2'b00
`define AP_IDLE 2'b01
`define AP_DONE 2'b10
`define SM_IDLE 1'b0
`define SM_DONE 1'b1

module fir 
#(  parameter pADDR_WIDTH = 12,
    parameter pDATA_WIDTH = 32,
    parameter Tape_Num    = 11,
    parameter Data_Num    = 600
)
(
    // Axilite
    // write
    output  wire                     awready,   //address write ready
    output  wire                     wready,    // data write ready
    input   wire                     awvalid,   // address write valid
    input   wire [(pADDR_WIDTH-1):0] awaddr,    // write address 
    input   wire                     wvalid,    // write valid
    input   wire [(pDATA_WIDTH-1):0] wdata,     // data

    // read
    output  wire                     arready,
    input   wire                     rready,
    input   wire                     arvalid,
    input   wire [(pADDR_WIDTH-1):0] araddr,
    output  wire                     rvalid,
    output  wire [(pDATA_WIDTH-1):0] rdata,

    // Stream x[n]
    input   wire                     ss_tvalid, 
    input   wire [(pDATA_WIDTH-1):0] ss_tdata, 
    input   wire                     ss_tlast, 
    output  wire                     ss_tready, 

    // Stream y[n]
    input   wire                     sm_tready, 
    output  wire                     sm_tvalid, 
    output  wire [(pDATA_WIDTH-1):0] sm_tdata, 
    output  wire                     sm_tlast, 
    
    // bram for tap RAM
    output  wire [3:0]               tap_WE,
    output  wire                     tap_EN,
    output  wire [(pDATA_WIDTH-1):0] tap_Di,
    output  wire [(pADDR_WIDTH-1):0] tap_A,
    input   wire [(pDATA_WIDTH-1):0] tap_Do,

    // bram for data RAM
    output  wire [3:0]               data_WE,
    output  wire                     data_EN,
    output  wire [(pDATA_WIDTH-1):0] data_Di,
    output  wire [(pADDR_WIDTH-1):0] data_A,
    input   wire [(pDATA_WIDTH-1):0] data_Do,

    input   wire                     axis_clk,
    input   wire                     axis_rst_n
);
// ------ start implement FIR ------ //

// ------ AXI-Lite ------ //
    reg tmp_rvalid;
    
    always @(posedge axis_clk) tmp_rvalid  <= arvalid & arready;

    assign awready = 1'b1;
    assign arready = ~(wvalid ^ awvalid);
    assign wready = 1'b1;
    assign rvalid = tmp_rvalid;
    assign rdata = (araddr [7:0] == 8'd0) ? ap_ctrl : tap_Do;


// --- Configuration --- //
    reg [2:0] ap_ctrl;          // {ap_idle, ap_done, ap_start}
    reg [1:0] ap_state;
    reg [1:0] next_ap_state;
    
    reg [10:0] data_length;
    wire [10:0] data_length_tmp;
    assign data_length_tmp = (awaddr == 32'h0000_0010) ? wdata : data_length; 
    
    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (!axis_rst_n) data_length <= 0;
        else data_length <= data_length_tmp;
    end
    
    always @* begin
        case (ap_state)
            `AP_INIT: begin
                if(awaddr == 12'd0 && wdata[0] == 1 && last_count != data_length) begin // start
                    ap_ctrl = 3'b001;
                    next_ap_state = `AP_IDLE;
                end
                else begin
                    ap_ctrl = 3'b100;
                    next_ap_state = `AP_INIT;
                end
            end
            `AP_IDLE: begin
                if(sm_tlast) begin
                    ap_ctrl = 3'b010;
                    next_ap_state = `AP_DONE;
                end
                else begin
                    ap_ctrl = 3'b000;
                    next_ap_state = `AP_IDLE;
                end
            end
            `AP_DONE: begin
                if (araddr == 12'd0 && arvalid && rvalid) begin
                    ap_ctrl = 3'b010;
                    next_ap_state = `AP_INIT;
                end
                else begin
                    ap_ctrl = 3'b010;
                    next_ap_state = `AP_DONE;
                end
            end
            default: begin
                if(awaddr == 12'd0 && wdata[0] == 1) begin // start
                    ap_ctrl = 3'b001;
                    next_ap_state = `AP_IDLE;
                end
                else begin
                    ap_ctrl = 3'b100;
                    next_ap_state = `AP_INIT;
                end 
            end
        endcase
    end
    
    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (!axis_rst_n) ap_state <= `AP_INIT;
        else ap_state <= next_ap_state;
    end
            
// ------ 0x00-FF tap parameter ------ //
    assign tap_EN = 1;                                              //(((awaddr[31:8] == 0) || (awaddr[31:8] == 0)) && (awaddr[7] ^ araddr[7]));
    assign tap_WE = ((awvalid && wvalid == 1) && (awaddr != 0)) ? 4'b1111 : 4'b0000;
    assign tap_A  = (awvalid == 1)? awaddr[5:0] : tap_AR[5:0];       // write prioirty
    assign tap_Di = wdata;
    
    wire [5:0] tap_AR;
    assign tap_AR = (ap_ctrl[2] == 0) ? 12'h080 + 4 * count : araddr[5:0];

// --- ss_tlast --- //
    reg ss_state;
    reg nxt_ss_state;
    reg ss_idle;

    always @* begin
        case (ss_state)
            `ss_idle:
                if (ss_tlast) begin
                    nxt_ss_state = `ss_done;
                    ss_idle = 1'b1;
                end
                else begin
                    nxt_ss_state = `ss_idle;
                    ss_idle = 1'b1;
                end
            `ss_done: 
                if (ss_tvalid) begin
                    nxt_ss_state = `ss_idle;
                    ss_idle = 1'b1;
                end
                else begin
                    nxt_ss_state = `ss_done;
                    ss_idle = 1'b0;
                end
            default: 
                if (ss_tvalid) begin
                    nxt_ss_state = `ss_idle;
                    ss_idle = 1'b1;
                end
                else begin
                    nxt_ss_state = `ss_done;
                    ss_idle = 1'b0;
                end
        endcase
    end

    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (!axis_rst_n) begin
            ss_state <= `ss_done;
        end 
        else begin
            ss_state <= nxt_ss_state;
        end
    end

    // ------ DRAM ------ //
    assign data_EN = ss_tvalid;
    assign data_Di = ss_tdata;
    assign ss_tready = ((init_cnt != 4'd11) || (count == 4'b0)) ? 1'b1 : 1'b0;
    assign data_WE = (ss_tready & ss_idle) ? 4'b1111 : 4'b0000;

    // ------ Counter signal ------ //
    reg [3:0] count = 4'd10; 
    reg [3:0] count_tmp = 4'b10;
    reg [5:0] val_count = 6'd0 - 6'd15;
    reg [5:0] val_count_tmp = 6'd0 - 6'd15;
    reg [3:0] l = 4'd10;
    reg [3:0] l_tmp = 4'd10;
    reg [3:0] init_cnt = 4'd0;
    reg [3:0] init_cnt_tmp = 4'd0;

    // Init Counter
    always @* begin
        if(ap_ctrl[2] == 1'b1) begin
            if (init_cnt != 4'd11) init_cnt_tmp = init_cnt + 1;
            else init_cnt_tmp = init_cnt;
        end
        else init_cnt_tmp = init_cnt;
    end
    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (!axis_rst_n) init_cnt <= 0;
        else init_cnt <= init_cnt_tmp;
    end

    // ------ Start to use the counter if ap_idle = 0 ------ //
    // counter count
    always @* begin
        if (ap_ctrl[2] != 1) begin
            if (count != 4'd10)
                    count_tmp = count + 1'b1; 
                else
                    count_tmp = 4'd0;
        end
        else count_tmp = count;
    end
    
    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (!axis_rst_n) count <= 4'd10;
        else count <= count_tmp;
    end

    // counter l
    always @* begin
        if (ap_ctrl[2] == 1'b0) begin
            if (count == 4'd10) begin
                if(l != 4'd10) 
                    l_tmp = l + 1'b1;
                else 
                    l_tmp = 4'd0; 
            end
            else begin
                l_tmp = l;
            end
        end
        else begin
            l_tmp = 4'd10;
        end
    end
    
    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (!axis_rst_n) l <= 4'd0;
        else l <= l_tmp;
    end
    

    // valid counter
    always @* begin
        if (ap_ctrl[2] == 1'b0) begin
            if (val_count != 4'd10) begin
                val_count_tmp = val_count + 1'b1; 
            end
            else begin
                val_count_tmp = 6'd0;
            end
        end
        else val_count_tmp = 6'd0 - 6'd15;
    end
    
    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (!axis_rst_n) val_count <= 6'd0 - 6'd15;
        else val_count <= val_count_tmp;
    end

    // ------ Address Generator for DRAM ------ //
    reg [5:0] data_A_tmp;           // temp data address
    reg [5:0] data_A_init;
 
    always @* begin
        if (count <= l) data_A_tmp = 6'd4 * (l - count);
        else data_A_tmp = 6'd4 * (11 + l - count);
    end
    
    always @* begin
        if (init_cnt != 6'd0)
            data_A_init = 6'd4 * init_cnt;
        else 
            data_A_init = 6'd0; 
    end
    
    assign data_A = (ap_ctrl[2] == 0) ? data_A_tmp : data_A_init;

    // ------ MUX for deciding x[n] from FF or BRAM ------ //
    reg x_sel;                      // mux sel 
    wire [31:0] data_ff;             // data from FF
    wire [31:0] data;               // x[n]

    always @* begin
        if (count == 1'b0) begin
            x_sel = 1'b1;
        end
        else begin
            x_sel = 1'b0;
        end
    end

    //always @(posedge axis_clk) begin
    //    data_ff <= ss_tdata;
    //end
    assign data_ff = ss_tdata;
    assign data = (x_sel) ? data_ff : data_Do; 

// ------ Pipeline ------ //

    //wire [(pDATA_WIDTH-1):0] h_tmp; // coefficient
    //wire [(pDATA_WIDTH-1):0] x_tmp; // Data stream-in
       
    wire  [(pDATA_WIDTH-1):0] h;
    wire  [(pDATA_WIDTH-1):0] x;
    
    wire [(pDATA_WIDTH-1):0] m_tmp; // after multi
    reg  [(pDATA_WIDTH-1):0] m; 
    
    wire [(pDATA_WIDTH-1):0] y_tmp; // Y[t] = sigma (h[i] * X[t-i])   
    reg  [(pDATA_WIDTH-1):0] y = 32'd0;     // Data Stream-out
    
    //assign h_tmp = tap_Do;          // h[i]
    assign h = tap_Do;
    assign x = data_Do;            // x[t-i]
    assign m_tmp = h * x;           // h[i] * x[t-i]
    assign y_tmp = (count == 4'd3) ? m : m + y;   
            
    // Operation Pipeline
    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (!axis_rst_n) begin
            //h <= 32'd0;
            //x <= 32'd0;
            m <= 32'd0;
            y <= 32'd0;
        end
        else begin
            //h <= h_tmp;
            //x <= x_tmp;
            m <= m_tmp;
            y <= y_tmp;
        end
    end

// ------ Stream signals for y[n] ------ //
assign sm_tdata = y;
assign sm_tvalid = (val_count == 4'd0)? 1'b1 : 1'b0;

// --- sm_tlast --- //
reg sm_tlast_tmp;
reg [9:0] last_count = 10'd0;
reg [9:0] last_count_tmp = 10'd0;

always @* begin
    if(sm_tvalid)
        last_count_tmp = last_count + 1'b1;
    else 
        last_count_tmp = last_count;
end

always @(posedge axis_clk or negedge axis_rst_n) begin
    if (!axis_rst_n) begin
        last_count <= 10'd0;
    end
    else begin
        last_count <= last_count_tmp;
    end
end

assign sm_tlast = sm_tlast_tmp;

reg sm_state;
reg nxt_sm_state;

always @* begin
    case(sm_state)
    `SM_IDLE: begin
        if (last_count_tmp == data_length) begin
            sm_tlast_tmp = 1'b1;
            nxt_sm_state = `SM_DONE;
        end
        else begin
            sm_tlast_tmp = 1'b0;
            nxt_sm_state = `SM_IDLE;
        end
    end
    `SM_DONE: begin
        if (sm_tvalid == 1'b1) begin
            sm_tlast_tmp = 1'b0;
            nxt_sm_state = `SM_IDLE; 
        end
        else begin
            sm_tlast_tmp = 1'b0;
            nxt_sm_state = `SM_DONE;
        end
    end
    endcase
end
always @(posedge axis_clk or negedge axis_rst_n) begin
    if (!axis_rst_n) sm_state <= 1'b0;
    else sm_state <= nxt_sm_state;
end

endmodule