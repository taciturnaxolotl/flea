-- ========================================================================
-- Renderer  (scrolling world)
-- Converts screen pixel (col, row) to world coords via camera offset,
-- then tests world-space position against all geometry.
--
-- world_col = pixel_column + cam_x
-- world_row = pixel_row    + cam_y
--
-- All boundary/obstacle constants are in world-space (11-bit).
-- ========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.STD_LOGIC_ARITH.all;
use IEEE.STD_LOGIC_UNSIGNED.all;

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

    -- Obstacle positions (must match physics_engine, 11-bit world-space)
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

    signal char_on, ground_on, wall_on, ceiling_on, obs_on : std_logic;

begin

    render : process(pixel_row, pixel_column, char_x, char_y,
                     char_width, char_height, cam_x, cam_y)
        variable wc : std_logic_vector(10 downto 0);  -- world column
        variable wr : std_logic_vector(10 downto 0);  -- world row
    begin
        wc := ('0' & pixel_column) + cam_x;
        wr := ('0' & pixel_row)    + cam_y;

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

        -- Ground / ceiling / walls (world edges)
        if wr >= GROUND_TOP then ground_on <= '1'; end if;
        if wr <= CEIL_BOT   then ceiling_on <= '1'; end if;
        if wc < LEFT_WALL or wc > RIGHT_WALL then wall_on <= '1'; end if;

        -- Obstacles
        if wc>=O1_L  and wc<=O1_R  and wr>=O1_T  and wr<=O1_B  then obs_on<='1'; end if;
        if wc>=O2_L  and wc<=O2_R  and wr>=O2_T  and wr<=O2_B  then obs_on<='1'; end if;
        if wc>=O3_L  and wc<=O3_R  and wr>=O3_T  and wr<=O3_B  then obs_on<='1'; end if;
        if wc>=O4_L  and wc<=O4_R  and wr>=O4_T  and wr<=O4_B  then obs_on<='1'; end if;
        if wc>=O5_L  and wc<=O5_R  and wr>=O5_T  and wr<=O5_B  then obs_on<='1'; end if;
        if wc>=O6_L  and wc<=O6_R  and wr>=O6_T  and wr<=O6_B  then obs_on<='1'; end if;
        if wc>=O7_L  and wc<=O7_R  and wr>=O7_T  and wr<=O7_B  then obs_on<='1'; end if;
        if wc>=O8_L  and wc<=O8_R  and wr>=O8_T  and wr<=O8_B  then obs_on<='1'; end if;
        if wc>=O9_L  and wc<=O9_R  and wr>=O9_T  and wr<=O9_B  then obs_on<='1'; end if;
        if wc>=O10_L and wc<=O10_R and wr>=O10_T and wr<=O10_B then obs_on<='1'; end if;
        if wc>=O11_L and wc<=O11_R and wr>=O11_T and wr<=O11_B then obs_on<='1'; end if;
        if wc>=O12_L and wc<=O12_R and wr>=O12_T and wr<=O12_B then obs_on<='1'; end if;
        if wc>=O13_L and wc<=O13_R and wr>=O13_T and wr<=O13_B then obs_on<='1'; end if;
        if wc>=O14_L and wc<=O14_R and wr>=O14_T and wr<=O14_B then obs_on<='1'; end if;
        if wc>=O15_L and wc<=O15_R and wr>=O15_T and wr<=O15_B then obs_on<='1'; end if;
        if wc>=O16_L and wc<=O16_R and wr>=O16_T and wr<=O16_B then obs_on<='1'; end if;

    end process render;

    -- Priority: char=Red(100), obstacles=Yellow(110), ground/ceil/walls=Green(010), sky=Black
    color : process(char_on, ground_on, wall_on, ceiling_on, obs_on)
    begin
        if char_on = '1' then
            red <= '1'; green <= '0'; blue <= '0';
        elsif obs_on = '1' then
            red <= '1'; green <= '1'; blue <= '0';
        elsif ground_on = '1' or ceiling_on = '1' then
            red <= '0'; green <= '1'; blue <= '0';
        elsif wall_on = '1' then
            red <= '0'; green <= '1'; blue <= '0';
        else
            red <= '0'; green <= '0'; blue <= '0';
        end if;
    end process color;

end behavior;
