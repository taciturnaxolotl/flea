-- ========================================================================
-- PS2 Keyboard Decoder
-- Receives serial data from a PS2 keyboard and outputs which
-- WASD keys are currently held down.
--
-- PS2 protocol: 11 bits per key event (start, 8 data LSB first, parity, stop)
-- Make code = key pressed, F0 + code = key released
-- Scan codes: W=1D, A=1C, S=1B, D=23
-- ========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.STD_LOGIC_UNSIGNED.all;

entity ps2_decoder is
    port(
        ps2_clk   : in  std_logic;   -- clock from keyboard
        ps2_data  : in  std_logic;   -- serial data from keyboard
        key_w     : out std_logic;   -- '1' when W is held
        key_a     : out std_logic;   -- '1' when A is held
        key_s     : out std_logic;   -- '1' when S is held
        key_d     : out std_logic    -- '1' when D is held
    );
end ps2_decoder;

architecture behavior of ps2_decoder is
    signal shift_reg   : std_logic_vector(10 downto 0);
    signal bit_count   : std_logic_vector(3 downto 0) := (others => '0');
    signal break_flag  : std_logic := '0';
    signal scan_code   : std_logic_vector(7 downto 0);
begin

    -- Single process: shift in bits, decode when frame complete
    ps2_receive : process(ps2_clk)
    begin
        if ps2_clk'event and ps2_clk = '0' then
            -- Shift in new bit (MSB first into shift register)
            shift_reg <= ps2_data & shift_reg(10 downto 1);

            if bit_count = "1010" then
                -- 11th bit received (stop bit), frame complete
                -- Data byte is in shift_reg(9 downto 2) at this point:
                --   shift_reg(10) = parity (from previous edge)
                --   shift_reg(9)  = data bit 7
                --   shift_reg(2)  = data bit 0
                --   shift_reg(1)  = start bit
                scan_code <= shift_reg(9 downto 2);

                -- Decode: F0 means next byte is a key release
                if shift_reg(9 downto 2) = X"F0" then
                    break_flag <= '1';
                elsif break_flag = '1' then
                    -- Key released
                    break_flag <= '0';
                    case shift_reg(9 downto 2) is
                        when X"1D" => key_w <= '0';
                        when X"1C" => key_a <= '0';
                        when X"1B" => key_s <= '0';
                        when X"23" => key_d <= '0';
                        when others => null;
                    end case;
                else
                    -- Key pressed
                    case shift_reg(9 downto 2) is
                        when X"1D" => key_w <= '1';
                        when X"1C" => key_a <= '1';
                        when X"1B" => key_s <= '1';
                        when X"23" => key_d <= '1';
                        when others => null;
                    end case;
                end if;

                bit_count <= (others => '0');
            else
                bit_count <= bit_count + 1;
            end if;
        end if;
    end process ps2_receive;

end behavior;
