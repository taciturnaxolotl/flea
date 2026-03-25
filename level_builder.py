#!/usr/bin/env python3
"""
Level Builder for VHDL Bouncy Game
World: 1500x1500 px  |  VGA viewport: 640x480

Controls:
  Left-drag   draw new platform (snapped to grid)
  Right-click delete platform under cursor
  Click       select platform  (shown in orange)
  Del/Bksp    delete selected
  Middle-drag pan view
  Scroll      zoom
  S           toggle grid snap
  E           export JSON + VHDL package
  L           load level.json
  Q / close   quit

Export writes two files:
  <name>.json        – reloadable level data
  <name>_pkg.vhd     – VHDL package (use work.<name>_pkg.all)

Prerequisites:  pip install pygame
"""

import pygame
import json
import sys
from pathlib import Path

# ── Window layout ──────────────────────────────────────────────────────────
WINDOW_W, WINDOW_H = 1280, 820
SIDEBAR_W = 270
VIEW_X   = SIDEBAR_W          # left edge of the world canvas
VIEW_W   = WINDOW_W - SIDEBAR_W
VIEW_H   = WINDOW_H

# ── World constants (must match VHDL) ──────────────────────────────────────
WORLD_W, WORLD_H = 1500, 1500
WALL_L    =    8   # physics LEFT_WALL
WALL_R    = 1492   # physics RIGHT_WALL
CEIL_Y    =   16   # physics CEILING  (character can't go above)
GROUND_Y  = 1480   # physics GROUND   (character center lands here)
CEIL_VIS  =    8   # renderer CEIL_BOT
GROUND_VIS= 1488   # renderer GROUND_TOP
CHAR_SIZE =    7   # physics SIZE (half-width/height)

GRID = 10           # snap grid in world pixels
MIN_DIM = 10        # minimum platform width or height

# ── Colours ────────────────────────────────────────────────────────────────
C_BG         = (18, 18, 18)
C_SIDEBAR    = (28, 28, 28)
C_SIDEBAR_SEP= (55, 55, 55)
C_SKY        = (20, 20, 40)
C_GROUND     = (20, 80, 20)
C_CEIL_STRIP = (20, 80, 20)
C_WALL       = (0,  70, 70)
C_OBS        = (210, 210, 0)
C_OBS_SEL    = (255, 130, 0)
C_OBS_GHOST  = (255, 255, 100, 70)
C_OBS_BORDER = (255, 255, 255)
C_VIEWPORT   = (80, 100, 220)
C_GRID       = (35, 35, 45)
C_TEXT       = (210, 210, 210)
C_TEXT_DIM   = (140, 140, 140)
C_TITLE      = (255, 210, 60)
C_ACCENT     = (100, 200, 255)
C_OK         = (80, 200, 80)
C_WARN       = (220, 80, 80)


class LevelBuilder:
    def __init__(self, level_name: str = "level"):
        pygame.init()
        self.screen = pygame.display.set_mode((WINDOW_W, WINDOW_H))
        pygame.display.set_caption("Level Builder — VHDL Bouncy Game")
        self.clock = pygame.time.Clock()

        self.font     = pygame.font.SysFont("monospace", 13)
        self.font_sm  = pygame.font.SysFont("monospace", 11)
        self.font_lg  = pygame.font.SysFont("monospace", 15, bold=True)

        self.level_name = level_name

        # ── view state ──
        fit = min(VIEW_W / WORLD_W, VIEW_H / WORLD_H) * 0.90
        self.zoom  = fit
        self.pan_x = VIEW_X + (VIEW_W - WORLD_W * fit) / 2
        self.pan_y = (VIEW_H - WORLD_H * fit) / 2
        self._panning   = False
        self._pan_last  = (0, 0)

        # ── edit state ──
        self.snap       = True
        self._drawing   = False
        self._draw_start= None   # world coords (snapped)

        self.obstacles = []      # list of [l, t, r, b]
        self.selected  = None    # index or None
        self.status    = "Ready"
        self.status_ok = True

    # ═══════════════════════════════════════════════════════ coordinate utils

    def w2s(self, wx, wy):
        """World → screen."""
        return (self.pan_x + wx * self.zoom,
                self.pan_y + wy * self.zoom)

    def s2w(self, sx, sy):
        """Screen → world (float)."""
        return ((sx - self.pan_x) / self.zoom,
                (sy - self.pan_y) / self.zoom)

    def _snap(self, v):
        return round(v / GRID) * GRID if self.snap else int(round(v))

    def _clamp_wx(self, v):
        return max(WALL_L, min(WALL_R, v))

    def _clamp_wy(self, v):
        return max(CEIL_Y, min(GROUND_Y, v))

    def _obs_at(self, wx, wy):
        """Index of topmost obstacle under world point, or None."""
        for i in range(len(self.obstacles) - 1, -1, -1):
            l, t, r, b = self.obstacles[i]
            if l <= wx <= r and t <= wy <= b:
                return i
        return None

    # ═══════════════════════════════════════════════════════════ main loop

    def run(self):
        while True:
            if not self._handle_events():
                break
            self._draw()
            pygame.display.flip()
            self.clock.tick(60)
        pygame.quit()

    # ═══════════════════════════════════════════════════════ event handling

    def _handle_events(self):
        for ev in pygame.event.get():
            if ev.type == pygame.QUIT:
                return False

            elif ev.type == pygame.KEYDOWN:
                if ev.key == pygame.K_q:
                    return False
                elif ev.key == pygame.K_ESCAPE:
                    self.selected = None
                    self._drawing = False
                elif ev.key == pygame.K_s:
                    self.snap = not self.snap
                    self._set_status(f"Snap {'ON' if self.snap else 'OFF'}")
                elif ev.key == pygame.K_e:
                    self.export()
                elif ev.key == pygame.K_l:
                    self.load()
                elif ev.key in (pygame.K_DELETE, pygame.K_BACKSPACE):
                    self._delete_selected()

            elif ev.type == pygame.MOUSEBUTTONDOWN:
                if not self._in_view(ev.pos):
                    continue
                if ev.button == 2:
                    self._panning = True
                    self._pan_last = ev.pos
                elif ev.button == 1:
                    self._on_lmb_down(ev.pos)
                elif ev.button == 3:
                    self._on_rmb_down(ev.pos)

            elif ev.type == pygame.MOUSEBUTTONUP:
                if ev.button == 2:
                    self._panning = False
                elif ev.button == 1 and self._drawing:
                    self._on_lmb_up(ev.pos)

            elif ev.type == pygame.MOUSEMOTION:
                if self._panning:
                    dx = ev.pos[0] - self._pan_last[0]
                    dy = ev.pos[1] - self._pan_last[1]
                    self.pan_x += dx
                    self.pan_y += dy
                    self._pan_last = ev.pos

            elif ev.type == pygame.MOUSEWHEEL:
                if self._in_view(pygame.mouse.get_pos()):
                    self._do_zoom(ev.y, pygame.mouse.get_pos())

        return True

    def _in_view(self, pos):
        return pos[0] >= VIEW_X

    def _on_lmb_down(self, pos):
        wx, wy = self.s2w(*pos)
        hit = self._obs_at(wx, wy)
        if hit is not None:
            self.selected = hit
            self._drawing = False
        else:
            self.selected = None
            self._drawing = True
            self._draw_start = (
                self._clamp_wx(self._snap(wx)),
                self._clamp_wy(self._snap(wy)),
            )

    def _on_lmb_up(self, pos):
        self._drawing = False
        if self._draw_start is None:
            return
        wx, wy = self.s2w(*pos)
        ex = self._clamp_wx(self._snap(wx))
        ey = self._clamp_wy(self._snap(wy))
        x0, y0 = self._draw_start
        l, r = sorted([x0, ex])
        t, b = sorted([y0, ey])
        if r - l >= MIN_DIM and b - t >= MIN_DIM:
            self.obstacles.append([l, t, r, b])
            self.selected = len(self.obstacles) - 1
            self._set_status(f"Added platform {len(self.obstacles)-1}  ({r-l}×{b-t}px)")
        else:
            self._set_status("Too small — drag further to create platform", ok=False)
        self._draw_start = None

    def _on_rmb_down(self, pos):
        wx, wy = self.s2w(*pos)
        hit = self._obs_at(wx, wy)
        if hit is not None:
            self.obstacles.pop(hit)
            if self.selected == hit:
                self.selected = None
            elif self.selected is not None and self.selected > hit:
                self.selected -= 1
            self._set_status(f"Deleted platform {hit}")

    def _delete_selected(self):
        if self.selected is not None and self.selected < len(self.obstacles):
            self.obstacles.pop(self.selected)
            self._set_status(f"Deleted platform {self.selected}")
            self.selected = None

    def _do_zoom(self, direction, pivot):
        factor = 1.15 if direction > 0 else (1 / 1.15)
        new_zoom = max(0.04, min(6.0, self.zoom * factor))
        mx, my = pivot
        self.pan_x = mx - (mx - self.pan_x) * (new_zoom / self.zoom)
        self.pan_y = my - (my - self.pan_y) * (new_zoom / self.zoom)
        self.zoom = new_zoom

    def _set_status(self, msg, ok=True):
        self.status = msg
        self.status_ok = ok

    # ═══════════════════════════════════════════════════════════ rendering

    def _draw(self):
        self.screen.fill(C_BG)

        clip = pygame.Rect(VIEW_X, 0, VIEW_W, VIEW_H)
        self.screen.set_clip(clip)
        self._draw_world()
        self.screen.set_clip(None)

        self._draw_sidebar()
        self._draw_cursor_coords()

    def _draw_world(self):
        z = self.zoom

        def r(wx, wy, ww, wh, color, border=0, border_color=None):
            sx, sy = self.w2s(wx, wy)
            sw = max(1, ww * z)
            sh = max(1, wh * z)
            rect = pygame.Rect(sx, sy, sw, sh)
            pygame.draw.rect(self.screen, color, rect)
            if border:
                pygame.draw.rect(self.screen, border_color or C_OBS_BORDER, rect, border)

        # Sky
        r(WALL_L, CEIL_VIS, WALL_R - WALL_L, GROUND_VIS - CEIL_VIS, C_SKY)
        # Ground
        r(0, GROUND_VIS, WORLD_W, WORLD_H - GROUND_VIS, C_GROUND)
        # Ceiling
        r(WALL_L, 0, WALL_R - WALL_L, CEIL_VIS, C_CEIL_STRIP)
        # Left wall
        r(0, 0, WALL_L, WORLD_H, C_WALL)
        # Right wall
        r(WALL_R, 0, WORLD_W - WALL_R, WORLD_H, C_WALL)

        # Grid
        if z >= 0.35:
            self._draw_grid()

        # Viewport indicator (blue box showing what FPGA screen would show at start pos)
        cam_x = max(0, min(860, 100 - 320))   # start pos x=100
        cam_y = max(0, min(1020, 1400 - 240))  # start pos y=1400
        vp_sl = self.w2s(cam_x, cam_y)
        vp_br = self.w2s(cam_x + 640, cam_y + 480)
        pygame.draw.rect(self.screen, C_VIEWPORT,
            pygame.Rect(vp_sl[0], vp_sl[1],
                        vp_br[0] - vp_sl[0], vp_br[1] - vp_sl[1]), 1)

        # Platforms
        for i, (l, t, rr, b) in enumerate(self.obstacles):
            color = C_OBS_SEL if i == self.selected else C_OBS
            r(l, t, rr - l, b - t, color, 1)

        # Ghost while drawing
        if self._drawing and self._draw_start:
            mx, my = pygame.mouse.get_pos()
            wx, wy = self.s2w(mx, my)
            ex = self._clamp_wx(self._snap(wx))
            ey = self._clamp_wy(self._snap(wy))
            x0, y0 = self._draw_start
            gl, gr = sorted([x0, ex])
            gt, gb = sorted([y0, ey])
            sl = self.w2s(gl, gt)
            sr = self.w2s(gr, gb)
            gw, gh = max(1, sr[0] - sl[0]), max(1, sr[1] - sl[1])
            ghost = pygame.Surface((gw, gh), pygame.SRCALPHA)
            ghost.fill(C_OBS_GHOST)
            self.screen.blit(ghost, (sl[0], sl[1]))
            pygame.draw.rect(self.screen, (255, 255, 100),
                pygame.Rect(sl[0], sl[1], gw, gh), 1)
            # Size label
            lbl = self.font_sm.render(f"{gr-gl}×{gb-gt}", True, (255, 255, 150))
            self.screen.blit(lbl, (sl[0] + 2, sl[1] + 2))

    def _draw_grid(self):
        g = GRID * self.zoom
        if g < 3:
            return
        sx0, sy0 = self.w2s(0, 0)
        sx1, sy1 = self.w2s(WORLD_W, WORLD_H)
        wx = 0
        while wx <= WORLD_W:
            sx = int(self.pan_x + wx * self.zoom)
            if VIEW_X <= sx <= VIEW_X + VIEW_W:
                pygame.draw.line(self.screen, C_GRID,
                    (sx, max(0, int(sy0))), (sx, min(VIEW_H, int(sy1))))
            wx += GRID
        wy = 0
        while wy <= WORLD_H:
            sy = int(self.pan_y + wy * self.zoom)
            if 0 <= sy <= VIEW_H:
                pygame.draw.line(self.screen, C_GRID,
                    (max(VIEW_X, int(sx0)), sy), (min(VIEW_X + VIEW_W, int(sx1)), sy))
            wy += GRID

    def _draw_sidebar(self):
        pygame.draw.rect(self.screen, C_SIDEBAR,
                         pygame.Rect(0, 0, SIDEBAR_W, WINDOW_H))
        pygame.draw.line(self.screen, C_SIDEBAR_SEP,
                         (SIDEBAR_W - 1, 0), (SIDEBAR_W - 1, WINDOW_H))

        y = [10]

        def line(text, color=C_TEXT, font=None):
            f = font or self.font
            s = f.render(text, True, color)
            self.screen.blit(s, (8, y[0]))
            y[0] += s.get_height() + 3

        def gap(n=6):
            y[0] += n

        line(f"LEVEL: {self.level_name}", C_TITLE, self.font_lg)
        gap()
        line(f"Platforms: {len(self.obstacles)}", C_TEXT_DIM)
        line(f"Snap {GRID}px: {'ON' if self.snap else 'OFF'}  [S]", C_TEXT_DIM)
        gap(10)

        line("CONTROLS", C_ACCENT, self.font_lg)
        gap(2)
        for ctrl, desc in [
            ("L-drag",   "draw platform"),
            ("R-click",  "delete"),
            ("Click",    "select"),
            ("Del",      "delete selected"),
            ("M-drag",   "pan"),
            ("Scroll",   "zoom"),
            ("S",        "toggle snap"),
            ("E",        "export"),
            ("L",        "load level.json"),
            ("Q",        "quit"),
        ]:
            row = f"  {ctrl:<10}{desc}"
            line(row, C_TEXT_DIM, self.font_sm)

        gap(10)
        line("PLATFORMS", C_ACCENT, self.font_lg)
        gap(2)

        # Scrollable obstacle list
        avail_h = WINDOW_H - y[0] - 50
        row_h   = 14
        max_rows = avail_h // row_h
        total    = len(self.obstacles)
        start    = max(0, total - max_rows)

        if start > 0:
            line(f"  … {start} more above …", C_TEXT_DIM, self.font_sm)

        for i in range(start, total):
            l, t, rr, b = self.obstacles[i]
            w, h = rr - l, b - t
            txt = f"  {i:2d}  ({l:4d},{t:4d}) {w:3d}×{h:2d}"
            color = C_OBS_SEL if i == self.selected else C_TEXT_DIM
            s = self.font_sm.render(txt, True, color)
            self.screen.blit(s, (0, y[0]))
            y[0] += row_h
            if y[0] > WINDOW_H - 50:
                break

        # Status bar
        status_color = C_OK if self.status_ok else C_WARN
        s = self.font_sm.render(self.status, True, status_color)
        self.screen.blit(s, (4, WINDOW_H - 34))

        # Export button hint
        hint = self.font_sm.render("[E] Export JSON + VHDL pkg", True, C_OK)
        self.screen.blit(hint, (4, WINDOW_H - 18))

    def _draw_cursor_coords(self):
        mx, my = pygame.mouse.get_pos()
        if mx < VIEW_X:
            return
        wx, wy = self.s2w(mx, my)
        txt = f"world ({int(wx)}, {int(wy)})   zoom {self.zoom:.2f}×"
        s = self.font_sm.render(txt, True, (100, 100, 120))
        self.screen.blit(s, (VIEW_X + 4, WINDOW_H - 16))

    # ═══════════════════════════════════════════════════════════ import/export

    def export(self, stem: str = None):
        stem = stem or self.level_name
        json_path = Path(f"{stem}.json")
        vhdl_path = Path(f"{stem}_pkg.vhd")

        # JSON
        data = {
            "level": stem,
            "world": {"w": WORLD_W, "h": WORLD_H},
            "obstacles": [
                {"l": l, "t": t, "r": r, "b": b}
                for l, t, r, b in self.obstacles
            ],
        }
        json_path.write_text(json.dumps(data, indent=2))

        # VHDL package
        self._write_vhdl_pkg(vhdl_path, stem)

        self._set_status(
            f"Exported {len(self.obstacles)} obstacles → {json_path}, {vhdl_path}"
        )
        print(f"[export] {json_path}  {vhdl_path}")

    def _write_vhdl_pkg(self, path: Path, pkg_name: str):
        n   = len(self.obstacles)
        pkg = pkg_name.replace("-", "_").replace(" ", "_")

        def arr(field_idx):
            if n == 0:
                return "(others => (others => '0'))"
            vals = ",\n        ".join(
                f"CONV_STD_LOGIC_VECTOR({self.obstacles[i][field_idx]}, 11)"
                for i in range(n)
            )
            return f"(\n        {vals}\n    )"

        content = f"""\
-- =======================================================================
-- Level package: {pkg}
-- Auto-generated by level_builder.py — do not edit by hand.
--
-- Usage in physics_engine / renderer:
--   library work;
--   use work.{pkg}.all;
--
-- Then iterate:
--   for i in 0 to OBS_COUNT-1 loop
--       if c_right >= OBS_L(i) and ... then  <collision logic>  end if;
--   end loop;
-- =======================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.STD_LOGIC_ARITH.all;
use IEEE.STD_LOGIC_UNSIGNED.all;

package {pkg} is

    constant OBS_COUNT : integer := {n};

    -- Obstacle coordinate arrays (11-bit world-space, left/top/right/bottom)
    type obs_arr_t is array(0 to OBS_COUNT-1) of std_logic_vector(10 downto 0);

    constant OBS_L : obs_arr_t := {arr(0)};
    constant OBS_T : obs_arr_t := {arr(1)};
    constant OBS_R : obs_arr_t := {arr(2)};
    constant OBS_B : obs_arr_t := {arr(3)};

end package {pkg};
"""
        path.write_text(content)

    def load(self, stem: str = None):
        stem = stem or self.level_name
        path = Path(f"{stem}.json")
        if not path.exists():
            # Try bare "level.json" as fallback
            path = Path("level.json")
        if not path.exists():
            self._set_status(f"File not found: {stem}.json", ok=False)
            return
        try:
            data  = json.loads(path.read_text())
            self.obstacles = [
                [o["l"], o["t"], o["r"], o["b"]]
                for o in data.get("obstacles", [])
            ]
            self.selected = None
            self._set_status(
                f"Loaded {len(self.obstacles)} obstacles from {path}"
            )
            if "level" in data:
                self.level_name = data["level"]
                pygame.display.set_caption(
                    f"Level Builder — {self.level_name}"
                )
        except Exception as e:
            self._set_status(f"Load error: {e}", ok=False)


# ═══════════════════════════════════════════════════════════════════════ main

def main():
    name = sys.argv[1] if len(sys.argv) > 1 else "level"
    builder = LevelBuilder(level_name=name)

    # Pre-populate with the current built-in level so you can tweak it
    builder.obstacles = [
        # bottom zone
        [100, 1380, 280, 1396],
        [450, 1320, 530, 1336],
        [750, 1390, 950, 1406],
        [1150,1300,1380,1316],
        # mid-lower
        [60,  1100, 250, 1116],
        [400, 1050, 550, 1066],
        [720, 1000, 920, 1016],
        [1100,1120,1350,1136],
        # mid-upper
        [150,  780, 380,  796],
        [550,  700, 650,  716],
        [850,  650,1050,  666],
        [1200, 760,1450,  776],
        # upper
        [200,  450, 420,  466],
        [620,  380, 820,  396],
        [1000, 320,1200,  336],
        [1320, 420,1460,  436],
    ]

    # Auto-load JSON if it exists (overrides pre-populated data)
    if Path(f"{name}.json").exists():
        builder.load(name)

    builder.run()


if __name__ == "__main__":
    main()
