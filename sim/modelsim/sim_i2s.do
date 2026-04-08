# =============================================================================
# sim_i2s.do
# Compila e executa o testbench de loopback I2S (TX → RX).
#
# Como usar:
#   do sim_i2s.do
#
# O que verificar:
#   - Waveform: serial_dat (dacdat→adcdat) variando conforme as amostras
#   - lrck alterna a cada 32 BCLKs (canal LEFT/RIGHT)
#   - rx_left / rx_right recebem exatamente os valores injetados
#   - rx_valid pulsa 1 vez por frame I2S
#   - Mensagens [PASS] para as 4 amostras de teste
# =============================================================================

do compile_all.do

echo "=== Iniciando simulacao: tb_i2s_loopback ==="

vsim -t 1ns -novopt work.tb_i2s_loopback

add wave -divider "=== CONTROLE ==="
add wave -radix binary /tb_i2s_loopback/reset_n
add wave -radix hex    /tb_i2s_loopback/tx_left
add wave -radix hex    /tb_i2s_loopback/tx_right
add wave -radix binary /tb_i2s_loopback/tx_valid

add wave -divider "=== BARRAMENTO I2S (TX saidas) ==="
add wave -radix binary /tb_i2s_loopback/bclk
add wave -radix binary /tb_i2s_loopback/lrck
add wave -radix binary /tb_i2s_loopback/serial_dat

add wave -divider "=== RECEPTOR (RX saidas) ==="
add wave -radix hex    /tb_i2s_loopback/rx_left
add wave -radix hex    /tb_i2s_loopback/rx_right
add wave -radix binary /tb_i2s_loopback/rx_valid

add wave -divider "=== CLOCKS ==="
add wave -radix binary /tb_i2s_loopback/clk
add wave -radix binary /tb_i2s_loopback/mclk

configure wave -namecolwidth 220
configure wave -valuecolwidth 100

run -all
wave zoom full

echo "=== Simulacao tb_i2s_loopback concluida ==="
