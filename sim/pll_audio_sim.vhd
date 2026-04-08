-- =============================================================================
-- pll_audio_sim.vhd
-- Modelo comportamental do PLL para simulação no ModelSim.
-- Substitui pll_audio.vhd nos scripts de simulação, evitando a dependência
-- com a biblioteca altera_mf (necessária para o ALTPLL real).
--
-- Comportamento:
--   - Gera c0 = inclk0 / 4  →  50 MHz / 4 = 12.5 MHz
--     (próximo dos 12.288 MHz reais, suficiente para verificação funcional)
--   - locked sobe para '1' após 1 µs (simula tempo de travamento do PLL)
--
-- IMPORTANTE: Este arquivo tem a MESMA entidade de pll_audio.vhd.
-- Compile este arquivo em vez de pll_audio.vhd nos scripts de simulação.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

entity pll_audio is
    port (
        inclk0  : in  std_logic;
        c0      : out std_logic;
        locked  : out std_logic
    );
end entity pll_audio;

architecture sim of pll_audio is
    signal div_cnt : integer range 0 to 3 := 0;
    signal c0_r    : std_logic := '0';
begin

    -- Divisor de clock por 4
    process(inclk0)
    begin
        if rising_edge(inclk0) then
            if div_cnt = 3 then
                div_cnt <= 0;
                c0_r    <= not c0_r;
            else
                div_cnt <= div_cnt + 1;
            end if;
        end if;
    end process;

    c0 <= c0_r;

    -- locked sobe após 1 µs (simula lock time do PLL real)
    process
    begin
        locked <= '0';
        wait for 1 us;
        locked <= '1';
        wait;
    end process;

end architecture sim;
