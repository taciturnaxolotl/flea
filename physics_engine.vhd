-- ========================================================================
-- Physics Engine
-- Runs once per frame on vert_sync rising edge (~60Hz).
-- Handles gravity, keyboard input, friction, bouncing off walls/floor/
-- ceiling/obstacles, and squish animation.
--
-- Outputs character position and animated dimensions for the renderer.
-- All velocity math is 10-bit 2's complement (bit 9 = sign).
-- ========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.STD_LOGIC_ARITH.all;
use IEEE.STD_LOGIC_UNSIGNED.all;

entity physics_engine is
    port(
        vert_sync   : in  std_logic;                      -- frame clock (~60Hz)
        key_w       : in  std_logic;                      -- from ps2_decoder
        key_a       : in  std_logic;
        key_s       : in  std_logic;
        key_d       : in  std_logic;
        char_x      : out std_logic_vector(9 downto 0);   -- character center X
        char_y      : out std_logic_vector(9 downto 0);   -- character center Y
        char_width  : out std_logic_vector(9 downto 0);   -- animated half-width
        char_height : out std_logic_vector(9 downto 0)    -- animated half-height
    );
end physics_engine;

architecture behavior of physics_engine is

    -- Character state
    signal pos_x : std_logic_vector(9 downto 0) := CONV_STD_LOGIC_VECTOR(100, 10);
    signal pos_y : std_logic_vector(9 downto 0) := CONV_STD_LOGIC_VECTOR(200, 10);
    signal vel_x : std_logic_vector(9 downto 0) := (others => '0');
    signal vel_y : std_logic_vector(9 downto 0) := (others => '0');

    constant SIZE : std_logic_vector(9 downto 0) := CONV_STD_LOGIC_VECTOR(7, 10);

    -- Tuning constants
    constant GRAVITY    : std_logic_vector(9 downto 0) := CONV_STD_LOGIC_VECTOR(1, 10);
    constant IMPULSE    : std_logic_vector(9 downto 0) := CONV_STD_LOGIC_VECTOR(3, 10);
    constant JUMP_FORCE : std_logic_vector(9 downto 0) := CONV_STD_LOGIC_VECTOR(13, 10);
    constant MAX_VEL_X  : std_logic_vector(9 downto 0) := CONV_STD_LOGIC_VECTOR(32, 10);

    -- Screen bounds
    constant GROUND    : std_logic_vector(9 downto 0) := CONV_STD_LOGIC_VECTOR(440, 10);
    constant CEILING   : std_logic_vector(9 downto 0) := CONV_STD_LOGIC_VECTOR(16, 10);
    constant LEFT_WALL : std_logic_vector(9 downto 0) := CONV_STD_LOGIC_VECTOR(8, 10);
    constant RIGHT_WALL: std_logic_vector(9 downto 0) := CONV_STD_LOGIC_VECTOR(631, 10);

    -- Obstacle positions (must match renderer)
    constant O1_L : std_logic_vector(9 downto 0) := CONV_STD_LOGIC_VECTOR(60, 10);
    constant O1_T : std_logic_vector(9 downto 0) := CONV_STD_LOGIC_VECTOR(370, 10);
    constant O1_R : std_logic_vector(9 downto 0) := CONV_STD_LOGIC_VECTOR(180, 10);
    constant O1_B : std_logic_vector(9 downto 0) := CONV_STD_LOGIC_VECTOR(386, 10);

    constant O2_L : std_logic_vector(9 downto 0) := CONV_STD_LOGIC_VECTOR(250, 10);
    constant O2_T : std_logic_vector(9 downto 0) := CONV_STD_LOGIC_VECTOR(300, 10);
    constant O2_R : std_logic_vector(9 downto 0) := CONV_STD_LOGIC_VECTOR(390, 10);
    constant O2_B : std_logic_vector(9 downto 0) := CONV_STD_LOGIC_VECTOR(316, 10);

    constant O3_L : std_logic_vector(9 downto 0) := CONV_STD_LOGIC_VECTOR(440, 10);
    constant O3_T : std_logic_vector(9 downto 0) := CONV_STD_LOGIC_VECTOR(200, 10);
    constant O3_R : std_logic_vector(9 downto 0) := CONV_STD_LOGIC_VECTOR(580, 10);
    constant O3_B : std_logic_vector(9 downto 0) := CONV_STD_LOGIC_VECTOR(216, 10);

    constant O4_L : std_logic_vector(9 downto 0) := CONV_STD_LOGIC_VECTOR(140, 10);
    constant O4_T : std_logic_vector(9 downto 0) := CONV_STD_LOGIC_VECTOR(120, 10);
    constant O4_R : std_logic_vector(9 downto 0) := CONV_STD_LOGIC_VECTOR(200, 10);
    constant O4_B : std_logic_vector(9 downto 0) := CONV_STD_LOGIC_VECTOR(150, 10);

    -- Animation state
    signal squish   : std_logic_vector(3 downto 0) := (others => '0');
    signal squish_h : std_logic := '0';  -- '0'=vertical squish, '1'=horizontal
    signal on_ground    : std_logic := '0';
    signal jump_pressed : std_logic := '0';

begin

    -- Output character position
    char_x <= pos_x;
    char_y <= pos_y;

    -- Squish deforms the character: vertical hit = wider+shorter, wall hit = taller+narrower
    char_width  <= SIZE + ("000000" & squish) when squish_h = '0'
              else SIZE - ("000000" & squish(3 downto 1));
    char_height <= SIZE - ("000000" & squish(3 downto 1)) when squish_h = '0'
              else SIZE + ("000000" & squish);

    -- Main physics process: one tick per frame
    physics : process
        variable vx, vy : std_logic_vector(9 downto 0);
        variable px, py : std_logic_vector(9 downto 0);
        variable bounced     : std_logic;
        variable bounce_wall : std_logic;
        variable bounce_speed : std_logic_vector(9 downto 0);
        variable grounded    : std_logic;
        variable c_left, c_right, c_top, c_bot : std_logic_vector(9 downto 0);
        variable overlap_x, overlap_y : std_logic_vector(9 downto 0);
    begin
        wait until vert_sync'event and vert_sync = '1';

        vx := vel_x;
        vy := vel_y;
        bounced := '0';
        bounce_wall := '0';
        bounce_speed := (others => '0');
        grounded := '0';

        -- == INPUT ==

        if key_w = '0' then
            jump_pressed <= '0';
        end if;

        -- Jump on ground (single impulse)
        if key_w = '1' and jump_pressed = '0' and on_ground = '1' then
            vy := (others => '0');
            vy := vy - JUMP_FORCE;
            jump_pressed <= '1';
        end if;

        -- Bounce boost: holding W adds energy each ground contact
        if key_w = '1' and jump_pressed = '1' and on_ground = '1' then
            vy := vy - 4;
        end if;

        -- Slam down (air only)
        if key_s = '1' and on_ground = '0' then
            vy := vy + IMPULSE;
        end if;

        -- Horizontal: full on ground, reduced in air
        if key_a = '1' then
            if on_ground = '1' then vx := vx - IMPULSE;
            else                     vx := vx - 2; end if;
        end if;
        if key_d = '1' then
            if on_ground = '1' then vx := vx + IMPULSE;
            else                     vx := vx + 2; end if;
        end if;

        -- == GRAVITY ==
        vy := vy + GRAVITY;

        -- == FRICTION: vel -= vel/4, min 1 ==
        if vx(9) = '0' then
            if vx > 0 then
                if vx(9 downto 2) = "00000000" then vx := vx - 1;
                else vx := vx - ("000" & vx(9 downto 3)); end if;
            end if;
        else
            if vx /= "0000000000" then
                if vx(9 downto 2) = "11111111" then vx := vx + 1;
                else vx := vx - ("11" & vx(9 downto 2)); end if;
            end if;
        end if;

        -- == CLAMP ==
        if vx(9) = '0' and vx > MAX_VEL_X then vx := MAX_VEL_X; end if;
        if vx(9) = '1' and vx < (not MAX_VEL_X) + 1 then vx := (not MAX_VEL_X) + 1; end if;
        if vy(9) = '0' and vy > 63 then vy := CONV_STD_LOGIC_VECTOR(63, 10); end if;
        if vy(9) = '1' and vy < CONV_STD_LOGIC_VECTOR(960, 10) then vy := CONV_STD_LOGIC_VECTOR(960, 10); end if;

        -- == MOVE ==
        px := pos_x + vx;
        py := pos_y + vy;

        -- == GROUND ==
        if py >= GROUND then
            py := GROUND;
            bounced := '1'; grounded := '1';
            bounce_speed := vy;
            vy := (not vy) + 1;
            if vy(9) = '1' then
                vy := vy + ("000" & ((not vy(9 downto 3)) + 1));
            end if;
            if vy(9) = '1' and vy >= CONV_STD_LOGIC_VECTOR(1022, 10) then vy := (others => '0');
            elsif vy(9) = '0' then vy := (others => '0'); end if;
        end if;

        -- == CEILING ==
        if py(9) = '1' or py <= CEILING then
            py := CEILING;
            bounced := '1';
            bounce_speed := (not vy) + 1;
            vy := (not vy) + 1;
            if vy(9) = '0' and vy > 1 then
                vy := vy - ("000" & vy(9 downto 3));
            end if;
        end if;

        -- == LEFT WALL ==
        -- Detect underflow: moving left (vx negative) but px wrapped to > pos_x
        if (vx(9) = '1' and px > pos_x) or px <= LEFT_WALL + SIZE then
            px := LEFT_WALL + SIZE;
            bounced := '1'; bounce_wall := '1';
            bounce_speed := (not vx) + 1;
            vx := (not vx) + 1;
            if vx(9) = '0' and vx > 1 then
                vx := vx - ("000" & vx(9 downto 3));
            end if;
        end if;

        -- == RIGHT WALL ==
        if px >= RIGHT_WALL - SIZE then
            px := RIGHT_WALL - SIZE;
            bounced := '1'; bounce_wall := '1';
            bounce_speed := vx;
            vx := (not vx) + 1;
            -- vx is now negative: reduce magnitude toward zero
            if vx(9) = '1' then
                vx := vx + ("000" & ((not vx(9 downto 3)) + 1));
            end if;
            -- Kill tiny bounces
            if vx(9) = '1' and vx >= CONV_STD_LOGIC_VECTOR(1022, 10) then vx := (others => '0'); end if;
        end if;

        -- == OBSTACLE COLLISIONS ==
        -- Pattern: AABB overlap -> resolve on shallower axis -> bounce

        -- Obstacle 1
        c_left := px - SIZE;  c_right := px + SIZE;
        c_top  := py - SIZE;  c_bot   := py + SIZE;
        if (c_right >= O1_L) and (c_left <= O1_R) and
           (c_bot >= O1_T) and (c_top <= O1_B) then
            if vy(9) = '0' then overlap_y := c_bot - O1_T;
            else                 overlap_y := O1_B - c_top; end if;
            if vx(9) = '0' then overlap_x := c_right - O1_L;
            else                 overlap_x := O1_R - c_left; end if;
            if overlap_y <= overlap_x then
                if vy(9) = '0' then py := O1_T - SIZE; grounded := '1';
                else                 py := O1_B + SIZE; end if;
                bounced := '1';
                vy := (not vy) + 1;
                if vy(9) = '0' and vy > 1 then vy := vy - ("000" & vy(9 downto 3));
                elsif vy(9) = '1' and vy < CONV_STD_LOGIC_VECTOR(1022, 10) then
                    vy := vy + ("000" & ((not vy(9 downto 3)) + 1)); end if;
                if vy(9) = '0' and vy < 2 then vy := (others => '0'); end if;
                if vy(9) = '1' and vy >= CONV_STD_LOGIC_VECTOR(1022, 10) then vy := (others => '0'); end if;
            else
                if vx(9) = '0' then px := O1_L - SIZE;
                else                 px := O1_R + SIZE; end if;
                bounced := '1'; bounce_wall := '1';
                vx := (not vx) + 1;
                if vx(9) = '0' and vx > 1 then vx := vx - ("000" & vx(9 downto 3));
                elsif vx(9) = '1' and vx < CONV_STD_LOGIC_VECTOR(1022, 10) then
                    vx := vx + ("000" & ((not vx(9 downto 3)) + 1)); end if;
            end if;
        end if;

        -- Obstacle 2
        c_left := px - SIZE;  c_right := px + SIZE;
        c_top  := py - SIZE;  c_bot   := py + SIZE;
        if (c_right >= O2_L) and (c_left <= O2_R) and
           (c_bot >= O2_T) and (c_top <= O2_B) then
            if vy(9) = '0' then overlap_y := c_bot - O2_T;
            else                 overlap_y := O2_B - c_top; end if;
            if vx(9) = '0' then overlap_x := c_right - O2_L;
            else                 overlap_x := O2_R - c_left; end if;
            if overlap_y <= overlap_x then
                if vy(9) = '0' then py := O2_T - SIZE; grounded := '1';
                else                 py := O2_B + SIZE; end if;
                bounced := '1';
                vy := (not vy) + 1;
                if vy(9) = '0' and vy > 1 then vy := vy - ("000" & vy(9 downto 3));
                elsif vy(9) = '1' and vy < CONV_STD_LOGIC_VECTOR(1022, 10) then
                    vy := vy + ("000" & ((not vy(9 downto 3)) + 1)); end if;
                if vy(9) = '0' and vy < 2 then vy := (others => '0'); end if;
                if vy(9) = '1' and vy >= CONV_STD_LOGIC_VECTOR(1022, 10) then vy := (others => '0'); end if;
            else
                if vx(9) = '0' then px := O2_L - SIZE;
                else                 px := O2_R + SIZE; end if;
                bounced := '1'; bounce_wall := '1';
                vx := (not vx) + 1;
                if vx(9) = '0' and vx > 1 then vx := vx - ("000" & vx(9 downto 3));
                elsif vx(9) = '1' and vx < CONV_STD_LOGIC_VECTOR(1022, 10) then
                    vx := vx + ("000" & ((not vx(9 downto 3)) + 1)); end if;
            end if;
        end if;

        -- Obstacle 3
        c_left := px - SIZE;  c_right := px + SIZE;
        c_top  := py - SIZE;  c_bot   := py + SIZE;
        if (c_right >= O3_L) and (c_left <= O3_R) and
           (c_bot >= O3_T) and (c_top <= O3_B) then
            if vy(9) = '0' then overlap_y := c_bot - O3_T;
            else                 overlap_y := O3_B - c_top; end if;
            if vx(9) = '0' then overlap_x := c_right - O3_L;
            else                 overlap_x := O3_R - c_left; end if;
            if overlap_y <= overlap_x then
                if vy(9) = '0' then py := O3_T - SIZE; grounded := '1';
                else                 py := O3_B + SIZE; end if;
                bounced := '1';
                vy := (not vy) + 1;
                if vy(9) = '0' and vy > 1 then vy := vy - ("000" & vy(9 downto 3));
                elsif vy(9) = '1' and vy < CONV_STD_LOGIC_VECTOR(1022, 10) then
                    vy := vy + ("000" & ((not vy(9 downto 3)) + 1)); end if;
                if vy(9) = '0' and vy < 2 then vy := (others => '0'); end if;
                if vy(9) = '1' and vy >= CONV_STD_LOGIC_VECTOR(1022, 10) then vy := (others => '0'); end if;
            else
                if vx(9) = '0' then px := O3_L - SIZE;
                else                 px := O3_R + SIZE; end if;
                bounced := '1'; bounce_wall := '1';
                vx := (not vx) + 1;
                if vx(9) = '0' and vx > 1 then vx := vx - ("000" & vx(9 downto 3));
                elsif vx(9) = '1' and vx < CONV_STD_LOGIC_VECTOR(1022, 10) then
                    vx := vx + ("000" & ((not vx(9 downto 3)) + 1)); end if;
            end if;
        end if;

        -- Obstacle 4
        c_left := px - SIZE;  c_right := px + SIZE;
        c_top  := py - SIZE;  c_bot   := py + SIZE;
        if (c_right >= O4_L) and (c_left <= O4_R) and
           (c_bot >= O4_T) and (c_top <= O4_B) then
            if vy(9) = '0' then overlap_y := c_bot - O4_T;
            else                 overlap_y := O4_B - c_top; end if;
            if vx(9) = '0' then overlap_x := c_right - O4_L;
            else                 overlap_x := O4_R - c_left; end if;
            if overlap_y <= overlap_x then
                if vy(9) = '0' then py := O4_T - SIZE; grounded := '1';
                else                 py := O4_B + SIZE; end if;
                bounced := '1';
                vy := (not vy) + 1;
                if vy(9) = '0' and vy > 1 then vy := vy - ("000" & vy(9 downto 3));
                elsif vy(9) = '1' and vy < CONV_STD_LOGIC_VECTOR(1022, 10) then
                    vy := vy + ("000" & ((not vy(9 downto 3)) + 1)); end if;
                if vy(9) = '0' and vy < 2 then vy := (others => '0'); end if;
                if vy(9) = '1' and vy >= CONV_STD_LOGIC_VECTOR(1022, 10) then vy := (others => '0'); end if;
            else
                if vx(9) = '0' then px := O4_L - SIZE;
                else                 px := O4_R + SIZE; end if;
                bounced := '1'; bounce_wall := '1';
                vx := (not vx) + 1;
                if vx(9) = '0' and vx > 1 then vx := vx - ("000" & vx(9 downto 3));
                elsif vx(9) = '1' and vx < CONV_STD_LOGIC_VECTOR(1022, 10) then
                    vx := vx + ("000" & ((not vx(9 downto 3)) + 1)); end if;
            end if;
        end if;

        -- == COMMIT ==
        vel_x <= vx;
        vel_y <= vy;
        pos_x <= px;
        pos_y <= py;

        -- Squish on meaningful impacts only
        if bounced = '1' and bounce_speed > 3 then
            if bounce_speed >= 8 then squish <= "1000";
            else squish <= bounce_speed(3 downto 0); end if;
            squish_h <= bounce_wall;
        elsif squish > 0 then
            squish <= squish - 1;
        end if;

        if grounded = '1' then on_ground <= '1';
        elsif py < GROUND - 1 then on_ground <= '0'; end if;

    end process physics;

end behavior;
