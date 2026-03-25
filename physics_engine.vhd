-- ========================================================================
-- Physics Engine  (scrolling 1500x1500 world)
-- Positions: 11-bit unsigned.  Valid range: 0..1492 (fits in 11-bit fine).
-- Velocities: 10-bit 2's complement, bit 9 = sign.
--
-- Underflow detection: uses >= 2000 threshold instead of bit-10 sign check.
-- Bit-10 was wrong because GROUND(1480) and RIGHT_WALL(1492) both have
-- bit 10 set (values >= 1024), causing false ceiling/wall triggers.
--
-- Obstacles imported from level package (use work.level.all).
-- ========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.STD_LOGIC_ARITH.all;
use IEEE.STD_LOGIC_UNSIGNED.all;
use work.level.all;

entity physics_engine is
    port(
        vert_sync   : in  std_logic;
        key_w       : in  std_logic;
        key_a       : in  std_logic;
        key_s       : in  std_logic;
        key_d       : in  std_logic;
        char_x      : out std_logic_vector(10 downto 0);
        char_y      : out std_logic_vector(10 downto 0);
        char_width  : out std_logic_vector(9 downto 0);
        char_height : out std_logic_vector(9 downto 0);
        cam_x       : out std_logic_vector(10 downto 0);
        cam_y       : out std_logic_vector(10 downto 0);
        vel_out     : out std_logic_vector(9 downto 0)
    );
end physics_engine;

architecture behavior of physics_engine is

    -- Character state
    signal pos_x     : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(100,  11);
    signal pos_y     : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(1400, 11);
    signal vel_x     : std_logic_vector(9 downto 0)  := (others => '0');
    signal vel_y     : std_logic_vector(9 downto 0)  := (others => '0');
    signal cam_x_sig : std_logic_vector(10 downto 0) := (others => '0');
    signal cam_y_sig : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(1020, 11);

    -- SIZE: 10-bit for squish output math, 11-bit for position arithmetic
    constant SIZE    : std_logic_vector(9 downto 0)  := CONV_STD_LOGIC_VECTOR(7, 10);
    constant SIZE11  : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(7, 11);

    -- Physics tuning
    constant GRAVITY    : std_logic_vector(9 downto 0) := CONV_STD_LOGIC_VECTOR(1,  10);
    constant IMPULSE    : std_logic_vector(9 downto 0) := CONV_STD_LOGIC_VECTOR(3,  10);
    constant JUMP_FORCE : std_logic_vector(9 downto 0) := CONV_STD_LOGIC_VECTOR(13, 10);
    constant MAX_VEL_X  : std_logic_vector(9 downto 0) := CONV_STD_LOGIC_VECTOR(32, 10);

    -- World bounds (11-bit)
    constant GROUND     : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(1480, 11);
    constant CEILING    : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(16,   11);
    constant LEFT_WALL  : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(8,    11);
    constant RIGHT_WALL : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(1492, 11);

    -- Underflow sentinel: valid positions top out at 1492; underflow wraps to >= 2000.
    -- (Min case: CEILING(16) - max_upward(64) = -48 -> 11-bit unsigned = 2000.)
    constant UNDERFLOW  : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(2000, 11);

    -- Tune: vertical speed (0-63) at which all 10 LEDs are fully lit.
    -- Lower  = more sensitive (fewer LEDs at low speed fill up faster).
    -- Higher = less sensitive (need a harder bounce to light all LEDs).
    constant LED_FULL_VEL : integer := 16;

    -- Animation
    signal squish       : std_logic_vector(3 downto 0) := (others => '0');
    signal squish_h     : std_logic := '0';
    signal on_ground    : std_logic := '0';
    signal jump_pressed : std_logic := '0';

    signal abs_vel_y : std_logic_vector(9 downto 0);

begin

    char_x <= pos_x;
    char_y <= pos_y;
    cam_x  <= cam_x_sig;
    cam_y  <= cam_y_sig;

    -- Absolute value of vertical velocity.
    abs_vel_y <= (not vel_y) + 1 when vel_y(9) = '1' else vel_y;

    -- Scale so LED_FULL_VEL maps to all 10 LEDs on (1023); clamp above that.
    vel_out <= CONV_STD_LOGIC_VECTOR(1023, 10)
               when CONV_INTEGER(abs_vel_y) >= LED_FULL_VEL else
               CONV_STD_LOGIC_VECTOR(CONV_INTEGER(abs_vel_y) * 1023 / LED_FULL_VEL, 10);

    char_width  <= SIZE + ("000000" & squish)           when squish_h = '0'
              else SIZE - ("000000" & squish(3 downto 1));
    char_height <= SIZE - ("000000" & squish(3 downto 1)) when squish_h = '0'
              else SIZE + ("000000" & squish);

    physics : process
        variable vx, vy       : std_logic_vector(9 downto 0);
        variable px, py        : std_logic_vector(10 downto 0);
        variable bounced       : std_logic;
        variable bounce_wall   : std_logic;
        variable bounce_speed  : std_logic_vector(9 downto 0);
        variable grounded      : std_logic;
        variable c_left, c_right, c_top, c_bot : std_logic_vector(10 downto 0);
        variable overlap_x, overlap_y           : std_logic_vector(10 downto 0);
        variable tcx, tcy, dcx, dcy            : std_logic_vector(10 downto 0);
    begin
        wait until vert_sync'event and vert_sync = '1';

        vx := vel_x;  vy := vel_y;
        bounced := '0';  bounce_wall := '0';
        bounce_speed := (others => '0');
        grounded := '0';

        -- == INPUT ==
        if key_w = '0' then jump_pressed <= '0'; end if;

        if key_w = '1' and jump_pressed = '0' and on_ground = '1' then
            vy := (others => '0');
            vy := vy - JUMP_FORCE;
            jump_pressed <= '1';
        end if;

        if key_w = '1' and jump_pressed = '1' and on_ground = '1' then
            vy := vy - 4;
        end if;

        if key_s = '1' and on_ground = '0' then vy := vy + IMPULSE; end if;

        if key_a = '1' then
            if on_ground = '1' then vx := vx - IMPULSE; else vx := vx - 2; end if;
        end if;
        if key_d = '1' then
            if on_ground = '1' then vx := vx + IMPULSE; else vx := vx + 2; end if;
        end if;

        -- == GRAVITY ==
        vy := vy + GRAVITY;

        -- == FRICTION: vel -= vel/4, min 1 ==
        if vx(9) = '0' then
            if vx > 0 then
                if vx(9 downto 2) = "00000000" then vx := vx - 1;
                else vx := vx - ("00" & vx(9 downto 2)); end if;
            end if;
        else
            if vx /= "0000000000" then
                if vx(9 downto 2) = "11111111" then vx := vx + 1;
                else vx := vx - ("11" & vx(9 downto 2)); end if;
            end if;
        end if;

        -- == CLAMP velocities ==
        if vx(9) = '0' and vx > MAX_VEL_X then vx := MAX_VEL_X; end if;
        if vx(9) = '1' and vx < (not MAX_VEL_X) + 1 then vx := (not MAX_VEL_X) + 1; end if;
        if vy(9) = '0' and vy > 63 then vy := CONV_STD_LOGIC_VECTOR(63, 10); end if;
        if vy(9) = '1' and vy < CONV_STD_LOGIC_VECTOR(960, 10) then
            vy := CONV_STD_LOGIC_VECTOR(960, 10);
        end if;

        -- == MOVE: sign-extend 10-bit velocity to 11-bit before adding ==
        px := pos_x + (vx(9) & vx);
        py := pos_y + (vy(9) & vy);

        -- == GROUND ==
        if py >= GROUND then
            py := GROUND;
            bounced := '1';  grounded := '1';
            bounce_speed := vy;
            vy := (not vy) + 1;
            if vy(9) = '1' then
                vy := vy + ("000" & ((not vy(9 downto 3)) + 1));
            end if;
            if vy(9) = '1' and vy >= CONV_STD_LOGIC_VECTOR(1022, 10) then
                vy := (others => '0');
            elsif vy(9) = '0' then vy := (others => '0'); end if;
        end if;

        -- == CEILING ==
        -- Underflow detection: py >= 2000 means it wrapped below zero.
        -- (GROUND=1480, RIGHT_WALL=1492 are both < 2000, so no false triggers.)
        if py >= UNDERFLOW or py <= CEILING then
            py := CEILING;
            bounced := '1';
            bounce_speed := (not vy) + 1;
            vy := (not vy) + 1;
            if vy(9) = '0' and vy > 1 then
                vy := vy - ("000" & vy(9 downto 3));
            end if;
        end if;

        -- == LEFT WALL ==
        -- Same underflow fix: px >= 2000 means wrapped below zero.
        if px >= UNDERFLOW or px <= LEFT_WALL + SIZE11 then
            px := LEFT_WALL + SIZE11;
            bounced := '1';  bounce_wall := '1';
            bounce_speed := (not vx) + 1;
            vx := (not vx) + 1;
            if vx(9) = '0' and vx > 1 then
                vx := vx - ("000" & vx(9 downto 3));
            end if;
        end if;

        -- == RIGHT WALL ==
        if px >= RIGHT_WALL - SIZE11 then
            px := RIGHT_WALL - SIZE11;
            bounced := '1';  bounce_wall := '1';
            bounce_speed := vx;
            vx := (not vx) + 1;
            if vx(9) = '1' then
                vx := vx + ("000" & ((not vx(9 downto 3)) + 1));
            end if;
            if vx(9) = '1' and vx >= CONV_STD_LOGIC_VECTOR(1022, 10) then
                vx := (others => '0');
            end if;
        end if;

        -- == OBSTACLE COLLISIONS (loop over level_pkg arrays) ==
        for obs_i in 0 to OBS_COUNT-1 loop
            c_left  := px - SIZE11;
            c_right := px + SIZE11;
            c_top   := py - SIZE11;
            c_bot   := py + SIZE11;

            if c_right >= OBS_L(obs_i) and c_left <= OBS_R(obs_i) and
               c_bot   >= OBS_T(obs_i) and c_top  <= OBS_B(obs_i) then

                if vy(9) = '0' then overlap_y := c_bot   - OBS_T(obs_i);
                else                 overlap_y := OBS_B(obs_i) - c_top;   end if;
                if vx(9) = '0' then overlap_x := c_right - OBS_L(obs_i);
                else                 overlap_x := OBS_R(obs_i) - c_left;  end if;

                if overlap_y <= overlap_x then
                    -- Vertical resolution
                    if vy(9) = '0' then py := OBS_T(obs_i) - SIZE11; grounded := '1';
                    else                 py := OBS_B(obs_i) + SIZE11; end if;
                    bounced := '1';
                    vy := (not vy) + 1;
                    if vy(9) = '0' and vy > 1 then
                        vy := vy - ("000" & vy(9 downto 3));
                    elsif vy(9) = '1' and vy < CONV_STD_LOGIC_VECTOR(1022, 10) then
                        vy := vy + ("000" & ((not vy(9 downto 3)) + 1));
                    end if;
                    if vy(9) = '0' and vy < 2 then vy := (others => '0'); end if;
                    if vy(9) = '1' and vy >= CONV_STD_LOGIC_VECTOR(1022, 10) then
                        vy := (others => '0');
                    end if;
                else
                    -- Horizontal resolution
                    if vx(9) = '0' then px := OBS_L(obs_i) - SIZE11;
                    else                 px := OBS_R(obs_i) + SIZE11; end if;
                    bounced := '1';  bounce_wall := '1';
                    vx := (not vx) + 1;
                    if vx(9) = '0' and vx > 1 then
                        vx := vx - ("000" & vx(9 downto 3));
                    elsif vx(9) = '1' and vx < CONV_STD_LOGIC_VECTOR(1022, 10) then
                        vx := vx + ("000" & ((not vx(9 downto 3)) + 1));
                    end if;
                end if;
            end if;
        end loop;

        -- == COMMIT ==
        vel_x <= vx;
        vel_y <= vy;
        pos_x <= px;
        pos_y <= py;

        -- == CAMERA: lag-follow character (1/8 of gap per frame, min 1px) ==
        -- Compute clamped target
        if px < CONV_STD_LOGIC_VECTOR(320, 11) then
            tcx := (others => '0');
        elsif px > CONV_STD_LOGIC_VECTOR(1180, 11) then
            tcx := CONV_STD_LOGIC_VECTOR(860, 11);
        else
            tcx := px - CONV_STD_LOGIC_VECTOR(320, 11);
        end if;

        if py < CONV_STD_LOGIC_VECTOR(240, 11) then
            tcy := (others => '0');
        elsif py > CONV_STD_LOGIC_VECTOR(1260, 11) then
            tcy := CONV_STD_LOGIC_VECTOR(1020, 11);
        else
            tcy := py - CONV_STD_LOGIC_VECTOR(240, 11);
        end if;

        -- Slide camera toward target
        if cam_x_sig < tcx then
            dcx := tcx - cam_x_sig;
            if dcx(10 downto 3) = "00000000" then
                cam_x_sig <= cam_x_sig + 1;
            else
                cam_x_sig <= cam_x_sig + ("000" & dcx(10 downto 3));
            end if;
        elsif cam_x_sig > tcx then
            dcx := cam_x_sig - tcx;
            if dcx(10 downto 3) = "00000000" then
                cam_x_sig <= cam_x_sig - 1;
            else
                cam_x_sig <= cam_x_sig - ("000" & dcx(10 downto 3));
            end if;
        end if;

        if cam_y_sig < tcy then
            dcy := tcy - cam_y_sig;
            if dcy(10 downto 3) = "00000000" then
                cam_y_sig <= cam_y_sig + 1;
            else
                cam_y_sig <= cam_y_sig + ("000" & dcy(10 downto 3));
            end if;
        elsif cam_y_sig > tcy then
            dcy := cam_y_sig - tcy;
            if dcy(10 downto 3) = "00000000" then
                cam_y_sig <= cam_y_sig - 1;
            else
                cam_y_sig <= cam_y_sig - ("000" & dcy(10 downto 3));
            end if;
        end if;

        -- == SQUISH ==
        if bounced = '1' and bounce_speed > 3 then
            if bounce_speed >= 8 then squish <= "1000";
            else squish <= bounce_speed(3 downto 0); end if;
            squish_h <= bounce_wall;
        elsif squish > 0 then
            squish <= squish - 1;
        end if;

        if grounded = '1' then on_ground <= '1';
        else on_ground <= '0'; end if;

    end process physics;

end behavior;
