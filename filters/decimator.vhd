library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity decimator is
	Generic (
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
end decimator;

architecture Behavioral of decimator is
	signal int  : signed(input'high + bitfactor downto 0);
	signal comb : signed(int'range);
	-- Timing
	signal newstrobe : std_logic;
	signal div : unsigned(divwidth - 1 downto 0) := (others => '0');
begin

	output <= resize(shift_right(comb, compensation), output'length);
	ostrobe <= newstrobe; -- Currently unused

	-- Timing strobes
	process(clk, rst)
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
		variable delay : signed(comb'range);
	begin
		if rst = '1' then
			comb <= (others => '0');
			delay := (others => '0');
		elsif rising_edge(clk) and newstrobe = '1' then
			-- Comb for the 5x decimator, gain-compensated
			comb <= resize(int,comb'length) - delay;
			delay := int;
		end if;
	end process;

end Behavioral;

