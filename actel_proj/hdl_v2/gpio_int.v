module gpio_int(clk, reset, GPIO, gpio_level, gpio_direction, sl_data, sl_arb_request, sl_arb_grant, sl_data_latch, global_counter, incr_ctr);
parameter GPIO_WIDTH=24;

input clk;
input reset;

inout [GPIO_WIDTH-1:0] GPIO;
input [GPIO_WIDTH-1:0] gpio_level;
input [GPIO_WIDTH-1:0] gpio_direction;

//Slave output bus
inout [7:0] sl_data;
output sl_arb_request;
input sl_arb_grant;
input sl_data_latch;

//Global counter for 'time-tagging'
input [7:0] global_counter;
output reg incr_ctr;

reg frame_req;
reg [7:0] frame_data;
wire data_latch;
wire [7:0] local_sl_data;
message_fifo #(9,0) mf1(
	.clk(clk),
	.rst(reset),
	.in_data(frame_data),
	.in_data_latch(data_latch),
	.in_frame_valid(frame_req),
	.in_data_overflow(),//TODO: No assignment to this for now (nothing we can really do about it since there's no back-pressure!)
	.populate_frame_length(1'b1),
	.out_data(local_sl_data),
	.out_frame_valid(sl_arb_request),
	.out_data_latch(sl_data_latch & sl_arb_grant)
);
assign sl_data = (sl_arb_grant) ? local_sl_data : 8'bzzzzzzzz;

//Logic to drive GPIOs using user-selected values (only if requested)
genvar ii;
generate
	for(ii = 0; ii < GPIO_WIDTH; ii=ii+1) begin
		assign GPIO[ii] = (gpio_direction[ii]) ? gpio_level[ii] : 1'bz;
	end
endgenerate

parameter STATE_IDLE = 0;
parameter STATE_MESSAGE0 = 1;
parameter STATE_MESSAGE1 = 2;
parameter STATE_MESSAGE2 = 3;
parameter STATE_MESSAGE3 = 4;
parameter STATE_MESSAGE4 = 5;

reg [3:0] state, next_state;
reg latch_gpio_levels, gpio_has_changed;
reg drive_id, drive_gcount, drive_len, drive_param, drive_latched_data;
assign data_latch = drive_id | drive_gcount | drive_len | drive_param | drive_latched_data;
reg [1:0] drive_ctr;
always @* begin
	next_state = state;
	latch_gpio_levels = 1'b0;
	frame_req = 1'b1;
	drive_id = 1'b0;
	drive_len = 1'b0;
	drive_param = 1'b0;
	drive_gcount = 1'b0;
	drive_latched_data = 1'b0;
	incr_ctr = 1'b0;
	
	case(state)
		STATE_IDLE: begin
			frame_req = 1'b0;
			latch_gpio_levels = 1'b1;
			if(gpio_has_changed)
				next_state = STATE_MESSAGE0;
		end
		
		STATE_MESSAGE0: begin
			drive_id = 1'b1;
			next_state = STATE_MESSAGE1;
		end
		
		STATE_MESSAGE1: begin
			drive_gcount = 1'b1;
			incr_ctr = 1'b1;
			next_state = STATE_MESSAGE2;
		end
		
		STATE_MESSAGE2: begin
			drive_len = 1'b1;
			next_state = STATE_MESSAGE3;
		end
		
		STATE_MESSAGE3: begin
			drive_param = 1'b1;
			next_state = STATE_MESSAGE4;
		end
		
		STATE_MESSAGE4: begin
			drive_latched_data = 1'b1;
			if(drive_ctr == 2)
				next_state = STATE_IDLE;
		end
	endcase
end

//Monitor for any changes to the un-driven bits
reg [GPIO_WIDTH-1:0] last_gpio_levels, last_gpio_levels_db;
integer jj;
always @* begin
	gpio_has_changed = 1'b0;
	for(jj = 0; jj < GPIO_WIDTH; jj = jj + 1) begin
		if(~gpio_direction[jj]) begin
			if(last_gpio_levels[jj] ^ last_gpio_levels_db[jj])
				gpio_has_changed = 1'b1;
		end
	end
	
	frame_data = 8'h67;
	if(drive_gcount) frame_data = global_counter;
	else if(drive_param) frame_data = 8'h6c;
	else if(drive_latched_data) begin
		if(drive_ctr == 0)
			frame_data = last_gpio_levels[23:16];
		else if(drive_ctr == 1)
			frame_data = last_gpio_levels[15:8];
		else
			frame_data = last_gpio_levels[7:0];
	end
end

always @(posedge clk) begin
	//The latch_gpio_levels keeps track of the last-communicated GPIO levels for the analysis of any changes
	//TODO: Probably needs this debouncing logic, eh?
	if(latch_gpio_levels) begin
		last_gpio_levels_db <= GPIO;
		last_gpio_levels <= last_gpio_levels_db;
	end
	
	if(drive_latched_data)
		drive_ctr <= drive_ctr + 1;
	else
		drive_ctr <= 0;

	if(reset) begin
		state <= STATE_IDLE;
	end else begin
		state <= next_state;
	end
end

endmodule