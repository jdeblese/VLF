library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
package clockgen_comp is
	type clockgen_status is record
		done      : std_logic;
		locked    : std_logic;
		clkin_err : std_logic;
		clkfx_err : std_logic;
	end record;
end package;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library UNISIM;
use UNISIM.VComponents.all;

use work.clockgen_comp.all;

entity toplevel is
	Port (
		RST : IN STD_LOGIC;
		CLK : in  STD_LOGIC;
		LED : OUT STD_LOGIC_VECTOR(7 downto 0);
		SW : IN STD_LOGIC_VECTOR(6 downto 0);
		BTN : IN STD_LOGIC_VECTOR(4 downto 0);
		TX  : out STD_LOGIC;
		AD_CS : out std_logic;
		AD_D0 : in std_logic;
		AD_D1 : in std_logic;
		AD_CK : out std_logic );
end toplevel;

architecture Behavioral of toplevel is
    signal clk2x_ub, clk2xn_ub : std_logic;
    signal adclk_ub, adclk : std_logic;
    signal clkfb : std_logic;
    signal statvec : std_logic_vector(7 downto 0);
    signal status : clockgen_status;

	signal cs_int, cs_strobe : std_logic;
	signal data : signed(11 downto 0);
	signal sample : signed(11 downto 0);
	signal latch : std_logic_vector(7 downto 0);

	-- Decimator variables
	signal downsampled : signed(sample'range);
	signal reduced : signed(latch'range);

	signal amp : unsigned(2 downto 0);
	signal direct : std_logic;
	signal clipping : std_logic;
begin

	-- Minimum output frequency of FX is 5 MHz, so have to use CLKDV instead
	dcm : DCM_SP
	generic map (
		CLKIN_PERIOD => 10.0,                  -- 10 ns clock period, assuming 100 MHz clock
		CLKIN_DIVIDE_BY_2 => FALSE,            -- CLKIN divide by two (TRUE/FALSE)
		CLK_FEEDBACK => "2X",                  -- Feedback source (NONE, 1X, 2X)
		CLKDV_DIVIDE => 2.5,                   -- CLKDV divide value
		CLKOUT_PHASE_SHIFT => "NONE",          -- Output phase shift (NONE, FIXED, VARIABLE)
		DESKEW_ADJUST => "SYSTEM_SYNCHRONOUS", -- SYSTEM_SYNCHRNOUS or SOURCE_SYNCHRONOUS
		STARTUP_WAIT => FALSE                  -- Delay config DONE until DCM_SP LOCKED (TRUE/FALSE)
	)
	port map (
		RST => rst,             -- 1-bit input: Active high reset input
		CLKIN => clk,           -- 1-bit input: Clock input
		CLKFB => clkfb,         -- 1-bit input: Clock feedback input

		CLK2X => clk2x_ub,      -- 1-bit output: 2X clock frequency clock output
		CLK2X180 => clk2xn_ub,  -- 1-bit output: 2X clock frequency, 180 degree clock output
		CLKFX => open,          -- 1-bit output: Digital Frequency Synthesizer output (DFS)
		CLKFX180 => open,       -- 1-bit output: 180 degree CLKFX output
		CLKDV => adclk_ub,      -- 1-bit output: Divided clock output
		CLK0 => open,           -- 1-bit output: 0 degree clock output
		CLK90 => open,          -- 1-bit output: 90 degree clock output
		CLK180 => open,         -- 1-bit output: 180 degree clock output
		CLK270 => open,         -- 1-bit output: 270 degree clock output
		LOCKED => status.locked,-- 1-bit output: DCM_SP Lock Output
		PSDONE => status.done,  -- 1-bit output: Phase shift done output
		STATUS => statvec,      -- 8-bit output: DCM_SP status output

		DSSEN => '0',           -- 1-bit input: Unsupported, specify to GND.
		PSCLK => open,          -- 1-bit input: Phase shift clock input
		PSEN => open,           -- 1-bit input: Phase shift enable
		PSINCDEC => open        -- 1-bit input: Phase shift increment/decrement input
	);

	-- Required for BUFIO2 above
	obuf : BUFIO2FB generic map ( DIVIDE_BYPASS => TRUE ) port map ( I => clk2x_ub, O => clkfb );

	-- 40 MHz clock (clk / 2.5)
	cbuf  : BUFG port map ( I => adclk_ub, O => adclk );

	status.clkin_err <= statvec(1);
	status.clkfx_err <= statvec(2);
	ucomm : entity work.uart
		port map(
			data => latch,
			TX => TX,
			CLK => CLK,
			RST => RST );

	uadc : entity work.pmodad1
		port map (
			rst => RST,
			clk40 => adclk,
			s0 => data,
			AD_CS => cs_int,
			AD_D0 => AD_D0,
			AD_D1 => AD_D1,
			AD_CK => AD_CK );
	AD_CS <= cs_int;

	to100k : entity work.decimator
		GENERIC MAP (
			divwidth => 4,
			width => sample'length,
			factor => 10,    -- Down to 100 kHz
			bitfactor => 4,  -- Space for gain of log2(10) (3.3)
			compensation => 4,
			N => 2 )
		PORT MAP ( rst, clk, sample, cs_strobe, downsampled, open );

	reduced <= resize(shift_right(downsampled, downsampled'length - reduced'length), reduced'length);

	-- Button debouncer
	-- Amplifies the incoming signal by shifting
	process(clk, rst)
		variable count : unsigned(22 downto 0) := (others => '0');
		variable btn_int : std_logic_vector(btn'range);
	begin
		if rst = '1' then
			btn_int := (others => '0');
			amp <= (others => '0');
			direct <= '0';
		elsif rising_edge(clk) then
			if count = "0" then
				-- Button actions
				if btn(1) = '1' and btn_int(1) = '0' then
					amp <= amp + "1";
				elsif btn(3) = '1' and btn_int(3) = '0' then
					amp <= amp - "1";
				end if;
				if btn(2) = '1' and btn_int(2) = '0' then
					direct <= not(direct);
				end if;
				-- Store
				btn_int := btn;
			end if;
			-- Divider
			count := count + "1";
		end if;
	end process;

	-- Memory
	process(clk,RST)
		variable cs_old : std_logic;
		variable count : unsigned(7 downto 0);
	begin
		if RST = '1' then
--			latch <= X"00";
			cs_old := '1';
			count := (others => '0');
		elsif rising_edge(clk) then

			-- Strobe on rising edge of CS
			if cs_old = '0' and cs_int = '1' then
				cs_strobe <= '1';
			else
				cs_strobe <= '0';
			end if;
			cs_old := cs_int;

			-- Attenuate by 2, amplify as requested, clip as needed
			-- FIXME find a better way to detect clipping in a generic way
			clipping <= '0';
			sample <= shift_left(data, to_integer(amp));
			if data(data'high) = '0' and data > shift_right(to_signed(2047, data'length), to_integer(amp)) then
				-- Maximum positive value
				sample <= (others => '1');
				sample(sample'high) <= '0';
				clipping <= '1';
			elsif data(data'high) = '1' and data < shift_right(to_signed(-2048, data'length), to_integer(amp)) then
				-- Minimum negative value
				sample <= (others => '0');
				sample(sample'high) <= '1';
				clipping <= '1';
			end if;
		end if;
	end process;

	-- This value need not be registered, as is latched inside filter output
	latch <= std_logic_vector(reduced) when direct = '0' else
	         std_logic_vector(sample(sample'high downto sample'high - (latch'length - 1)));

	LED(0) <= direct;
	LED(3 downto 1) <= std_logic_vector(amp);
	LED(4) <= clipping;
	LED(7 downto 5) <= (others => '0');

end Behavioral;

