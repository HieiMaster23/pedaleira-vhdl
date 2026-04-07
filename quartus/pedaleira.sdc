# =============================================================================
# pedaleira.sdc — Restrições de Timing (Synopsys Design Constraints)
# Quartus 13.0 SP1 / Cyclone IV EP4CE6E22C8
# =============================================================================

# Clock principal
create_clock -name clk_50mhz -period 20.000 [get_ports clk_50mhz]

# Clock gerado pelo PLL (MCLK ~12.288 MHz)
# O Quartus reconhece automaticamente saídas de ALTPLL como clocks derivados.
# Se necessário, adicione:
# create_generated_clock -name mclk -source [get_ports clk_50mhz] \
#     -multiply_by 24 -divide_by 98 [get_pins u_pll|altpll_component|auto_generated|pll1|clk[0]]

# Relaxar os paths de I2C (sinais lentos, 100 kHz)
set_false_path -from [get_ports i2c_sdat] -to [all_registers]
set_false_path -from [all_registers] -to [get_ports i2c_sdat]
set_false_path -from [all_registers] -to [get_ports i2c_sclk]

# Relaxar paths de controle (switches, LEDs — sem requisito de timing estrito)
set_false_path -from [get_ports {gain_sw[*] reset_n}]
set_false_path -to   [get_ports {led_config_done led_clipping}]

# Dados de áudio ADC (sincronizados internamente com double-flop)
set_input_delay  -clock clk_50mhz -max 5.0 [get_ports aud_adcdat]
set_input_delay  -clock clk_50mhz -min 0.0 [get_ports aud_adcdat]
set_input_delay  -clock clk_50mhz -max 5.0 [get_ports aud_adclrck]

# Dados de áudio DAC e clocks de saída
set_output_delay -clock clk_50mhz -max 5.0 [get_ports {aud_dacdat aud_bclk aud_daclrck aud_mclk}]
set_output_delay -clock clk_50mhz -min 0.0 [get_ports {aud_dacdat aud_bclk aud_daclrck aud_mclk}]
