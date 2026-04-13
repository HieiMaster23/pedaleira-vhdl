-- =============================================================================
-- tb_overdrive.vhd
-- Testbench self-checking para o módulo overdrive.vhd
--
-- Verifica o soft clipper de 3 segmentos:
--   Região linear  : |y| < T       → out = y
--   Região knee    : T ≤ |y| < 2T  → out = T + (|y| − T) / 2
--   Saturação      : |y| ≥ 2T      → out = ±T3_2
--
-- Constantes do DUT:
--   T    = 2^22 = 4_194_304 = x"400000"
--   T2   = 2^23 = 8_388_608
--   T3_2 = 6_291_456          = x"600000"
--
-- Latência do DUT: 2 ciclos de clk (pipeline de 2 estágios).
--
-- Como executar no ModelSim:
--   do sim/modelsim/sim_overdrive.do
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_overdrive is
end entity tb_overdrive;

architecture bench of tb_overdrive is

    -- -------------------------------------------------------------------------
    -- DUT
    -- -------------------------------------------------------------------------
    component overdrive is
        port (
            clk        : in  std_logic;
            reset_n    : in  std_logic;
            gain_sw    : in  std_logic_vector(2 downto 0);
            left_in    : in  std_logic_vector(23 downto 0);
            right_in   : in  std_logic_vector(23 downto 0);
            data_valid : in  std_logic;
            left_out   : out std_logic_vector(23 downto 0);
            right_out  : out std_logic_vector(23 downto 0);
            valid_out  : out std_logic;
            clipping   : out std_logic
        );
    end component;

    -- -------------------------------------------------------------------------
    -- Sinais
    -- -------------------------------------------------------------------------
    signal clk        : std_logic := '0';
    signal reset_n    : std_logic := '0';
    signal gain_sw    : std_logic_vector(2 downto 0) := "000";
    signal left_in    : std_logic_vector(23 downto 0) := (others => '0');
    signal right_in   : std_logic_vector(23 downto 0) := (others => '0');
    signal data_valid : std_logic := '0';
    signal left_out   : std_logic_vector(23 downto 0);
    signal right_out  : std_logic_vector(23 downto 0);
    signal valid_out  : std_logic;
    signal clipping   : std_logic;

    -- -------------------------------------------------------------------------
    -- Constantes de referência (espelham o DUT)
    -- -------------------------------------------------------------------------
    constant T    : integer := 4_194_304;   -- 2^22
    constant T2   : integer := 8_388_608;   -- 2^23
    constant T3_2 : integer := 6_291_456;   -- 3 * 2^22 / 2

    -- -------------------------------------------------------------------------
    -- Contadores de testes
    -- -------------------------------------------------------------------------
    shared variable tests_run    : integer := 0;
    shared variable tests_passed : integer := 0;

    -- -------------------------------------------------------------------------
    -- Auxiliares
    -- -------------------------------------------------------------------------
    constant CLK_PERIOD : time := 20 ns;   -- 50 MHz

    -- Aplica um vetor de teste e verifica a saída após 2 ciclos de latência
    procedure apply_and_check(
        signal clk        : in  std_logic;
        signal gain_sw    : out std_logic_vector(2 downto 0);
        signal left_in    : out std_logic_vector(23 downto 0);
        signal right_in   : out std_logic_vector(23 downto 0);
        signal data_valid : out std_logic;
        signal left_out   : in  std_logic_vector(23 downto 0);
        signal valid_out  : in  std_logic;
        signal clipping   : in  std_logic;
        gain_val   : in std_logic_vector(2 downto 0);
        input_val  : in integer;
        expect_out : in integer;
        expect_clip: in std_logic;
        test_name  : in string
    ) is
        variable got_out : integer;
    begin
        -- Aplica entradas
        gain_sw    <= gain_val;
        left_in    <= std_logic_vector(to_signed(input_val, 24));
        right_in   <= std_logic_vector(to_signed(input_val, 24));
        data_valid <= '1';
        wait until rising_edge(clk);
        data_valid <= '0';

        -- Aguarda 2 ciclos de latência do pipeline
        wait until rising_edge(clk);
        wait until rising_edge(clk);

        -- Aguarda valid_out (deve ter chegado)
        wait for 1 ns;  -- estabilização

        got_out := to_integer(signed(left_out));
        tests_run := tests_run + 1;

        if got_out = expect_out and clipping = expect_clip then
            tests_passed := tests_passed + 1;
            report "[PASS] " & test_name &
                   " | in=" & integer'image(input_val) &
                   " gain=" & integer'image(to_integer(unsigned(gain_val))) &
                   " out=" & integer'image(got_out);
        else
            report "[FAIL] " & test_name &
                   " | in=" & integer'image(input_val) &
                   " gain=" & integer'image(to_integer(unsigned(gain_val))) &
                   " | expected out=" & integer'image(expect_out) &
                   " got=" & integer'image(got_out) &
                   " | expected clip=" & std_logic'image(expect_clip) &
                   " got=" & std_logic'image(clipping)
            severity error;
        end if;
    end procedure;

begin

    -- -------------------------------------------------------------------------
    -- Instância do DUT
    -- -------------------------------------------------------------------------
    u_dut : overdrive
        port map (
            clk        => clk,
            reset_n    => reset_n,
            gain_sw    => gain_sw,
            left_in    => left_in,
            right_in   => right_in,
            data_valid => data_valid,
            left_out   => left_out,
            right_out  => right_out,
            valid_out  => valid_out,
            clipping   => clipping
        );

    -- -------------------------------------------------------------------------
    -- Gerador de clock
    -- -------------------------------------------------------------------------
    clk <= not clk after CLK_PERIOD / 2;

    -- -------------------------------------------------------------------------
    -- Processo de estímulos e verificação
    -- -------------------------------------------------------------------------
    process
        variable v_latency_ok : boolean;
        variable v_valid_cycle : integer;
    begin
        -- Reset inicial
        reset_n    <= '0';
        data_valid <= '0';
        wait for CLK_PERIOD * 5;
        reset_n <= '1';
        wait for CLK_PERIOD * 3;

        report "=== OVERDRIVE TESTBENCH INICIADO ===";
        report "Constantes: T=" & integer'image(T) &
               " T2=" & integer'image(T2) &
               " T3_2=" & integer'image(T3_2);

        -- =====================================================================
        -- GRUPO 1: gain=0 (1x) — sem amplificação
        -- Verifica as 3 regiões do clipper com sinal de entrada direto
        -- =====================================================================
        report "--- Grupo 1: gain=0 (1x) ---";

        -- Região linear: sinal pequeno → passa sem distorção
        apply_and_check(clk, gain_sw, left_in, right_in, data_valid,
                        left_out, valid_out, clipping,
                        "000", 256, 256, '0',
                        "Linear: 0x000100 passthrough");

        -- Limite inferior da região linear
        apply_and_check(clk, gain_sw, left_in, right_in, data_valid,
                        left_out, valid_out, clipping,
                        "000", T - 1, T - 1, '0',
                        "Linear: T-1 passthrough");

        -- Exatamente no limiar T (início do knee)
        -- out = T + (T-T)/2 = T
        apply_and_check(clk, gain_sw, left_in, right_in, data_valid,
                        left_out, valid_out, clipping,
                        "000", T, T, '1',
                        "Knee boundary: input=T, out=T");

        -- Meio do knee: input = 0x500000 = 5242880
        -- out = T + (5242880 - T)/2 = 4194304 + 524288 = 4718592 = 0x480000
        apply_and_check(clk, gain_sw, left_in, right_in, data_valid,
                        left_out, valid_out, clipping,
                        "000", 5_242_880, 4_718_592, '1',
                        "Knee middle: 0x500000 -> 0x480000");

        -- Próximo do limite superior do knee: input = 0x7FFFFF = 8388607
        -- out = T + (8388607 - T)/2 = 4194304 + 2097151 = 6291455 = 0x5FFFFF
        apply_and_check(clk, gain_sw, left_in, right_in, data_valid,
                        left_out, valid_out, clipping,
                        "000", 8_388_607, 6_291_455, '1',
                        "Knee top: 0x7FFFFF -> 0x5FFFFF");

        -- =====================================================================
        -- GRUPO 2: gain=1 (2x) — dobra o sinal antes de clipar
        -- =====================================================================
        report "--- Grupo 2: gain=1 (2x) ---";

        -- input=0x200000 (T/2), após 2x → T → knee boundary
        -- out = T + (T-T)/2 = T = 0x400000
        apply_and_check(clk, gain_sw, left_in, right_in, data_valid,
                        left_out, valid_out, clipping,
                        "001", T/2, T, '1',
                        "gain=2x: T/2 -> knee at T");

        -- input=0x300000 (T*3/4), após 2x → T*3/2 = T3_2 (no meio do knee)
        -- abs_y = 6291456 = T3_2
        -- out = T + (T3_2 - T)/2 = T + T/4 = 5242880 = 0x500000
        apply_and_check(clk, gain_sw, left_in, right_in, data_valid,
                        left_out, valid_out, clipping,
                        "001", T*3/4, T + T/4, '1',
                        "gain=2x: 3T/4 -> knee mid");

        -- input=T (0x400000), após 2x → 2T → saturação
        -- out = T3_2 = 0x600000
        apply_and_check(clk, gain_sw, left_in, right_in, data_valid,
                        left_out, valid_out, clipping,
                        "001", T, T3_2, '1',
                        "gain=2x: T -> saturation -> T3_2");

        -- =====================================================================
        -- GRUPO 3: gain=7 (128x) — overdrive máximo
        -- =====================================================================
        report "--- Grupo 3: gain=7 (128x, overdrive maximo) ---";

        -- input=0x000100 (256), após 128x = 32768 < T → linear
        apply_and_check(clk, gain_sw, left_in, right_in, data_valid,
                        left_out, valid_out, clipping,
                        "111", 256, 32768, '0',
                        "gain=128x: small signal stays linear");

        -- input=0x008000 (32768 = T/128), após 128x = T → knee boundary
        -- out = T = 0x400000
        apply_and_check(clk, gain_sw, left_in, right_in, data_valid,
                        left_out, valid_out, clipping,
                        "111", 32768, T, '1',
                        "gain=128x: T/128 -> knee at T");

        -- input=0x010000 (65536 = T/64), após 128x = 2T → saturação
        -- out = T3_2 = 0x600000
        apply_and_check(clk, gain_sw, left_in, right_in, data_valid,
                        left_out, valid_out, clipping,
                        "111", 65536, T3_2, '1',
                        "gain=128x: T/64 -> saturation");

        -- input maior → saturação máxima (out fixo em T3_2)
        apply_and_check(clk, gain_sw, left_in, right_in, data_valid,
                        left_out, valid_out, clipping,
                        "111", 100_000, T3_2, '1',
                        "gain=128x: large input -> saturation");

        -- =====================================================================
        -- GRUPO 4: Entradas negativas (simetria do clipper)
        -- =====================================================================
        report "--- Grupo 4: Simetria (entradas negativas) ---";

        -- input=-256 → linear → out=-256
        apply_and_check(clk, gain_sw, left_in, right_in, data_valid,
                        left_out, valid_out, clipping,
                        "000", -256, -256, '0',
                        "Neg linear: -256 passthrough");

        -- input=-T → knee boundary → out=-T
        apply_and_check(clk, gain_sw, left_in, right_in, data_valid,
                        left_out, valid_out, clipping,
                        "000", -T, -T, '1',
                        "Neg knee: -T -> -T");

        -- input=-5242880 → knee → out = -(T + 524288) = -4718592
        apply_and_check(clk, gain_sw, left_in, right_in, data_valid,
                        left_out, valid_out, clipping,
                        "000", -5_242_880, -4_718_592, '1',
                        "Neg knee mid: -0x500000 -> -0x480000");

        -- input=-T com gain=1 (2x) → -2T → saturação → out=-T3_2
        apply_and_check(clk, gain_sw, left_in, right_in, data_valid,
                        left_out, valid_out, clipping,
                        "001", -T, -T3_2, '1',
                        "Neg sat: gain=2x, -T -> -T3_2");

        -- =====================================================================
        -- GRUPO 5: Zero e bordas
        -- =====================================================================
        report "--- Grupo 5: Casos de borda ---";

        -- input=0 → out=0
        apply_and_check(clk, gain_sw, left_in, right_in, data_valid,
                        left_out, valid_out, clipping,
                        "000", 0, 0, '0',
                        "Zero input -> zero output");

        -- input=1 (mínimo positivo) → linear → out=1
        apply_and_check(clk, gain_sw, left_in, right_in, data_valid,
                        left_out, valid_out, clipping,
                        "000", 1, 1, '0',
                        "Min positive: 1 -> 1");

        -- =====================================================================
        -- VERIFICAÇÃO DE LATÊNCIA
        -- O pipeline tem 2 estágios registrados (apply_gain → soft_clip),
        -- mas ambos são capturados em bordas consecutivas, resultando em
        -- 1 período de clock de latência:
        --
        --   T1 (borda onde data_valid='1' é capturado):
        --        Stage 1 registra: s1_valid='1', s1_left/right válidos
        --   T2 (borda seguinte):
        --        Stage 2 registra: s2_valid='1' → valid_out='1'  ← saída aqui
        --   T3: s2_valid volta a '0' (pulso de 1 ciclo)
        -- =====================================================================
        report "--- Verificacao de latencia (1 periodo de clock) ---";

        gain_sw    <= "000";
        left_in    <= x"001000";
        right_in   <= x"001000";
        data_valid <= '1';
        wait until rising_edge(clk);   -- T1: DUT captura data_valid='1'
        data_valid <= '0';

        -- T1 + 1 ns: Stage 2 ainda não atualizou → valid_out deve ser '0'
        wait for 1 ns;
        if valid_out = '0' then
            tests_passed := tests_passed + 1;
            report "[PASS] Latencia: valid_out='0' no proprio ciclo de captura";
        else
            report "[FAIL] Latencia: valid_out='1' prematuramente no ciclo de captura"
                severity error;
        end if;
        tests_run := tests_run + 1;

        -- T2 (1 periodo de clock apos data_valid): Stage 2 atualiza → valid_out='1'
        wait until rising_edge(clk);
        wait for 1 ns;
        if valid_out = '1' then
            tests_passed := tests_passed + 1;
            report "[PASS] Latencia: valid_out='1' em T+1 ciclo (correto)";
        else
            report "[FAIL] Latencia: valid_out nao subiu 1 ciclo apos data_valid"
                severity error;
        end if;
        tests_run := tests_run + 1;

        -- =====================================================================
        -- RESULTADO FINAL
        -- =====================================================================
        wait for CLK_PERIOD * 5;
        report "=== RESULTADO: " &
               integer'image(tests_passed) & "/" &
               integer'image(tests_run) & " testes passaram ===";

        if tests_passed = tests_run then
            report ">>> OVERDRIVE TB: ALL TESTS PASSED <<<";
        else
            report ">>> OVERDRIVE TB: " &
                   integer'image(tests_run - tests_passed) &
                   " TESTE(S) FALHARAM <<<" severity failure;
        end if;

        wait;
    end process;

end architecture bench;
