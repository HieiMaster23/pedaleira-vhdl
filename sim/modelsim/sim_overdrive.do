# =============================================================================
# sim_overdrive.do
# Compila e executa o testbench do módulo overdrive (DSP de soft clipping).
#
# Como usar no ModelSim:
#   1. Abra o ModelSim-Altera (via Quartus → Tools → Run Simulation Tool → RTL Simulation)
#   2. Na janela Transcript: cd <caminho_do_projeto>/sim/modelsim
#   3. do sim_overdrive.do
#
# O que verificar:
#   - Janela Transcript: mensagens [PASS] para cada vetor de teste
#   - Mensagem final: "OVERDRIVE TB: ALL TESTS PASSED"
#   - Waveform: forma do transfer curve (in x out) nos sinais left_in / left_out
# =============================================================================

# Compila tudo
do compile_all.do

echo "=== Iniciando simulacao: tb_overdrive ==="

# Inicia simulação
vsim -t 1ns -novopt work.tb_overdrive

# Configuração da janela de waveform
add wave -divider "=== CONTROLE ==="
add wave -radix binary /tb_overdrive/reset_n
add wave -radix binary /tb_overdrive/gain_sw

add wave -divider "=== ENTRADA ==="
add wave -radix hex    /tb_overdrive/left_in
add wave -radix hex    /tb_overdrive/right_in
add wave -radix binary /tb_overdrive/data_valid

add wave -divider "=== SAIDA ==="
add wave -radix hex    /tb_overdrive/left_out
add wave -radix hex    /tb_overdrive/right_out
add wave -radix binary /tb_overdrive/valid_out
add wave -radix binary /tb_overdrive/clipping

add wave -divider "=== CLOCK ==="
add wave -radix binary /tb_overdrive/clk

# Ajusta a visualização
configure wave -namecolwidth 200
configure wave -valuecolwidth 100
configure wave -signalnamewidth 1

# Executa toda a simulação
run -all

# Zoom para ver toda a simulação
wave zoom full

echo "=== Simulacao tb_overdrive concluida ==="
echo "Verifique as mensagens [PASS]/[FAIL] acima."
