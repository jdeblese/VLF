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
		x"FFF", x"FE4", x"F99", x"F1E", x"E77",
		x"DA6", x"CB2", x"BA0", x"A78", x"940",
		x"800", x"6BF", x"587", x"45F", x"34D",
		x"259", x"188", x"0E1", x"066", x"01B",
		x"000", x"01B", x"066", x"0E1", x"188",
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
		AD_D0 <= 'U';
		wait for 137.5 ns;  -- First falling edge of CS
		wait for 2.5 ns;  -- Should be 20 ns
		AD_D0 <= 'L';
		wait for 10.0 ns;  -- First falling edge of SCLK

	loop
		for I in sine'range loop
			for B in 0 to 19 loop
				-- Current location: falling edge of SCLK
				-- Old data hold time is 10 ns
				wait for 10 ns;
				-- Transition period
				if B > 14 then
					AD_D0 <= 'Z';
				else
					AD_D0 <= 'X';
				end if;
				-- Data is available again 40 ns after SCLK falling edge
				wait for 30 ns;
				-- Set the new data
				if B < 3 then
					AD_D0 <= 'L';
				elsif B < 15 then
					AD_D0 <= sine(I)(14 - B);
				else
					AD_D0 <= 'Z';
				end if;
				-- 10 ns left until the next falling edge of SCLK
				wait for 10 ns;
			end loop;
		end loop;
	end loop;

	wait;
	end process;

END;
