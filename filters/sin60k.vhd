library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity sin60k is
	Generic ( width : integer := 12 );
	Port (
		RST : IN STD_LOGIC;
		CLK : in STD_LOGIC;
		input   : in signed(width - 1 downto 0);
		istrobe : in std_logic;
		output  : out signed(width - 1 downto 0);
		ostrobe : out std_logic );
end sin60k;

architecture Behavioral of sin60k is
	type fir_type is array(integer range <>) of signed(7 downto 0);
	constant fir_co : fir_type(0 to 11) := (
		x"10", x"1f", x"2e", x"3d",
		x"4a", x"56", x"61", x"6a",
		x"72", x"78", x"7c", x"7e" );

	-- Multiply element outputs
	-- width bits input to the multiplier
	-- fir_co(0)'length bits wide coefficients
	type products_type is array(fir_co'range) of signed(width + fir_co(0)'length - 1 downto 0);

	-- Inputs come from MAC elements
	-- width bits input to the multiplier
	-- fir_co(0)'length bits wide coefficients
	-- 12 steps, so up to 4 bits gain from the adders
	type line_type is array (fir_co'range) of signed(width + fir_co(0)'length + 3 downto 0);

	-- No bit gain associated with the final delay line
	-- Must delay by 25, but decimated by 5 => 5
	type final_type is array(0 to 4) of signed(input'range);

	-- High-speed terms
	signal forward, reverse, revdelay : line_type;
	signal sum : signed(forward(0)'high + 1 downto 0);
	signal reduced : signed(input'range);

	-- Low-speed terms
	signal lostrobe : std_logic;
	signal decimated : signed(input'range);
	signal oddsymmetry : final_type;       -- a sine wave has odd symmetry
	signal diff : signed(width downto 0);  -- output comb difference
begin

	ostrobe <= lostrobe;

	output <= resize(shift_right(diff, diff'length - width), width);

	-- FIXME Does the decimator need to run at the bit depth of 'sum'?
	reduced <= resize(shift_right(sum, sum'length - reduced'length), reduced'length);
	decim5x : entity work.decimator
		generic map (
			divwidth => 3,      -- maximum count of 8
			width => width,     -- 12-bit I/O
			factor => 5,        -- decimate by 5 to ease the final delay line
			bitfactor => 3,     -- this decimation induces a gain of 2.3 bits
			compensation => 3,  -- ensure a gain less than zero
			N => 1 )
		port map (
			RST => RST,
			CLK => CLK,
			input => reduced,
			istrobe => istrobe,
			output => decimated,
			ostrobe => lostrobe );

	process(rst,clk,istrobe)
		variable products : products_type;
	begin
		if rst = '1' then
			-- Not a recursive filter, so not really necessary
			forward <= (others => (others => '0'));
			reverse <= (others => (others => '0'));
			revdelay <= (others => (others => '0'));
			sum <= (others => '0');
		elsif rising_edge(clk) and istrobe = '1' then
			-- Compute the required product terms
			for T in fir_co'range loop
				products(T) := fir_co(T) * input;
			end loop;
			-- The normal transposed form of a filter, forward(0) the output
			--   a_n * z^-n  n=1..12
			for T in 0 to fir_co'high-1 loop
				forward(T) <= products(T) + forward(T+1);
			end loop;
			forward(fir_co'high) <= resize(products(fir_co'high), forward(0)'length);
			-- The reversed transposed form of a filter, reverse(12) the output
			--   a_(13-n) * z^-n  n=1..12
			for T in 1 to fir_co'high loop
				reverse(T) <= products(T) + reverse(T-1);
			end loop;
			reverse(0) <= resize(products(0), reverse(0)'length);
			-- The reversed filter is delayed 12 units versus the forward
			for T in 0 to fir_co'high-1 loop
				revdelay(T) <= revdelay(T+1);
			end loop;
			revdelay(fir_co'high) <= reverse(fir_co'high);
			-- Sum of the forward and reverse branches
			sum <= resize(forward(0), sum'length) + resize(revdelay(0), sum'length);
		end if;
	end process;

	process(rst,clk,lostrobe)
	begin
		if rst = '1' then
			-- Not a recursive filter, so not really necessary
			oddsymmetry <= (others => (others => '0'));
			diff <= (others => '0');
		elsif rising_edge(clk) and lostrobe = '1' then
			-- Final delay line
			for T in 0 to oddsymmetry'high - 1 loop
				oddsymmetry(T) <= oddsymmetry(T+1);
			end loop;
			oddsymmetry(oddsymmetry'high) <= decimated;
			-- Final difference (1 - z^-25)
			diff <= resize(decimated, diff'length) - resize(oddsymmetry(0), diff'length);
		end if;
	end process;

end Behavioral;

