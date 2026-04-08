-- =============================================================================
-- tb_i2s_loopback.vhd
-- Testbench de loopback I2S: conecta i2s_transmitter diretamente ao
-- i2s_receiver e verifica que os dados chegam intactos.
--
-- Topologia:
--   [left=0x123456, right=0x654321] → i2s_transmitter ─┐
--                                                        │ bclk, lrck, dacdat
--                                                        ↓
--                                               i2s_receiver
--                                                        │
--                                                        ↓
--                                         [verifica left=0x123456, right=0x654321]
--
-- O teste injeta 3 pares de amostras diferentes e verifica cada um.
--
-- Nota de timing I2S (com mclk=12.288 MHz, period≈81 ns):
--   BCLK  = mclk / 4          → period ≈ 325 ns
--   LRCK  = BCLK / 64         → period ≈ 20.8 µs  (≈ 48 kHz)
--   1 frame completo (L+R)    = 64 BCLKs ≈ 20.8 µs
--
-- Como executar no ModelSim:
--   do sim/modelsim/sim_i2s.do
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_i2s_loopback is
end entity tb_i2s_loopback;

architecture bench of tb_i2s_loopback is

    -- -------------------------------------------------------------------------
    -- Componentes
    -- -------------------------------------------------------------------------
    component i2s_transmitter is
        port (
            clk        : in  std_logic;
            reset_n    : in  std_logic;
            mclk       : in  std_logic;
            left_data  : in  std_logic_vector(23 downto 0);
            right_data : in  std_logic_vector(23 downto 0);
            data_valid : in  std_logic;
            bclk       : out std_logic;
            lrck       : out std_logic;
            dacdat     : out std_logic
        );
    end component;

    component i2s_receiver is
        port (
            clk        : in  std_logic;
            reset_n    : in  std_logic;
            bclk       : in  std_logic;
            lrck       : in  std_logic;
            adcdat     : in  std_logic;
            left_data  : out std_logic_vector(23 downto 0);
            right_data : out std_logic_vector(23 downto 0);
            data_valid : out std_logic
        );
    end component;

    -- -------------------------------------------------------------------------
    -- Sinais
    -- -------------------------------------------------------------------------
    constant CLK_PERIOD  : time := 20 ns;    -- 50 MHz
    constant MCLK_PERIOD : time := 81 ns;    -- ~12.288 MHz
    -- 1 frame = 64 BCLKs, BCLK = MCLK/4 → 1 frame = 256 MCLK pulses
    constant FRAME_TIME  : time := 256 * MCLK_PERIOD;  -- ≈ 20.7 µs

    signal clk        : std_logic := '0';
    signal mclk       : std_logic := '0';
    signal reset_n    : std_logic := '0';

    -- TX ↔ RX (loopback)
    signal bclk       : std_logic;
    signal lrck       : std_logic;
    signal serial_dat : std_logic;

    -- Entradas do TX
    signal tx_left    : std_logic_vector(23 downto 0) := (others => '0');
    signal tx_right   : std_logic_vector(23 downto 0) := (others => '0');
    signal tx_valid   : std_logic := '0';

    -- Saídas do RX
    signal rx_left    : std_logic_vector(23 downto 0);
    signal rx_right   : std_logic_vector(23 downto 0);
    signal rx_valid   : std_logic;

    -- Contagem de testes
    shared variable pass_cnt : integer := 0;
    shared variable fail_cnt : integer := 0;

    -- -------------------------------------------------------------------------
    -- Procedimento de verificação
    -- -------------------------------------------------------------------------
    procedure check_sample(
        signal rx_left  : in std_logic_vector(23 downto 0);
        signal rx_right : in std_logic_vector(23 downto 0);
        expected_l : in std_logic_vector(23 downto 0);
        expected_r : in std_logic_vector(23 downto 0);
        test_name  : in string
    ) is
    begin
        if rx_left = expected_l and rx_right = expected_r then
            pass_cnt := pass_cnt + 1;
            report "[PASS] " & test_name &
                   " L=0x" & to_hstring(rx_left) &
                   " R=0x" & to_hstring(rx_right);
        else
            fail_cnt := fail_cnt + 1;
            report "[FAIL] " & test_name &
                   " | esperado L=0x" & to_hstring(expected_l) &
                   " R=0x" & to_hstring(expected_r) &
                   " | recebido L=0x" & to_hstring(rx_left) &
                   " R=0x" & to_hstring(rx_right) severity error;
        end if;
    end procedure;

begin

    -- -------------------------------------------------------------------------
    -- Instâncias (loopback: TX → RX)
    -- -------------------------------------------------------------------------
    u_tx : i2s_transmitter
        port map (
            clk        => clk,
            reset_n    => reset_n,
            mclk       => mclk,
            left_data  => tx_left,
            right_data => tx_right,
            data_valid => tx_valid,
            bclk       => bclk,
            lrck       => lrck,
            dacdat     => serial_dat
        );

    u_rx : i2s_receiver
        port map (
            clk        => clk,
            reset_n    => reset_n,
            bclk       => bclk,
            lrck       => lrck,
            adcdat     => serial_dat,
            left_data  => rx_left,
            right_data => rx_right,
            data_valid => rx_valid
        );

    -- -------------------------------------------------------------------------
    -- Geradores de clock
    -- -------------------------------------------------------------------------
    clk  <= not clk  after CLK_PERIOD  / 2;
    mclk <= not mclk after MCLK_PERIOD / 2;

    -- -------------------------------------------------------------------------
    -- Estímulos
    -- -------------------------------------------------------------------------
    process
    begin
        report "=== I2S LOOPBACK TESTBENCH INICIADO ===";

        -- Reset
        reset_n  <= '0';
        tx_valid <= '0';
        wait for CLK_PERIOD * 10;
        reset_n  <= '1';

        -- Aguarda 2 frames para o TX inicializar (LRCK e BCLK estabilizarem)
        wait for FRAME_TIME * 2;

        -- ==============================================================
        -- AMOSTRA 1: padrão genérico
        -- ==============================================================
        report "--- Amostra 1: L=0x123456 R=0x654321 ---";
        tx_left  <= x"123456";
        tx_right <= x"654321";
        tx_valid <= '1';
        wait until rising_edge(clk);
        tx_valid <= '0';

        -- Aguarda o RX capturar (até 3 frames)
        wait until rx_valid = '1' for FRAME_TIME * 3;
        wait for 5 ns;
        if rx_valid = '1' then
            check_sample(rx_left, rx_right, x"123456", x"654321", "Amostra 1");
        else
            report "[FAIL] Amostra 1: rx_valid nao chegou (timeout)" severity error;
            fail_cnt := fail_cnt + 1;
        end if;

        wait for FRAME_TIME;

        -- ==============================================================
        -- AMOSTRA 2: todos os bits em '1' (valor máximo positivo)
        -- ==============================================================
        report "--- Amostra 2: L=0x7FFFFF R=0x7FFFFF ---";
        tx_left  <= x"7FFFFF";
        tx_right <= x"7FFFFF";
        tx_valid <= '1';
        wait until rising_edge(clk);
        tx_valid <= '0';

        wait until rx_valid = '1' for FRAME_TIME * 3;
        wait for 5 ns;
        if rx_valid = '1' then
            check_sample(rx_left, rx_right, x"7FFFFF", x"7FFFFF", "Amostra 2 (max positivo)");
        else
            report "[FAIL] Amostra 2: timeout" severity error;
            fail_cnt := fail_cnt + 1;
        end if;

        wait for FRAME_TIME;

        -- ==============================================================
        -- AMOSTRA 3: valor negativo (complemento de dois)
        -- 0x800001 = -8388607 (mais negativo + 1)
        -- ==============================================================
        report "--- Amostra 3: L=0x800001 R=0xFFFF00 (negativos) ---";
        tx_left  <= x"800001";
        tx_right <= x"FFFF00";
        tx_valid <= '1';
        wait until rising_edge(clk);
        tx_valid <= '0';

        wait until rx_valid = '1' for FRAME_TIME * 3;
        wait for 5 ns;
        if rx_valid = '1' then
            check_sample(rx_left, rx_right, x"800001", x"FFFF00", "Amostra 3 (negativos)");
        else
            report "[FAIL] Amostra 3: timeout" severity error;
            fail_cnt := fail_cnt + 1;
        end if;

        wait for FRAME_TIME;

        -- ==============================================================
        -- AMOSTRA 4: zero
        -- ==============================================================
        report "--- Amostra 4: L=0x000000 R=0x000000 (zero) ---";
        tx_left  <= x"000000";
        tx_right <= x"000000";
        tx_valid <= '1';
        wait until rising_edge(clk);
        tx_valid <= '0';

        wait until rx_valid = '1' for FRAME_TIME * 3;
        wait for 5 ns;
        if rx_valid = '1' then
            check_sample(rx_left, rx_right, x"000000", x"000000", "Amostra 4 (zero)");
        else
            report "[FAIL] Amostra 4: timeout" severity error;
            fail_cnt := fail_cnt + 1;
        end if;

        -- ==============================================================
        -- RESULTADO
        -- ==============================================================
        wait for FRAME_TIME;
        report "=== RESULTADO: " &
               integer'image(pass_cnt) & " passaram, " &
               integer'image(fail_cnt) & " falharam ===";

        if fail_cnt = 0 then
            report ">>> I2S LOOPBACK TB: ALL TESTS PASSED <<<";
        else
            report ">>> I2S LOOPBACK TB: " &
                   integer'image(fail_cnt) & " FALHAS <<<" severity failure;
        end if;

        wait;
    end process;

end architecture bench;
