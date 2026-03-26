-- ========================================================================
-- Trail
-- Stores 16 world-space positions (updated every 3 frames = ~0.8 s at 60 Hz).
-- Combinationally checks each pixel against stored positions (radius 4 box).
-- trail_on fires for any pixel within 4 world-pixels of any stored dot.
-- ========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.STD_LOGIC_ARITH.all;
use IEEE.STD_LOGIC_UNSIGNED.all;

entity trail is
    port(
        vert_sync    : in  std_logic;
        char_x       : in  std_logic_vector(10 downto 0);
        char_y       : in  std_logic_vector(10 downto 0);
        pixel_column : in  std_logic_vector(9 downto 0);
        pixel_row    : in  std_logic_vector(9 downto 0);
        cam_x        : in  std_logic_vector(10 downto 0);
        cam_y        : in  std_logic_vector(10 downto 0);
        trail_on     : out std_logic
    );
end trail;

architecture behavior of trail is

    constant TRAIL_LEN    : integer := 16;
    constant TRAIL_DIV    : integer := 3;   -- update once every 3 frames
    constant TRAIL_RADIUS : integer := 4;   -- Chebyshev radius in world-pixels

    type pos_arr_t is array(0 to TRAIL_LEN-1) of std_logic_vector(10 downto 0);

    signal tx          : pos_arr_t := (others => (others => '0'));
    signal ty          : pos_arr_t := (others => (others => '0'));
    signal trail_valid : std_logic_vector(TRAIL_LEN-1 downto 0) := (others => '0');
    signal frame_ctr   : integer range 0 to TRAIL_DIV-1 := 0;

begin

    -- Shift register: push new position every TRAIL_DIV frames
    shift : process
    begin
        wait until vert_sync'event and vert_sync = '1';

        if frame_ctr = TRAIL_DIV - 1 then
            for i in TRAIL_LEN-1 downto 1 loop
                tx(i)          <= tx(i-1);
                ty(i)          <= ty(i-1);
                trail_valid(i) <= trail_valid(i-1);
            end loop;
            tx(0)          <= char_x;
            ty(0)          <= char_y;
            trail_valid(0) <= '1';
            frame_ctr      <= 0;
        else
            frame_ctr <= frame_ctr + 1;
        end if;
    end process shift;

    -- Pixel check: is current pixel within TRAIL_RADIUS of any valid trail dot?
    check : process(pixel_column, pixel_row, cam_x, cam_y, tx, ty, trail_valid)
        variable wci, wri : integer;
        variable xi, yi   : integer;
        variable dx, dy   : integer;
        variable hit      : std_logic;
    begin
        wci := CONV_INTEGER('0' & pixel_column) + CONV_INTEGER(cam_x);
        wri := CONV_INTEGER('0' & pixel_row)    + CONV_INTEGER(cam_y);
        hit := '0';

        for i in 0 to TRAIL_LEN-1 loop
            if trail_valid(i) = '1' then
                xi := CONV_INTEGER(tx(i));
                yi := CONV_INTEGER(ty(i));
                dx := wci - xi;
                dy := wri - yi;
                if dx < 0 then dx := -dx; end if;
                if dy < 0 then dy := -dy; end if;
                if dx <= TRAIL_RADIUS and dy <= TRAIL_RADIUS then
                    hit := '1';
                end if;
            end if;
        end loop;

        trail_on <= hit;
    end process check;

end behavior;
