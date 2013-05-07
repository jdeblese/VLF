LIBRARY ieee;
USE ieee.std_logic_1164.ALL;

use work.toplevel_comp.all;

ENTITY toplevel_tb IS
END toplevel_tb;

ARCHITECTURE behavior OF toplevel_tb IS 

	--Inputs
	signal RX : std_logic := '1';
	signal RST : std_logic := '1';
	signal SW : std_logic_vector(6 downto 0);
	signal BTN : std_logic_vector(4 downto 0);
	signal AD_D0 : std_logic := 'Z';
	signal AD_D1 : std_logic := '0';

	--Outputs
	signal TX : std_logic;
	signal AD_CS : std_logic;
	signal AD_CK : std_logic;
	signal LED : std_logic_vector(7 downto 0);

	-- Clock period definitions
	signal CLK : std_logic := '0';
	constant CLK_period : time := 10 ns;

BEGIN
 
	-- Instantiate the Unit Under Test (UUT)
	uut: toplevel PORT MAP ( RST, CLK, LED, SW, BTN, TX, RX, AD_CS, AD_D0, AD_D1, AD_CK );

	-- Clock process definitions
	CLK_process :process
	begin
		CLK <= '0';
		wait for CLK_period/2;
		CLK <= '1';
		wait for CLK_period/2;
	end process;
 

	-- Stimulus process
	stim_proc: process
	begin		
		wait for CLK_period*10;
		rst <= '0';

		wait for 140 ns;

		AD_D0 <= '0';

		wait for 170 ns;

		AD_D0 <= '1';
		wait for 4*50 ns;

		AD_D0 <= '0';
		wait for 3*50 ns;

		AD_D0 <= '1';
		wait for 1*50 ns;

		AD_D0 <= '0';
		wait for 2*50 ns;

		AD_D0 <= '1';
		wait for 2*50 ns;

		AD_D0 <= '0';

		wait;
	end process;

END;
