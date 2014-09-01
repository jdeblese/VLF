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

	signal sclk, sclk_new : std_logic;
	signal bcnt, bcnt_new : unsigned(4 downto 0);
	signal cs, cs_new : std_logic;
	signal data, data_new : std_logic_vector(11 downto 0);
	signal prev, prev_new : std_logic_vector(data'range);
	signal sync_d0 : std_logic_vector(1 downto 0);
	signal latch, latch_new : std_logic_vector(7 downto 0);


	constant bitgain : integer := 4;
	constant decim_factor : integer := 10;
	signal acc, acc_new : signed(data'high + bitgain downto 0);
	type delayline is array (0 to 0) of signed(acc'range);  -- Extend to (0 to 1) to narrow the passband
	signal delayed, delayed_new : delayline;
	signal comb, comb_new : signed(acc'range);
	signal decim, decim_new : unsigned(4 downto 0);
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

	cbuf  : BUFG port map ( I => adclk_ub, O => adclk );

	status.clkin_err <= statvec(1);
	status.clkfx_err <= statvec(2);
	ucomm : entity work.uart
		port map(
			data => latch,
			TX => TX,
			CLK => CLK,
			RST => RST );

	AD_CS <= cs;
	AD_CK <= sclk;

	-- Synchronize incoming data
	process(CLK,RST)
	begin
		if RST = '1' then
			sync_d0 <= "00";
		elsif rising_edge(clk) then
			sync_d0(1) <= sync_d0(0);
			sync_d0(0) <= AD_D0;
		end if;
	end process;
			
	process(adclk,RST)
	begin
		if RST = '1' then
			sclk <= '0';
			bcnt <= (others => '0');
			data <= (others => '0');
			prev <= (others => '0');
			latch <= X"00";
			acc <= (others => '0');
			delayed <= (others => (others => '0'));
			comb <= (others => '0');
			decim <= to_unsigned(0, decim'length);
		elsif rising_edge(adclk) then
			sclk <= not(sclk);  -- Note: divides adclk by 2
			bcnt <= bcnt_new;
			prev <= prev_new;
			data <= data_new;
			latch <= latch_new;
			delayed <= delayed_new;
			acc <= acc_new;
			comb <= comb_new;
			decim <= decim_new;
		end if;
	end process;

	process(adclk,RST)
	begin
		if RST = '1' then
			cs <= '1';
		elsif falling_edge(adclk) then
			cs <= cs_new;
		end if;
	end process;

	process(bcnt, cs, sclk, data, prev, latch, sync_d0, acc, delayed, comb, decim)
		variable bcnt_nxt : unsigned(4 downto 0);
		variable cs_nxt : std_logic;
		variable data_nxt : std_logic_vector(11 downto 0);
		variable prev_nxt : std_logic_vector(prev'range);
		variable latch_nxt : std_logic_vector(7 downto 0);
		variable sample : signed(data'high + 1 downto 0);
		variable acc_nxt : signed(acc'range);
		variable delayed_nxt : delayline;
		variable comb_nxt : signed(comb'range);
		variable decim_nxt : unsigned(decim'range);
		variable tmp : signed(comb'high + 1 downto 0);
	begin
		bcnt_nxt := bcnt;
		cs_nxt := cs;
		data_nxt := data;
		prev_nxt := prev;
		latch_nxt := latch;
		acc_nxt := acc;
		delayed_nxt := delayed;
		comb_nxt := comb;
		decim_nxt := decim;

		if sclk = '1' then
			bcnt_nxt := bcnt + "1";
			if bcnt = "0" then
				cs_nxt := '0';
				data_nxt := (others => '0');
			elsif bcnt = x"13" then
				if decim = to_unsigned(decim_factor - 1, decim'length) then
					decim_nxt := (others => '0');
				else
					decim_nxt := decim + "1";
				end if;
				bcnt_nxt := (others => '0');
				-- DC Filter
				prev_nxt := data;
				sample := signed("0" & data) - signed("0" & prev);  -- Comb filter to remove DC
				-- Integrator 1/(1 + z^-1)
				acc_nxt := acc + sample(sample'high downto 1);      -- Downshift 'sample' to compensate for the DC filter's gain
				-- Post-decimate comb (1 - z^-1)
				if decim = "0" then
					comb_nxt := acc - delayed(0);
					delayed_nxt(delayed'high) := acc;
					for I in delayed'high downto 1 loop
						delayed_nxt(I-1) := delayed(I);
					end loop;
				end if;
				tmp := comb + shift_left(to_signed(1,tmp'length), tmp'length - 2);
				assert tmp >= "0" report "Here be dragons, tmp must be greater than zero" severity error;
				latch_nxt := std_logic_vector(tmp(tmp'high - 1 downto tmp'high - 8));
			end if;
			-- When active, shift in data or go inactive
			if cs = '0' then
				if bcnt = x"12" then
					cs_nxt := '1';
				end if;
			end if;
		elsif cs = '0' then
			if bcnt = x"10" then
				cs_nxt := '1';
			elsif bcnt > x"3" and bcnt < x"10" then
				data_nxt := data(data'high-1 downto 0) & sync_d0(1);
			end if;
		end if;

		cs_new <= cs_nxt;
		bcnt_new <= bcnt_nxt;
		data_new <= data_nxt;
		prev_new <= prev_nxt;
		latch_new <= latch_nxt;
		acc_new <= acc_nxt;
		delayed_new <= delayed_nxt;
		comb_new <= comb_nxt;
		decim_new <= decim_nxt;
	end process;

--	LED(0) <= cs;
--	LED(1) <= sclk;
--	LED(3 downto 2) <= sync_d0;
--	LED(7 downto 4) <= data(11 downto 8);
	LED <= latch;

end Behavioral;

