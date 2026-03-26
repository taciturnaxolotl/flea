-- ========================================================================
-- Renderer  (scrolling world)
-- world_col = pixel_column + cam_x
-- world_row = pixel_row    + cam_y
-- All comparisons in world-space (11-bit).
-- Obstacles imported from level package (use work.level.all).
--
-- Color priority:
--   Arrow = White (111)  >  Char = Red (100)  >  Obs = Yellow (110)
--   >  Ground/Ceil/Walls = Green (010)  >  Trail = Magenta (101)  >  Sky = Black (000)
-- ========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.STD_LOGIC_ARITH.all;
use IEEE.STD_LOGIC_UNSIGNED.all;
use work.level.all;

entity renderer is
    port(
        pixel_row    : in  std_logic_vector(9 downto 0);
        pixel_column : in  std_logic_vector(9 downto 0);
        char_x       : in  std_logic_vector(10 downto 0);
        char_y       : in  std_logic_vector(10 downto 0);
        char_width   : in  std_logic_vector(9 downto 0);
        char_height  : in  std_logic_vector(9 downto 0);
        cam_x        : in  std_logic_vector(10 downto 0);
        cam_y        : in  std_logic_vector(10 downto 0);
        vel_x_in     : in  std_logic_vector(9 downto 0);
        vel_y_in     : in  std_logic_vector(9 downto 0);
        trail_on_in  : in  std_logic;
        red          : out std_logic;
        green        : out std_logic;
        blue         : out std_logic
    );
end renderer;

architecture behavior of renderer is

    -- World boundaries (11-bit)
    constant GROUND_TOP : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(1488, 11);
    constant CEIL_BOT   : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(8,    11);
    constant LEFT_WALL  : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(8,    11);
    constant RIGHT_WALL : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(1492, 11);

    -- World-space pixel coordinates (shared between processes)
    signal wc : std_logic_vector(10 downto 0);
    signal wr : std_logic_vector(10 downto 0);

    signal char_on, ground_on, wall_on, ceiling_on, obs_on, arrow_on : std_logic;

begin

    -- Convert screen coordinates to world coordinates
    wc <= ('0' & pixel_column) + cam_x;
    wr <= ('0' & pixel_row)    + cam_y;

    -- ----------------------------------------------------------------
    -- Scene geometry: character, world edges, obstacles
    -- ----------------------------------------------------------------
    render : process(wc, wr, char_x, char_y, char_width, char_height)
    begin
        char_on    <= '0';
        ground_on  <= '0';
        wall_on    <= '0';
        ceiling_on <= '0';
        obs_on     <= '0';

        -- Character
        if wc >= char_x - ('0' & char_width)  and
           wc <= char_x + ('0' & char_width)  and
           wr >= char_y - ('0' & char_height) and
           wr <= char_y + ('0' & char_height) then
            char_on <= '1';
        end if;

        -- World edges
        if wr >= GROUND_TOP then ground_on  <= '1'; end if;
        if wr <= CEIL_BOT   then ceiling_on <= '1'; end if;
        if wc < LEFT_WALL or wc > RIGHT_WALL then wall_on <= '1'; end if;

        -- Obstacles (loop over level_pkg arrays)
        for obs_i in 0 to OBS_COUNT-1 loop
            if wc >= OBS_L(obs_i) and wc <= OBS_R(obs_i) and
               wr >= OBS_T(obs_i) and wr <= OBS_B(obs_i) then
                obs_on <= '1';
            end if;
        end loop;

    end process render;

    -- ----------------------------------------------------------------
    -- Velocity vector arrow
    -- Line from (char_x, char_y) to (char_x + 3*vx, char_y + 3*vy).
    -- Uses cross-product line-segment test:
    --   pixel on segment iff |dy*(px-x0) - dx*(py-y0)| <= max(|dx|,|dy|)
    --                    and  dx*(px-x0) + dy*(py-y0)  in [0, dx^2+dy^2]
    -- ----------------------------------------------------------------
    arrow_proc : process(wc, wr, char_x, char_y, vel_x_in, vel_y_in)
        variable wci, wri   : integer;
        variable cx, cy     : integer;
        variable vxi, vyi   : integer;
        variable dx, dy     : integer;
        variable cross      : integer;
        variable dot_p      : integer;
        variable len_sq     : integer;
        variable maxd       : integer;
    begin
        wci := CONV_INTEGER(wc);
        wri := CONV_INTEGER(wr);
        cx  := CONV_INTEGER(char_x);
        cy  := CONV_INTEGER(char_y);

        -- Convert 10-bit 2's complement velocity to signed integer
        if vel_x_in(9) = '1' then vxi := CONV_INTEGER(vel_x_in) - 1024;
        else                       vxi := CONV_INTEGER(vel_x_in); end if;
        if vel_y_in(9) = '1' then vyi := CONV_INTEGER(vel_y_in) - 1024;
        else                       vyi := CONV_INTEGER(vel_y_in); end if;

        -- Scale arrow by 3 for visibility
        dx := vxi * 3;
        dy := vyi * 3;

        -- Precompute line metrics
        cross  := dy * (wci - cx) - dx * (wri - cy);
        dot_p  := dx * (wci - cx) + dy * (wri - cy);
        len_sq := dx * dx + dy * dy;

        -- Chebyshev thickness (~1-2 world-pixels wide)
        maxd := dx; if maxd < 0 then maxd := -maxd; end if;
        if  dy > maxd then maxd :=  dy;
        elsif -dy > maxd then maxd := -dy; end if;

        arrow_on <= '0';
        if maxd > 4 then  -- skip arrow when velocity is negligible
            if cross >= -maxd and cross <= maxd and
               dot_p >= 0     and dot_p <= len_sq then
                arrow_on <= '1';
            end if;
        end if;
    end process arrow_proc;

    -- ----------------------------------------------------------------
    -- Color output with priority
    -- ----------------------------------------------------------------
    color : process(char_on, ground_on, wall_on, ceiling_on,
                    obs_on, arrow_on, trail_on_in)
    begin
        if    arrow_on = '1' then
            red <= '1'; green <= '1'; blue <= '1';  -- White
        elsif char_on = '1' then
            red <= '1'; green <= '0'; blue <= '0';  -- Red
        elsif obs_on = '1' then
            red <= '1'; green <= '1'; blue <= '0';  -- Yellow
        elsif ground_on = '1' or ceiling_on = '1' then
            red <= '0'; green <= '1'; blue <= '0';  -- Green
        elsif wall_on = '1' then
            red <= '0'; green <= '1'; blue <= '0';  -- Green
        elsif trail_on_in = '1' then
            red <= '1'; green <= '0'; blue <= '1';  -- Magenta
        else
            red <= '0'; green <= '0'; blue <= '0';  -- Black (sky)
        end if;
    end process color;

end behavior;
