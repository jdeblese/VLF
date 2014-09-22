library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity interpolator is
	Generic (
		divmax : integer := 100;
		divwidth : integer := 8;
		width : integer := 12;
		factor : integer := 3;
		bitfactor : integer := 2;
		compensation : integer := 2 );
	Port (
		RST : IN STD_LOGIC;
		CLK : in STD_LOGIC;
		input   : in signed(width - 1 downto 0);
		istrobe : in std_logic;
		output  : out signed(width - 1 downto 0);
		ostrobe : out std_logic );
end interpolator;

architecture Behavioral of interpolator is
	signal comb : signed(input'high + bitfactor downto 0);
	signal int : signed(comb'range);
	-- Timing
	signal newstrobe : std_logic;
	signal div : unsigned(divwidth - 1 downto 0) := (others => '0');
begin

	output <= resize(shift_right(int, compensation), output'length);
	ostrobe <= newstrobe; -- Currently unused

	-- Timing strobes
	process(clk, rst)
	begin
		if rst = '1' then
			div <= (others => '0');
		elsif rising_edge(clk) then
			if istrobe = '1' then  -- Should occur every 100 tics
				div <= (others => '0');
			else
				div <= div + "1";
			end if;
		end if;
	end process;

	process(istrobe, div)
	begin
		newstrobe <= istrobe;
		for T in 1 to factor - 1 loop
			if div = T * divmax / factor then
				newstrobe <= '1';
			end if;
		end loop;
	end process;

	process(rst,clk,istrobe)
		variable delay : signed(input'range);
	begin
		if rst = '1' then
			comb  <= (others => '0');
			delay := (others => '0');
		elsif rising_edge(clk) and istrobe = '1' then
			-- Comb filter for the interpolator
			comb <= resize(input, comb'length) - resize(delay, comb'length);
			delay := input;
		end if;
	end process;

	process(rst,clk,newstrobe)
		variable upsampled : signed(int'range);
	begin
		if rst = '1' then
			int <= (others => '0');
		elsif rising_edge(clk) and newstrobe = '1' then
			upsampled := comb;
--			if istrobe = '1' then
--				upsampled := comb;
--			else
--				upsampled := (others => '0');
--			end if;

			-- Integrator for the interpolator
			int <= resize(upsampled, int'length) + int;
		end if;
	end process;

end Behavioral;

