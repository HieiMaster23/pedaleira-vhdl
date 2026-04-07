-- =============================================================================
-- overdrive.vhd
-- Efeito de overdrive digital com soft clipping cúbico.
--
-- Algoritmo (3 segmentos, normalizado ao limiar T):
--
--   Passo 1 — Ganho variável:
--     y = audio_in <<< gain_sw   (shift aritmético com saturação)
--     gain_sw(2:0) → shifts de 0 a 7 bits → fator de ganho 1x a 128x
--
--   Passo 2 — Soft clipper cúbico por partes:
--     Seja T = 2^22 (1/2 do fundo de escala de 24 bits)
--
--     se |y| >= 2T  → out = ±(2*T/3)            [saturação dura]
--     se T <= |y| < 2T → out = sgn(y)*(3T/2 - T²/(2|y|))  [curva suave]
--     se |y| < T   → out = y                    [linear]
--
--   Nota: a região T ≤ |y| < 2T é aproximada em ponto-fixo por:
--     out = sgn(y) * (3*T/2 - T^2 / (2*|y|))
--
--   Para evitar divisão em hardware, usamos uma aproximação linear de 2 segmentos
--   que é sintetizável diretamente em LEs:
--
--     se |y| < T:      out = y
--     se T <= |y| < 2T: out = sgn(y) * (T + (2T - |y|) / 2)  [knee linear]
--     se |y| >= 2T:    out = sgn(y) * T * 3/2  (fixo)
--
--   Esta aproximação produz overdrive warm (semelhante a tube screamer) sem
--   precisar de multiplicador ou divisor, usando apenas adições e shifts.
--
-- Latência: 2 ciclos de clock do sistema.
-- Bits: entrada/saída 24 bits, aritmética interna 26 bits.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity overdrive is
    port (
        clk         : in  std_logic;
        reset_n     : in  std_logic;

        -- Controle de ganho (SW[2:0] da placa)
        -- 000 = ganho 1x (bypass suave)
        -- 111 = ganho 128x (overdrive intenso)
        gain_sw     : in  std_logic_vector(2 downto 0);

        -- Amostras de áudio (24 bits, complemento de dois)
        left_in     : in  std_logic_vector(23 downto 0);
        right_in    : in  std_logic_vector(23 downto 0);
        data_valid  : in  std_logic;   -- pulso: novos dados na entrada

        left_out    : out std_logic_vector(23 downto 0);
        right_out   : out std_logic_vector(23 downto 0);
        valid_out   : out std_logic;   -- pulso: saída pronta (2 ciclos após entrada)

        clipping    : out std_logic    -- '1' quando saturação ativa (para LED)
    );
end entity overdrive;

architecture rtl of overdrive is

    -- Limiar T = 2^22 = 4_194_304 (em 26 bits para aritmética interna)
    constant T     : signed(25 downto 0) := to_signed(4_194_304, 26);
    constant T2    : signed(25 downto 0) := to_signed(8_388_608, 26);  -- 2*T
    constant T3_2  : signed(25 downto 0) := to_signed(6_291_456, 26);  -- 3*T/2

    -- Função: aplica ganho com saturação a 26 bits
    -- (entram 24 bits, saem 26 bits após shift)
    function apply_gain(sample : signed(23 downto 0);
                        gain   : std_logic_vector(2 downto 0))
                        return signed is
        variable ext  : signed(25 downto 0);
        variable g    : integer range 0 to 7;
        variable tmp  : signed(25 downto 0);
        constant MAX_POS : signed(25 downto 0) := (25 => '0', others => '1');
        constant MAX_NEG : signed(25 downto 0) := (25 => '1', others => '0');
    begin
        ext := resize(sample, 26);
        g   := to_integer(unsigned(gain));

        -- Shift aritmético com saturação
        case g is
            when 0 => tmp := ext;
            when 1 =>
                if ext > MAX_POS / 2 then tmp := MAX_POS;
                elsif ext < MAX_NEG / 2 then tmp := MAX_NEG;
                else tmp := ext sll 1; end if;
            when 2 =>
                if ext > MAX_POS / 4 then tmp := MAX_POS;
                elsif ext < MAX_NEG / 4 then tmp := MAX_NEG;
                else tmp := ext sll 2; end if;
            when 3 =>
                if ext > MAX_POS / 8 then tmp := MAX_POS;
                elsif ext < MAX_NEG / 8 then tmp := MAX_NEG;
                else tmp := ext sll 3; end if;
            when 4 =>
                if ext > MAX_POS / 16 then tmp := MAX_POS;
                elsif ext < MAX_NEG / 16 then tmp := MAX_NEG;
                else tmp := ext sll 4; end if;
            when 5 =>
                if ext > MAX_POS / 32 then tmp := MAX_POS;
                elsif ext < MAX_NEG / 32 then tmp := MAX_NEG;
                else tmp := ext sll 5; end if;
            when 6 =>
                if ext > MAX_POS / 64 then tmp := MAX_POS;
                elsif ext < MAX_NEG / 64 then tmp := MAX_NEG;
                else tmp := ext sll 6; end if;
            when others =>
                if ext > MAX_POS / 128 then tmp := MAX_POS;
                elsif ext < MAX_NEG / 128 then tmp := MAX_NEG;
                else tmp := ext sll 7; end if;
        end case;

        return tmp;
    end function;

    -- Função: soft clipper linear de 3 segmentos
    function soft_clip(y : signed(25 downto 0)) return signed is
        variable abs_y : signed(25 downto 0);
        variable result: signed(25 downto 0);
    begin
        if y < 0 then
            abs_y := -y;
        else
            abs_y := y;
        end if;

        if abs_y >= T2 then
            -- Saturação: ±3T/2
            if y >= 0 then result := T3_2;
            else            result := -T3_2; end if;

        elsif abs_y >= T then
            -- Knee suave: out = sgn(y) * (T + (2T - abs_y) / 2)
            --           = sgn(y) * (T + T - abs_y/2)
            --           = sgn(y) * (2T - abs_y/2)   ... simplificado
            -- Valor no ponto T:   2T - T/2 = 3T/2 ✓ (continua em T3_2)
            -- Valor no ponto 2T:  2T - T   = T     ... declive corretamente < T3_2
            -- Nota: a fórmula correta para continuidade em T é:
            --   out(T) = T (do segmento linear)
            --   out(2T) = T3_2 (saturação)
            -- Usamos: out = T + (abs_y - T) * (T3_2 - T) / T
            --             = T + (abs_y - T) / 2    (pois T3_2 - T = T/2)
            result := T + shift_right(abs_y - T, 1);
            if y < 0 then result := -result; end if;

        else
            -- Região linear: sem clipping
            result := y;
        end if;

        return result;
    end function;

    -- Pipeline estágio 1: aplicar ganho
    signal s1_left  : signed(25 downto 0) := (others => '0');
    signal s1_right : signed(25 downto 0) := (others => '0');
    signal s1_valid : std_logic := '0';

    -- Pipeline estágio 2: soft clip e truncar para 24 bits
    signal s2_left  : signed(23 downto 0) := (others => '0');
    signal s2_right : signed(23 downto 0) := (others => '0');
    signal s2_valid : std_logic := '0';
    signal s2_clip  : std_logic := '0';

begin

    -- ==========================================================================
    -- Estágio 1: Amplificação com saturação (registrado)
    -- ==========================================================================
    process(clk, reset_n)
    begin
        if reset_n = '0' then
            s1_left  <= (others => '0');
            s1_right <= (others => '0');
            s1_valid <= '0';
        elsif rising_edge(clk) then
            s1_valid <= data_valid;
            if data_valid = '1' then
                s1_left  <= apply_gain(signed(left_in),  gain_sw);
                s1_right <= apply_gain(signed(right_in), gain_sw);
            end if;
        end if;
    end process;

    -- ==========================================================================
    -- Estágio 2: Soft clipping e truncamento para 24 bits (registrado)
    -- ==========================================================================
    process(clk, reset_n)
        variable cl, cr : signed(25 downto 0);
    begin
        if reset_n = '0' then
            s2_left  <= (others => '0');
            s2_right <= (others => '0');
            s2_valid <= '0';
            s2_clip  <= '0';
        elsif rising_edge(clk) then
            s2_valid <= s1_valid;
            if s1_valid = '1' then
                cl := soft_clip(s1_left);
                cr := soft_clip(s1_right);

                -- Trunca os 2 MSBs (redundantes após clipping) → 24 bits
                s2_left  <= cl(23 downto 0);
                s2_right <= cr(23 downto 0);

                -- Detecta clipping ativo
                if (abs(s1_left) >= T) or (abs(s1_right) >= T) then
                    s2_clip <= '1';
                else
                    s2_clip <= '0';
                end if;
            end if;
        end if;
    end process;

    -- Saídas
    left_out  <= std_logic_vector(s2_left);
    right_out <= std_logic_vector(s2_right);
    valid_out <= s2_valid;
    clipping  <= s2_clip;

end architecture rtl;
