-- ========================================================================
-- Physics Engine  (scrolling 1500x1500 world)
-- Positions: 11-bit unsigned (0..2047, world fits in 0..1500).
-- Velocities: 10-bit 2's complement (bit 9 = sign), unchanged.
-- Camera: follows character, clamped to world bounds, output for renderer.
-- ========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.STD_LOGIC_ARITH.all;
use IEEE.STD_LOGIC_UNSIGNED.all;

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
        cam_y       : out std_logic_vector(10 downto 0)
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

    -- SIZE: 10-bit for squish outputs, 11-bit for position arithmetic
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
    constant LEFT_WALL  : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(15,    11);
    constant RIGHT_WALL : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(1492, 11);

    -- ---- Obstacle constants (L, T, R, B) in world-space (11-bit) ----
    -- Bottom zone (near ground, y ~1300-1420)
    constant O1_L  : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(100,  11);
    constant O1_T  : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(1380, 11);
    constant O1_R  : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(280,  11);
    constant O1_B  : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(1396, 11);

    constant O2_L  : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(450,  11);
    constant O2_T  : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(1320, 11);
    constant O2_R  : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(530,  11);
    constant O2_B  : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(1336, 11);

    constant O3_L  : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(750,  11);
    constant O3_T  : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(1390, 11);
    constant O3_R  : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(950,  11);
    constant O3_B  : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(1406, 11);

    constant O4_L  : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(1150, 11);
    constant O4_T  : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(1300, 11);
    constant O4_R  : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(1380, 11);
    constant O4_B  : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(1316, 11);

    -- Mid-lower zone (y ~1000-1140)
    constant O5_L  : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(60,   11);
    constant O5_T  : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(1100, 11);
    constant O5_R  : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(250,  11);
    constant O5_B  : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(1116, 11);

    constant O6_L  : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(400,  11);
    constant O6_T  : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(1050, 11);
    constant O6_R  : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(550,  11);
    constant O6_B  : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(1066, 11);

    constant O7_L  : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(720,  11);
    constant O7_T  : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(1000, 11);
    constant O7_R  : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(920,  11);
    constant O7_B  : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(1016, 11);

    constant O8_L  : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(1100, 11);
    constant O8_T  : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(1120, 11);
    constant O8_R  : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(1350, 11);
    constant O8_B  : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(1136, 11);

    -- Mid-upper zone (y ~650-800)
    constant O9_L  : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(150,  11);
    constant O9_T  : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(780,  11);
    constant O9_R  : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(380,  11);
    constant O9_B  : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(796,  11);

    constant O10_L : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(550,  11);
    constant O10_T : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(700,  11);
    constant O10_R : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(650,  11);
    constant O10_B : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(716,  11);

    constant O11_L : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(850,  11);
    constant O11_T : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(650,  11);
    constant O11_R : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(1050, 11);
    constant O11_B : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(666,  11);

    constant O12_L : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(1200, 11);
    constant O12_T : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(760,  11);
    constant O12_R : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(1450, 11);
    constant O12_B : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(776,  11);

    -- Upper zone (y ~320-500)
    constant O13_L : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(200,  11);
    constant O13_T : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(450,  11);
    constant O13_R : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(420,  11);
    constant O13_B : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(466,  11);

    constant O14_L : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(620,  11);
    constant O14_T : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(380,  11);
    constant O14_R : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(820,  11);
    constant O14_B : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(396,  11);

    constant O15_L : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(1000, 11);
    constant O15_T : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(320,  11);
    constant O15_R : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(1200, 11);
    constant O15_B : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(336,  11);

    constant O16_L : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(1320, 11);
    constant O16_T : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(420,  11);
    constant O16_R : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(1460, 11);
    constant O16_B : std_logic_vector(10 downto 0) := CONV_STD_LOGIC_VECTOR(436,  11);

    -- Animation
    signal squish       : std_logic_vector(3 downto 0) := (others => '0');
    signal squish_h     : std_logic := '0';
    signal on_ground    : std_logic := '0';
    signal jump_pressed : std_logic := '0';

begin

    char_x <= pos_x;
    char_y <= pos_y;
    cam_x  <= cam_x_sig;
    cam_y  <= cam_y_sig;

    char_width  <= SIZE + ("000000" & squish)           when squish_h = '0'
              else SIZE - ("000000" & squish(3 downto 1));
    char_height <= SIZE - ("000000" & squish(3 downto 1)) when squish_h = '0'
              else SIZE + ("000000" & squish);

    physics : process
        variable vx, vy      : std_logic_vector(9 downto 0);
        variable px, py      : std_logic_vector(10 downto 0);
        variable bounced     : std_logic;
        variable bounce_wall : std_logic;
        variable bounce_speed: std_logic_vector(9 downto 0);
        variable grounded    : std_logic;
        variable c_left, c_right, c_top, c_bot : std_logic_vector(10 downto 0);
        variable overlap_x, overlap_y           : std_logic_vector(10 downto 0);
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
                else vx := vx - ("000" & vx(9 downto 3)); end if;
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

        -- == CEILING (py(10)='1' catches negative-wrap underflow) ==
        if py(10) = '1' or py <= CEILING then
            py := CEILING;
            bounced := '1';
            bounce_speed := (not vy) + 1;
            vy := (not vy) + 1;
            if vy(9) = '0' and vy > 1 then
                vy := vy - ("000" & vy(9 downto 3));
            end if;
        end if;

        -- == LEFT WALL (px(10)='1' catches underflow) ==
        if px(10) = '1' or px <= LEFT_WALL + SIZE11 then
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

        -- == OBSTACLE COLLISIONS ==
        -- Shared bounce helpers (vert and horiz) used identically per obstacle.

        -- O1
        c_left:=px-SIZE11; c_right:=px+SIZE11; c_top:=py-SIZE11; c_bot:=py+SIZE11;
        if c_right>=O1_L and c_left<=O1_R and c_bot>=O1_T and c_top<=O1_B then
            if vy(9)='0' then overlap_y:=c_bot-O1_T; else overlap_y:=O1_B-c_top; end if;
            if vx(9)='0' then overlap_x:=c_right-O1_L; else overlap_x:=O1_R-c_left; end if;
            if overlap_y<=overlap_x then
                if vy(9)='0' then py:=O1_T-SIZE11; grounded:='1'; else py:=O1_B+SIZE11; end if;
                bounced:='1';
                vy:=(not vy)+1;
                if vy(9)='0' and vy>1 then vy:=vy-("000"&vy(9 downto 3));
                elsif vy(9)='1' and vy<CONV_STD_LOGIC_VECTOR(1022,10) then vy:=vy+("000"&((not vy(9 downto 3))+1)); end if;
                if vy(9)='0' and vy<2 then vy:=(others=>'0'); end if;
                if vy(9)='1' and vy>=CONV_STD_LOGIC_VECTOR(1022,10) then vy:=(others=>'0'); end if;
            else
                if vx(9)='0' then px:=O1_L-SIZE11; else px:=O1_R+SIZE11; end if;
                bounced:='1'; bounce_wall:='1';
                vx:=(not vx)+1;
                if vx(9)='0' and vx>1 then vx:=vx-("000"&vx(9 downto 3));
                elsif vx(9)='1' and vx<CONV_STD_LOGIC_VECTOR(1022,10) then vx:=vx+("000"&((not vx(9 downto 3))+1)); end if;
            end if;
        end if;

        -- O2
        c_left:=px-SIZE11; c_right:=px+SIZE11; c_top:=py-SIZE11; c_bot:=py+SIZE11;
        if c_right>=O2_L and c_left<=O2_R and c_bot>=O2_T and c_top<=O2_B then
            if vy(9)='0' then overlap_y:=c_bot-O2_T; else overlap_y:=O2_B-c_top; end if;
            if vx(9)='0' then overlap_x:=c_right-O2_L; else overlap_x:=O2_R-c_left; end if;
            if overlap_y<=overlap_x then
                if vy(9)='0' then py:=O2_T-SIZE11; grounded:='1'; else py:=O2_B+SIZE11; end if;
                bounced:='1';
                vy:=(not vy)+1;
                if vy(9)='0' and vy>1 then vy:=vy-("000"&vy(9 downto 3));
                elsif vy(9)='1' and vy<CONV_STD_LOGIC_VECTOR(1022,10) then vy:=vy+("000"&((not vy(9 downto 3))+1)); end if;
                if vy(9)='0' and vy<2 then vy:=(others=>'0'); end if;
                if vy(9)='1' and vy>=CONV_STD_LOGIC_VECTOR(1022,10) then vy:=(others=>'0'); end if;
            else
                if vx(9)='0' then px:=O2_L-SIZE11; else px:=O2_R+SIZE11; end if;
                bounced:='1'; bounce_wall:='1';
                vx:=(not vx)+1;
                if vx(9)='0' and vx>1 then vx:=vx-("000"&vx(9 downto 3));
                elsif vx(9)='1' and vx<CONV_STD_LOGIC_VECTOR(1022,10) then vx:=vx+("000"&((not vx(9 downto 3))+1)); end if;
            end if;
        end if;

        -- O3
        c_left:=px-SIZE11; c_right:=px+SIZE11; c_top:=py-SIZE11; c_bot:=py+SIZE11;
        if c_right>=O3_L and c_left<=O3_R and c_bot>=O3_T and c_top<=O3_B then
            if vy(9)='0' then overlap_y:=c_bot-O3_T; else overlap_y:=O3_B-c_top; end if;
            if vx(9)='0' then overlap_x:=c_right-O3_L; else overlap_x:=O3_R-c_left; end if;
            if overlap_y<=overlap_x then
                if vy(9)='0' then py:=O3_T-SIZE11; grounded:='1'; else py:=O3_B+SIZE11; end if;
                bounced:='1';
                vy:=(not vy)+1;
                if vy(9)='0' and vy>1 then vy:=vy-("000"&vy(9 downto 3));
                elsif vy(9)='1' and vy<CONV_STD_LOGIC_VECTOR(1022,10) then vy:=vy+("000"&((not vy(9 downto 3))+1)); end if;
                if vy(9)='0' and vy<2 then vy:=(others=>'0'); end if;
                if vy(9)='1' and vy>=CONV_STD_LOGIC_VECTOR(1022,10) then vy:=(others=>'0'); end if;
            else
                if vx(9)='0' then px:=O3_L-SIZE11; else px:=O3_R+SIZE11; end if;
                bounced:='1'; bounce_wall:='1';
                vx:=(not vx)+1;
                if vx(9)='0' and vx>1 then vx:=vx-("000"&vx(9 downto 3));
                elsif vx(9)='1' and vx<CONV_STD_LOGIC_VECTOR(1022,10) then vx:=vx+("000"&((not vx(9 downto 3))+1)); end if;
            end if;
        end if;

        -- O4
        c_left:=px-SIZE11; c_right:=px+SIZE11; c_top:=py-SIZE11; c_bot:=py+SIZE11;
        if c_right>=O4_L and c_left<=O4_R and c_bot>=O4_T and c_top<=O4_B then
            if vy(9)='0' then overlap_y:=c_bot-O4_T; else overlap_y:=O4_B-c_top; end if;
            if vx(9)='0' then overlap_x:=c_right-O4_L; else overlap_x:=O4_R-c_left; end if;
            if overlap_y<=overlap_x then
                if vy(9)='0' then py:=O4_T-SIZE11; grounded:='1'; else py:=O4_B+SIZE11; end if;
                bounced:='1';
                vy:=(not vy)+1;
                if vy(9)='0' and vy>1 then vy:=vy-("000"&vy(9 downto 3));
                elsif vy(9)='1' and vy<CONV_STD_LOGIC_VECTOR(1022,10) then vy:=vy+("000"&((not vy(9 downto 3))+1)); end if;
                if vy(9)='0' and vy<2 then vy:=(others=>'0'); end if;
                if vy(9)='1' and vy>=CONV_STD_LOGIC_VECTOR(1022,10) then vy:=(others=>'0'); end if;
            else
                if vx(9)='0' then px:=O4_L-SIZE11; else px:=O4_R+SIZE11; end if;
                bounced:='1'; bounce_wall:='1';
                vx:=(not vx)+1;
                if vx(9)='0' and vx>1 then vx:=vx-("000"&vx(9 downto 3));
                elsif vx(9)='1' and vx<CONV_STD_LOGIC_VECTOR(1022,10) then vx:=vx+("000"&((not vx(9 downto 3))+1)); end if;
            end if;
        end if;

        -- O5
        c_left:=px-SIZE11; c_right:=px+SIZE11; c_top:=py-SIZE11; c_bot:=py+SIZE11;
        if c_right>=O5_L and c_left<=O5_R and c_bot>=O5_T and c_top<=O5_B then
            if vy(9)='0' then overlap_y:=c_bot-O5_T; else overlap_y:=O5_B-c_top; end if;
            if vx(9)='0' then overlap_x:=c_right-O5_L; else overlap_x:=O5_R-c_left; end if;
            if overlap_y<=overlap_x then
                if vy(9)='0' then py:=O5_T-SIZE11; grounded:='1'; else py:=O5_B+SIZE11; end if;
                bounced:='1';
                vy:=(not vy)+1;
                if vy(9)='0' and vy>1 then vy:=vy-("000"&vy(9 downto 3));
                elsif vy(9)='1' and vy<CONV_STD_LOGIC_VECTOR(1022,10) then vy:=vy+("000"&((not vy(9 downto 3))+1)); end if;
                if vy(9)='0' and vy<2 then vy:=(others=>'0'); end if;
                if vy(9)='1' and vy>=CONV_STD_LOGIC_VECTOR(1022,10) then vy:=(others=>'0'); end if;
            else
                if vx(9)='0' then px:=O5_L-SIZE11; else px:=O5_R+SIZE11; end if;
                bounced:='1'; bounce_wall:='1';
                vx:=(not vx)+1;
                if vx(9)='0' and vx>1 then vx:=vx-("000"&vx(9 downto 3));
                elsif vx(9)='1' and vx<CONV_STD_LOGIC_VECTOR(1022,10) then vx:=vx+("000"&((not vx(9 downto 3))+1)); end if;
            end if;
        end if;

        -- O6
        c_left:=px-SIZE11; c_right:=px+SIZE11; c_top:=py-SIZE11; c_bot:=py+SIZE11;
        if c_right>=O6_L and c_left<=O6_R and c_bot>=O6_T and c_top<=O6_B then
            if vy(9)='0' then overlap_y:=c_bot-O6_T; else overlap_y:=O6_B-c_top; end if;
            if vx(9)='0' then overlap_x:=c_right-O6_L; else overlap_x:=O6_R-c_left; end if;
            if overlap_y<=overlap_x then
                if vy(9)='0' then py:=O6_T-SIZE11; grounded:='1'; else py:=O6_B+SIZE11; end if;
                bounced:='1';
                vy:=(not vy)+1;
                if vy(9)='0' and vy>1 then vy:=vy-("000"&vy(9 downto 3));
                elsif vy(9)='1' and vy<CONV_STD_LOGIC_VECTOR(1022,10) then vy:=vy+("000"&((not vy(9 downto 3))+1)); end if;
                if vy(9)='0' and vy<2 then vy:=(others=>'0'); end if;
                if vy(9)='1' and vy>=CONV_STD_LOGIC_VECTOR(1022,10) then vy:=(others=>'0'); end if;
            else
                if vx(9)='0' then px:=O6_L-SIZE11; else px:=O6_R+SIZE11; end if;
                bounced:='1'; bounce_wall:='1';
                vx:=(not vx)+1;
                if vx(9)='0' and vx>1 then vx:=vx-("000"&vx(9 downto 3));
                elsif vx(9)='1' and vx<CONV_STD_LOGIC_VECTOR(1022,10) then vx:=vx+("000"&((not vx(9 downto 3))+1)); end if;
            end if;
        end if;

        -- O7
        c_left:=px-SIZE11; c_right:=px+SIZE11; c_top:=py-SIZE11; c_bot:=py+SIZE11;
        if c_right>=O7_L and c_left<=O7_R and c_bot>=O7_T and c_top<=O7_B then
            if vy(9)='0' then overlap_y:=c_bot-O7_T; else overlap_y:=O7_B-c_top; end if;
            if vx(9)='0' then overlap_x:=c_right-O7_L; else overlap_x:=O7_R-c_left; end if;
            if overlap_y<=overlap_x then
                if vy(9)='0' then py:=O7_T-SIZE11; grounded:='1'; else py:=O7_B+SIZE11; end if;
                bounced:='1';
                vy:=(not vy)+1;
                if vy(9)='0' and vy>1 then vy:=vy-("000"&vy(9 downto 3));
                elsif vy(9)='1' and vy<CONV_STD_LOGIC_VECTOR(1022,10) then vy:=vy+("000"&((not vy(9 downto 3))+1)); end if;
                if vy(9)='0' and vy<2 then vy:=(others=>'0'); end if;
                if vy(9)='1' and vy>=CONV_STD_LOGIC_VECTOR(1022,10) then vy:=(others=>'0'); end if;
            else
                if vx(9)='0' then px:=O7_L-SIZE11; else px:=O7_R+SIZE11; end if;
                bounced:='1'; bounce_wall:='1';
                vx:=(not vx)+1;
                if vx(9)='0' and vx>1 then vx:=vx-("000"&vx(9 downto 3));
                elsif vx(9)='1' and vx<CONV_STD_LOGIC_VECTOR(1022,10) then vx:=vx+("000"&((not vx(9 downto 3))+1)); end if;
            end if;
        end if;

        -- O8
        c_left:=px-SIZE11; c_right:=px+SIZE11; c_top:=py-SIZE11; c_bot:=py+SIZE11;
        if c_right>=O8_L and c_left<=O8_R and c_bot>=O8_T and c_top<=O8_B then
            if vy(9)='0' then overlap_y:=c_bot-O8_T; else overlap_y:=O8_B-c_top; end if;
            if vx(9)='0' then overlap_x:=c_right-O8_L; else overlap_x:=O8_R-c_left; end if;
            if overlap_y<=overlap_x then
                if vy(9)='0' then py:=O8_T-SIZE11; grounded:='1'; else py:=O8_B+SIZE11; end if;
                bounced:='1';
                vy:=(not vy)+1;
                if vy(9)='0' and vy>1 then vy:=vy-("000"&vy(9 downto 3));
                elsif vy(9)='1' and vy<CONV_STD_LOGIC_VECTOR(1022,10) then vy:=vy+("000"&((not vy(9 downto 3))+1)); end if;
                if vy(9)='0' and vy<2 then vy:=(others=>'0'); end if;
                if vy(9)='1' and vy>=CONV_STD_LOGIC_VECTOR(1022,10) then vy:=(others=>'0'); end if;
            else
                if vx(9)='0' then px:=O8_L-SIZE11; else px:=O8_R+SIZE11; end if;
                bounced:='1'; bounce_wall:='1';
                vx:=(not vx)+1;
                if vx(9)='0' and vx>1 then vx:=vx-("000"&vx(9 downto 3));
                elsif vx(9)='1' and vx<CONV_STD_LOGIC_VECTOR(1022,10) then vx:=vx+("000"&((not vx(9 downto 3))+1)); end if;
            end if;
        end if;

        -- O9
        c_left:=px-SIZE11; c_right:=px+SIZE11; c_top:=py-SIZE11; c_bot:=py+SIZE11;
        if c_right>=O9_L and c_left<=O9_R and c_bot>=O9_T and c_top<=O9_B then
            if vy(9)='0' then overlap_y:=c_bot-O9_T; else overlap_y:=O9_B-c_top; end if;
            if vx(9)='0' then overlap_x:=c_right-O9_L; else overlap_x:=O9_R-c_left; end if;
            if overlap_y<=overlap_x then
                if vy(9)='0' then py:=O9_T-SIZE11; grounded:='1'; else py:=O9_B+SIZE11; end if;
                bounced:='1';
                vy:=(not vy)+1;
                if vy(9)='0' and vy>1 then vy:=vy-("000"&vy(9 downto 3));
                elsif vy(9)='1' and vy<CONV_STD_LOGIC_VECTOR(1022,10) then vy:=vy+("000"&((not vy(9 downto 3))+1)); end if;
                if vy(9)='0' and vy<2 then vy:=(others=>'0'); end if;
                if vy(9)='1' and vy>=CONV_STD_LOGIC_VECTOR(1022,10) then vy:=(others=>'0'); end if;
            else
                if vx(9)='0' then px:=O9_L-SIZE11; else px:=O9_R+SIZE11; end if;
                bounced:='1'; bounce_wall:='1';
                vx:=(not vx)+1;
                if vx(9)='0' and vx>1 then vx:=vx-("000"&vx(9 downto 3));
                elsif vx(9)='1' and vx<CONV_STD_LOGIC_VECTOR(1022,10) then vx:=vx+("000"&((not vx(9 downto 3))+1)); end if;
            end if;
        end if;

        -- O10
        c_left:=px-SIZE11; c_right:=px+SIZE11; c_top:=py-SIZE11; c_bot:=py+SIZE11;
        if c_right>=O10_L and c_left<=O10_R and c_bot>=O10_T and c_top<=O10_B then
            if vy(9)='0' then overlap_y:=c_bot-O10_T; else overlap_y:=O10_B-c_top; end if;
            if vx(9)='0' then overlap_x:=c_right-O10_L; else overlap_x:=O10_R-c_left; end if;
            if overlap_y<=overlap_x then
                if vy(9)='0' then py:=O10_T-SIZE11; grounded:='1'; else py:=O10_B+SIZE11; end if;
                bounced:='1';
                vy:=(not vy)+1;
                if vy(9)='0' and vy>1 then vy:=vy-("000"&vy(9 downto 3));
                elsif vy(9)='1' and vy<CONV_STD_LOGIC_VECTOR(1022,10) then vy:=vy+("000"&((not vy(9 downto 3))+1)); end if;
                if vy(9)='0' and vy<2 then vy:=(others=>'0'); end if;
                if vy(9)='1' and vy>=CONV_STD_LOGIC_VECTOR(1022,10) then vy:=(others=>'0'); end if;
            else
                if vx(9)='0' then px:=O10_L-SIZE11; else px:=O10_R+SIZE11; end if;
                bounced:='1'; bounce_wall:='1';
                vx:=(not vx)+1;
                if vx(9)='0' and vx>1 then vx:=vx-("000"&vx(9 downto 3));
                elsif vx(9)='1' and vx<CONV_STD_LOGIC_VECTOR(1022,10) then vx:=vx+("000"&((not vx(9 downto 3))+1)); end if;
            end if;
        end if;

        -- O11
        c_left:=px-SIZE11; c_right:=px+SIZE11; c_top:=py-SIZE11; c_bot:=py+SIZE11;
        if c_right>=O11_L and c_left<=O11_R and c_bot>=O11_T and c_top<=O11_B then
            if vy(9)='0' then overlap_y:=c_bot-O11_T; else overlap_y:=O11_B-c_top; end if;
            if vx(9)='0' then overlap_x:=c_right-O11_L; else overlap_x:=O11_R-c_left; end if;
            if overlap_y<=overlap_x then
                if vy(9)='0' then py:=O11_T-SIZE11; grounded:='1'; else py:=O11_B+SIZE11; end if;
                bounced:='1';
                vy:=(not vy)+1;
                if vy(9)='0' and vy>1 then vy:=vy-("000"&vy(9 downto 3));
                elsif vy(9)='1' and vy<CONV_STD_LOGIC_VECTOR(1022,10) then vy:=vy+("000"&((not vy(9 downto 3))+1)); end if;
                if vy(9)='0' and vy<2 then vy:=(others=>'0'); end if;
                if vy(9)='1' and vy>=CONV_STD_LOGIC_VECTOR(1022,10) then vy:=(others=>'0'); end if;
            else
                if vx(9)='0' then px:=O11_L-SIZE11; else px:=O11_R+SIZE11; end if;
                bounced:='1'; bounce_wall:='1';
                vx:=(not vx)+1;
                if vx(9)='0' and vx>1 then vx:=vx-("000"&vx(9 downto 3));
                elsif vx(9)='1' and vx<CONV_STD_LOGIC_VECTOR(1022,10) then vx:=vx+("000"&((not vx(9 downto 3))+1)); end if;
            end if;
        end if;

        -- O12
        c_left:=px-SIZE11; c_right:=px+SIZE11; c_top:=py-SIZE11; c_bot:=py+SIZE11;
        if c_right>=O12_L and c_left<=O12_R and c_bot>=O12_T and c_top<=O12_B then
            if vy(9)='0' then overlap_y:=c_bot-O12_T; else overlap_y:=O12_B-c_top; end if;
            if vx(9)='0' then overlap_x:=c_right-O12_L; else overlap_x:=O12_R-c_left; end if;
            if overlap_y<=overlap_x then
                if vy(9)='0' then py:=O12_T-SIZE11; grounded:='1'; else py:=O12_B+SIZE11; end if;
                bounced:='1';
                vy:=(not vy)+1;
                if vy(9)='0' and vy>1 then vy:=vy-("000"&vy(9 downto 3));
                elsif vy(9)='1' and vy<CONV_STD_LOGIC_VECTOR(1022,10) then vy:=vy+("000"&((not vy(9 downto 3))+1)); end if;
                if vy(9)='0' and vy<2 then vy:=(others=>'0'); end if;
                if vy(9)='1' and vy>=CONV_STD_LOGIC_VECTOR(1022,10) then vy:=(others=>'0'); end if;
            else
                if vx(9)='0' then px:=O12_L-SIZE11; else px:=O12_R+SIZE11; end if;
                bounced:='1'; bounce_wall:='1';
                vx:=(not vx)+1;
                if vx(9)='0' and vx>1 then vx:=vx-("000"&vx(9 downto 3));
                elsif vx(9)='1' and vx<CONV_STD_LOGIC_VECTOR(1022,10) then vx:=vx+("000"&((not vx(9 downto 3))+1)); end if;
            end if;
        end if;

        -- O13
        c_left:=px-SIZE11; c_right:=px+SIZE11; c_top:=py-SIZE11; c_bot:=py+SIZE11;
        if c_right>=O13_L and c_left<=O13_R and c_bot>=O13_T and c_top<=O13_B then
            if vy(9)='0' then overlap_y:=c_bot-O13_T; else overlap_y:=O13_B-c_top; end if;
            if vx(9)='0' then overlap_x:=c_right-O13_L; else overlap_x:=O13_R-c_left; end if;
            if overlap_y<=overlap_x then
                if vy(9)='0' then py:=O13_T-SIZE11; grounded:='1'; else py:=O13_B+SIZE11; end if;
                bounced:='1';
                vy:=(not vy)+1;
                if vy(9)='0' and vy>1 then vy:=vy-("000"&vy(9 downto 3));
                elsif vy(9)='1' and vy<CONV_STD_LOGIC_VECTOR(1022,10) then vy:=vy+("000"&((not vy(9 downto 3))+1)); end if;
                if vy(9)='0' and vy<2 then vy:=(others=>'0'); end if;
                if vy(9)='1' and vy>=CONV_STD_LOGIC_VECTOR(1022,10) then vy:=(others=>'0'); end if;
            else
                if vx(9)='0' then px:=O13_L-SIZE11; else px:=O13_R+SIZE11; end if;
                bounced:='1'; bounce_wall:='1';
                vx:=(not vx)+1;
                if vx(9)='0' and vx>1 then vx:=vx-("000"&vx(9 downto 3));
                elsif vx(9)='1' and vx<CONV_STD_LOGIC_VECTOR(1022,10) then vx:=vx+("000"&((not vx(9 downto 3))+1)); end if;
            end if;
        end if;

        -- O14
        c_left:=px-SIZE11; c_right:=px+SIZE11; c_top:=py-SIZE11; c_bot:=py+SIZE11;
        if c_right>=O14_L and c_left<=O14_R and c_bot>=O14_T and c_top<=O14_B then
            if vy(9)='0' then overlap_y:=c_bot-O14_T; else overlap_y:=O14_B-c_top; end if;
            if vx(9)='0' then overlap_x:=c_right-O14_L; else overlap_x:=O14_R-c_left; end if;
            if overlap_y<=overlap_x then
                if vy(9)='0' then py:=O14_T-SIZE11; grounded:='1'; else py:=O14_B+SIZE11; end if;
                bounced:='1';
                vy:=(not vy)+1;
                if vy(9)='0' and vy>1 then vy:=vy-("000"&vy(9 downto 3));
                elsif vy(9)='1' and vy<CONV_STD_LOGIC_VECTOR(1022,10) then vy:=vy+("000"&((not vy(9 downto 3))+1)); end if;
                if vy(9)='0' and vy<2 then vy:=(others=>'0'); end if;
                if vy(9)='1' and vy>=CONV_STD_LOGIC_VECTOR(1022,10) then vy:=(others=>'0'); end if;
            else
                if vx(9)='0' then px:=O14_L-SIZE11; else px:=O14_R+SIZE11; end if;
                bounced:='1'; bounce_wall:='1';
                vx:=(not vx)+1;
                if vx(9)='0' and vx>1 then vx:=vx-("000"&vx(9 downto 3));
                elsif vx(9)='1' and vx<CONV_STD_LOGIC_VECTOR(1022,10) then vx:=vx+("000"&((not vx(9 downto 3))+1)); end if;
            end if;
        end if;

        -- O15
        c_left:=px-SIZE11; c_right:=px+SIZE11; c_top:=py-SIZE11; c_bot:=py+SIZE11;
        if c_right>=O15_L and c_left<=O15_R and c_bot>=O15_T and c_top<=O15_B then
            if vy(9)='0' then overlap_y:=c_bot-O15_T; else overlap_y:=O15_B-c_top; end if;
            if vx(9)='0' then overlap_x:=c_right-O15_L; else overlap_x:=O15_R-c_left; end if;
            if overlap_y<=overlap_x then
                if vy(9)='0' then py:=O15_T-SIZE11; grounded:='1'; else py:=O15_B+SIZE11; end if;
                bounced:='1';
                vy:=(not vy)+1;
                if vy(9)='0' and vy>1 then vy:=vy-("000"&vy(9 downto 3));
                elsif vy(9)='1' and vy<CONV_STD_LOGIC_VECTOR(1022,10) then vy:=vy+("000"&((not vy(9 downto 3))+1)); end if;
                if vy(9)='0' and vy<2 then vy:=(others=>'0'); end if;
                if vy(9)='1' and vy>=CONV_STD_LOGIC_VECTOR(1022,10) then vy:=(others=>'0'); end if;
            else
                if vx(9)='0' then px:=O15_L-SIZE11; else px:=O15_R+SIZE11; end if;
                bounced:='1'; bounce_wall:='1';
                vx:=(not vx)+1;
                if vx(9)='0' and vx>1 then vx:=vx-("000"&vx(9 downto 3));
                elsif vx(9)='1' and vx<CONV_STD_LOGIC_VECTOR(1022,10) then vx:=vx+("000"&((not vx(9 downto 3))+1)); end if;
            end if;
        end if;

        -- O16
        c_left:=px-SIZE11; c_right:=px+SIZE11; c_top:=py-SIZE11; c_bot:=py+SIZE11;
        if c_right>=O16_L and c_left<=O16_R and c_bot>=O16_T and c_top<=O16_B then
            if vy(9)='0' then overlap_y:=c_bot-O16_T; else overlap_y:=O16_B-c_top; end if;
            if vx(9)='0' then overlap_x:=c_right-O16_L; else overlap_x:=O16_R-c_left; end if;
            if overlap_y<=overlap_x then
                if vy(9)='0' then py:=O16_T-SIZE11; grounded:='1'; else py:=O16_B+SIZE11; end if;
                bounced:='1';
                vy:=(not vy)+1;
                if vy(9)='0' and vy>1 then vy:=vy-("000"&vy(9 downto 3));
                elsif vy(9)='1' and vy<CONV_STD_LOGIC_VECTOR(1022,10) then vy:=vy+("000"&((not vy(9 downto 3))+1)); end if;
                if vy(9)='0' and vy<2 then vy:=(others=>'0'); end if;
                if vy(9)='1' and vy>=CONV_STD_LOGIC_VECTOR(1022,10) then vy:=(others=>'0'); end if;
            else
                if vx(9)='0' then px:=O16_L-SIZE11; else px:=O16_R+SIZE11; end if;
                bounced:='1'; bounce_wall:='1';
                vx:=(not vx)+1;
                if vx(9)='0' and vx>1 then vx:=vx-("000"&vx(9 downto 3));
                elsif vx(9)='1' and vx<CONV_STD_LOGIC_VECTOR(1022,10) then vx:=vx+("000"&((not vx(9 downto 3))+1)); end if;
            end if;
        end if;

        -- == COMMIT ==
        vel_x <= vx;
        vel_y <= vy;
        pos_x <= px;
        pos_y <= py;

        -- == CAMERA: center on character (px/py), clamp to world ==
        -- cam_x = clamp(px - 320, 0, 860)  [world 1500 - screen 640 = 860]
        if px < CONV_STD_LOGIC_VECTOR(320, 11) then
            cam_x_sig <= (others => '0');
        elsif px > CONV_STD_LOGIC_VECTOR(1180, 11) then
            cam_x_sig <= CONV_STD_LOGIC_VECTOR(860, 11);
        else
            cam_x_sig <= px - CONV_STD_LOGIC_VECTOR(320, 11);
        end if;

        -- cam_y = clamp(py - 240, 0, 1020)  [world 1500 - screen 480 = 1020]
        if py < CONV_STD_LOGIC_VECTOR(240, 11) then
            cam_y_sig <= (others => '0');
        elsif py > CONV_STD_LOGIC_VECTOR(1260, 11) then
            cam_y_sig <= CONV_STD_LOGIC_VECTOR(1020, 11);
        else
            cam_y_sig <= py - CONV_STD_LOGIC_VECTOR(240, 11);
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
        elsif py < GROUND - 1 then on_ground <= '0'; end if;

    end process physics;

end behavior;
