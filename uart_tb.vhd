LIBRARY ieee;
USE ieee.std_logic_1164.ALL;

use work.uart_comp.all;

ENTITY uart_tb IS
END uart_tb;

ARCHITECTURE behavior OF uart_tb IS 

	--Inputs
	signal DATA : std_logic_vector(7 downto 0) := (others => '0');
	signal RX : std_logic := '1';
	signal RST : std_logic := '1';

	--Outputs
	signal TX : std_logic;

	-- Clock period definitions
	signal CLK : std_logic := '0';
	constant CLK_period : time := 10 ns;

BEGIN
 
	-- Instantiate the Unit Under Test (UUT)
	uut: uart PORT MAP ( DATA, TX, RX, CLK, RST );

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
		DATA <= "01111101";

		wait;
	end process;

END;
