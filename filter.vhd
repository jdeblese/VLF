library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity filter is
	Generic (
		inb : integer := 12;
		outb : integer := 8 );
	Port (
		RST : IN STD_LOGIC;
		CLK : in STD_LOGIC;
		input   : in signed(inb-1 downto 0);
		istrobe : in std_logic;
		output  : out signed(outb-1 downto 0);
		ostrobe : out std_logic );
end filter;

architecture Behavioral of filter is
	constant bitgain : integer := 4;
	constant decim_factor : integer := 10;

	-- Not actually used, only here for internal'range attribute
	signal internal : signed(input'high + bitgain downto 0);

	-- Extend the delay line to (0 to 1) to narrow the passband
	type delayline is array (0 to 1) of signed(internal'range);
	-- Symmetric three-tap fir, so third coefficient = first
	type threetapfir is array(0 to 1) of signed(input'range);
	-- Local signals
	type local_type is record
		decim    : unsigned(4 downto 0);
		acc      : signed(internal'range);
		comb     : signed(internal'range);
		delayed  : delayline;
		ttfdelay : threetapfir;
		ttf      : signed(input'range);
		latch    : signed(output'range);
		strobe   : std_logic;
	end record;
	signal local, local_new : local_type;
begin

	output <= local.latch;
	ostrobe <= local.strobe;

	-- Memory
	process(clk,RST)
	begin
		if RST = '1' then
			local <= (
				decim => to_unsigned(0, local.decim'length),
				acc => (others => '0'),
				comb => (others => '0'),
				delayed => (others => (others => '0')),
				ttfdelay => (others => (others => '0')),
				ttf => (others => '0'),
				latch => X"00",
				strobe => '0' );
		elsif rising_edge(clk) then
			local <= local_new;
		end if;
	end process;

	-- Combinatorial
	process(local, input, istrobe)
		variable local_next : local_type;
	begin
		local_next := local;

		-- The whole filter is timed by and ticks over on the incoming
		-- 'istrobe' signal, which indicates when data is available
		if istrobe = '1' then
			-- Increment the decimation counter
			if local.decim = to_unsigned(decim_factor - 1, local.decim'length) then
				local_next.decim := (others => '0');
			else
				local_next.decim := local.decim + "1";
			end if;

			-- Pre-decimate integrator 1/(1 + z^-1)
			local_next.acc := local.acc + input;

			if local.decim = "0" then
				-- Post-decimate comb (1 - z^-1)
				local_next.comb := local.acc - local.delayed(0);
				local_next.delayed(local.delayed'high) := local.acc;
				-- FIXME Null range warning when delay line is one element long
				for I in local.delayed'high downto 1 loop
					local_next.delayed(I-1) := local.delayed(I);
				end loop;

				-- Post-decimate FIR Filter
				local_next.ttfdelay(local.ttfdelay'high) := local.comb(local.comb'high downto local.comb'high + 1 - local.ttf'length);
				for I in local.ttfdelay'high downto 1 loop
					local_next.ttfdelay(I-1) := local.ttfdelay(I);
				end loop;
				local_next.ttf := shift_right(local.ttfdelay(0),0) + shift_right( shift_right(local.ttfdelay(0),3) - shift_right(local.comb(local.comb'high downto local.comb'high + 1 - local.ttf'length),4) - shift_right(local.ttfdelay(1),4) , 0);

				-- Output Strobe
				local_next.strobe := '1';
			else
				local_next.strobe := '0';
			end if;
			-- Output, signed 8-bit value
			local_next.latch := local.ttf(local.ttf'high downto local.ttf'high - (local.latch'length - 1));
		end if;

		local_new <= local_next;
	end process;

end Behavioral;

