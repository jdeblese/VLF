library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
package toplevel_comp is
	component toplevel
	Port (
		RST : IN STD_LOGIC;
		CLK : in  STD_LOGIC;
		LED : OUT STD_LOGIC_VECTOR(7 downto 0);
		SW : IN STD_LOGIC_VECTOR(6 downto 0);
		BTN : IN STD_LOGIC_VECTOR(4 downto 0);
		TX  : out STD_LOGIC;
		RX  : in STD_LOGIC;
		AD_CS : out std_logic;
		AD_D0 : in std_logic;
		AD_D1 : in std_logic;
		AD_CK : out std_logic );
	end component;
end package;

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
use work.uart_comp.all;

entity toplevel is
	Port (
		RST : IN STD_LOGIC;
		CLK : in  STD_LOGIC;
		LED : OUT STD_LOGIC_VECTOR(7 downto 0);
		SW : IN STD_LOGIC_VECTOR(6 downto 0);
		BTN : IN STD_LOGIC_VECTOR(4 downto 0);
		TX  : out STD_LOGIC;
		RX  : in STD_LOGIC;
		AD_CS : out std_logic;
		AD_D0 : in std_logic;
		AD_D1 : in std_logic;
		AD_CK : out std_logic );
end toplevel;

architecture Behavioral of toplevel is
    signal master_buf : std_logic;
    signal clk2x_ub, clk2xn_ub : std_logic;
    signal adclk_ub, adclk : std_logic;
    signal clkfb : std_logic;
    signal statvec : std_logic_vector(7 downto 0);
    signal status : clockgen_status;

	signal sclk, sclk_new : std_logic;
	signal bcnt, bcnt_new : unsigned(4 downto 0);
	signal cs, cs_new : std_logic;
	signal data, data_new : std_logic_vector(11 downto 0);
	signal sync_d0 : std_logic_vector(1 downto 0);
	signal latch, latch_new : std_logic_vector(7 downto 0);

	signal prev, prev_new : std_logic_vector(11 downto 0);

begin

	-- Is this buffer really required?
	ibuf : BUFIO2
	generic map (
	   DIVIDE => 1,           -- DIVCLK divider (1-8)
	   DIVIDE_BYPASS => TRUE, -- Bypass the divider circuitry (TRUE -> DIVCLK is passthrough)
	   I_INVERT => FALSE,     -- Invert clock (TRUE/FALSE)
	   USE_DOUBLER => FALSE   -- Use doubler circuitry (TRUE/FALSE)
	)
	port map (
	   I => CLK,             -- 1-bit input: Clock input (connect to IBUFG)
	   DIVCLK => master_buf, -- 1-bit output: Divided clock output
	   IOCLK => open,        -- 1-bit output: I/O output clock
	   SERDESSTROBE => open  -- 1-bit output: Output SERDES strobe (connect to ISERDES2/OSERDES2)
	);

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
	ucomm : uart port map( latch, TX, RX, CLK, RST );

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
			bcnt <= "00000";
			latch <= X"00";
			prev <= X"000";
		elsif rising_edge(adclk) then
			sclk <= not(sclk);
			bcnt <= bcnt_new;
			latch <= latch_new;
			prev <= prev_new;
		end if;
	end process;

	process(adclk,RST)
	begin
		if RST = '1' then
			cs <= '1';
			data <= X"000";
		elsif falling_edge(adclk) then
			cs <= cs_new;
			data <= data_new;
		end if;
	end process;

	process(bcnt, cs, sclk, data, latch, prev, sync_d0)
		variable bcnt_nxt : unsigned(4 downto 0);
		variable cs_nxt : std_logic;
		variable data_nxt : std_logic_vector(11 downto 0);
		variable latch_nxt : std_logic_vector(7 downto 0);
		variable prev_nxt : std_logic_vector(11 downto 0);
		variable delta : unsigned(11 downto 0);
	begin
		bcnt_nxt := bcnt;
		cs_nxt := cs;
		data_nxt := data;
		latch_nxt := latch;
		prev_nxt := prev;

		if bcnt = "00000" and sclk = '1' then
			cs_nxt := '0';
			data_nxt := (others => '0');
		end if;

		if sclk = '1' then
			-- Count bits on falling edge of sclk
			if bcnt_nxt = "10011" then
				bcnt_nxt := "00000";
				prev_nxt := data;
				delta := unsigned(data) - unsigned(prev);
				latch_nxt := std_logic_vector(delta(7 downto 0));
			else
				bcnt_nxt := bcnt + "1";
			end if;
			-- When active, shift in data or go inactive
			if cs = '0' then
				if bcnt = "10010" then
					cs_nxt := '1';
				end if;
			end if;
		else
			if cs = '0' and bcnt > "00011" and bcnt < "10001" then
				data_nxt := data(10 downto 0) & sync_d0(1);
			end if;
		end if;

		cs_new <= cs_nxt;
		bcnt_new <= bcnt_nxt;
		data_new <= data_nxt;
		latch_new <= latch_nxt;
		prev_new <= prev_nxt;
	end process;

--	LED(0) <= cs;
--	LED(1) <= sclk;
--	LED(3 downto 2) <= sync_d0;
--	LED(7 downto 4) <= data(11 downto 8);
	LED <= latch;

end Behavioral;

