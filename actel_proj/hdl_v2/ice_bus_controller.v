module ice_bus_controller(
	input clk,
	input rst,
	
	//Interface to UART (or other character device)
	input [7:0] rx_char,
	input rx_char_valid,
	output [7:0] tx_char,
	output tx_char_valid,
	input tx_char_ready,

	//Immediate NAKs have their own controller =)
	output reg generate_nak,
	output reg [7:0] evt_id,
	
	//Master-driven bus (data & control)
	output [7:0] ma_data,
	output [7:0] ma_addr,
	output ma_data_valid,
	output ma_frame_valid,
	input sl_overflow,
	
	//Bus controller outputs (data & control)
	input [7:0] sl_data,
	input sl_arb_request,
	output sl_arb_grant,
	output sl_data_latch
);
parameter NUM_DEV=2;

wire [NUM_DEV-1:0] sl_arb_grant, sl_arb_request;

wire pri_en, pri_granted;
reg pri_latch;
priority_select #(NUM_DEV) pri1(
	.clk(clk),
	.rst(rst),
	.enable(pri_en),
	.latch(pri_latch),
	
	.requests(sl_arb_request),
	.grants(sl_arb_grant),
	.granted(pri_granted)
);

reg record_addr, record_evt_id;
reg next_frame_valid;
reg [15:0] byte_counter;
reg [15:0] payload_len;

//Bus controller RX state machine
parameter STATE_RX_IDLE = 0;
parameter STATE_RX_ID = 1;
parameter STATE_RX_LEN = 2;
parameter STATE_RX_PYLD = 3;
parameter STATE_RX_OVERFLOW = 4;

always @* begin
	next_state = state;
	record_addr = 1'b0;
	record_evt_id = 1'b0;
	byte_counter_incr = 1'b0;
	byte_counter_decr = 1'b0;
	byte_counter_reset = 1'b0;
	shift_in_pyld_len = 1'b0;
	ma_data_valid = 1'b0;
	ma_frame_valid = 1'b0;
	set_byte_counter = 1'b0;
	
	case(rx_state)
		STATE_RX_IDLE: begin
			record_addr = 1'b1;
			byte_counter_reset = 1'b1;
			if(rx_char_vaild)
				next_state = STATE_RX_ID;
		end
		
		STATE_RX_ID: begin
			ma_frame_valid = rx_char_valid;
			record_evt_id = 1'b1;
			if(rx_char_valid)
				next_state = STATE_RX_LEN;
		end
		
		STATE_RX_LEN: begin
			ma_frame_valid = 1'b1;
			byte_counter_incr = rx_char_valid;
			shift_in_pyld_len = rx_char_valid;
			if(byte_counter[1:0] == 2'd2) begin
				byte_counter_reset = 1'b1;
				next_state = STATE_RX_PYLD;
			end
		end
		
		STATE_RX_PYLD: begin
			ma_frame_valid = 1'b1;
			ma_data_valid = rx_char_valid;
			byte_counter_incr = rx_char_valid;
			if(byte_counter == payload_len)
				next_state = STATE_RX_IDLE;
			else if(sl_overflow)
				next_state = STATE_RX_OVERFLOW;
		end
		
		STATE_RX_OVERFLOW: begin
			generate_nak = 1'b1;
			next_state = STATE_RX_IDLE;
		end
	endcase
end

always @(posedge clk) begin
	if(shift_in_pyld_len)
		payload_len <= {payload_len[7:0], rx_char};
	if(record_addr)
		ma_addr <= rx_char;
	if(record_evt_id)
		evt_id <= rx_char;

	if(rst) begin
		state <= STATE_IDLE;
		byte_counter <= 16'd0;
	end else begin
			
		//Byte counter keeps track of packets up to 65535 bytes in size
		if(byte_counter_reset)
			byte_counter <= 16'd0;
		else if(byte_counter_incr)
			byte_counter <= byte_counter + 16'd1;
	end
end

//TX state machine... (though it doesn't seem to really be a state machine at the moment...)
//Luckily, this is extremely easy to take care of
assign tx_char = sl_data;
assign tx_char_valid = tx_char_ready & pri_granted;
assign pri_latch = ~pri_granted;
assign pri_en = 1'b1;

endmodule