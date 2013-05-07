library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

package uart_comp is
	component uart
	Port(
		DATA  : in std_logic_vector(7 downto 0);
		TX    : out std_logic;
		RX    : in std_logic;
		CLK   : in std_logic;
		RST   : in std_logic );
	end component;
end package;


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library UNISIM;
use UNISIM.VComponents.all;

-- FIXME: How does starting, stopping and changing the uart affect
--  the phase of the clock divider, if at all?

use work.uart_comp.all;

entity uart is
	Port(
		DATA  : in std_logic_vector(7 downto 0);
		TX    : out std_logic;
		RX    : in std_logic;
		CLK   : in std_logic;
		RST   : in std_logic );
end uart;

architecture Behaviour of uart is

	-- Registers
	signal shift, shift_new : std_logic_vector(7 downto 0);
	signal bitcount, bitcount_new : unsigned(3 downto 0);
	signal div, div_new : unsigned(6 downto 0);

	-- OUTPUT
	signal tx_int, tx_new : std_logic;

begin

	TX <= tx_int;

	latchproc : process(CLK, RST)
	begin
		if RST = '1' then
			shift <= (others => '0');
			tx_int <= '1';
			bitcount <= (others => '0');
			div <= (others => '0');
		elsif rising_edge(CLK) then
			shift <= shift_new;
			tx_int <= tx_new;
			bitcount <= bitcount_new;
			div <= div_new;
		end if;
	end process;

	combproc : process(shift, tx_int, div, bitcount, DATA)
		variable shift_nxt : std_logic_vector(7 downto 0);
		variable tx_nxt : std_logic;
		variable bitcount_nxt : unsigned(3 downto 0);
		variable div_nxt : unsigned(6 downto 0);
	begin
		shift_nxt := shift;
		bitcount_nxt := bitcount;
		div_nxt   := div + "1";
		tx_nxt    := tx_int;

		if div = "1100011" then
			div_nxt := (others => '0');
			bitcount_nxt := bitcount + "1";
		end if;

		if bitcount = "0000" then
			tx_nxt := '0';  -- start bit
			shift_nxt := DATA;
		elsif bitcount = "1001" then
			tx_nxt := '1';  -- stop bit
			if bitcount_nxt = "1010" then
				bitcount_nxt := (others => '0');
			end if;
		elsif div = "0000000" then
			shift_nxt := '0' & shift(7 downto 1);
			tx_nxt := shift(0);
		end if;

		shift_new <= shift_nxt;
		bitcount_new <= bitcount_nxt;
		div_new   <= div_nxt;
		tx_new    <= tx_nxt;
	end process;

end Behaviour;
