-- =============================================================================
-- codec_config.vhd
-- Máquina de estados que configura o WM8731 via I2C ao ligar o sistema.
--
-- Sequência de registradores enviados (endereço I2C = 0x1A, CS=GND):
--   R15 (0x0F) : Reset chip
--   R6  (0x06) : Power Down  → liga ADC, DAC, oscilador; desliga MIC e CLKOUT
--   R0  (0x00) : Left Line In  → 0 dB, unmute
--   R1  (0x01) : Right Line In → 0 dB, unmute
--   R4  (0x04) : Analogue Path → DAC selecionado, sem bypass, sem MIC
--   R5  (0x05) : Digital Path  → sem HPF, sem deênfase, sem mute
--   R7  (0x07) : Interface Fmt → I2S, 24 bits, slave mode, MSB primeiro
--   R8  (0x08) : Sampling      → USB mode (12 MHz → 48 kHz), BOSR=0
--   R9  (0x09) : Active        → ativa o codec
--
-- Após enviar todos os registradores, config_done fica '1'.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity codec_config is
    generic (
        CLK_FREQ : integer := 50_000_000   -- Hz
    );
    port (
        clk         : in    std_logic;
        reset_n     : in    std_logic;

        -- Interface com i2c_master
        i2c_start   : out   std_logic;
        i2c_addr    : out   std_logic_vector(6 downto 0);
        i2c_data    : out   std_logic_vector(15 downto 0);
        i2c_done    : in    std_logic;
        i2c_err     : in    std_logic;

        config_done : out   std_logic   -- '1' quando configuração concluída
    );
end entity codec_config;

architecture rtl of codec_config is

    -- Endereço I2C do WM8731 com CS = GND
    constant WM8731_ADDR : std_logic_vector(6 downto 0) := "0011010"; -- 0x1A

    -- Cada entrada: bits(15:9)=reg_addr(6:0), bits(8:0)=reg_data(8:0)
    type reg_array_t is array(0 to 8) of std_logic_vector(15 downto 0);
    constant REGS : reg_array_t := (
        -- R15: Reset
        0 => "000" & "1111" & "0" & "00000000",   -- 0x1E00 (7 bits reg: 0001111)
        -- R6: Power Down: POWEROFF=0, CLKOUTPD=1, OSCPD=0, OUTPD=0,
        --                  DACPD=0, ADCPD=0, MICPD=1, LINEINPD=0
        1 => "000" & "0110" & "0" & "00100010",   -- 0x0C22
        -- R0: Left Line In: LINVOL=10111 (0 dB), LINMUTE=0, LRINBOTH=0
        2 => "000" & "0000" & "0" & "00010111",   -- 0x0017
        -- R1: Right Line In: igual
        3 => "000" & "0001" & "0" & "00010111",   -- 0x0217
        -- R4: Analogue Path: SIDEATT=00, SIDETONE=0, DACSEL=1,
        --                    BYPASS=0, INSEL=0 (linein), MUTEMIC=1, MICBOOST=0
        4 => "000" & "0100" & "0" & "00010010",   -- 0x0812  DACSEL=1, MUTEMIC=1
        -- R5: Digital Path: DACMU=0, DEEMP=00, ADCHPD=0
        5 => "000" & "0101" & "0" & "00000000",   -- 0x0A00
        -- R7: Interface Format: BCLKINV=0, MS=0 (slave), LRSWAP=0, LRP=0,
        --                        IWL=11 (24 bits), FORMAT=10 (I2S)
        6 => "000" & "0111" & "0" & "00001110",   -- 0x0E0E
        -- R8: Sampling: CLKODIV2=0, CLKIDIV2=0, SR=0000, BOSR=0, USB/NORM=1
        --   USB mode + SR=0000 → 48kHz com MCLK 12 MHz
        7 => "000" & "1000" & "0" & "00000001",   -- 0x1001
        -- R9: Active: ACTIVE=1
        8 => "000" & "1001" & "0" & "00000001"    -- 0x1201
    );

    -- Delay inicial: esperar PLL travar (~1 ms)
    constant INIT_DELAY : integer := CLK_FREQ / 1000;  -- 1 ms

    type state_t is (S_WAIT, S_SEND, S_WAIT_DONE, S_DONE);
    signal state      : state_t := S_WAIT;
    signal delay_cnt  : integer range 0 to INIT_DELAY - 1 := 0;
    signal reg_idx    : integer range 0 to 8 := 0;

begin

    i2c_addr <= WM8731_ADDR;

    process(clk, reset_n)
    begin
        if reset_n = '0' then
            state       <= S_WAIT;
            delay_cnt   <= 0;
            reg_idx     <= 0;
            i2c_start   <= '0';
            i2c_data    <= (others => '0');
            config_done <= '0';

        elsif rising_edge(clk) then
            i2c_start <= '0';

            case state is

                -- Aguarda PLL travar e hardware estabilizar
                when S_WAIT =>
                    if delay_cnt = INIT_DELAY - 1 then
                        delay_cnt <= 0;
                        state     <= S_SEND;
                    else
                        delay_cnt <= delay_cnt + 1;
                    end if;

                -- Dispara transferência I2C do registrador atual
                when S_SEND =>
                    i2c_data  <= REGS(reg_idx);
                    i2c_start <= '1';
                    state     <= S_WAIT_DONE;

                -- Aguarda conclusão ou erro
                when S_WAIT_DONE =>
                    if i2c_done = '1' then
                        if reg_idx = 8 then
                            state <= S_DONE;
                        else
                            reg_idx <= reg_idx + 1;
                            state   <= S_SEND;
                        end if;
                    elsif i2c_err = '1' then
                        -- Em caso de erro, retenta o mesmo registrador
                        state <= S_SEND;
                    end if;

                when S_DONE =>
                    config_done <= '1';

                when others =>
                    state <= S_WAIT;

            end case;
        end if;
    end process;

end architecture rtl;
