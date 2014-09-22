LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

ENTITY decimator_tb IS
END decimator_tb;

ARCHITECTURE behavior OF decimator_tb IS 

	-- Parameters
	constant width : integer := 12;

	constant divwidth : integer := 8;

	constant factor : integer := 5;
	constant bitfactor : integer := 3;

	constant compensation : integer := 3;

	-- Inputs
	signal RST : std_logic := '1';
	signal idata : signed(width - 1 downto 0) := (others => '0');
	signal istrobe : std_logic := '0';

	-- Outputs
	constant outb : integer := 8;
	signal odata : signed(width - 1 downto 0);
	signal ostrobe : std_logic := '0';

	-- Clock period definitions
	signal CLK : std_logic := '0';
	constant CLK_period : time := 10 ns;

	-- Sine generation
	signal pinc_in : unsigned(15 downto 0);
	signal dds : std_logic_vector(11 downto 0);
BEGIN
 
	udds : entity work.dds_compiler_v4_0_0
	   port map (
		   CLK => clk,
		   PINC_IN => pinc_in,
		   SINE => dds );
	pinc_in <= to_unsigned(8, pinc_in'length);

	-- Instantiate the Unit Under Test (UUT)
	uut: entity work.decimator
		GENERIC MAP ( divwidth, width, factor, bitfactor, compensation )
		PORT MAP ( RST, CLK, idata, istrobe, odata, ostrobe );

	CLK <= not CLK after CLK_period / 2;

	-- Stimulus process
	stim_proc: process
	begin		
		wait for CLK_period * 10;  -- 100 ns
		rst <= '0';
		wait until CLK = '0';

		loop
			idata <= signed(dds);
			istrobe <= '1';
			wait for CLK_period;
			istrobe <= '0';
			wait for CLK_period * 99;
		end loop;

		wait;
	end process;

END;
