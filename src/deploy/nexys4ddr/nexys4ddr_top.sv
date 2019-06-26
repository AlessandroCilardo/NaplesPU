`timescale 1ns / 1ps

module nexys4ddr_top #(
	parameter BAUD_RATE   = 9600
	) (
		input  clk,
		input  reset_n,

		input  uart_rx,
		output uart_tx,

		inout [15:0]  ddr2_dq,
		inout [1:0]   ddr2_dqs_n,
		inout [1:0]   ddr2_dqs_p,

		// Outputs
		output [12:0] ddr2_addr,
		output [2:0]  ddr2_ba,
		output        ddr2_ras_n,
		output        ddr2_cas_n,
		output        ddr2_we_n,

		output [0:0]  ddr2_ck_p,
		output [0:0]  ddr2_ck_n,
		output [0:0]  ddr2_cke,
		output [0:0]  ddr2_cs_n,

		output [1:0]  ddr2_dm,

		output [0:0]  ddr2_odt,

		output logic  led,
		output logic  ddr_calib_done,
		output logic  uart_overrun,
		output logic  uart_frame_error,
		output logic  reset_out
	);

	localparam UART_CLK = 32'd50_000_000;

	logic reset, locked, async_reset;
	logic mig_ui_clk, mig_ui_reset;
	logic mig_ref_clk;
	logic nup_clk;

	clk_wiz_0 u_clk_gen (
		// Clock out ports
		.clk_out1           ( mig_ref_clk ),
		// Status and control signals
		.reset              ( reset       ),
		.locked             ( locked      ),
		// Clock in ports
		.clk_in1            ( clk         )
	);

	assign nup_clk = mig_ui_clk;

	assign reset = ~reset_n;
	assign async_reset = reset | ~locked | ~mmcm_locked;

	logic       uart_ready_out;
	logic [7:0] uart_char_tx, uart_char_rx;

	// Tx serializer
	logic [1:0] tx_cnt;
	logic uart_router_command_consumed, router_uart_command_valid;
	logic [31:0] router_uart_command_word;

	assign uart_char_tx = router_uart_command_word[tx_cnt * 8 +: 8];

	always_ff @(posedge mig_ui_clk) begin
		if (async_reset) begin
			tx_cnt <= 2'd0;
		end else begin
			if (router_uart_command_valid & uart_ready_out)
				tx_cnt <= tx_cnt + 2'd1;
		end
	end

	assign uart_router_command_consumed = (tx_cnt == 2'd3) & uart_ready_out;

	// Rx deserializer
	logic        uart_rx_fifo_empty, uart_char_out_valid, uart_read_en;
	logic [31:0] uart_router_command_word;
	logic        uart_router_command_valid, router_uart_command_consumed;
	logic  [2:0] rx_cnt;

	assign uart_char_out_valid = ~uart_rx_fifo_empty;
	assign uart_router_command_valid = rx_cnt == 3'd4;
	assign uart_read_en = uart_char_out_valid & rx_cnt != 3'd4;

	always_ff @(posedge mig_ui_clk) begin
		if (async_reset) begin
			rx_cnt <= 3'd0;
		end else begin
			if (rx_cnt < 3'd4 & uart_char_out_valid) begin
				rx_cnt <= rx_cnt + 3'd1;
			end else if (rx_cnt == 3'd4 & router_uart_command_consumed) begin
				rx_cnt <= 3'd0;
			end

			if (rx_cnt < 3'd4 & uart_char_out_valid)
				uart_router_command_word[rx_cnt * 8 +: 8] <= uart_char_rx;
		end
	end

	uart u_uart (
		.clk(mig_ui_clk),
		.reset(async_reset),

		.divisor_set(1'b1),
		.divisor_reg(UART_CLK / BAUD_RATE),

		.tx_en_in(router_uart_command_valid & uart_ready_out),
		.tx_char_in(uart_char_tx),
		.tx_ready_out(uart_ready_out),

		.rx_fifo_read_in(uart_read_en),
		.rx_fifo_frame_error_out(uart_trigger_frame_error),
		.rx_fifo_empty_out(uart_rx_fifo_empty),
		.rx_fifo_overrun_out(uart_trigger_overrun),
		.rx_fifo_char_out(uart_char_rx),

		.uart_tx(uart_tx),
		.uart_rx(uart_rx)
	);

	logic [31:0] router_mc_command_word;
	logic        router_mc_command_valid, mc_router_command_consumed;
	logic [31:0] mc_router_command_word;
	logic        mc_router_command_valid, router_mc_command_consumed;

	logic [31:0] router_acc_command_word;
	logic        router_acc_command_valid, acc_router_command_consumed;
	logic [31:0] acc_router_command_word;
	logic        acc_router_command_valid, router_acc_command_consumed;

	uart_router u_uart_router (
		.clk             ( mig_ui_clk                   ),
		.reset           ( async_reset                  ),

		.command_valid_i ( uart_router_command_valid    ),
		.command_word_i  ( uart_router_command_word     ),
		.command_ready_o ( router_uart_command_consumed ),

		.command_valid_o ( router_uart_command_valid    ),
		.command_word_o  ( router_uart_command_word     ),
		.command_ready_i ( uart_router_command_consumed ),

		.port_0_word_o   ( router_mc_command_word       ),
		.port_0_valid_o  ( router_mc_command_valid      ),
		.port_0_ready_i  ( mc_router_command_consumed   ),

		.port_0_word_i   ( mc_router_command_word       ),
		.port_0_valid_i  ( mc_router_command_valid      ),
		.port_0_ready_o  ( router_mc_command_consumed   ),

		.port_1_word_o   ( router_acc_command_word      ),
		.port_1_valid_o  ( router_acc_command_valid     ),
		.port_1_ready_i  ( acc_router_command_consumed  ),

		.port_1_word_i   ( acc_router_command_word      ),
		.port_1_valid_i  ( acc_router_command_valid     ),
		.port_1_ready_o  ( router_acc_command_consumed  )
	);

	logic           mem2acc_response_valid;
	logic [31 : 0]  mem2acc_response_address;
	logic [511 : 0] mem2acc_response_data;
	logic           acc_available;

	logic [31 : 0]  acc2mem_request_address;
	logic [63 : 0]  acc2mem_request_dirty_mask;
	logic [511 : 0] acc2mem_request_data;
	logic           acc2mem_request_read;
	logic           acc2mem_request_write;
	logic           mem_request_available;

//	dummy_acc u_dummy_acc (
//		.clk             ( mig_ui_clk                   ),
//		.reset           ( async_reset                  ),
//
//		.command_valid_i ( router_acc_command_valid    ),
//		.command_word_i  ( router_acc_command_word     ),
//		.command_ready_o ( acc_router_command_consumed ),
//
//		.command_word_o  ( acc_router_command_word     ),
//		.command_valid_o ( acc_router_command_valid    ),
//		.command_ready_i ( router_acc_command_consumed ),
//
//		.mem2acc_response_valid     ( mem2acc_response_valid     ),
//		.mem2acc_response_address   ( mem2acc_response_address   ),
//		.mem2acc_response_data      ( mem2acc_response_data      ),
//		.acc_available              ( acc_available              ),
//
//		.acc2mem_request_address    ( acc2mem_request_address    ),
//		.acc2mem_request_dirty_mask ( acc2mem_request_dirty_mask ),
//		.acc2mem_request_data       ( acc2mem_request_data       ),
//		.acc2mem_request_read       ( acc2mem_request_read       ),
//		.acc2mem_request_write      ( acc2mem_request_write      ),
//		.mem_request_available      ( mem_request_available      )
//	);

	npu_system u_npu_system (
		.clk                       ( mig_ui_clk                 ),
		.reset                     ( async_reset                ),
		.hi_thread_en              (                            ),
		.mem2nup_request_available ( mem_request_available      ),
		.mem2nup_response_valid    ( mem2acc_response_valid     ),
		.mem2nup_response_address  ( mem2acc_response_address   ),
		.mem2nup_response_data     ( mem2acc_response_data      ),
		.nup2mem_request_address   ( acc2mem_request_address    ),
		.nup2mem_request_dirty_mask( acc2mem_request_dirty_mask ),
		.nup2mem_request_data      ( acc2mem_request_data       ),
		.nup2mem_request_read      ( acc2mem_request_read       ),
		.nup2mem_request_write     ( acc2mem_request_write      ),
		.nup_available             ( acc_available              ),
		.item_data_i               ( router_acc_command_word    ),
		.item_valid_i              ( router_acc_command_valid   ),
		.item_avail_o              ( acc_router_command_consumed ),
		.item_data_o               ( acc_router_command_word    ),
		.item_valid_o              ( acc_router_command_valid   ),
		.item_avail_i              ( router_acc_command_consumed )
	);

	logic        mc_axi_awready;
	logic [3:0]  mc_axi_awid;
	logic [31:0] mc_axi_awaddr;
	logic [7:0]  mc_axi_awlen;
	logic [2:0]  mc_axi_awsize;
	logic [1:0]  mc_axi_awburst;
	logic [1:0]  mc_axi_awlock;
	logic [3:0]  mc_axi_awcache;
	logic [3:0]  mc_axi_awqos;
	logic [3:0]  mc_axi_awregion;
	logic [2:0]  mc_axi_awprot;
	logic        mc_axi_awvalid;

	logic        mc_axi_wready;
	logic [3:0]  mc_axi_wid;
	logic [31:0] mc_axi_wdata;
	logic [3:0]  mc_axi_wstrb;
	logic        mc_axi_wlast;
	logic        mc_axi_wvalid;

	logic [3:0]  mc_axi_bid;
	logic [1:0]  mc_axi_bresp;
	logic        mc_axi_bvalid;
	logic        mc_axi_bready;

	logic        mc_axi_arready;
	logic [3:0]  mc_axi_arid;
	logic [31:0] mc_axi_araddr;
	logic [7:0]  mc_axi_arlen;
	logic [2:0]  mc_axi_arsize;
	logic [1:0]  mc_axi_arburst;
	logic [1:0]  mc_axi_arlock;
	logic [3:0]  mc_axi_arcache;
	logic [3:0]  mc_axi_arqos;
	logic [3:0]  mc_axi_arregion;
	logic [2:0]  mc_axi_arprot;
	logic        mc_axi_arvalid;

	logic [3:0]  mc_axi_rid;
	logic [1:0]  mc_axi_rresp;
	logic        mc_axi_rvalid;
	logic [31:0] mc_axi_rdata;
	logic        mc_axi_rlast;
	logic        mc_axi_rready;

	memory_controller u_memory_controller (
		.clk(mig_ui_clk),
		.reset(async_reset),

		.command_valid_i        (router_mc_command_valid),
		.command_word_i         (router_mc_command_word),
		.command_ready_o        (mc_router_command_consumed),

		.command_valid_o        (mc_router_command_valid),
		.command_word_o         (mc_router_command_word),
		.command_ready_i        (router_mc_command_consumed),

		.blk_request_address    (acc2mem_request_address),
		.blk_request_dirty_mask (acc2mem_request_dirty_mask),
		.blk_request_data       (acc2mem_request_data),
		.blk_request_read       (acc2mem_request_read),
		.blk_request_write      (acc2mem_request_write),
		.mc_available           (mem_request_available),

		.mc_response_valid      (mem2acc_response_valid),
		.mc_response_address    (mem2acc_response_address),
		.mc_response_data       (mem2acc_response_data),
		.blk_available          (acc_available),

		.axi_awready(mc_axi_awready),
		.axi_awid(mc_axi_awid),
		.axi_awaddr(mc_axi_awaddr),
		.axi_awlen(mc_axi_awlen),
		.axi_awsize(mc_axi_awsize),
		.axi_awburst(mc_axi_awburst),
		.axi_awlock(mc_axi_awlock),
		.axi_awcache(mc_axi_awcache),
		.axi_awqos(mc_axi_awqos),
		.axi_awregion(mc_axi_awregion),
		.axi_awprot(mc_axi_awprot),
		.axi_awvalid(mc_axi_awvalid),

		.axi_wready(mc_axi_wready),
		.axi_wid(mc_axi_wid),
		.axi_wdata(mc_axi_wdata),
		.axi_wstrb(mc_axi_wstrb),
		.axi_wlast(mc_axi_wlast),
		.axi_wvalid(mc_axi_wvalid),

		.axi_bid(mc_axi_bid),
		.axi_bresp(mc_axi_bresp),
		.axi_bvalid(mc_axi_bvalid),
		.axi_bready(mc_axi_bready),

		.axi_arready(mc_axi_arready),
		.axi_arid(mc_axi_arid),
		.axi_araddr(mc_axi_araddr),
		.axi_arlen(mc_axi_arlen),
		.axi_arsize(mc_axi_arsize),
		.axi_arburst(mc_axi_arburst),
		.axi_arlock(mc_axi_arlock),
		.axi_arcache(mc_axi_arcache),
		.axi_arqos(mc_axi_arqos),
		.axi_arregion(mc_axi_arregion),
		.axi_arprot(mc_axi_arprot),
		.axi_arvalid(mc_axi_arvalid),

		.axi_rid(mc_axi_rid),
		.axi_rresp(mc_axi_rresp),
		.axi_rvalid(mc_axi_rvalid),
		.axi_rdata(mc_axi_rdata),
		.axi_rlast(mc_axi_rlast),
		.axi_rready(mc_axi_rready)
	);

	mig_7series_0 u_mig_7series_0 (
		// Memory interface ports
		.ddr2_addr                      (ddr2_addr),
		.ddr2_ba                        (ddr2_ba),
		.ddr2_cas_n                     (ddr2_cas_n),
		.ddr2_ck_n                      (ddr2_ck_n),
		.ddr2_ck_p                      (ddr2_ck_p),
		.ddr2_cke                       (ddr2_cke),
		.ddr2_ras_n                     (ddr2_ras_n),
		.ddr2_we_n                      (ddr2_we_n),
		.ddr2_dq                        (ddr2_dq),
		.ddr2_dqs_n                     (ddr2_dqs_n),
		.ddr2_dqs_p                     (ddr2_dqs_p),

		.init_calib_complete            (ddr_calib_done),

		.ddr2_cs_n                      (ddr2_cs_n),
		.ddr2_dm                        (ddr2_dm),
		.ddr2_odt                       (ddr2_odt),

		// Application interface ports
		.ui_clk                         (mig_ui_clk),
		.ui_clk_sync_rst                (mig_ui_reset),

		.mmcm_locked                    (mmcm_locked),
		.aresetn                        (~mig_ui_reset),
		.app_sr_req                     (1'b0),
		.app_ref_req                    (1'b0),
		.app_zq_req                     (1'b0),
		.app_sr_active                  (app_sr_active),
		.app_ref_ack                    (app_ref_ack),
		.app_zq_ack                     (app_zq_ack),

		.s_axi_awaddr(mc_axi_awaddr),
		.s_axi_awprot(mc_axi_awprot),
		.s_axi_awvalid(mc_axi_awvalid),
		.s_axi_awready(mc_axi_awready),
		.s_axi_awsize(mc_axi_awsize),
		.s_axi_awburst(mc_axi_awburst),
		.s_axi_awcache(mc_axi_awcache),
		.s_axi_awlen(mc_axi_awlen),
		.s_axi_awlock(mc_axi_awlock),
		.s_axi_awqos(mc_axi_awqos),
		.s_axi_awid(mc_axi_awid),
		/**************** Write Data Channel Signals ****************/
		.s_axi_wdata(mc_axi_wdata),
		.s_axi_wstrb(mc_axi_wstrb),
		.s_axi_wvalid(mc_axi_wvalid),
		.s_axi_wready(mc_axi_wready),
		.s_axi_wlast(mc_axi_wlast),
		/**************** Write Response Channel Signals ****************/
		.s_axi_bresp(mc_axi_bresp),
		.s_axi_bvalid(mc_axi_bvalid),
		.s_axi_bready(mc_axi_bready),
		.s_axi_bid(mc_axi_bid),

		/**************** Read Address Channel Signals ****************/
		.s_axi_araddr(mc_axi_araddr),
		.s_axi_arprot(mc_axi_arprot),
		.s_axi_arvalid(mc_axi_arvalid),
		.s_axi_arready(mc_axi_arready),
		.s_axi_arsize(mc_axi_arsize),
		.s_axi_arburst(mc_axi_arburst),
		.s_axi_arcache(mc_axi_arcache),
		.s_axi_arlock(mc_axi_arlock),
		.s_axi_arlen(mc_axi_arlen),
		.s_axi_arqos(mc_axi_arqos),
		.s_axi_arid(mc_axi_arid),
		/**************** Read Data Channel Signals ****************/
		.s_axi_rdata(mc_axi_rdata),
		.s_axi_rresp(mc_axi_rresp),
		.s_axi_rvalid(mc_axi_rvalid),
		.s_axi_rready(mc_axi_rready),
		.s_axi_rlast(mc_axi_rlast),
		.s_axi_rid(mc_axi_rid),

		// System Clock Ports
		.sys_clk_i                      (mig_ref_clk),
		.sys_rst                        (reset | ~locked)
	);

	reg [24:0] count = 0;

	assign led = count[24];

	always_ff @ (posedge(clk)) count <= count + 1;

	always_ff @(posedge mig_ui_clk) begin
		if (async_reset) begin
			uart_overrun       <= 1'b0;
			uart_frame_error   <= 1'b0;
		end else begin
			if (uart_trigger_overrun)
				uart_overrun     <= 1'b1;

			if (uart_trigger_frame_error)
				uart_frame_error <= 1'b1;
		end
	end

	assign reset_out = async_reset;

endmodule
