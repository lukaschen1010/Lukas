`timescale 1ns / 1ps

`define ToUART 2'b10
`define ToBRAM 2'b01
`define ToNONE 2'b00

module wb_decode #(
    parameter MPRJ_IO_PADS = 38
    )(
    
    // Wishbone Slave ports
    input         wb_clk_i,
    input         wb_rst_i,
    input         wbs_stb_i,
    input         wbs_cyc_i,
    input         wbs_we_i,
    input  [3:0]  wbs_sel_i,
    input  [31:0] wbs_dat_i,
    input  [31:0] wbs_adr_i,
    output        wbs_ack_o,
    output [31:0] wbs_dat_o,

    // IOs
    input  [MPRJ_IO_PADS-1:0] io_in,
    output [MPRJ_IO_PADS-1:0] io_out,
    output [MPRJ_IO_PADS-1:0] io_oeb,

    // IRQ
    output [2:0] irq
    );

    // 2 paths, UART or user BRAM
    wire        uart_ack_o, bram_ack_o;
    wire [31:0] uart_dat_o, bram_dat_o;
    
    // Decode Wishbone Address
    reg  [1:0]  wb_decode;

    always @* begin
        // First, check if the signal is VALID
        if (wbs_cyc_i && wbs_stb_i)
            // 0x3000_0000: UART 
            if (wbs_adr_i[31:16] == 16'h3000)
                wb_decode = `ToUART;
            // 0x3800_0000: user project area
            else if (wbs_adr_i[31:16] == 16'h3800)
                wb_decode = `ToBRAM;
            else
                wb_decode = `ToNONE;
        else
            wb_decode = `ToNONE;
    end

    assign wbs_ack_o = (wb_decode == `ToUART)? uart_ack_o : (wb_decode == `ToBRAM)? bram_ack_o : 0;
    assign wbs_dat_o = (wb_decode == `ToUART)? uart_dat_o : (wb_decode == `ToBRAM)? bram_dat_o : 0;
    
    uart UART (
        .wb_clk_i  (wb_clk_i),
        .wb_rst_i  (wb_rst_i),
        .wbs_cyc_i (wb_decode[1]), // since ToUART is 2'b10
        .wbs_stb_i (wb_decode[1]),
        .wbs_we_i  (wbs_we_i),
        .wbs_sel_i (wbs_sel_i),
        .wbs_dat_i (wbs_dat_i),
        .wbs_adr_i (wbs_adr_i),
        .wbs_ack_o (uart_ack_o),   // ACK from UART
        .wbs_dat_o (uart_dat_o),   // DATA from UART
        
        .io_in     (io_in),
        .io_out    (io_out),
        .io_oeb    (io_oeb),
        
        .user_irq  (irq)
    );

    exmem EXMEM (
        .wb_clk_i  (wb_clk_i),
        .wb_rst_i  (wb_rst_i),
        .wbs_cyc_i (wb_decode[0]), // since ToBRAM is 2'b01
        .wbs_stb_i (wb_decode[0]),
        .wbs_we_i  (wbs_we_i),
        .wbs_sel_i (wbs_sel_i),
        .wbs_dat_i (wbs_dat_i),
        .wbs_adr_i (wbs_adr_i),
        .wbs_ack_o (bram_ack_o),   // ACK from user BRAM
        .wbs_dat_o (bram_dat_o)    // DATA from user BRAM
    );
    
endmodule
