LIBRARY ieee;
USE ieee.std_logic_1164.ALL;

ENTITY toplevel_tb IS
END toplevel_tb;

ARCHITECTURE behavior OF toplevel_tb IS 

	--Inputs
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
	constant AD_CK_period : time := 50 ns;

	type samplemem is array(0 to 39) of std_logic_vector(11 downto 0);
	signal sine : samplemem := (
		x"800", x"940", x"A78", x"BA0", x"CB2",
		x"DA6", x"E77", x"F1E", x"F99", x"FE4",
		x"FFD", x"FE4", x"F99", x"F1E", x"E77",
		x"DA6", x"CB2", x"BA0", x"A78", x"940",
		x"800", x"6BF", x"587", x"45F", x"34D",
		x"259", x"188", x"0E1", x"066", x"01B",
		x"002", x"01B", x"066", x"0E1", x"188",
		x"259", x"34D", x"45F", x"587", x"6BF" );
BEGIN
 
	-- Instantiate the Unit Under Test (UUT)
	uut: entity work.toplevel PORT MAP ( RST, CLK, LED, SW, BTN, TX, AD_CS, AD_D0, AD_D1, AD_CK );

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
		wait for CLK_period*10;  -- 100 ns
		rst <= '0';
		AD_D0 <= 'Z';
		wait for 100 ns;  -- First falling edge of AD_CK

	loop
		for I in sine'range loop
			for B in 0 to 19 loop
				if B < 4 then
					AD_D0 <= '0';
					wait for AD_CK_period;
				elsif B < 16 then
					AD_D0 <= sine(I)(15 - B);
					wait for AD_CK_period;
				else
					AD_D0 <= 'Z';
					wait for AD_CK_period;
				end if;
			end loop;
		end loop;
	end loop;

		wait;
	end process;

END;
