-- =============================================================================
-- pll_audio.vhd
-- Wrapper do ALTPLL do Quartus para gerar 12.288 MHz (MCLK do WM8731)
-- a partir do clock de 50 MHz da placa.
--
-- Configuração do ALTPLL:
--   Entrada : 50.000 MHz
--   VCO     : 50 * 24 = 1200 MHz  (dentro da faixa 600–1300 MHz do Cyclone IV)
--   c0      : 1200 / 98 = 12.2448 MHz  (~12.288 MHz, desvio < 0.4%)
--
-- Obs: Para desvio zero, reconfigure o ALTPLL no MegaWizard com
--      multiplicador/divisor customizado. O valor acima é suficiente para
--      operação funcional a 48 kHz.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

entity pll_audio is
    port (
        inclk0  : in  std_logic;   -- 50 MHz (clock da placa)
        c0      : out std_logic;   -- ~12.288 MHz (MCLK para WM8731)
        locked  : out std_logic    -- '1' quando PLL travado
    );
end entity pll_audio;

architecture rtl of pll_audio is

    -- Componente ALTPLL do Quartus (gerado pelo MegaWizard)
    component altpll
        generic (
            clk0_divide_by          : natural;
            clk0_duty_cycle         : natural;
            clk0_multiply_by        : natural;
            clk0_phase_shift        : string;
            compensate_clock        : string;
            gate_lock_signal        : string;
            inclk0_input_frequency  : natural;   -- período em ps
            intended_device_family  : string;
            lpm_type                : string;
            operation_mode          : string;
            pll_type                : string;
            port_activeclock        : string;
            port_areset             : string;
            port_clkbad0            : string;
            port_clkena0            : string;
            port_clkloss            : string;
            port_clkswitch          : string;
            port_configupdate       : string;
            port_fbin               : string;
            port_inclk0             : string;
            port_inclk1             : string;
            port_locked             : string;
            port_pfdena             : string;
            port_phasecounterselect : string;
            port_phasedone          : string;
            port_phasestep          : string;
            port_phaseupdown        : string;
            port_pllena             : string;
            port_scanaclr           : string;
            port_scanclk            : string;
            port_scanclkena         : string;
            port_scandata           : string;
            port_scandataout        : string;
            port_scandone           : string;
            port_scanread           : string;
            port_scanwrite          : string;
            port_clk0               : string;
            port_clk1               : string;
            port_clk2               : string;
            port_clk3               : string;
            port_clk4               : string;
            port_clk5               : string;
            port_clkena0            : string;
            port_clkena1            : string;
            port_clkena2            : string;
            port_clkena3            : string;
            port_clkena4            : string;
            port_clkena5            : string;
            self_reset_on_loss_lock : string;
            width_clock             : natural
        );
        port (
            inclk  : in  std_logic_vector(1 downto 0);
            clk    : out std_logic_vector(4 downto 0);
            locked : out std_logic
        );
    end component;

    signal inclk_vec : std_logic_vector(1 downto 0);
    signal clk_vec   : std_logic_vector(4 downto 0);

begin

    inclk_vec <= '0' & inclk0;

    -- Instância do ALTPLL
    -- clk0_multiply_by=24, clk0_divide_by=98 → 50*24/98 = 12.244 MHz
    -- Para 12.288 MHz exato, use multiply=384, divide=1562 (verificar no MegaWizard)
    u_pll : altpll
        generic map (
            clk0_divide_by          => 98,
            clk0_duty_cycle         => 50,
            clk0_multiply_by        => 24,
            clk0_phase_shift        => "0",
            compensate_clock        => "CLK0",
            gate_lock_signal        => "NO",
            inclk0_input_frequency  => 20000,   -- 50 MHz = período de 20000 ps
            intended_device_family  => "Cyclone IV E",
            lpm_type                => "altpll",
            operation_mode          => "NORMAL",
            pll_type                => "AUTO",
            port_activeclock        => "PORT_UNUSED",
            port_areset             => "PORT_UNUSED",
            port_clkbad0            => "PORT_UNUSED",
            port_clkena0            => "PORT_UNUSED",
            port_clkloss            => "PORT_UNUSED",
            port_clkswitch          => "PORT_UNUSED",
            port_configupdate       => "PORT_UNUSED",
            port_fbin               => "PORT_UNUSED",
            port_inclk0             => "PORT_USED",
            port_inclk1             => "PORT_UNUSED",
            port_locked             => "PORT_USED",
            port_pfdena             => "PORT_UNUSED",
            port_phasecounterselect => "PORT_UNUSED",
            port_phasedone          => "PORT_UNUSED",
            port_phasestep          => "PORT_UNUSED",
            port_phaseupdown        => "PORT_UNUSED",
            port_pllena             => "PORT_UNUSED",
            port_scanaclr           => "PORT_UNUSED",
            port_scanclk            => "PORT_UNUSED",
            port_scanclkena         => "PORT_UNUSED",
            port_scandata           => "PORT_UNUSED",
            port_scandataout        => "PORT_UNUSED",
            port_scandone           => "PORT_UNUSED",
            port_scanread           => "PORT_UNUSED",
            port_scanwrite          => "PORT_UNUSED",
            port_clk0               => "PORT_USED",
            port_clk1               => "PORT_UNUSED",
            port_clk2               => "PORT_UNUSED",
            port_clk3               => "PORT_UNUSED",
            port_clk4               => "PORT_UNUSED",
            port_clk5               => "PORT_UNUSED",
            port_clkena1            => "PORT_UNUSED",
            port_clkena2            => "PORT_UNUSED",
            port_clkena3            => "PORT_UNUSED",
            port_clkena4            => "PORT_UNUSED",
            port_clkena5            => "PORT_UNUSED",
            self_reset_on_loss_lock => "OFF",
            width_clock             => 5
        )
        port map (
            inclk  => inclk_vec,
            clk    => clk_vec,
            locked => locked
        );

    c0 <= clk_vec(0);

end architecture rtl;
