-- =============================================================================
-- tb_i2c_master.vhd
-- Testbench do módulo i2c_master.vhd com modelo de escravo I2C.
--
-- O modelo de escravo monitora SCL e responde com ACK (SDA='0') após cada
-- byte completo (8 bits), simulando o comportamento do WM8731.
--
-- Testes realizados:
--   Teste 1 — Transferência com ACK:
--     Envia addr=0x1A, data=x"0017" → escravo ACK → verifica done='1'
--   Teste 2 — NACK:
--     Escravo não responde (SDA='Z' no slot de ACK) → verifica err='1'
--
-- Como executar no ModelSim:
--   do sim/modelsim/sim_i2c.do
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_i2c_master is
end entity tb_i2c_master;

architecture bench of tb_i2c_master is

    -- -------------------------------------------------------------------------
    -- DUT
    -- -------------------------------------------------------------------------
    component i2c_master is
        generic (
            CLK_FREQ : integer;
            I2C_FREQ : integer
        );
        port (
            clk     : in    std_logic;
            reset_n : in    std_logic;
            start   : in    std_logic;
            addr    : in    std_logic_vector(6 downto 0);
            data    : in    std_logic_vector(15 downto 0);
            done    : out   std_logic;
            err     : out   std_logic;
            i2c_scl : out   std_logic;
            i2c_sda : inout std_logic
        );
    end component;

    -- -------------------------------------------------------------------------
    -- Sinais
    -- -------------------------------------------------------------------------
    constant CLK_PERIOD  : time    := 20 ns;    -- 50 MHz
    -- Usar I2C_FREQ menor para simulação rápida
    constant I2C_FREQ_TB : integer := 1_000_000; -- 1 MHz em simulação (acelera)
    constant HALF_I2C    : time    := 500 ns;    -- meio período I2C = 1/(2*1MHz)

    signal clk      : std_logic := '0';
    signal reset_n  : std_logic := '0';
    signal start    : std_logic := '0';
    signal addr     : std_logic_vector(6 downto 0) := (others => '0');
    signal data     : std_logic_vector(15 downto 0) := (others => '0');
    signal done     : std_logic;
    signal err      : std_logic;
    signal i2c_scl  : std_logic;
    signal i2c_sda  : std_logic;

    -- Pull-up na linha SDA: '1' fraco, dominado por '0' forte do DUT/escravo
    signal sda_slave : std_logic := 'Z';

    -- Conecta pull-up + driver do escravo à SDA
    -- O DUT (open-drain) também escreve via seu port INOUT
    -- std_logic resolution: 'Z'+'Z'='Z','Z'+'0'='0','H'+'Z'='H','H'+'0'='0'

    -- Controle do slave
    signal slave_ack_enable : std_logic := '1';  -- '1'=ACK, '0'=NACK

    -- Resultado
    shared variable test_pass : boolean := true;

begin

    -- Pull-up externo na SDA (simula resistor de pull-up da placa)
    i2c_sda <= 'H';

    -- O escravo também pode forçar SDA via sda_slave
    i2c_sda <= sda_slave;

    -- -------------------------------------------------------------------------
    -- Instância do DUT
    -- -------------------------------------------------------------------------
    u_dut : i2c_master
        generic map (
            CLK_FREQ => 50_000_000,
            I2C_FREQ => I2C_FREQ_TB
        )
        port map (
            clk     => clk,
            reset_n => reset_n,
            start   => start,
            addr    => addr,
            data    => data,
            done    => done,
            err     => err,
            i2c_scl => i2c_scl,
            i2c_sda => i2c_sda
        );

    -- -------------------------------------------------------------------------
    -- Gerador de clock
    -- -------------------------------------------------------------------------
    clk <= not clk after CLK_PERIOD / 2;

    -- -------------------------------------------------------------------------
    -- Modelo de escravo I2C
    -- Monitora SCL e gera ACK após cada byte (se slave_ack_enable='1')
    -- -------------------------------------------------------------------------
    slave_model : process
        variable scl_rise_cnt : integer := 0;
    begin
        sda_slave <= 'Z';
        -- Aguarda reset sair
        wait until reset_n = '1';
        wait for 1 us;

        loop
            -- Detecta condição de START (SDA cai com SCL alto)
            wait until falling_edge(i2c_sda) and i2c_scl = '1';
            scl_rise_cnt := 0;

            -- Conta 8 bordas de subida do SCL (1 byte)
            for byte_idx in 0 to 2 loop  -- 3 bytes: addr + data_high + data_low
                scl_rise_cnt := 0;
                while scl_rise_cnt < 8 loop
                    wait until rising_edge(i2c_scl);
                    scl_rise_cnt := scl_rise_cnt + 1;
                end loop;

                -- 9º ciclo SCL: slot de ACK
                -- Aguarda SCL cair (fim do 8º bit)
                wait until falling_edge(i2c_scl);
                wait for HALF_I2C / 4;  -- pequeno delay

                if slave_ack_enable = '1' then
                    -- ACK: puxa SDA para '0'
                    sda_slave <= '0';
                    wait until falling_edge(i2c_scl);  -- mantém durante SCL alto
                    wait for HALF_I2C / 4;
                    sda_slave <= 'Z';  -- libera SDA
                else
                    -- NACK: mantém SDA em 'Z' (vai para 'H' pelo pull-up)
                    sda_slave <= 'Z';
                end if;
            end loop;
        end loop;
    end process;

    -- -------------------------------------------------------------------------
    -- Estímulos principais
    -- -------------------------------------------------------------------------
    process
    begin
        report "=== I2C MASTER TESTBENCH INICIADO ===";

        -- Reset
        reset_n <= '0';
        start   <= '0';
        wait for CLK_PERIOD * 10;
        reset_n <= '1';
        wait for CLK_PERIOD * 5;

        -- ==============================================================
        -- TESTE 1: Transferência com ACK do escravo
        -- Envia addr=0x1A (WM8731), data=x"0017" (R0: Line In 0 dB)
        -- ==============================================================
        report "--- Teste 1: Transferencia com ACK ---";
        slave_ack_enable <= '1';

        addr  <= "0011010";     -- 0x1A
        data  <= x"0017";       -- R0 = 0 dB
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';

        -- Aguarda done ou err (timeout de 5 ms simulado)
        wait until (done = '1' or err = '1') for 5 ms;

        if done = '1' then
            report "[PASS] Teste 1: done='1' recebido (transferencia completa com ACK)";
        elsif err = '1' then
            report "[FAIL] Teste 1: err='1' inesperado (esperado done)" severity error;
            test_pass := false;
        else
            report "[FAIL] Teste 1: timeout - nem done nem err recebidos" severity error;
            test_pass := false;
        end if;

        wait for CLK_PERIOD * 20;

        -- ==============================================================
        -- TESTE 2: NACK — escravo não responde (SDA permanece alta)
        -- ==============================================================
        report "--- Teste 2: NACK (escravo nao responde) ---";
        slave_ack_enable <= '0';

        addr  <= "0011010";
        data  <= x"1E00";       -- R15 = Reset
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';

        wait until (done = '1' or err = '1') for 5 ms;

        if err = '1' then
            report "[PASS] Teste 2: err='1' recebido (NACK detectado corretamente)";
        elsif done = '1' then
            report "[FAIL] Teste 2: done='1' inesperado (esperado err)" severity error;
            test_pass := false;
        else
            report "[FAIL] Teste 2: timeout" severity error;
            test_pass := false;
        end if;

        wait for CLK_PERIOD * 20;

        -- ==============================================================
        -- TESTE 3: Segunda transferência após NACK (recuperação)
        -- ==============================================================
        report "--- Teste 3: Recuperacao apos NACK ---";
        slave_ack_enable <= '1';

        addr  <= "0011010";
        data  <= x"1201";       -- R9 = Active
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';

        wait until (done = '1' or err = '1') for 5 ms;

        if done = '1' then
            report "[PASS] Teste 3: Recuperacao OK, done='1'";
        else
            report "[FAIL] Teste 3: Nao recuperou apos NACK" severity error;
            test_pass := false;
        end if;

        -- ==============================================================
        -- RESULTADO
        -- ==============================================================
        wait for CLK_PERIOD * 10;
        if test_pass then
            report ">>> I2C MASTER TB: ALL TESTS PASSED <<<";
        else
            report ">>> I2C MASTER TB: ALGUNS TESTES FALHARAM <<<" severity failure;
        end if;

        wait;
    end process;

end architecture bench;
