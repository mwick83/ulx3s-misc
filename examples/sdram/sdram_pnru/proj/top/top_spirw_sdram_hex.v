module top_spirw_sdram_hex
(
  input  wire clk_25mhz,
  input  wire [6:0] btn,
  output wire [7:0] led,

  output wire oled_csn,
  output wire oled_clk,
  output wire oled_mosi,
  output wire oled_dc,
  output wire oled_resn,

  //  SDRAM interface (For use with 16Mx16bit or 32Mx16bit SDR DRAM, depending on version)
  output sdram_csn,       // chip select
  output sdram_clk,       // clock to SDRAM
  output sdram_cke,       // clock enable to SDRAM	
  output sdram_rasn,      // SDRAM RAS
  output sdram_casn,      // SDRAM CAS
  output sdram_wen,       // SDRAM write-enable
  output [12:0] sdram_a,  // SDRAM address bus
  output [1:0] sdram_ba,  // SDRAM bank-address
  output [1:0] sdram_dqm, // byte select
  inout [15:0] sdram_d,   // data bus to/from SDRAM	

  input  wire ftdi_txd,
  output wire ftdi_rxd,

  inout  wire sd_clk, sd_cmd,
  inout  wire [3:0] sd_d, // wifi_gpio4=sd_d[1] wifi_gpio12=sd_d[2]

  input  wire wifi_txd,
  output wire wifi_rxd,
  input  wire wifi_gpio16,
  input  wire wifi_gpio5,
  output wire wifi_gpio0
);
  assign wifi_gpio0 = btn[0];

  // passthru to ESP32 micropython serial console
  assign wifi_rxd = ftdi_txd;
  assign ftdi_rxd = wifi_txd;

  wire locked;
  wire [3:0] clocks;
  ecp5pll
  #(
      .in_hz( 25*1000000),
    .out0_hz(125*1000000),
    .out1_hz(125*1000000), .out1_deg(90) // phase shifted for SDRAM chip
  )
  ecp5pll_inst
  (
    .clk_i(clk_25mhz),
    .clk_o(clocks),
    .locked(locked)
  );
  wire clk_sdram   = clocks[0];
  wire clk         = clocks[0];
  assign sdram_clk = clocks[1];
  assign sdram_cke = 1'b1;

  assign sd_d[3] = 1'bz; // FPGA pin pullup sets SD card inactive at SPI bus
  
  wire spi_cs = wifi_gpio5;
  wire spi_csn = ~wifi_gpio5; // LED is used as SPI CS

  wire spi_ram_rd, spi_ram_wr;
  wire [31:0] spi_ram_addr;
  wire  [7:0] spi_ram_di;
  wire  [7:0] spi_ram_do;
  wire [15:0] ram_do;
  spirw_slave_v
  #(
    .c_addr_bits(32),
    .c_sclk_capable_pin(1'b0)
  )
  spirw_slave_v_inst
  (
    .clk(clk_sdram), // clk will work too
    .csn(spi_csn),
    .sclk(wifi_gpio16),
    .mosi(sd_d[1]), // wifi_gpio4
    .miso(sd_d[2]), // wifi_gpio12
    .rd(spi_ram_rd),
    .wr(spi_ram_wr),
    .addr(spi_ram_addr),
    .data_in(spi_ram_addr[0] ? ram_do[7:0] : ram_do[15:8]),
    .data_out(spi_ram_do)
  );

  reg [7:0] R_cpu_control;
  // SPI 8-bit to 16-bit conversion
  reg [7:0] R_spi_ram_byte[0:1];
  reg R_spi_ram_wr;
  reg spi_ram_word_wr;
  always @(posedge clk_sdram)
  begin
    R_spi_ram_wr <= spi_ram_wr;
    if(spi_ram_wr == 1'b1)
    begin
      if(spi_ram_addr[31:24] == 8'hFF)
	R_cpu_control <= spi_ram_do;
      else
	R_spi_ram_byte[spi_ram_addr[0]] <= spi_ram_do;
      if(R_spi_ram_wr == 1'b0)
      begin
        if(spi_ram_addr[31:24] == 8'h00 && spi_ram_addr[0] == 1'b1)
          spi_ram_word_wr <= 1'b1;
      end
    end
    else
    begin
      spi_ram_word_wr <= 1'b0;
    end
  end
  wire [15:0] ram_di = { R_spi_ram_byte[0], R_spi_ram_byte[1] };


  wire ram_rdy;
  wire ram_ack = ~(spi_ram_rd|spi_ram_word_wr);
  wire ram_rd = spi_ram_addr[31:24] == 8'h00 ? spi_ram_rd : 1'b0;
  sdram_pnru
  sdram_pnru_inst
  (
    .sys_clk(clk_sdram),
    .sys_rd(ram_rd),
    .sys_wr(spi_ram_word_wr),
    .sys_ab(spi_ram_addr[23:1]),
    .sys_di(ram_di),
    .sys_do(ram_do),
    .sys_ack(ram_ack),
    .sys_rdy(ram_rdy),

    .sdr_ab(sdram_a),
    .sdr_db(sdram_d),
    .sdr_ba(sdram_ba),
    .sdr_n_CS_WE_RAS_CAS({sdram_csn, sdram_wen, sdram_rasn, sdram_casn}),
    .sdr_dqm(sdram_dqm)
  );
  /*
  // this doesn't work properly
  sdram_pnru2
  sdram_pnru2_inst
  (
    .sys_clk(clk_sdram),
    .sys_cs(spi_cs),
    .sys_rd(ram_rd),
    .sys_wr(ram_wr),
    .sys_ab(ram_addr),
    .sys_di({ram_di[7:0],ram_di[7:0]}),
    .sys_do(ram_do),
    .sys_rdy(ram_rdy),

    .sdr_ab(sdram_a),
    .sdr_db(sdram_d),
    .sdr_ba(sdram_ba),
    .sdr_cmd({sdram_csn, sdram_wen, sdram_rasn, sdram_casn}),
    .sdr_dqm(sdram_dqm)
  );
  */
  assign led[0] = ram_rd;
  assign led[1] = ram_wr;
  assign led[5:2] = 0;
  assign led[6] = ram_rdy;
  assign led[7] = |ram_do;

  localparam C_color_bits   = 16; 
  localparam C_display_bits = 128;
  reg [C_display_bits-1:0] R_display;
  always @(posedge clk)
  begin
    R_display[23:0] <= ram_addr;
    R_display[39:24] <= ram_do;
    R_display[55:40] <= ram_di;
    R_display[15+64:0+64] <= sdram_a;
  end

  wire [7:0] x;
  wire [7:0] y;
  // for reverse screen:
  //wire [7:0] ry = 239-y;
  wire [C_color_bits-1:0] color;
  hex_decoder_v
  #(
    .c_data_len(128),
    .c_row_bits(4),
    .c_grid_6x8(1), // NOTE: TRELLIS needs -abc9 option to compile
    .c_font_file("hex_font.mem"),
    .c_color_bits(C_color_bits)
  )
  hex_decoder_v_inst
  (
    .clk(clk),
    .data(R_display),
    .x(x[7:1]),
    .y(y[7:1]),
    .color(color)
  );

  // allow large combinatorial logic
  // to calculate color(x,y)
  wire next_pixel;
  reg [C_color_bits-1:0] R_color;
  always @(posedge clk)
    if(next_pixel)
      R_color <= color;

  wire w_oled_csn;
  lcd_video
  #(
    .c_clk_mhz(125),
    .c_init_file("st7789_linit_xflip.mem"),
    .c_clk_phase(0),
    .c_clk_polarity(1),
    .c_init_size(38)
  )
  lcd_video_inst
  (
    .clk(clk),
    .reset(~btn[0]),
    .x(x),
    .y(y),
    .next_pixel(next_pixel),
    .color(R_color),
    .spi_clk(oled_clk),
    .spi_mosi(oled_mosi),
    .spi_dc(oled_dc),
    .spi_resn(oled_resn),
    .spi_csn(w_oled_csn)
  );
  assign oled_csn = 1'b1; // 7-pin ST7789: oled_csn is connected to BLK (backlight enable pin)
  //assign oled_csn = w_oled_csn; // 8-pin ST7789: oled_csn is connected to CSn

endmodule
