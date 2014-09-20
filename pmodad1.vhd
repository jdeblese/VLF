library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library UNISIM;
use UNISIM.VComponents.all;

entity pmodad1 is
	Port (
		rst : IN STD_LOGIC;
		clk40 : in  STD_LOGIC;
		s0 : out signed(11 downto 0);
		s1 : out signed(11 downto 0);
		AD_CS : out std_logic;
		AD_D0 : in std_logic;
		AD_D1 : in std_logic;
		AD_CK : out std_logic );
end pmodad1;

architecture Behavioral of pmodad1 is
	signal sclk : std_logic;
	signal bcnt, bcnt_new : unsigned(4 downto 0);
	signal cs, cs_new : std_logic;
	signal data, data_new : std_logic_vector(11 downto 0);
	signal sync_d0 : std_logic_vector(1 downto 0);
	signal s0_int, s0_new : signed(s0'range);

begin

	s0 <= s0_int;
	s1 <= (others => '0');

	AD_CS <= cs;
	AD_CK <= sclk;

	-- Synchronize incoming data
	process(clk40,RST)
	begin
		if RST = '1' then
			sync_d0 <= "00";
		elsif rising_edge(clk40) then
			sync_d0(0) <= AD_D0;
		elsif falling_edge(clk40) then
			sync_d0(1) <= sync_d0(0);
		end if;
	end process;

	-- Memory process
	process(clk40,RST)
	begin
		if RST = '1' then
			sclk <= '0';
			bcnt <= (others => '1');
			data <= (others => '0');
		elsif rising_edge(clk40) then
			sclk <= not(sclk);  -- Note: divides clk40 by 2 down to 20 MHz
			bcnt <= bcnt_new;
			data <= data_new;

			if sclk = '1' and bcnt = x"0f" then
				-- Convert to signed, centered around half range
				-- [0,4095]  ->  [-2048,2047]
				s0_int <= signed(data(data'high-1 downto 0) & sync_d0(1)) - shift_left(to_signed(1,s0'length), s0'length - 1);
			end if;

		end if;
	end process;

	-- CS should transition when SCK is high in the middle of the clock period,
	-- so on the falling edge of clk40
	process(clk40,RST)
	begin
		if RST = '1' then
			cs <= '1';
		elsif falling_edge(clk40) then
			cs <= cs_new;
		end if;
	end process;

	process(bcnt, cs, sclk, data, sync_d0)
		variable bcnt_nxt : unsigned(4 downto 0);
		variable cs_nxt : std_logic;
		variable data_nxt : std_logic_vector(11 downto 0);
	begin
		bcnt_nxt := bcnt;
		cs_nxt := cs;
		data_nxt := data;

		if sclk = '1' then
			if bcnt = "0" then
				cs_nxt := '0';
				data_nxt := (others => '0');
			elsif bcnt = x"10" then
				cs_nxt := '1';
			end if;
		else
			-- Data should be latched on the falling edge of SCLK. Due
			-- to the delay introduced by the synchronizer, it will instead
			-- be latched in on the following rising edge of SCLK.
			if bcnt = x"13" then
				bcnt_nxt := (others => '0');
			else
				bcnt_nxt := bcnt + "1";
			end if;

			data_nxt := data(data'high-1 downto 0) & sync_d0(1);
		end if;

		cs_new <= cs_nxt;
		bcnt_new <= bcnt_nxt;
		data_new <= data_nxt;
	end process;

end Behavioral;

