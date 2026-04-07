-- =============================================================================
-- i2s_transmitter.vhd
-- Transmissor I2S para o WM8731 (FPGA → DAC).
--
-- Formato I2S padrão (LRP=0):
--   - LRCK alto  → canal LEFT
--   - LRCK baixo → canal RIGHT
--   - MSB primeiro, 24 bits, dados mudam na borda de descida do BCLK
--
-- O FPGA gera BCLK e LRCK (WM8731 em slave mode).
-- Clock de entrada: MCLK (~12.288 MHz).
--   BCLK = MCLK / 4  (3.072 MHz)
--   LRCK = BCLK / 64 = MCLK / 256 (48 kHz)
--
-- A cada novo par de amostras (left_data/right_data válidas em data_valid),
-- o transmissor as carrega e envia no próximo quadro I2S.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2s_transmitter is
    port (
        clk        : in  std_logic;   -- clock do sistema (50 MHz)
        reset_n    : in  std_logic;

        -- Clock mestre do codec (MCLK ~12.288 MHz)
        mclk       : in  std_logic;

        -- Dados a transmitir (atualizados a cada data_valid)
        left_data  : in  std_logic_vector(23 downto 0);
        right_data : in  std_logic_vector(23 downto 0);
        data_valid : in  std_logic;  -- pulso indicando novos dados disponíveis

        -- Saídas I2S para o WM8731
        bclk       : out std_logic;
        lrck       : out std_logic;
        dacdat     : out std_logic
    );
end entity i2s_transmitter;

architecture rtl of i2s_transmitter is

    -- Divisores de clock (no domínio do MCLK)
    -- MCLK / 4 = BCLK: dividir por 2 com half-period de 2
    -- BCLK / 64 = LRCK: contador de 0..63 de BCLKs

    signal bclk_cnt  : unsigned(1 downto 0) := (others => '0');   -- divide MCLK por 4
    signal lrck_cnt  : unsigned(5 downto 0) := (others => '0');   -- divide BCLK por 64
    signal bclk_r    : std_logic := '0';
    signal lrck_r    : std_logic := '1';

    -- Registros internos de dados a serializar
    signal left_r    : std_logic_vector(23 downto 0) := (others => '0');
    signal right_r   : std_logic_vector(23 downto 0) := (others => '0');
    signal shift_reg : std_logic_vector(23 downto 0) := (others => '0');

    -- Contador de bits dentro do meio-quadro (0..31: I2S tem 32 BCLKs por canal)
    signal bit_cnt   : unsigned(4 downto 0) := (others => '0');

    -- Sinalização de borda de BCLK (no domínio MCLK)
    signal bclk_rise : std_logic;
    signal bclk_fall : std_logic;

    -- Sincronização de data_valid para domínio MCLK
    signal dv_r1, dv_r2 : std_logic := '0';

begin

    bclk <= bclk_r;
    lrck <= lrck_r;

    -- ==========================================================================
    -- Geração de BCLK e LRCK a partir do MCLK (tudo no domínio MCLK)
    -- ==========================================================================
    process(mclk, reset_n)
    begin
        if reset_n = '0' then
            bclk_cnt  <= (others => '0');
            lrck_cnt  <= (others => '0');
            bclk_r    <= '0';
            lrck_r    <= '1';
            bit_cnt   <= (others => '0');
            shift_reg <= (others => '0');
            left_r    <= (others => '0');
            right_r   <= (others => '0');
            dacdat    <= '0';
            dv_r1     <= '0';
            dv_r2     <= '0';

        elsif rising_edge(mclk) then

            -- Sincroniza data_valid para domínio MCLK
            dv_r1 <= data_valid;
            dv_r2 <= dv_r1;

            -- Captura novos dados assim que disponíveis
            if dv_r2 = '1' then
                left_r  <= left_data;
                right_r <= right_data;
            end if;

            -- Divisor de MCLK por 4 → BCLK
            bclk_cnt <= bclk_cnt + 1;
            bclk_fall <= '0';
            bclk_rise <= '0';

            if bclk_cnt = "01" then
                bclk_r    <= '1';
                bclk_rise <= '1';
            elsif bclk_cnt = "11" then
                bclk_r    <= '0';
                bclk_fall <= '1';
            end if;

            -- Lógica de serialização (ativada na borda de descida do BCLK)
            -- No I2S: MSB do LEFT é enviado 1 BCLK após a borda de subida do LRCK.
            -- Aqui simplificamos: na borda de descida colocamos o próximo bit,
            -- a borda de subida é o ponto de amostragem do receptor.
            if bclk_fall = '1' then

                -- Contagem de BECLKs para LRCK (32 BCLKs por canal = 64 total)
                lrck_cnt <= lrck_cnt + 1;

                if lrck_cnt = "000000" then
                    -- Início do canal LEFT: carrega shift register
                    lrck_r    <= '1';
                    shift_reg <= left_r;
                    bit_cnt   <= (others => '0');
                elsif lrck_cnt = "100000" then
                    -- Início do canal RIGHT
                    lrck_r    <= '0';
                    shift_reg <= right_r;
                    bit_cnt   <= (others => '0');
                end if;

                -- Serializa bit (MSB primeiro)
                if bit_cnt < 24 then
                    dacdat    <= shift_reg(23);
                    shift_reg <= shift_reg(22 downto 0) & '0';
                    bit_cnt   <= bit_cnt + 1;
                else
                    dacdat <= '0';  -- bits 25..32 = padding zeros
                end if;

            end if;
        end if;
    end process;

end architecture rtl;
