# =============================================================================
# sim_top.do
# Compila e executa o testbench de integração completo (tb_top).
#
# ATENÇÃO: Este script usa pll_audio_sim.vhd (modelo comportamental).
#          O pll_audio.vhd real (com ALTPLL) NÃO é compilado aqui.
#
# Como usar:
#   do sim_top.do
#
# Duração estimada: ~10 ms simulados
#   (~3 ms para configuração I2C + ~7 ms para testes de áudio)
#   Pode demorar alguns segundos de tempo real para simular.
#
# O que verificar:
#   - led_config_done sobe após ~2-3 ms simulados (9 transferências I2C)
#   - aud_bclk e aud_daclrck oscilam continuamente (I2S ativo)
#   - led_clipping='1' com gain=8x + sinal grande (Fase 2)
#   - aud_dacdat tem atividade após processamento (Fase 3)
#   - led_clipping='0' com gain=1x + sinal pequeno (Fase 4)
# =============================================================================

do compile_all.do

echo "=== Iniciando simulacao: tb_top (integracao completa) ==="
echo "AVISO: Simulacao pode demorar - aguarda ~10 ms simulados"

vsim -t 1ns -novopt work.tb_top

add wave -divider "=== SISTEMA ==="
add wave -radix binary /tb_top/reset_n
add wave -radix binary /tb_top/gain_sw

add wave -divider "=== STATUS LEDs ==="
add wave -radix binary /tb_top/led_config_done
add wave -radix binary /tb_top/led_clipping

add wave -divider "=== AUDIO I2S ==="
add wave -radix binary /tb_top/aud_mclk
add wave -radix binary /tb_top/aud_bclk
add wave -radix binary /tb_top/aud_daclrck
add wave -radix binary /tb_top/aud_dacdat
add wave -radix binary /tb_top/aud_adcdat

add wave -divider "=== I2C ==="
add wave -radix binary /tb_top/i2c_sclk
add wave -radix binary /tb_top/i2c_sdat

add wave -divider "=== ESTIMULOS ==="
add wave -radix binary /tb_top/inject_enable
add wave -radix hex    /tb_top/inject_sample

configure wave -namecolwidth 220
configure wave -valuecolwidth 80

# Executa a simulação completa
run -all

wave zoom full

echo "=== Simulacao tb_top concluida ==="
echo "Verifique as fases 1-4 nas mensagens acima."
