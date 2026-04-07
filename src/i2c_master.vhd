-- =============================================================================
-- i2c_master.vhd
-- Mestre I2C simples para configuração do WM8731.
-- Suporta transferências de 16 bits (endereço 7 bits + dados 9 bits do WM8731).
--
-- Parâmetros:
--   CLK_FREQ  : frequência do clock do sistema (Hz), default 50_000_000
--   I2C_FREQ  : frequência do barramento I2C (Hz), default 100_000
--
-- Protocolo:
--   - Pulsar start=1 com addr (7 bits), data (16 bits) válidos
--   - Aguardar done=1 (transferência completa) ou err=1 (NACK)
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2c_master is
    generic (
        CLK_FREQ : integer := 50_000_000;   -- Hz
        I2C_FREQ : integer := 100_000        -- Hz
    );
    port (
        clk     : in    std_logic;
        reset_n : in    std_logic;

        -- Interface de controle
        start   : in    std_logic;           -- pulso de 1 ciclo para iniciar
        addr    : in    std_logic_vector(6 downto 0);  -- endereço I2C do periférico
        data    : in    std_logic_vector(15 downto 0); -- 16 bits a transmitir
        done    : out   std_logic;           -- '1' por 1 ciclo ao terminar com ACK
        err     : out   std_logic;           -- '1' por 1 ciclo se NACK recebido

        -- Pinos I2C
        i2c_scl : out   std_logic;
        i2c_sda : inout std_logic
    );
end entity i2c_master;

architecture rtl of i2c_master is

    -- Divisor de clock: número de ciclos de sistema por meio-período I2C
    constant HALF_PERIOD : integer := CLK_FREQ / (2 * I2C_FREQ);

    type state_t is (
        S_IDLE,
        S_START,
        S_ADDR,        -- 7 bits de endereço + bit R/W (sempre '0' = write)
        S_ACK_ADDR,
        S_DATA_HIGH,   -- 8 bits altos dos dados
        S_ACK_HIGH,
        S_DATA_LOW,    -- 8 bits baixos dos dados
        S_ACK_LOW,
        S_STOP,
        S_DONE,
        S_ERR
    );

    signal state      : state_t := S_IDLE;
    signal clk_cnt    : integer range 0 to HALF_PERIOD - 1 := 0;
    signal bit_cnt    : integer range 0 to 7 := 0;
    signal scl_r      : std_logic := '1';
    signal sda_r      : std_logic := '1';
    signal sda_oe     : std_logic := '0'; -- '1' = FPGA controla SDA
    signal shift_reg  : std_logic_vector(7 downto 0) := (others => '0');
    signal tick       : std_logic := '0'; -- pulso a cada meio-período I2C
    signal tick_phase : std_logic := '0'; -- alterna a cada tick (0=low, 1=high)

    -- Dados capturados ao iniciar
    signal addr_r     : std_logic_vector(7 downto 0) := (others => '0'); -- addr & '0'
    signal data_r     : std_logic_vector(15 downto 0) := (others => '0');

begin

    -- Drive open-drain: SDA = '0' quando oe=1 e sda_r='0', senão Hi-Z
    i2c_sda <= '0' when (sda_oe = '1' and sda_r = '0') else 'Z';
    i2c_scl <= scl_r;

    -- Gerador de tick (meio-período I2C)
    process(clk, reset_n)
    begin
        if reset_n = '0' then
            clk_cnt <= 0;
            tick    <= '0';
        elsif rising_edge(clk) then
            tick <= '0';
            if clk_cnt = HALF_PERIOD - 1 then
                clk_cnt <= 0;
                tick    <= '1';
            else
                clk_cnt <= clk_cnt + 1;
            end if;
        end if;
    end process;

    -- Máquina de estados I2C
    process(clk, reset_n)
    begin
        if reset_n = '0' then
            state      <= S_IDLE;
            scl_r      <= '1';
            sda_r      <= '1';
            sda_oe     <= '0';
            done       <= '0';
            err        <= '0';
            bit_cnt    <= 0;
            tick_phase <= '0';
            shift_reg  <= (others => '0');
            addr_r     <= (others => '0');
            data_r     <= (others => '0');

        elsif rising_edge(clk) then
            done <= '0';
            err  <= '0';

            case state is

                -- -------------------------------------------------------
                when S_IDLE =>
                    scl_r  <= '1';
                    sda_r  <= '1';
                    sda_oe <= '1';
                    if start = '1' then
                        addr_r     <= addr & '0';   -- R/W = 0 (write)
                        data_r     <= data;
                        tick_phase <= '0';
                        state      <= S_START;
                    end if;

                -- -------------------------------------------------------
                -- START: SDA cai enquanto SCL está alto
                when S_START =>
                    if tick = '1' then
                        if tick_phase = '0' then
                            sda_r      <= '0';   -- SDA desce
                            tick_phase <= '1';
                        else
                            scl_r      <= '0';   -- SCL desce → começa clock
                            shift_reg  <= addr_r;
                            bit_cnt    <= 7;
                            tick_phase <= '0';
                            state      <= S_ADDR;
                        end if;
                    end if;

                -- -------------------------------------------------------
                -- Envia 8 bits (7 addr + R/W)
                when S_ADDR =>
                    if tick = '1' then
                        if tick_phase = '0' then
                            -- SCL baixo: colocar bit na SDA
                            sda_r      <= shift_reg(7);
                            scl_r      <= '0';
                            tick_phase <= '1';
                        else
                            -- SCL alto: periférico lê o bit
                            scl_r      <= '1';
                            tick_phase <= '0';
                            if bit_cnt = 0 then
                                state <= S_ACK_ADDR;
                            else
                                shift_reg <= shift_reg(6 downto 0) & '0';
                                bit_cnt   <= bit_cnt - 1;
                            end if;
                        end if;
                    end if;

                -- -------------------------------------------------------
                -- ACK do endereço
                when S_ACK_ADDR =>
                    if tick = '1' then
                        if tick_phase = '0' then
                            sda_oe     <= '0';   -- libera SDA para periférico
                            scl_r      <= '0';
                            tick_phase <= '1';
                        else
                            scl_r      <= '1';
                            tick_phase <= '0';
                            if i2c_sda = '0' then   -- ACK recebido
                                shift_reg <= data_r(15 downto 8);
                                bit_cnt   <= 7;
                                state     <= S_DATA_HIGH;
                            else
                                state <= S_ERR;
                            end if;
                            sda_oe <= '1';
                        end if;
                    end if;

                -- -------------------------------------------------------
                -- Envia byte alto dos dados
                when S_DATA_HIGH =>
                    if tick = '1' then
                        if tick_phase = '0' then
                            sda_r      <= shift_reg(7);
                            scl_r      <= '0';
                            tick_phase <= '1';
                        else
                            scl_r      <= '1';
                            tick_phase <= '0';
                            if bit_cnt = 0 then
                                state <= S_ACK_HIGH;
                            else
                                shift_reg <= shift_reg(6 downto 0) & '0';
                                bit_cnt   <= bit_cnt - 1;
                            end if;
                        end if;
                    end if;

                -- -------------------------------------------------------
                when S_ACK_HIGH =>
                    if tick = '1' then
                        if tick_phase = '0' then
                            sda_oe     <= '0';
                            scl_r      <= '0';
                            tick_phase <= '1';
                        else
                            scl_r      <= '1';
                            tick_phase <= '0';
                            if i2c_sda = '0' then
                                shift_reg <= data_r(7 downto 0);
                                bit_cnt   <= 7;
                                state     <= S_DATA_LOW;
                            else
                                state <= S_ERR;
                            end if;
                            sda_oe <= '1';
                        end if;
                    end if;

                -- -------------------------------------------------------
                -- Envia byte baixo dos dados
                when S_DATA_LOW =>
                    if tick = '1' then
                        if tick_phase = '0' then
                            sda_r      <= shift_reg(7);
                            scl_r      <= '0';
                            tick_phase <= '1';
                        else
                            scl_r      <= '1';
                            tick_phase <= '0';
                            if bit_cnt = 0 then
                                state <= S_ACK_LOW;
                            else
                                shift_reg <= shift_reg(6 downto 0) & '0';
                                bit_cnt   <= bit_cnt - 1;
                            end if;
                        end if;
                    end if;

                -- -------------------------------------------------------
                when S_ACK_LOW =>
                    if tick = '1' then
                        if tick_phase = '0' then
                            sda_oe     <= '0';
                            scl_r      <= '0';
                            tick_phase <= '1';
                        else
                            scl_r      <= '1';
                            tick_phase <= '0';
                            if i2c_sda = '0' then
                                state <= S_STOP;
                            else
                                state <= S_ERR;
                            end if;
                            sda_oe <= '1';
                        end if;
                    end if;

                -- -------------------------------------------------------
                -- STOP: SDA sobe enquanto SCL está alto
                when S_STOP =>
                    if tick = '1' then
                        if tick_phase = '0' then
                            sda_r      <= '0';
                            scl_r      <= '0';
                            tick_phase <= '1';
                        else
                            scl_r      <= '1';
                            tick_phase <= '0';
                            state      <= S_DONE;
                        end if;
                    end if;

                -- -------------------------------------------------------
                when S_DONE =>
                    if tick = '1' then
                        sda_r  <= '1';
                        done   <= '1';
                        state  <= S_IDLE;
                    end if;

                -- -------------------------------------------------------
                when S_ERR =>
                    if tick = '1' then
                        sda_r  <= '1';
                        scl_r  <= '1';
                        err    <= '1';
                        state  <= S_IDLE;
                    end if;

                when others =>
                    state <= S_IDLE;

            end case;
        end if;
    end process;

end architecture rtl;
