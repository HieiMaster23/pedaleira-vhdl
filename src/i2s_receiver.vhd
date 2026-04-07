-- =============================================================================
-- i2s_receiver.vhd
-- Receptor I2S para o WM8731 (ADC → FPGA).
--
-- O WM8731 opera em SLAVE MODE: o FPGA fornece BCLK e LRCK.
-- Formato I2S padrão (LRP=0):
--   - LRCK alto  → canal LEFT  (começa 1 BCLK após a borda de descida do LRCK)
--   - LRCK baixo → canal RIGHT
--   - Dados: MSB primeiro, 24 bits válidos
--
-- Entradas de clock geradas externamente (pelo top-level):
--   bclk    : bit clock = MCLK / 4  (~3.072 MHz para 48 kHz / 24 bits)
--   lrck    : word clock = 48 kHz   (gerado por contagem de bclk)
--
-- Saídas:
--   left_data / right_data  : amostras de 24 bits (complemento de dois)
--   data_valid              : pulso de 1 ciclo de clk quando novos dados prontos
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2s_receiver is
    port (
        clk        : in  std_logic;   -- clock do sistema (50 MHz)
        reset_n    : in  std_logic;

        -- Sinais I2S (vêm do codec / gerados pelo top)
        bclk       : in  std_logic;   -- bit clock
        lrck       : in  std_logic;   -- left/right clock
        adcdat     : in  std_logic;   -- dados seriais do ADC

        -- Saída paralela
        left_data  : out std_logic_vector(23 downto 0);
        right_data : out std_logic_vector(23 downto 0);
        data_valid : out std_logic    -- pulso quando par L+R está pronto
    );
end entity i2s_receiver;

architecture rtl of i2s_receiver is

    -- Detecção de bordas de bclk e lrck (domínio do clock do sistema)
    signal bclk_r1, bclk_r2   : std_logic := '0';
    signal lrck_r1, lrck_r2   : std_logic := '0';
    signal bclk_fall           : std_logic;
    signal lrck_rise, lrck_fall: std_logic;

    -- Shift register de 24 bits
    signal shift_reg  : std_logic_vector(23 downto 0) := (others => '0');
    signal bit_cnt    : integer range 0 to 31 := 0;

    -- Estado do canal: '1' = left, '0' = right
    signal is_left    : std_logic := '1';
    signal left_buf   : std_logic_vector(23 downto 0) := (others => '0');
    signal right_buf  : std_logic_vector(23 downto 0) := (others => '0');

    -- Sinalização interna
    signal right_done : std_logic := '0';

begin

    -- Sincronização e detecção de bordas (amostrado no clock do sistema)
    process(clk, reset_n)
    begin
        if reset_n = '0' then
            bclk_r1 <= '0'; bclk_r2 <= '0';
            lrck_r1 <= '0'; lrck_r2 <= '0';
        elsif rising_edge(clk) then
            bclk_r1 <= bclk; bclk_r2 <= bclk_r1;
            lrck_r1 <= lrck; lrck_r2 <= lrck_r1;
        end if;
    end process;

    -- Bordas detectadas
    bclk_fall  <= bclk_r2 and (not bclk_r1);   -- borda de descida de BCLK
    lrck_rise  <= (not lrck_r2) and lrck_r1;   -- borda de subida de LRCK
    lrck_fall  <= lrck_r2 and (not lrck_r1);   -- borda de descida de LRCK

    -- Máquina de captura I2S
    -- No formato I2S, o MSB é transmitido 1 BCLK após a mudança de LRCK.
    -- Capturamos na borda de descida do BCLK (setup time garantido).
    process(clk, reset_n)
    begin
        if reset_n = '0' then
            shift_reg  <= (others => '0');
            bit_cnt    <= 0;
            is_left    <= '1';
            left_buf   <= (others => '0');
            right_buf  <= (others => '0');
            right_done <= '0';
            data_valid <= '0';
            left_data  <= (others => '0');
            right_data <= (others => '0');

        elsif rising_edge(clk) then
            data_valid <= '0';
            right_done <= '0';

            -- Mudança de canal
            if lrck_rise = '1' then
                -- Fim do canal RIGHT → salva o que foi recebido
                right_buf  <= shift_reg;
                shift_reg  <= (others => '0');
                bit_cnt    <= 0;
                is_left    <= '1';
                right_done <= '1';
            elsif lrck_fall = '1' then
                -- Fim do canal LEFT → salva
                left_buf  <= shift_reg;
                shift_reg <= (others => '0');
                bit_cnt   <= 0;
                is_left   <= '0';
            end if;

            -- Captura de bit na descida de BCLK (dados estáveis)
            if bclk_fall = '1' then
                if bit_cnt < 24 then
                    shift_reg <= shift_reg(22 downto 0) & adcdat;
                    bit_cnt   <= bit_cnt + 1;
                end if;
            end if;

            -- Sinaliza par de amostras prontas após salvar o canal Right
            if right_done = '1' then
                left_data  <= left_buf;
                right_data <= right_buf;
                data_valid <= '1';
            end if;
        end if;
    end process;

end architecture rtl;
