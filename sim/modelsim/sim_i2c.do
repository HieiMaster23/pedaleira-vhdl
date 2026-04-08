# =============================================================================
# sim_i2c.do
# Compila e executa o testbench do módulo i2c_master.
#
# Como usar:
#   do sim_i2c.do
#
# O que verificar:
#   - Waveform: forma de onda I2C em i2c_scl e i2c_sda
#     (deve mostrar START, 3 bytes, ACK bits, STOP)
#   - Teste 1: done='1' após ACK do escravo
#   - Teste 2: err='1' após NACK
#   - Teste 3: done='1' novamente (recuperação)
# =============================================================================

do compile_all.do

echo "=== Iniciando simulacao: tb_i2c_master ==="

vsim -t 1ns -novopt work.tb_i2c_master

add wave -divider "=== CONTROLE ==="
add wave -radix binary /tb_i2c_master/reset_n
add wave -radix binary /tb_i2c_master/start
add wave -radix hex    /tb_i2c_master/addr
add wave -radix hex    /tb_i2c_master/data

add wave -divider "=== STATUS ==="
add wave -radix binary /tb_i2c_master/done
add wave -radix binary /tb_i2c_master/err

add wave -divider "=== BARRAMENTO I2C ==="
add wave -radix binary /tb_i2c_master/i2c_scl
add wave -radix binary /tb_i2c_master/i2c_sda

add wave -divider "=== ESCRAVO (modelo) ==="
add wave -radix binary /tb_i2c_master/slave_ack_enable
add wave -radix binary /tb_i2c_master/sda_slave

configure wave -namecolwidth 200
configure wave -valuecolwidth 80

run -all
wave zoom full

echo "=== Simulacao tb_i2c_master concluida ==="
