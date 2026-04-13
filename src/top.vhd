-- =============================================================================
-- top.vhd
-- Entidade de topo da pedaleira de guitarra com overdrive.
-- Alvo: Cyclone IV EP4CE6E22C8 / Quartus 13.0 SP1
--
-- Fluxo de sinal:
--   Guitarra → [WM8731 ADC] → I2S RX → Overdrive DSP → I2S TX → [WM8731 DAC] → Amp
--
-- Pinos (ajustar no .qsf para a placa específica):
--   clk_50mhz    : clock de 50 MHz da placa
--   reset_n      : botão de reset (ativo baixo)
--   gain_sw[2:0] : 3 switches para controle de ganho do overdrive
--   led_*        : LEDs de status
--   aud_*        : interface com WM8731
--   i2c_*        : barramento I2C para configurar o WM8731
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity top is
    port (
        -- Sistema
        clk_50mhz       : in    std_logic;
        reset_n         : in    std_logic;          -- KEY0 (ativo baixo)

        -- Controles do usuário
        gain_sw         : in    std_logic_vector(2 downto 0);  -- SW[2:0]

        -- LEDs de status
        led_config_done : out   std_logic;          -- verde: codec configurado
        led_clipping    : out   std_logic;          -- vermelho: sinal saturando

        -- Interface com WM8731 — Áudio I2S
        aud_mclk        : out   std_logic;          -- master clock → WM8731
        aud_bclk        : out   std_logic;          -- bit clock
        aud_daclrck     : out   std_logic;          -- DAC left/right clock
        aud_dacdat      : out   std_logic;          -- DAC data (FPGA → codec)
        aud_adclrck     : in    std_logic;          -- ADC left/right clock (do codec)
        aud_adcdat      : in    std_logic;          -- ADC data (codec → FPGA)

        -- Interface com WM8731 — Configuração I2C
        i2c_sclk        : out   std_logic;
        i2c_sdat        : inout std_logic
    );
end entity top;

architecture rtl of top is

    -- =========================================================================
    -- Declaração de componentes
    -- =========================================================================

    component pll_audio is
        port (
            inclk0 : in  std_logic;
            c0     : out std_logic;
            locked : out std_logic
        );
    end component;

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

    component codec_config is
        generic (
            CLK_FREQ : integer
        );
        port (
            clk         : in    std_logic;
            reset_n     : in    std_logic;
            i2c_start   : out   std_logic;
            i2c_addr    : out   std_logic_vector(6 downto 0);
            i2c_data    : out   std_logic_vector(15 downto 0);
            i2c_done    : in    std_logic;
            i2c_err     : in    std_logic;
            config_done : out   std_logic
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

    -- =========================================================================
    -- Sinais internos
    -- =========================================================================

    -- PLL
    signal mclk         : std_logic;
    signal pll_locked   : std_logic;

    -- Reset ativo-baixo do sistema: '1' quando reset_n='1' e PLL travado
    signal sys_reset_n  : std_logic;

    -- I2C
    signal i2c_start    : std_logic;
    signal i2c_addr_s   : std_logic_vector(6 downto 0);
    signal i2c_data_s   : std_logic_vector(15 downto 0);
    signal i2c_done     : std_logic;
    signal i2c_err      : std_logic;
    signal cfg_done     : std_logic;

    -- I2S / áudio
    signal bclk_s       : std_logic;
    signal lrck_s       : std_logic;

    -- ADC → overdrive
    signal adc_left     : std_logic_vector(23 downto 0);
    signal adc_right    : std_logic_vector(23 downto 0);
    signal adc_valid    : std_logic;

    -- overdrive → DAC
    signal od_left      : std_logic_vector(23 downto 0);
    signal od_right     : std_logic_vector(23 downto 0);
    signal od_valid     : std_logic;
    signal od_clipping  : std_logic;

begin

    -- =========================================================================
    -- Reset: '1' (liberado) somente quando botão não pressionado e PLL travado
    -- =========================================================================
    sys_reset_n <= reset_n and pll_locked;

    -- =========================================================================
    -- PLL: 50 MHz → ~12.288 MHz (MCLK do WM8731)
    -- =========================================================================
    u_pll : pll_audio
        port map (
            inclk0 => clk_50mhz,
            c0     => mclk,
            locked => pll_locked
        );

    aud_mclk <= mclk;

    -- =========================================================================
    -- I2C Master
    -- =========================================================================
    u_i2c : i2c_master
        generic map (
            CLK_FREQ => 50_000_000,
            I2C_FREQ => 100_000
        )
        port map (
            clk     => clk_50mhz,
            reset_n => sys_reset_n,
            start   => i2c_start,
            addr    => i2c_addr_s,
            data    => i2c_data_s,
            done    => i2c_done,
            err     => i2c_err,
            i2c_scl => i2c_sclk,
            i2c_sda => i2c_sdat
        );

    -- =========================================================================
    -- Configuração do WM8731
    -- =========================================================================
    u_cfg : codec_config
        generic map (
            CLK_FREQ => 50_000_000
        )
        port map (
            clk         => clk_50mhz,
            reset_n     => sys_reset_n,
            i2c_start   => i2c_start,
            i2c_addr    => i2c_addr_s,
            i2c_data    => i2c_data_s,
            i2c_done    => i2c_done,
            i2c_err     => i2c_err,
            config_done => cfg_done
        );

    led_config_done <= cfg_done;

    -- =========================================================================
    -- I2S Receiver (ADC → FPGA)
    -- LRCK do ADC vem do próprio codec (aud_adclrck), mas como gerado pelo
    -- mesmo BCLK que o FPGA gera, é seguro usar o sinal gerado internamente.
    -- =========================================================================
    u_rx : i2s_receiver
        port map (
            clk        => clk_50mhz,
            reset_n    => sys_reset_n,
            bclk       => bclk_s,
            lrck       => lrck_s,
            adcdat     => aud_adcdat,
            left_data  => adc_left,
            right_data => adc_right,
            data_valid => adc_valid
        );

    -- =========================================================================
    -- DSP: Overdrive com soft clipping
    -- =========================================================================
    u_od : overdrive
        port map (
            clk        => clk_50mhz,
            reset_n    => sys_reset_n,
            gain_sw    => gain_sw,
            left_in    => adc_left,
            right_in   => adc_right,
            data_valid => adc_valid,
            left_out   => od_left,
            right_out  => od_right,
            valid_out  => od_valid,
            clipping   => od_clipping
        );

    led_clipping <= od_clipping;

    -- =========================================================================
    -- I2S Transmitter (FPGA → DAC)
    -- =========================================================================
    u_tx : i2s_transmitter
        port map (
            clk        => clk_50mhz,
            reset_n    => sys_reset_n,
            mclk       => mclk,
            left_data  => od_left,
            right_data => od_right,
            data_valid => od_valid,
            bclk       => bclk_s,
            lrck       => lrck_s,
            dacdat     => aud_dacdat
        );

    aud_bclk    <= bclk_s;
    aud_daclrck <= lrck_s;

end architecture rtl;
