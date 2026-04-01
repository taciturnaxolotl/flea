#!/usr/bin/env python3
"""
Bouncy Game Visualizer — mirrors the VHDL physics exactly.

Controls: WASD to move/jump, R to reset, T to toggle trail, Q to quit.

Prerequisites:
    pip install pygame

Usage:
    python3 visualizer.py
"""

import math
import pygame
import sys

# --- Screen / VGA constants (match VHDL) ---
SCREEN_W = 640
SCREEN_H = 480
FPS = 60

# --- Physics constants (match VHDL exactly) ---
GRAVITY = 1
IMPULSE = 3
SLAM_TAP_FORCE   = 18   # instant downward burst on S press in air
SLAM_BOOST_CLOSE = 24   # upward boost on hold-slam landing, close range
SLAM_BOOST_MED   = 16   # upward boost, medium range
SLAM_BOOST_FAR   = 8    # upward boost, far range
SLAM_CLOSE_THR   = 80   # pixels: "close to surface" threshold
SLAM_MED_THR     = 200  # pixels: "medium distance" threshold
AIR_CONTROL = 2
JUMP_FORCE = 14         # initial jump force at zero velocity (scales down with |vel_y|)
JUMP_VEL_SCALE = 12    # velocity magnitude at which initial jump force is halved
JUMP_MIN_FORCE = 4     # floor for inverse-scaled initial jump
JUMP_BOUNCE = 6        # fixed additive boost on each ground contact while W held (trampoline)
MAX_VEL_X = 32
SIZE = 7
BOUNCE_SHIFT = 3  # energy loss = vel >> 3 (keep 87.5%)

# --- Bounds (match VHDL) ---
GROUND = 440
CEILING = 16
LEFT_WALL = 8
RIGHT_WALL = 631
GROUND_TOP = 448
CEIL_BOT = 8

# --- Obstacles: (left, top, right, bottom) matching VHDL ---
OBSTACLES = [
    (60,  370, 180, 386),   # Low platform left
    (250, 300, 390, 316),   # Middle floating platform
    (440, 200, 580, 216),   # High platform right
    (140, 120, 200, 150),   # Small block upper-left
]

# --- Colors (1-bit RGB) ---
COLOR_SKY    = (0, 0, 0)
COLOR_GROUND = (0, 255, 0)
COLOR_CEIL   = (0, 255, 0)
COLOR_WALL   = (0, 255, 255)
COLOR_CHAR   = (255, 0, 0)
COLOR_OBS    = (255, 255, 0)

# --- 10-bit signed helpers ---
MASK = 0x3FF

def to_signed(val):
    val = val & MASK
    return val - 1024 if val >= 512 else val

def to_unsigned(val):
    return val & MASK

def negate(v):
    return ((~v) + 1) & MASK


def main():
    pygame.init()
    screen = pygame.display.set_mode((SCREEN_W, SCREEN_H))
    pygame.display.set_caption("Bouncy Game — VHDL Physics Preview")
    clock = pygame.time.Clock()

    char_x = 100
    char_y = 200
    vel_x = to_unsigned(0)
    vel_y = to_unsigned(0)
    squish = 0
    squish_h = False  # False = vertical squish (floor/ceil), True = horizontal squish (walls)
    on_ground = False
    jump_pressed = False
    slam_held = False
    slam_start_y = 0
    prev_key_s = False

    keys_held = {'w': False, 'a': False, 's': False, 'd': False}
    trail = []
    show_trail = True
    font = pygame.font.SysFont("monospace", 14)

    running = True
    while running:
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                running = False
            elif event.type == pygame.KEYDOWN:
                if event.key == pygame.K_w: keys_held['w'] = True
                elif event.key == pygame.K_a: keys_held['a'] = True
                elif event.key == pygame.K_s: keys_held['s'] = True
                elif event.key == pygame.K_d: keys_held['d'] = True
                elif event.key == pygame.K_q: running = False
                elif event.key == pygame.K_t:
                    show_trail = not show_trail; trail.clear()
                elif event.key == pygame.K_r:
                    char_x, char_y = 100, 200
                    vel_x = vel_y = to_unsigned(0)
                    squish = 0; squish_h = False; on_ground = False; jump_pressed = False
                    slam_held = False; slam_start_y = 0; prev_key_s = False
                    trail.clear()
            elif event.type == pygame.KEYUP:
                if event.key == pygame.K_w: keys_held['w'] = False
                elif event.key == pygame.K_a: keys_held['a'] = False
                elif event.key == pygame.K_s: keys_held['s'] = False
                elif event.key == pygame.K_d: keys_held['d'] = False

        # =============================================================
        # Physics — matches VHDL exactly
        # =============================================================
        vx = vel_x
        vy = vel_y
        bounced = False
        bounce_wall = False
        bounce_speed = 0
        grounded = False

        # Jump latch
        if not keys_held['w']:
            jump_pressed = False

        # Compute scaled jump force: full force at zero velocity, tapers off as speed rises
        def scaled_jump():
            speed = abs(to_signed(vel_y))
            force = JUMP_FORCE * JUMP_VEL_SCALE / (JUMP_VEL_SCALE + speed)
            return max(int(force), JUMP_MIN_FORCE)

        # First press on ground: full jump (elif prevents double-apply on same frame)
        if keys_held['w'] and not jump_pressed and on_ground:
            vy = (vy - scaled_jump()) & MASK
            jump_pressed = True
        elif keys_held['w'] and jump_pressed and on_ground:
            # Holding W while bouncing: fixed boost so trampoline accumulates each contact
            vy = (vy - JUMP_BOUNCE) & MASK

        # S slam: rising edge in air = tap burst downward; hold to get landing boost
        if keys_held['s'] and not prev_key_s and not on_ground:
            slam_start_y = char_y
            slam_held = True
            vy = (vy + SLAM_TAP_FORCE) & MASK
        if not keys_held['s']:
            slam_held = False
        prev_key_s = keys_held['s']

        # A/D
        if keys_held['a']:
            if on_ground:
                vx = (vx - IMPULSE) & MASK
            else:
                vx = (vx - AIR_CONTROL) & MASK

        if keys_held['d']:
            if on_ground:
                vx = (vx + IMPULSE) & MASK
            else:
                vx = (vx + AIR_CONTROL) & MASK

        # Gravity
        vy = (vy + GRAVITY) & MASK

        # Friction: vel -= vel/4, min 1
        svx = to_signed(vx)
        if svx > 0:
            drag = svx >> 2
            if drag == 0: drag = 1
            svx -= drag
        elif svx < 0:
            drag = (-svx) >> 2
            if drag == 0: drag = 1
            svx += drag
        vx = to_unsigned(svx)

        # Clamp X
        svx = to_signed(vx)
        if svx > MAX_VEL_X: svx = MAX_VEL_X
        elif svx < -MAX_VEL_X: svx = -MAX_VEL_X
        vx = to_unsigned(svx)

        # Clamp Y
        svy = to_signed(vy)
        if svy > 80: svy = 80
        elif svy < -100: svy = -100
        vy = to_unsigned(svy)

        # Update position
        px = char_x + to_signed(vx)
        py = char_y + to_signed(vy)

        # --- Ground bounce ---
        if py >= GROUND:
            py = GROUND
            bounced = True
            grounded = True
            bounce_speed = abs(to_signed(vy))
            vy = negate(vy)
            svy = to_signed(vy)
            # svy is now negative (upward), apply energy loss on magnitude
            if svy < -1:
                svy += (-svy) >> BOUNCE_SHIFT  # reduce magnitude
            # Kill tiny bounces
            if abs(svy) < 2:
                svy = 0
            vy = to_unsigned(svy)

        # --- Ceiling bounce ---
        if py <= CEILING:
            py = CEILING
            bounced = True
            bounce_speed = abs(to_signed(vy))
            vy = negate(vy)
            svy = to_signed(vy)
            if abs(svy) > 1:
                svy_abs = abs(svy)
                loss = svy_abs >> BOUNCE_SHIFT
                if svy > 0:
                    svy -= loss
                else:
                    svy += loss
            vy = to_unsigned(svy)

        # --- Left wall bounce ---
        if px <= LEFT_WALL + SIZE:
            px = LEFT_WALL + SIZE
            bounced = True; bounce_wall = True
            bounce_speed = abs(to_signed(vx))
            vx = negate(vx)
            svx = to_signed(vx)
            if svx > 1:
                svx -= svx >> BOUNCE_SHIFT
            vx = to_unsigned(svx)

        # --- Right wall bounce ---
        if px >= RIGHT_WALL - SIZE:
            px = RIGHT_WALL - SIZE
            bounced = True; bounce_wall = True
            bounce_speed = abs(to_signed(vx))
            vx = negate(vx)
            svx = to_signed(vx)
            if svx < -1:
                svx += (-svx) >> BOUNCE_SHIFT
            vx = to_unsigned(svx)

        # --- Obstacle collisions (entry-face detection using prev position) ---
        prev_top   = char_y - SIZE
        prev_bot   = char_y + SIZE
        prev_left  = char_x - SIZE
        prev_right = char_x + SIZE

        for (ol, ot, orr, ob) in OBSTACLES:
            c_left = px - SIZE
            c_right = px + SIZE
            c_top = py - SIZE
            c_bot = py + SIZE

            if c_right >= ol and c_left <= orr and c_bot >= ot and c_top <= ob:
                if prev_bot <= ot:
                    # Entered from top
                    py = ot - SIZE; grounded = True
                    bounced = True
                    bounce_speed = abs(to_signed(vy))
                    vy = negate(vy)
                    svy = to_signed(vy)
                    if abs(svy) > 1:
                        loss = abs(svy) >> BOUNCE_SHIFT
                        svy = svy - loss if svy > 0 else svy + loss
                    if abs(svy) < 2: svy = 0
                    vy = to_unsigned(svy)
                elif prev_top >= ob:
                    # Entered from bottom
                    py = ob + SIZE
                    bounced = True
                    vy = negate(vy)
                    svy = to_signed(vy)
                    if svy > 1:
                        svy -= svy >> BOUNCE_SHIFT
                    vy = to_unsigned(svy)
                elif prev_right <= ol:
                    # Entered from left
                    px = ol - SIZE
                    bounced = True; bounce_wall = True
                    bounce_speed = abs(to_signed(vx))
                    vx = negate(vx)
                    svx = to_signed(vx)
                    if svx > 1:      svx -= svx >> BOUNCE_SHIFT
                    elif svx < -1:   svx += (-svx) >> BOUNCE_SHIFT
                    vx = to_unsigned(svx)
                elif prev_left >= orr:
                    # Entered from right
                    px = orr + SIZE
                    bounced = True; bounce_wall = True
                    bounce_speed = abs(to_signed(vx))
                    vx = negate(vx)
                    svx = to_signed(vx)
                    if svx > 1:      svx -= svx >> BOUNCE_SHIFT
                    elif svx < -1:   svx += (-svx) >> BOUNCE_SHIFT
                    vx = to_unsigned(svx)
                else:
                    # Corner/inside fallback
                    svy_now = to_signed(vy)
                    if svy_now >= 0: py = ot - SIZE; grounded = True
                    else:            py = ob + SIZE
                    bounced = True
                    vy = negate(vy)
                    svy = to_signed(vy)
                    if abs(svy) > 1:
                        loss = abs(svy) >> BOUNCE_SHIFT
                        svy = svy - loss if svy > 0 else svy + loss
                    vy = to_unsigned(svy)

        # Hold-slam landing boost: bigger boost when slam started closer to the surface
        if grounded and slam_held:
            dist = py - slam_start_y
            if dist < SLAM_CLOSE_THR:
                slam_boost_val = SLAM_BOOST_CLOSE
            elif dist < SLAM_MED_THR:
                slam_boost_val = SLAM_BOOST_MED
            else:
                slam_boost_val = SLAM_BOOST_FAR
            vy = (vy - slam_boost_val) & MASK
            slam_held = False

        # Commit
        char_x = px
        char_y = py
        vel_x = vx
        vel_y = vy

        # On ground
        on_ground = grounded or (py >= GROUND - 1)

        # Squish — only on impacts with real velocity, not idle ground contact
        if bounced and bounce_speed > 3:
            squish = min(bounce_speed, 8)
            squish_h = bounce_wall
        elif squish > 0:
            squish -= 1

        # Trail
        if show_trail:
            trail.append((char_x, char_y))
            if len(trail) > 300:
                trail.pop(0)

        # =============================================================
        # Rendering
        # =============================================================
        screen.fill(COLOR_SKY)

        # Ceiling
        pygame.draw.rect(screen, COLOR_CEIL, (0, 0, SCREEN_W, CEIL_BOT))

        # Ground
        pygame.draw.rect(screen, COLOR_GROUND,
                         (0, GROUND_TOP, SCREEN_W, SCREEN_H - GROUND_TOP))

        # Walls
        pygame.draw.rect(screen, COLOR_WALL, (0, 0, LEFT_WALL, SCREEN_H))
        pygame.draw.rect(screen, COLOR_WALL,
                         (RIGHT_WALL, 0, SCREEN_W - RIGHT_WALL, SCREEN_H))

        # Obstacles
        for (ol, ot, orr, ob) in OBSTACLES:
            pygame.draw.rect(screen, COLOR_OBS,
                             (ol, ot, orr - ol, ob - ot))

        # Trail
        if show_trail and len(trail) > 1:
            for i, (tx, ty) in enumerate(trail):
                alpha = int(80 * i / len(trail))
                s = pygame.Surface((1, 1))
                s.set_alpha(alpha)
                s.fill((255, 100, 100))
                screen.blit(s, (tx, ty))

        # Character with squish
        # Vertical squish (floor/ceil): wider + shorter
        # Horizontal squish (walls): taller + narrower
        if not squish_h:
            cw = SIZE + squish
            ch = SIZE - squish // 2
        else:
            cw = SIZE - squish // 2
            ch = SIZE + squish
        pygame.draw.rect(screen, COLOR_CHAR,
                         (char_x - cw, char_y - ch, cw * 2, ch * 2))

        # Velocity vector arrow (scale: 2px per unit of velocity)
        svx = to_signed(vel_x)
        svy = to_signed(vel_y)
        ARROW_SCALE = 2
        ax = char_x + svx * ARROW_SCALE
        ay = char_y + svy * ARROW_SCALE
        if svx != 0 or svy != 0:
            pygame.draw.line(screen, (255, 255, 255), (char_x, char_y), (ax, ay), 2)
            # Arrowhead
            angle = math.atan2(svy, svx)
            head = 6
            for side in (+0.5, -0.5):
                hx = ax - head * math.cos(angle + side)
                hy = ay - head * math.sin(angle + side)
                pygame.draw.line(screen, (255, 255, 255), (ax, ay), (int(hx), int(hy)), 2)

        # HUD
        info = [
            f"pos: ({char_x}, {char_y})  vel: ({svx}, {svy})",
            f"squish: {squish}  ground: {'yes' if on_ground else 'no'}",
            "",
            "WASD: move/jump   R: reset   T: trail   Q: quit",
        ]
        for i, line in enumerate(info):
            surf = font.render(line, True, (255, 255, 255))
            screen.blit(surf, (LEFT_WALL + 4, CEIL_BOT + 4 + i * 16))

        pygame.display.flip()
        clock.tick(FPS)

    pygame.quit()


if __name__ == "__main__":
    main()
