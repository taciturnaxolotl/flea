-- ========================================================================
-- Renderer
-- Combinational logic: given the current pixel position and character
-- state, outputs the RGB color for that pixel.
--
-- Draws: character (red), 4 obstacles (yellow), ground/ceiling (green),
--        walls (cyan), sky (black)
-- ========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.STD_LOGIC_ARITH.all;
use IEEE.STD_LOGIC_UNSIGNED.all;

entity renderer is
    port(
        pixel_row    : in  std_logic_vector(9 downto 0);  -- from vga_sync
        pixel_column : in  std_logic_vector(9 downto 0);  -- from vga_sync
        char_x       : in  std_logic_vector(9 downto 0);  -- from physics
        char_y       : in  std_logic_vector(9 downto 0);  -- from physics
        char_width   : in  std_logic_vector(9 downto 0);  -- from physics (animated)
        char_height  : in  std_logic_vector(9 downto 0);  -- from physics (animated)
        red          : out std_logic;
        green        : out std_logic;
        blue         : out std_logic
    );
end renderer;

architecture behavior of renderer is

    -- Screen boundaries
    constant GROUND_TOP : std_logic_vector(9 downto 0) := CONV_STD_LOGIC_VECTOR(448, 10);
    constant CEIL_BOT   : std_logic_vector(9 downto 0) := CONV_STD_LOGIC_VECTOR(8, 10);
    constant LEFT_WALL  : std_logic_vector(9 downto 0) := CONV_STD_LOGIC_VECTOR(8, 10);
    constant RIGHT_WALL : std_logic_vector(9 downto 0) := CONV_STD_LOGIC_VECTOR(631, 10);

    -- Obstacle positions (must match physics_engine)
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

    signal char_on, ground_on, wall_on, ceiling_on, obs_on : std_logic;

begin

    -- Check what the current pixel overlaps
    render : process(pixel_row, pixel_column, char_x, char_y,
                     char_width, char_height)
    begin
        char_on    <= '0';
        ground_on  <= '0';
        wall_on    <= '0';
        ceiling_on <= '0';
        obs_on     <= '0';

        -- Character
        if (pixel_column >= char_x - char_width) and
           (pixel_column <= char_x + char_width) and
           (pixel_row >= char_y - char_height) and
           (pixel_row <= char_y + char_height) then
            char_on <= '1';
        end if;

        -- Ground
        if pixel_row >= GROUND_TOP then ground_on <= '1'; end if;

        -- Ceiling
        if pixel_row <= CEIL_BOT then ceiling_on <= '1'; end if;

        -- Walls
        if (pixel_column < LEFT_WALL) or (pixel_column > RIGHT_WALL) then
            wall_on <= '1';
        end if;

        -- Obstacles
        if (pixel_column >= O1_L) and (pixel_column <= O1_R) and
           (pixel_row >= O1_T) and (pixel_row <= O1_B) then obs_on <= '1'; end if;
        if (pixel_column >= O2_L) and (pixel_column <= O2_R) and
           (pixel_row >= O2_T) and (pixel_row <= O2_B) then obs_on <= '1'; end if;
        if (pixel_column >= O3_L) and (pixel_column <= O3_R) and
           (pixel_row >= O3_T) and (pixel_row <= O3_B) then obs_on <= '1'; end if;
        if (pixel_column >= O4_L) and (pixel_column <= O4_R) and
           (pixel_row >= O4_T) and (pixel_row <= O4_B) then obs_on <= '1'; end if;
    end process render;

    -- Priority color encoder
    -- Character=Red(100), Obstacles=Yellow(110), Ground/Ceil=Green(010),
    -- Walls=Green(010), Sky=Black(000)
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
