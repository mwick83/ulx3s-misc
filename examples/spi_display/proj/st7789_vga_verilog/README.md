# SPI LCD VGA core in VHDL

This VHDL core takes VGA style input
(pixel clock, RGB pixel data, vsync, hsync, blank)
and display it as video on LCD screen.

overscan - runs both VGA and LCD at the same clock domain

VGA generates faster frame rate than SPI can send.
LCD SPI sends pixel by its speed and waits until both 
Y counters from input and output match to update next scanline.
LCD timing is achieved with standard format of VGA timings
by setting large horizontal porch timings (around 1900).

for fast frame updates, VGA generator needs to be slowed down by clk_pixel_ena
otherwise it can work also but screen update will be unacceptably slow (0.5Hz frame rate)

# TODO

diamond reports multiple drivers
