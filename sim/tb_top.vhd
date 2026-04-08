-- =============================================================================
-- tb_top.vhd
-- Testbench de integração do sistema completo (top.vhd).
--
-- IMPORTANTE: Compile pll_audio_sim.vhd em vez de pll_audio.vhd.
-- O script sim_top.do faz isso automaticamente.
--
-- Fluxo do teste:
--   1. Reset → aguarda PLL (pll_audio_sim) travar
--   2. codec_config envia 9 registradores via I2C
--      → slave model responde com ACK automaticamente
--      → aguarda led_config_done='1'
--   3. Injeta sinal de áudio via I2S (aud_adcdat) com amplitude grande
--      para forçar overdrive (gain_sw="011" = 8x)
--   4. Verifica:
--      - aud_dacdat tem atividade (áudio sendo retransmitido)
--      - led_clipping='1' (sinal saturando com gain alto)
--   5. Repete com gain_sw="000" (1x) e sinal pequeno:
--      - led_clipping deve ser '0'
--
-- Como executar no ModelSim:
--   do sim/modelsim/sim_top.do
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_top is
end entity tb_top;

architecture bench of tb_top is

    -- -------------------------------------------------------------------------
    -- DUT (top-level)
    -- -------------------------------------------------------------------------
    component top is
        port (
            clk_50mhz       : in    std_logic;
            reset_n         : in    std_logic;
            gain_sw         : in    std_logic_vector(2 downto 0);
            led_config_done : out   std_logic;
            led_clipping    : out   std_logic;
            aud_mclk        : out   std_logic;
            aud_bclk        : out   std_logic;
            aud_daclrck     : out   std_logic;
            aud_dacdat      : out   std_logic;
            aud_adclrck     : in    std_logic;
            aud_adcdat      : in    std_logic;
            i2c_sclk        : out   std_logic;
            i2c_sdat        : inout std_logic
        );
    end component;

    -- -------------------------------------------------------------------------
    -- Sinais
    -- -------------------------------------------------------------------------
    constant CLK_PERIOD  : time := 20 ns;     -- 50 MHz

    signal clk_50mhz       : std_logic := '0';
    signal reset_n         : std_logic := '0';
    signal gain_sw         : std_logic_vector(2 downto 0) := "011";  -- 8x
    signal led_config_done : std_logic;
    signal led_clipping    : std_logic;
    signal aud_mclk        : std_logic;
    signal aud_bclk        : std_logic;
    signal aud_daclrck     : std_logic;
    signal aud_dacdat      : std_logic;
    signal aud_adclrck     : std_logic := '0';
    signal aud_adcdat      : std_logic := '0';
    signal i2c_sclk        : std_logic;
    signal i2c_sdat        : std_logic;

    -- -------------------------------------------------------------------------
    -- Gerador de áudio I2S (injeta bits no aud_adcdat sincronizado com bclk/lrck)
    -- -------------------------------------------------------------------------
    -- Amostra a injetar: amplitude máxima para forçar overdrive
    signal inject_sample   : std_logic_vector(23 downto 0) := x"600000";
    signal inject_enable   : std_logic := '0';

    -- Contagem de testes
    shared variable pass_cnt : integer := 0;
    shared variable fail_cnt : integer := 0;

begin

    -- Pull-up na SDA
    i2c_sdat <= 'H';

    -- -------------------------------------------------------------------------
    -- Instância do DUT
    -- -------------------------------------------------------------------------
    u_dut : top
        port map (
            clk_50mhz       => clk_50mhz,
            reset_n         => reset_n,
            gain_sw         => gain_sw,
            led_config_done => led_config_done,
            led_clipping    => led_clipping,
            aud_mclk        => aud_mclk,
            aud_bclk        => aud_bclk,
            aud_daclrck     => aud_daclrck,
            aud_dacdat      => aud_dacdat,
            aud_adclrck     => aud_adclrck,
            aud_adcdat      => aud_adcdat,
            i2c_sclk        => i2c_sclk,
            i2c_sdat        => i2c_sdat
        );

    -- -------------------------------------------------------------------------
    -- Clock principal
    -- -------------------------------------------------------------------------
    clk_50mhz <= not clk_50mhz after CLK_PERIOD / 2;

    -- -------------------------------------------------------------------------
    -- Modelo de escravo I2C (ACK automático para todas as transferências)
    -- Necessário para que codec_config conclua e led_config_done suba.
    -- -------------------------------------------------------------------------
    i2c_slave_model : process
        variable scl_cnt : integer;
    begin
        -- Aguarda sistema sair do reset
        wait until reset_n = '1';
        wait for 2 us;

        loop
            -- Aguarda condição de START (SDA cai com SCL alto)
            wait until (falling_edge(i2c_sdat) and i2c_sclk = '1')
                       for 20 ms;

            if i2c_sdat'event then
                -- 3 bytes por transferência I2C do WM8731
                for byte_num in 0 to 2 loop
                    scl_cnt := 0;
                    -- Conta 8 bordas de subida (1 byte)
                    while scl_cnt < 8 loop
                        wait until rising_edge(i2c_sclk) for 5 ms;
                        if i2c_sclk'event then
                            scl_cnt := scl_cnt + 1;
                        end if;
                    end loop;
                    -- Slot de ACK: aguarda SCL baixar, puxa SDA para '0'
                    wait until falling_edge(i2c_sclk) for 3 ms;
                    if i2c_sclk'event then
                        wait for 1 us;
                        i2c_sdat <= '0';        -- ACK
                        wait until falling_edge(i2c_sclk) for 3 ms;
                        wait for 100 ns;
                        i2c_sdat <= 'Z';        -- libera
                    end if;
                end loop;
            end if;
        end loop;
    end process;

    -- -------------------------------------------------------------------------
    -- Gerador de dados I2S (injeta áudio no aud_adcdat)
    -- Sincronizado com o BCLK e LRCK gerados pelo DUT.
    -- Transmite a mesma amostra (inject_sample) nos dois canais.
    -- -------------------------------------------------------------------------
    i2s_data_gen : process
        variable bit_idx  : integer;
        variable samp     : std_logic_vector(23 downto 0);
        variable is_left  : boolean;
        variable bclk_cnt : integer;
    begin
        aud_adcdat  <= '0';
        aud_adclrck <= '0';

        -- Aguarda sistema ativo
        wait until inject_enable = '1';

        loop
            exit when inject_enable = '0';

            samp     := inject_sample;
            is_left  := true;
            bclk_cnt := 0;

            -- Aguarda borda de subida do LRCK (início do canal LEFT)
            wait until rising_edge(aud_daclrck) for 1 ms;
            exit when inject_enable = '0';

            -- Envia canal LEFT (24 bits MSB first)
            -- No I2S, dados mudam na borda de subida do BCLK e são válidos na borda de descida
            for i in 23 downto 0 loop
                wait until rising_edge(aud_bclk) for 1 ms;
                exit when inject_enable = '0';
                aud_adcdat <= samp(i);
            end loop;
            -- Bits de padding até LRCK cair
            wait until falling_edge(aud_daclrck) for 1 ms;
            exit when inject_enable = '0';

            -- Envia canal RIGHT (mesma amostra)
            for i in 23 downto 0 loop
                wait until rising_edge(aud_bclk) for 1 ms;
                exit when inject_enable = '0';
                aud_adcdat <= samp(i);
            end loop;

        end loop;

        aud_adcdat <= '0';
    end process;

    -- -------------------------------------------------------------------------
    -- Estímulos principais
    -- -------------------------------------------------------------------------
    process
        variable dacdat_toggle : integer := 0;
        variable clip_seen     : boolean := false;
    begin
        report "=== TOP INTEGRATION TESTBENCH INICIADO ===";
        report "Nota: Este TB tem duracao longa (~3 ms simulados para configuracao I2C)";

        -- Reset
        reset_n <= '0';
        wait for CLK_PERIOD * 20;
        reset_n <= '1';

        -- ==============================================================
        -- FASE 1: Aguardar configuração do codec (led_config_done='1')
        -- codec_config envia 9 registradores × ~3 bytes I2C cada.
        -- Com I2C em 100 kHz e 9 palavras: ~9 × (27 SCL cycles) / 100kHz
        -- ≈ 2.4 ms. Damos timeout generoso de 10 ms.
        -- ==============================================================
        report "--- Fase 1: Aguardando configuracao do codec ---";
        wait until led_config_done = '1' for 10 ms;

        if led_config_done = '1' then
            pass_cnt := pass_cnt + 1;
            report "[PASS] Fase 1: led_config_done='1' (codec configurado)";
        else
            fail_cnt := fail_cnt + 1;
            report "[FAIL] Fase 1: timeout aguardando led_config_done" severity error;
        end if;

        -- ==============================================================
        -- FASE 2: Overdrive ativo — gain=8x + sinal grande → clipping
        -- ==============================================================
        report "--- Fase 2: gain=8x + sinal grande -> led_clipping='1' ---";
        gain_sw        <= "011";           -- 8x
        inject_sample  <= x"600000";       -- amplitude: 6291456 (acima do limiar com 8x)
        inject_enable  <= '1';

        -- Aguarda led_clipping subir (até 5 frames I2S ≈ 100 µs)
        wait until led_clipping = '1' for 200 us;

        if led_clipping = '1' then
            pass_cnt := pass_cnt + 1;
            report "[PASS] Fase 2: led_clipping='1' (overdrive ativo com gain=8x)";
        else
            fail_cnt := fail_cnt + 1;
            report "[FAIL] Fase 2: led_clipping nao subiu (overdrive nao detectado)" severity error;
        end if;

        -- ==============================================================
        -- FASE 3: Verificar atividade no aud_dacdat
        -- ==============================================================
        report "--- Fase 3: Verificando atividade no DAC ---";
        dacdat_toggle := 0;
        for i in 0 to 63 loop
            wait until rising_edge(aud_bclk) for 1 ms;
            if aud_dacdat = '1' then
                dacdat_toggle := dacdat_toggle + 1;
            end if;
        end loop;

        if dacdat_toggle > 0 then
            pass_cnt := pass_cnt + 1;
            report "[PASS] Fase 3: aud_dacdat tem atividade (" &
                   integer'image(dacdat_toggle) & "/64 bits em '1')";
        else
            fail_cnt := fail_cnt + 1;
            report "[FAIL] Fase 3: aud_dacdat sem atividade" severity error;
        end if;

        -- ==============================================================
        -- FASE 4: gain=0 + sinal pequeno → sem clipping
        -- ==============================================================
        report "--- Fase 4: gain=1x + sinal pequeno -> sem clipping ---";
        inject_enable  <= '0';
        wait for 10 us;
        gain_sw        <= "000";           -- 1x (sem ganho)
        inject_sample  <= x"001000";       -- amplitude bem abaixo de T
        inject_enable  <= '1';
        wait for 5 us;

        -- Aguarda 5 frames e verifica que clipping nao ocorre
        wait for 100 us;
        if led_clipping = '0' then
            pass_cnt := pass_cnt + 1;
            report "[PASS] Fase 4: led_clipping='0' correto (sinal pequeno sem overdrive)";
        else
            fail_cnt := fail_cnt + 1;
            report "[FAIL] Fase 4: led_clipping='1' inesperado com sinal pequeno" severity error;
        end if;

        inject_enable <= '0';

        -- ==============================================================
        -- RESULTADO FINAL
        -- ==============================================================
        wait for CLK_PERIOD * 20;
        report "=== RESULTADO: " &
               integer'image(pass_cnt) & " passaram, " &
               integer'image(fail_cnt) & " falharam ===";

        if fail_cnt = 0 then
            report ">>> TOP INTEGRATION TB: ALL TESTS PASSED <<<";
        else
            report ">>> TOP INTEGRATION TB: " &
                   integer'image(fail_cnt) & " FALHA(S) <<<" severity failure;
        end if;

        wait;
    end process;

end architecture bench;
