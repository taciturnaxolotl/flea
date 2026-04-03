#!/usr/bin/env python3
"""
Bouncy Game Visualizer — mirrors the VHDL physics exactly.

Updates for Full Game:
- Expanded to 1500x1500 world bounds
- Added 1/8th-step lag-following camera (scrolling viewport)
- Reads obstacles from level.json (with fallback)
- Matches piecewise jump scaling logic exactly

Controls: WASD to move/jump, R to reset, T to toggle trail, Q to quit.

Prerequisites:
    pip install pygame

Usage:
    python3 visualizer.py
"""

import math
import pygame
import os
import json

# --- Screen / VGA constants (match VHDL) ---
SCREEN_W = 640
SCREEN_H = 480
WORLD_W = 1500
WORLD_H = 1500
FPS = 60

# --- Physics constants (match VHDL exactly) ---
GRAVITY = 1
IMPULSE = 3
SLAM_TAP_FORCE   = 18
SLAM_BOOST_CLOSE = 24
SLAM_BOOST_MED   = 16
SLAM_BOOST_FAR   = 8
SLAM_CLOSE_THR   = 270
SLAM_MED_THR     = 660
AIR_CONTROL = 2

JUMP_BOUNCE = 6
MAX_VEL_X = 32
SIZE = 7
BOUNCE_SHIFT = 3

# --- Bounds (match VHDL) ---
GROUND = 1480
CEILING = 16
LEFT_WALL = 8
RIGHT_WALL = 1492
GROUND_TOP = 1488
CEIL_BOT = 8

# --- Obstacles (Fallback if level.json is missing) ---
DEFAULT_OBSTACLES = [
    (60, 1430, 150, 1440), (250, 1380, 360, 1390), (490, 1420, 620, 1430),
    (690, 1360, 980, 1370), (460, 1220, 620, 1230), (100, 1170, 270, 1180),
    (200, 980, 460, 990), (570, 1060, 1050, 1070), (930, 1210, 1140, 1220),
    (590, 480, 600, 760), (590, 480, 790, 490), (790, 480, 930, 490),
    (920, 500, 930, 760), (920, 490, 930, 500), (590, 760, 820, 770),
    (720, 640, 820, 650), (650, 570, 730, 580), (310, 800, 510, 810),
    (70, 620, 180, 640), (190, 360, 370, 410), (420, 540, 500, 550),
    (490, 200, 650, 220), (200, 170, 300, 180), (1010, 220, 1170, 290),
    (780, 280, 890, 290), (1120, 580, 1280, 590), (990, 770, 1220, 790),
    (940, 970, 1340, 980), (1280, 850, 1350, 890), (640, 910, 700, 940),
    (1250, 350, 1330, 380), (1200, 1360, 1300, 1380), (1330, 1220, 1400, 1250),
    (1270, 1100, 1430, 1140)
]

def load_obstacles():
    if os.path.exists("level.json"):
        try:
            with open("level.json", "r") as f:
                data = json.load(f)
                return [(o["l"], o["t"], o["r"], o["b"]) for o in data.get("obstacles", [])]
        except Exception as e:
            print(f"Warning: Failed to load level.json ({e}). Using fallback.")
    return DEFAULT_OBSTACLES

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
    pygame.display.set_caption("Bouncy Game — Full Level Visualizer")
    clock = pygame.time.Clock()

    obstacles = load_obstacles()

    char_x = 100
    char_y = 1400
    cam_x = 0
    cam_y = 1020

    vel_x = to_unsigned(0)
    vel_y = to_unsigned(0)
    squish = 0
    squish_h = False
    on_ground = False
    jump_pressed = False
    slam_held = False
    slam_tap = False
    slam_start_y = 0
    prev_key_s = False

    keys_held = {'w': False, 'a': False, 's': False, 'd': False}
    trail = []
    show_trail = True
    show_vector = False
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
                elif event.key == pygame.K_v:
                    show_vector = not show_vector
                elif event.key == pygame.K_r:
                    char_x, char_y = 100, 1400
                    cam_x, cam_y = 0, 1020
                    vel_x = vel_y = to_unsigned(0)
                    squish = 0; squish_h = False; on_ground = False; jump_pressed = False
                    slam_held = False; slam_tap = False; slam_start_y = 0; prev_key_s = False
                    trail.clear()
                    obstacles = load_obstacles() # Reload map on reset
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

        if not keys_held['w']:
            jump_pressed = False

        # VHDL piecewise jump logic
        def scaled_jump():
            speed = abs(to_signed(vel_y))
            if speed <= 3: return 14
            elif speed <= 10: return 8
            elif speed <= 20: return 6
            else: return 4

        if keys_held['w'] and not jump_pressed and on_ground:
            vy = (vy - scaled_jump()) & MASK
            jump_pressed = True
        elif keys_held['w'] and jump_pressed and on_ground:
            vy = (vy - JUMP_BOUNCE) & MASK

        if keys_held['s'] and not prev_key_s and not on_ground:
            slam_start_y = char_y
            slam_held = True
            slam_tap = True
            vy = (vy + SLAM_TAP_FORCE) & MASK
        if not keys_held['s'] and slam_held:
            slam_held = False
        prev_key_s = keys_held['s']

        if keys_held['a']:
            if on_ground: vx = (vx - IMPULSE) & MASK
            else:         vx = (vx - AIR_CONTROL) & MASK

        if keys_held['d']:
            if on_ground: vx = (vx + IMPULSE) & MASK
            else:         vx = (vx + AIR_CONTROL) & MASK

        vy = (vy + GRAVITY) & MASK

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

        svx = to_signed(vx)
        if svx > MAX_VEL_X: svx = MAX_VEL_X
        elif svx < -MAX_VEL_X: svx = -MAX_VEL_X
        vx = to_unsigned(svx)

        svy = to_signed(vy)
        if svy > 80: svy = 80
        elif svy < -100: svy = -100
        vy = to_unsigned(svy)

        px = char_x + to_signed(vx)
        py = char_y + to_signed(vy)

        if py >= GROUND:
            py = GROUND
            bounced = True; grounded = True
            bounce_speed = abs(to_signed(vy))
            vy = negate(vy)
            svy = to_signed(vy)
            if svy < -1: svy += (-svy) >> BOUNCE_SHIFT
            if abs(svy) < 2: svy = 0
            vy = to_unsigned(svy)

        if py <= CEILING:
            py = CEILING
            bounced = True
            bounce_speed = abs(to_signed(vy))
            vy = negate(vy)
            svy = to_signed(vy)
            if abs(svy) > 1:
                loss = abs(svy) >> BOUNCE_SHIFT
                if svy > 0: svy -= loss
                else:       svy += loss
            vy = to_unsigned(svy)

        # AABB Sweep
        prev_top   = char_y - SIZE
        prev_bot   = char_y + SIZE
        prev_left  = char_x - SIZE
        prev_right = char_x + SIZE

        for (ol, ot, orr, ob) in obstacles:
            c_left = px - SIZE;  c_right = px + SIZE
            c_top  = py - SIZE;  c_bot   = py + SIZE

            if to_signed(vx) >= 0: x_overlap = c_right >= ol and prev_left < orr
            else:                  x_overlap = prev_right > ol and c_left <= orr

            if to_signed(vy) >= 0: y_overlap = c_bot >= ot and prev_top < ob
            else:                  y_overlap = prev_bot > ot and c_top <= ob

            if x_overlap and y_overlap:
                if prev_bot <= ot + SIZE and to_signed(vy) >= 0:
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
                elif prev_top >= ob and to_signed(vy) < 0:
                    py = ob + SIZE
                    bounced = True
                    vy = negate(vy)
                    svy = to_signed(vy)
                    if svy > 1: svy -= svy >> BOUNCE_SHIFT
                    vy = to_unsigned(svy)
                elif prev_right <= ol and to_signed(vx) >= 0:
                    px = ol - SIZE
                    bounced = True; bounce_wall = True
                    bounce_speed = abs(to_signed(vx))
                    vx = negate(vx)
                    svx = to_signed(vx)
                    if svx > 1:    svx -= svx >> BOUNCE_SHIFT
                    elif svx < -1: svx += (-svx) >> BOUNCE_SHIFT
                    vx = to_unsigned(svx)
                elif prev_left >= orr and to_signed(vx) < 0:
                    px = orr + SIZE
                    bounced = True; bounce_wall = True
                    bounce_speed = abs(to_signed(vx))
                    vx = negate(vx)
                    svx = to_signed(vx)
                    if svx > 1:    svx -= svx >> BOUNCE_SHIFT
                    elif svx < -1: svx += (-svx) >> BOUNCE_SHIFT
                    vx = to_unsigned(svx)
                else:
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

        if px <= LEFT_WALL + SIZE:
            px = LEFT_WALL + SIZE
            bounced = True; bounce_wall = True
            bounce_speed = abs(to_signed(vx))
            vx = negate(vx)
            svx = to_signed(vx)
            if svx > 1: svx -= svx >> BOUNCE_SHIFT
            vx = to_unsigned(svx)

        if px >= RIGHT_WALL - SIZE:
            px = RIGHT_WALL - SIZE
            bounced = True; bounce_wall = True
            bounce_speed = abs(to_signed(vx))
            vx = negate(vx)
            svx = to_signed(vx)
            if svx < -1: svx += (-svx) >> BOUNCE_SHIFT
            vx = to_unsigned(svx)

        if grounded and slam_tap and not slam_held:
            vy = to_unsigned(0)
            slam_tap = False
        elif grounded and slam_held:
            dist = py - slam_start_y
            if dist < SLAM_CLOSE_THR: slam_boost_val = SLAM_BOOST_CLOSE
            elif dist < SLAM_MED_THR: slam_boost_val = SLAM_BOOST_MED
            else:                     slam_boost_val = SLAM_BOOST_FAR
            vy = (vy - slam_boost_val) & MASK
            slam_held = False
            slam_tap = False

        char_x = px
        char_y = py
        vel_x = vx
        vel_y = vy

        on_ground = grounded or (py >= GROUND - 1)

        if bounced and bounce_speed > 3:
            squish = min(bounce_speed, 8)
            squish_h = bounce_wall
        elif squish > 0:
            squish -= 1

        if show_trail:
            trail.append((char_x, char_y))
            if len(trail) > 300:
                trail.pop(0)

        # =============================================================
        # Camera Update (Matches VHDL Lag-Follow)
        # =============================================================
        if char_x < 320: tcx = 0
        elif char_x > 1180: tcx = 860
        else: tcx = char_x - 320

        if char_y < 240: tcy = 0
        elif char_y > 1260: tcy = 1020
        else: tcy = char_y - 240

        if cam_x < tcx:
            dcx = tcx - cam_x
            cam_x += 1 if (dcx >> 3) == 0 else (dcx >> 3)
        elif cam_x > tcx:
            dcx = cam_x - tcx
            cam_x -= 1 if (dcx >> 3) == 0 else (dcx >> 3)

        if cam_y < tcy:
            dcy = tcy - cam_y
            cam_y += 1 if (dcy >> 3) == 0 else (dcy >> 3)
        elif cam_y > tcy:
            dcy = cam_y - tcy
            cam_y -= 1 if (dcy >> 3) == 0 else (dcy >> 3)


        # =============================================================
        # Rendering
        # =============================================================
        def w2s(wx, wy):
            return (wx - cam_x, wy - cam_y)

        screen.fill(COLOR_SKY)

        # Ceil / Ground / Walls
        pygame.draw.rect(screen, COLOR_CEIL, (0, 0 - cam_y, WORLD_W, CEIL_BOT))
        pygame.draw.rect(screen, COLOR_GROUND, (0, GROUND_TOP - cam_y, WORLD_W, WORLD_H - GROUND_TOP))
        pygame.draw.rect(screen, COLOR_WALL, (0 - cam_x, 0, LEFT_WALL, WORLD_H))
        pygame.draw.rect(screen, COLOR_WALL, (RIGHT_WALL - cam_x, 0, WORLD_W - RIGHT_WALL, WORLD_H))

        # Obstacles
        for (ol, ot, orr, ob) in obstacles:
            sx, sy = w2s(ol, ot)
            pygame.draw.rect(screen, COLOR_OBS, (sx, sy, orr - ol, ob - ot))

        # Trail
        if show_trail and len(trail) > 1:
            for i, (tx, ty) in enumerate(trail):
                sx, sy = w2s(tx, ty)
                alpha = int(80 * i / len(trail))
                s = pygame.Surface((1, 1))
                s.set_alpha(alpha)
                s.fill((255, 100, 100))
                screen.blit(s, (sx, sy))

        # Character
        cx, cy = w2s(char_x, char_y)
        if not squish_h:
            cw = SIZE + squish
            ch = SIZE - squish // 2
        else:
            cw = SIZE - squish // 2
            ch = SIZE + squish
        pygame.draw.rect(screen, COLOR_CHAR, (cx - cw, cy - ch, cw * 2, ch * 2))

        # Velocity Vector
        svx = to_signed(vel_x)
        svy = to_signed(vel_y)
        if show_vector and (svx != 0 or svy != 0):
            ARROW_SCALE = 2
            ax = cx + svx * ARROW_SCALE
            ay = cy + svy * ARROW_SCALE
            pygame.draw.line(screen, (255, 255, 255), (cx, cy), (ax, ay), 2)
            angle = math.atan2(svy, svx)
            head = 6
            for side in (+0.5, -0.5):
                hx = ax - head * math.cos(angle + side)
                hy = ay - head * math.sin(angle + side)
                pygame.draw.line(screen, (255, 255, 255), (ax, ay), (int(hx), int(hy)), 2)

        # Static HUD
        info = [
            f"pos: ({char_x}, {char_y})  vel: ({svx}, {svy})",
            f"cam: ({cam_x}, {cam_y})  squish: {squish}",
            "WASD: move/jump   R: reset   T: trail   V: vector   Q: quit",
        ]
        for i, line in enumerate(info):
            surf = font.render(line, True, (255, 255, 255))
            screen.blit(surf, (8, 8 + i * 16))

        pygame.display.flip()
        clock.tick(FPS)

    pygame.quit()

if __name__ == "__main__":
    main()