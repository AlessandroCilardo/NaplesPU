`timescale 1ns / 1ps
module serializer# (
		parameter REG_SIZE = 32)
	(
		input                       clk,
		input                       reset,
		input        [REG_SIZE-1:0] data_in,
		input                       start_shift,
		input                       load,
		output logic                data_out,
		output logic				stop_shift
	) ;

	logic            [$clog2 (REG_SIZE) : 0]    cnt;
	logic            [REG_SIZE-1:0]             reg_temp;

	always_ff @ ( posedge clk, posedge reset ) begin
		if ( reset ) begin
			reg_temp   <= {REG_SIZE{1'b0}};
			cnt        <= {$clog2(REG_SIZE){1'b0}};
			stop_shift <= 1'b0;
			data_out   <= {REG_SIZE{1'b0}};
		end else if (load) begin
			reg_temp   <= data_in;
			cnt        <= {$clog2(REG_SIZE){1'b0}};
			stop_shift <= 1'b0;
			data_out   <= {REG_SIZE{1'b0}};
		end else begin
			if (cnt != REG_SIZE) begin
				if (start_shift) begin
					data_out   <= reg_temp[REG_SIZE-1];
					reg_temp   <= {reg_temp[REG_SIZE-2:0],1'b0};
					cnt        <= cnt + 1'b1;
				end else
					stop_shift <= 1'b0;
			end else begin
				cnt        <= {$clog2(REG_SIZE){1'b0}};
				stop_shift <= 1'b1;
			end
		end
	end
endmodule
