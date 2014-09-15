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
	signal data : std_logic_vector(11 downto 0);
	signal prev, prev_new : std_logic_vector(data'range);
	signal latch, latch_new : std_logic_vector(7 downto 0);


	constant bitgain : integer := 4;
	constant decim_factor : integer := 10;
	signal acc, acc_new : signed(data'high + bitgain downto 0);
	type delayline is array (0 to 1) of signed(acc'range);  -- Extend to (0 to 1) to narrow the passband
	signal delayed, delayed_new : delayline;
	signal comb, comb_new : signed(acc'range);
	signal decim, decim_new : unsigned(4 downto 0);

	-- Delay line and output of a three-tap fir filter
	type threetapfir is array(0 to 1) of signed(data'range);
	signal ttfdelay, ttfdelay_new : threetapfir;
	signal ttf, ttf_new : signed(data'range);

	signal amp : unsigned(2 downto 0);

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

	-- Button debouncer
	-- Amplifies the incoming signal by shifting
	process(clk, rst)
		variable count : unsigned(22 downto 0) := (others => '0');
		variable btn_int : std_logic_vector(btn'range);
	begin
		if rst = '1' then
			btn_int := (others => '0');
			amp <= (others => '0');
		elsif rising_edge(clk) then
			if count = "0" then
				-- Button actions
				if btn(1) = '1' and btn_int(1) = '0' then
					amp <= amp + "1";
				elsif btn(3) = '1' and btn_int(3) = '0' then
					amp <= amp - "1";
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
	begin
		if RST = '1' then
			prev <= (others => '0');
			latch <= X"00";
			acc <= (others => '0');
			delayed <= (others => (others => '0'));
			comb <= (others => '0');
			decim <= to_unsigned(0, decim'length);
			ttfdelay <= (others => (others => '0'));
			ttf <= (others => '0');
			cs_old := '1';
		elsif rising_edge(clk) then
			prev <= prev_new;
			latch <= latch_new;
			delayed <= delayed_new;
			acc <= acc_new;
			comb <= comb_new;
			decim <= decim_new;
			ttfdelay <= ttfdelay_new;
			ttf <= ttf_new;

			-- Strobe on rising edge of CS
			if cs_old = '0' and cs_int = '1' then
				cs_strobe <= '1';
			else
				cs_strobe <= '0';
			end if;
			cs_old := cs_int;
		end if;
	end process;

	-- Combinatorial
	process(data, cs_strobe, prev, latch, acc, delayed, comb, decim, ttfdelay, ttf)
		variable prev_nxt : std_logic_vector(prev'range);
		variable latch_nxt : std_logic_vector(7 downto 0);
		variable sample : signed(data'range);
		variable acc_nxt : signed(acc'range);
		variable delayed_nxt : delayline;
		variable comb_nxt : signed(comb'range);
		variable decim_nxt : unsigned(decim'range);
		variable tmp : signed(ttf'high + 1 downto 0);
		variable ttfdelay_nxt : threetapfir;
		variable ttf_nxt, ttftmp : signed(ttf'range);
	begin
		prev_nxt := prev;
		latch_nxt := latch;
		acc_nxt := acc;
		delayed_nxt := delayed;
		comb_nxt := comb;
		decim_nxt := decim;
		ttfdelay_nxt := ttfdelay;
		ttf_nxt := ttf;

		if cs_strobe = '1' then
			if decim = to_unsigned(decim_factor - 1, decim'length) then
				decim_nxt := (others => '0');
			else
				decim_nxt := decim + "1";
			end if;
			-- Convert to signed, centered around 1.65 V
			sample := shift_left( signed(data) - shift_left(to_signed(1,sample'length), sample'length - 1) ,to_integer(amp));
			-- Pre-decimate integrator 1/(1 + z^-1)
			acc_nxt := acc + sample;
			if decim = "0" then
				-- Post-decimate comb (1 - z^-1)
				comb_nxt := acc - delayed(0);
				delayed_nxt(delayed'high) := acc;
				for I in delayed'high downto 1 loop  -- FIXME Null range warning when delay line is one element long
					delayed_nxt(I-1) := delayed(I);
				end loop;
				-- Post-decimate FIR Filter
				ttfdelay_nxt(ttfdelay'high) := comb(comb'high downto comb'high + 1 - ttf'length);
				for I in ttfdelay'high downto 1 loop
					ttfdelay_nxt(I-1) := ttfdelay(I);
				end loop;
				ttf_nxt := shift_right(ttfdelay(0),0) + shift_right( shift_right(ttfdelay(0),3) - shift_right(comb(comb'high downto comb'high + 1 - ttf'length),4) - shift_right(ttfdelay(1),4) , 0);
			end if;
			-- Output, signed 8-bit value
			latch_nxt := std_logic_vector(ttf(ttf'high downto ttf'high - 7));
		end if;

		prev_new <= prev_nxt;
		latch_new <= latch_nxt;
		acc_new <= acc_nxt;
		delayed_new <= delayed_nxt;
		comb_new <= comb_nxt;
		decim_new <= decim_nxt;
		ttfdelay_new <= ttfdelay_nxt;
		ttf_new <= ttf_nxt;
	end process;

--	LED(0) <= cs;
--	LED(1) <= sclk;
--	LED(3 downto 2) <= sync_d0;
--	LED(7 downto 4) <= data(11 downto 8);
	LED <= latch;

end Behavioral;

