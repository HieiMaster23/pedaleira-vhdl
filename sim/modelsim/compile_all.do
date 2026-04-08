# =============================================================================
# compile_all.do
# Compila todas as fontes e testbenches do projeto para a biblioteca 'work'.
#
# Execute a partir do diretório sim/modelsim/ dentro do ModelSim:
#   do compile_all.do
#
# NOTA: pll_audio_sim.vhd é compilado em vez de pll_audio.vhd para evitar
#       a dependência com a biblioteca altera_mf (ALTPLL não simulável sem ela).
# =============================================================================

# Cria a biblioteca work (recria se já existir)
if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

echo "=== Compilando fontes (src/) ==="

# Módulos sem dependências internas
vcom -93 -work work ../../src/i2c_master.vhd
if {[catch {vcom -93 -work work ../../src/i2c_master.vhd} err]} {
    echo "ERRO: i2c_master.vhd - $err"
}

vcom -93 -work work ../../src/codec_config.vhd
vcom -93 -work work ../../src/i2s_receiver.vhd
vcom -93 -work work ../../src/i2s_transmitter.vhd
vcom -93 -work work ../../src/overdrive.vhd

# PLL: usa modelo comportamental de simulação (NÃO compila pll_audio.vhd)
echo "=== Usando pll_audio_sim (modelo comportamental, sem ALTPLL) ==="
vcom -93 -work work ../pll_audio_sim.vhd

# Top-level (depende de todos os módulos acima)
vcom -93 -work work ../../src/top.vhd

echo "=== Compilando testbenches (sim/) ==="
vcom -93 -work work ../tb_overdrive.vhd
vcom -93 -work work ../tb_i2c_master.vhd
vcom -93 -work work ../tb_i2s_loopback.vhd
vcom -93 -work work ../tb_top.vhd

echo "=== Compilacao concluida ==="
echo "Testbenches disponiveis:"
echo "  work.tb_overdrive    - DSP soft clipping"
echo "  work.tb_i2c_master   - Protocolo I2C"
echo "  work.tb_i2s_loopback - Loopback I2S TX->RX"
echo "  work.tb_top          - Integracao completa"
