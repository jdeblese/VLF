library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity decimator is
	Generic (
		divwidth : integer := 8;
		width : integer := 12;
		factor : integer := 3;
		bitfactor : integer := 2;
		compensation : integer := 2;
		N : integer := 1 );
	Port (
		RST : IN STD_LOGIC;
		CLK : in STD_LOGIC;
		input   : in signed(width - 1 downto 0);
		istrobe : in std_logic;
		output  : out signed(width - 1 downto 0);
		ostrobe : out std_logic );
end decimator;

architecture Behavioral of decimator is
	signal int  : signed(input'high + bitfactor downto 0);
	signal comb : signed(int'range);
	signal equalizer  : signed(comb'high + 1 downto 0);
	-- Timing
	signal newstrobe : std_logic;
	signal div : unsigned(divwidth - 1 downto 0) := (others => '0');

	type delayline1 is array (integer range <>) of signed(comb'range);
	type delayline2 is array (integer range <>) of signed(equalizer'range);

begin

	-- Shift right at least one, due to equalizer's gain
	output <= resize(shift_right(equalizer, compensation + 1), output'length);
	ostrobe <= newstrobe;

	-- Timing strobes
	process(clk, rst, istrobe)
	begin
		if rst = '1' then
			div <= (others => '0');
		elsif rising_edge(clk) and istrobe = '1' then
			if div = factor - 1 then
				div <= (others => '0');
			else
				div <= div + "1";
			end if;
		end if;
	end process;

	process(clk)
	begin
		if rising_edge(clk) then
			if div = 0 and istrobe = '1' then
				newstrobe <= '1';
			else
				newstrobe <= '0';
			end if;
		end if;
	end process;

	process(rst,clk,istrobe)
	begin
		if rst = '1' then
			int <= (others => '0');
		elsif rising_edge(clk) and istrobe = '1' then
			int <= resize(input,int'length) + int;
		end if;
	end process;

	process(rst,clk,newstrobe)
		variable combdelay : delayline1(0 to N-1); -- 2 taps adds a zero at fs/2
		variable equalizerdelay : delayline2(0 to 1);  -- 2 taps for 3 coefficients
	begin
		if rst = '1' then
			comb <= (others => '0');
			combdelay := (others => (others => '0'));
			equalizerdelay := (others => (others => '0'));
			equalizer <= (others => '0');
		elsif rising_edge(clk) and newstrobe = '1' then
			-- Comb for the 5x decimator, variable tap delay line
			comb <= resize(int,comb'length) - combdelay(combdelay'high);
			for T in combdelay'high downto 1 loop
				combdelay(T) := combdelay(T-1);
			end loop;
			combdelay(0) := int;
			-- Equalization FIR filter
			--   coefficients: -1/16 9/8 -1/16
			--   gain: 2 (+6 dB)
			for T in equalizerdelay'high downto 1 loop
				equalizerdelay(T) := equalizerdelay(T-1);
			end loop;
			equalizerdelay(0) := resize(comb, equalizer'length);
			equalizer <= resize(shift_right(equalizerdelay(0),0), equalizer'length)
				- resize(shift_right(comb,4), equalizer'length)
				- resize(shift_right(equalizerdelay(1),4), equalizer'length)
				+ resize(shift_right(equalizerdelay(0),3), equalizer'length);
		end if;
	end process;

end Behavioral;

