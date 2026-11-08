#!/usr/bin/env python3
"""Draws the README mock-ups of EzWoW - Flight Map (docs/images/ui_*.png, settings_*.png).

The flight map window (title buttons, one-line destination labels, route highlight,
tooltip, destination list), the flight timer bar with its mini games button, the
mini games window and the settings window are rebuilt from the sizes, coordinates,
colours and strings in the addon code (UI/FlightMapWindow.lua, UI/FlightBar.lua,
UI/OptionsWindow.lua, Core/Init.lua, Core/Locales.lua, Libs/EzWoWMiniGames), in
game pixels x scale. The continent art is a simplified drawing; fares and times
are examples.

usage: python scripts/make_readme_images.py .
Renders with a local headless Chrome (set CHROME=<path> if it is not found).
Pillow is used to read the .tga icons; without it simple shapes are drawn.
"""
import base64
import html
import io
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

PAGE_W = 1600
CALL = "#85b9ff"

# ---------------------------------------------------------------------------
# Values read from the Lua code
# ---------------------------------------------------------------------------


def read(root, rel):
    return (root / rel).read_text(encoding="utf-8")


def parse_style(src):
    block = re.search(r"local STYLE = \{(.*?)\n\}", src, re.S).group(1)
    return {k: [float(v) for v in body.split(",")] for k, body in re.findall(r"(\w+)\s*=\s*\{\s*([\d.,\s]+)\}", block)}


def parse_defaults(src):
    block = re.search(r"ns\.defaults = \{(.*?)\n\}", src, re.S).group(1)
    out = {}
    for k, v in re.findall(r"^\s*(\w+)\s*=\s*([^,\n]+),", block, re.M):
        v = v.strip()
        out[k] = True if v == "true" else False if v == "false" else None if v == "nil" else v.strip('"') if v.startswith('"') else float(v)
    return out


def parse_consts(src):
    out = {}
    for names, vals in re.findall(r"^ns\.([\w, ns.]+?) = ([\d, ]+)$", src, re.M):
        keys = [n.strip().replace("ns.", "") for n in names.split(",")]
        for k, v in zip(keys, vals.split(",")):
            out[k] = int(v)
    return out


def _strings(block):
    return {k: v.replace('\\"', '"').replace("\\n", "\n")
            for k, v in re.findall(r'^\s*(\w+)\s*=\s*"((?:[^"\\]|\\.)*)"', block, re.M)}


def parse_locales(src):
    en = src[src.index("    enUS = {"):src.index("    koKR = {")]
    ko = src[src.index("    koKR = {"):src.index("    deDE = {")]
    out = {"en": _strings(en), "ko": _strings(ko)}
    for lang, blk in (("en", en), ("ko", ko)):
        wm = re.search(r"WM = \{(.*?)\n        \}", blk, re.S).group(1)
        out[lang]["WM"] = dict(re.findall(r'(\w+)\s*=\s*"((?:[^"\\]|\\.)*)"', wm))
    return out


def parse_minigame_strings(src):
    def block(key):
        s = src.index(f"    {key} = {{")
        return src[s:src.index("\n    },", s)]
    return {"ko": dict(re.findall(r'(\w+)\s*=\s*"((?:[^"\\]|\\.)*)"', block("koKR"))),
            "en": dict(re.findall(r'(\w+)\s*=\s*"((?:[^"\\]|\\.)*)"', block("enUS")))}


def parse_settings(src):
    block = re.search(r"local SETTINGS = \{(.*?)\n\}", src, re.S).group(1)
    rows = []
    for line in block.splitlines():
        kind = re.search(r'kind = "(\w+)"', line)
        if not kind:
            continue
        r = {"kind": kind.group(1)}
        for k in ("key", "label", "sub"):
            m = re.search(rf'{k} = "(\w+)"', line)
            r[k] = m.group(1) if m else None
        for k in ("min", "max"):
            m = re.search(rf"{k} = (\d+)", line)
            r[k] = int(m.group(1)) if m else None
        m = re.search(r'fmt = "([^"]+)"', line)
        r["fmt"] = m.group(1) if m else None
        rows.append(r)
    return rows


def parse_version(src):
    m = re.search(r"^## Version:\s*(\S+)", src, re.M)
    return m.group(1) if m else ""


def css(c, alpha=None):
    r, g, b = (round(min(1, v) * 255) for v in c[:3])
    a = alpha if alpha is not None else (c[3] if len(c) > 3 else 1)
    return f"rgba({r},{g},{b},{a:.2f})"


def esc(s):
    return html.escape(s, quote=False)


def tga_uri(path, fallback_svg):
    try:
        from PIL import Image
        buf = io.BytesIO()
        Image.open(path).convert("RGBA").save(buf, "PNG")
        return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()
    except Exception:
        return "data:image/svg+xml;base64," + base64.b64encode(fallback_svg.encode()).decode()


def circle_svg(color):
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><circle cx="32" cy="32" r="28" fill="{color}" stroke="#222" stroke-width="4"/></svg>'


# ---------------------------------------------------------------------------
# Scene: an Alliance flight master in Stormwind, hovering Booty Bay
# ---------------------------------------------------------------------------
# (key, name ko, zone ko, name en, zone en, x%, y%, type, fare copper, seconds, recorded, hops)
NODES = [
    ("sw", "스톰윈드", "엘윈 숲", "Stormwind", "Elwynn", 36.5, 64.5, "CURRENT", None, None, False, 0),
    ("aerie", "맹금의 봉우리", "동부 내륙지", "Aerie Peak", "The Hinterlands", 62.0, 21.0, "REACHABLE", 14000, 375, False, 3),
    ("south", "남녘해안", "힐스브래드 구릉지", "Southshore", "Hillsbrad", 44.0, 27.5, "REACHABLE", 10000, 312, False, 3),
    ("refuge", "피난의 언덕", "아라시 고원", "Refuge Pointe", "Arathi", 58.5, 32.0, "REACHABLE", 10000, 287, True, 3),
    ("menethil", "메네실 항구", "저습지", "Menethil Harbor", "Wetlands", 41.0, 40.5, "REACHABLE", 5000, 256, False, 2),
    ("thelsamar", "텔사마", "모단 호수", "Thelsamar", "Loch Modan", 61.5, 47.0, "REACHABLE", 5000, 228, False, 2),
    ("ironforge", "아이언포지", "던 모로", "Ironforge", "Dun Morogh", 45.0, 50.5, "REACHABLE", 5000, 183, False, 1),
    ("thorium", "토륨 거점", "이글거리는 협곡", "Thorium Point", "Searing Gorge", 57.0, 58.5, "DISTANT", None, None, False, 0),
    ("morgan", "모건의 망루", "불타는 평원", "Morgan's Vigil", "Burning Steppes", 60.0, 66.0, "REACHABLE", 12000, 130, False, 1),
    ("lake", "호숫골", "붉은마루 산맥", "Lakeshire", "Redridge", 49.0, 72.5, "REACHABLE", 5000, 78, True, 1),
    ("sentinel", "감시의 언덕", "서부 몰락지대", "Sentinel Hill", "Westfall", 27.0, 74.5, "REACHABLE", 5000, 92, True, 1),
    ("dark", "어둠골", "그늘숲", "Darkshire", "Duskwood", 43.5, 78.0, "REACHABLE", 5000, 111, True, 1),
    ("nether", "네더가드 요새", "저주받은 땅", "Nethergarde Keep", "Blasted Lands", 58.5, 83.0, "REACHABLE", 12000, 162, False, 2),
    ("booty", "무법항", "가시덤불 골짜기", "Booty Bay", "Stranglethorn", 33.0, 93.0, "REACHABLE", 12000, 228, False, 2),
    ("chill", "서리바람 야영지", "서부 역병지대", "Chillwind Camp", "Western Plaguelands", 54.0, 11.0, "DISTANT", None, None, False, 0),
]
HOVER = "booty"
ROUTE = ["sw", "dark", "booty"]
FAVORITE = "booty"
RECENT = "lake"
PLAYER_COPPER = 12500  # 1g 25s: Aerie Peak (1g 40s) is too expensive -> red

T = {
    "ko": {
        "lead": "비행 조련사와 대화하면 목적지 이름 · 시간 · 요금을 한눈에 보여 주는 전용 비행 지도, 남은 시간 막대와 비행 중 미니게임",
        "notes": [
            ("제목 줄 버튼", "톱니바퀴: 설정창, 목록 아이콘: 오른쪽 목적지 목록 켜기/끄기, X: 닫기. 제목 줄을 끌어 옮기고 Ctrl+휠로 크기 조절."),
            ("목적지 이름표", "기본은 한 줄 이름표(이름 · 시간)이고, 요금과 지역은 마우스를 올리면 나옵니다. 설정에서 끄면 이름 · 지역 · 요금 · 시간의 세 줄 이름표. “약”이 붙은 시간은 거리로 계산한 예상치, 없는 것은 실제로 날아서 기록한 시간."),
            ("검색", "이름 일부를 입력하면 걸러지고, Enter를 누르면 첫 번째 비행 가능 목적지로 바로 출발합니다."),
            ("정렬 · 즐겨찾기", "이름/시간/요금 정렬. 이 조련사에서 최근에 간 곳과 별(★)을 누른 곳이 맨 위에 고정됩니다. 돈이 모자라면 요금이 빨간색."),
            ("경로 강조 · 툴팁", "마우스를 올리면 경로선과 이동 방향 빛, 요금 · 시간 · 경유지 수가 나옵니다. 클릭하면 비행합니다."),
            ("남은 시간 막대", "비행 중 남은 시간, 경유 구간, 도착 예정 시각. 도착하면 소리와 작업 표시줄 깜빡임. 퀘스트 비행처럼 지도 없이 시작한 비행도 표시하고 시간을 기록합니다."),
            ("미니게임", "지뢰찾기 · 짝 맞추기 · 퍼즐 맞추기 · 솔리테어. 비행을 시작하면 열리고 착륙하면 닫힙니다. 비행 중에 창을 닫으면 다음부터 자동으로 열지 않습니다."),
        ],
        "foot": "애드온 코드의 창 크기·좌표·색상·문구로 재현한 예시 화면입니다. 실제 창에는 게임의 대륙 지도가 배경으로 나옵니다. 요금과 시간은 예시입니다.",
        "sTitle": "설정창",
        "sLead": "/ezfl config · 언어, 지도 사용, 대화창 건너뛰기, 세계지도 조련사 표시, 이름표, 목록, 창 크기, 비행 중 알림",
        "sNotes": [
            ("언어", "상자를 누르고 목록에서 자동 또는 8개 언어 중 고릅니다. 화면 문구가 바로 바뀝니다."),
            ("기본", "전용 비행 지도 사용, 대화창 없이 바로 지도 열기(Shift를 누른 채 말을 걸면 대화창), 비행 전 확인 창."),
            ("세계지도", "얼라이언스(파랑) · 호드(빨강) · 중립(금색) 비행 조련사를 진영별로 켜고 끄고, 왼쪽 아래 도킹 버튼(2번째 칸)을 자동 정렬합니다."),
            ("지도 표시", "이름표, 한 줄 이름표(처음엔 켜짐), 비행 지점 부분만 확대, 미발견 · 미연결 지점, 목적지 목록, 현재 위치 파동, 검색창 바로 입력."),
            ("슬라이더", "창 크기 50~120%, 창 투명도 0~70%, 글자 크기 8~14."),
            ("비행 중", "남은 시간 막대, 도착 알림, 착륙 직전 알림(처음엔 꺼짐, 기본 15초 전 · /ezfl soon 숫자로 변경)."),
            ("하단", "창 · 버튼 위치 초기화(지도 창에서 열면 ‘기본 비행 지도로 보기’), 후원하기."),
        ],
        "sFoot": "애드온 코드의 창 크기·좌표·색상·문구로 재현한 예시 화면입니다. 체크 상태는 기본값(얼라이언스 캐릭터)입니다.",
        "reset": "창·버튼 위치 초기화",
    },
    "en": {
        "lead": "A dedicated flight map that shows each destination's name, time and fare at a glance, a flight timer bar and mini games for the ride",
        "notes": [
            ("Title buttons", "Gear: settings, list icon: toggle the destination list, X: close. Drag the title to move, Ctrl + wheel to resize."),
            ("Destination labels", "Short one-line labels (name · time) by default; fare and zone show on hover. Turn the option off for three-line labels with name, zone, fare and time. Times with “~” are estimates from the route distance, the others were recorded on real flights."),
            ("Search", "Type part of a name to filter. Enter flies to the first reachable result."),
            ("Sort · favourites", "Sort by name, time or fare. The place you last flew to from this flight master and starred (★) places stay on top. Fares you cannot afford are red."),
            ("Route highlight · tooltip", "Hover to see the path with a moving light, fare, time and number of stops. Click to fly."),
            ("Flight timer bar", "Time left, current leg and arrival time; a sound and a taskbar flash on arrival. Flights started without the map, such as quest flights, are shown and timed too."),
            ("Mini games", "Minesweeper · Memory · Sliding Puzzle · Solitaire. Opens when a flight starts and closes on landing. Close it during a flight and it stops opening by itself."),
        ],
        "foot": "Mock-up rebuilt from the window sizes, coordinates, colours and strings in the addon code. In game the continent map art is shown in the background. Fares and times are examples.",
        "sTitle": "Settings",
        "sLead": "/ezfl config · language, custom map, gossip skip, world map flight masters, labels, list, window size, in-flight alerts",
        "sNotes": [
            ("Language", "Click the box and pick Auto or one of 8 languages. Texts change at once."),
            ("General", "Use the custom flight map, skip the gossip and open the map directly (hold Shift to see it), confirm before flying."),
            ("World Map", "Alliance (blue), Horde (red) and Neutral (gold) flight masters by faction, and auto-align of the bottom-left dock button (2nd slot)."),
            ("Map", "Labels, short one-line labels (on by default), zoom to flight points, undiscovered and unconnected points, destination list, location pulse, type into the search box at once."),
            ("Sliders", "Window size 50–120%, transparency 0–70%, text size 8–14."),
            ("In flight", "Timer bar, arrival alert, alert shortly before landing (off by default, 15 seconds before; change with /ezfl soon <seconds>)."),
            ("Bottom", "Reset window and button positions (‘Show default flight map’ when opened from the map), donate."),
        ],
        "sFoot": "Mock-up rebuilt from the window size, coordinates, colours and strings in the addon code. Check boxes show the defaults (Alliance character).",
        "reset": "Reset Window Position",
    },
}

SHADOW = "text-shadow:1px 1px 0 #000,0 0 2px rgba(0,0,0,.8);"

CSS = f"""
* {{ box-sizing: border-box; margin: 0; padding: 0; }}
body {{ width: {PAGE_W}px; overflow: hidden; background: radial-gradient(ellipse at 30% 0%, #1f2a3d 0%, #121922 55%, #0b1014 100%);
  font-family: 'Noto Sans KR', 'Malgun Gothic', sans-serif; color: #edf4f7; }}
.page {{ position: relative; padding: 34px 50px 40px; }}
h1 {{ color: {CALL}; font-size: 40px; font-weight: 700; letter-spacing: .3px; display: flex; align-items: center; gap: 14px; }}
h1 .badge {{ font-size: 15px; background: {CALL}; color: #0b1a33; padding: 2px 9px; border-radius: 5px; }}
.lead {{ color: #d5dde2; font-size: 19px; margin-top: 6px; }}
.abs {{ position: absolute; }}
.t {{ position: absolute; white-space: nowrap; line-height: 1.15; }}
.call {{ position: absolute; width: 30px; height: 30px; border-radius: 50%; background: {CALL}; color: #0b1a33; font-weight: 700;
  font-size: 16px; display: flex; align-items: center; justify-content: center; border: 2px solid #0b1a33; box-shadow: 0 0 0 2px {CALL}55; z-index: 60; }}
.notes {{ position: absolute; }}
.note {{ display: flex; gap: 12px; margin-bottom: 10px; font-size: 16px; line-height: 1.5; color: #dfe6ea; }}
.note .n {{ flex: none; width: 28px; height: 28px; border-radius: 50%; background: {CALL}; color: #0b1a33; font-weight: 700;
  font-size: 15px; display: flex; align-items: center; justify-content: center; }}
.note b {{ color: #fff; }}
.foot {{ color: #7d8d98; font-size: 13.5px; line-height: 1.5; }}
.fit {{ display: inline-block; }}
.tip {{ position: absolute; background: rgba(6,10,16,.94); border: 2px solid #5d6d7a; border-radius: 4px; padding: 7px 11px;
  font-size: 14px; line-height: 1.5; white-space: nowrap; z-index: 40; }}
.coin {{ display: inline-block; width: .8em; height: .8em; border-radius: 50%; margin: 0 2px 0 1px; vertical-align: -.05em; }}
.coin.g {{ background: radial-gradient(circle at 35% 35%, #fff2a8, #e8b923 55%, #8a6411); }}
.coin.s {{ background: radial-gradient(circle at 35% 35%, #ffffff, #c4c9cf 55%, #6c7177); }}
"""

FIT_JS = """
<script>
document.querySelectorAll('[data-fit]').forEach(function (e) {
  var max = parseFloat(e.dataset.fit), min = parseFloat(e.dataset.min || 8);
  var fs = parseFloat(getComputedStyle(e).fontSize);
  while (e.scrollWidth > max && fs > min) { fs -= 0.25; e.style.fontSize = fs + 'px'; }
});
</script>
"""


def notes_height(notes, width):
    h = 0
    for a, b in notes:
        chars = len(a) + len(b) + 3
        wide = sum(1 for ch in a + b if ord(ch) > 0x2e80)
        per_line = width / (8.4 + 7.4 * wide / chars)
        h += max(1, math.ceil(chars / per_line)) * 24 + 10
    return h


def note_html(start, lst):
    return "".join(f'<div class="note"><span class="n">{start + i}</span><div><b>{esc(a)}</b> — {esc(b)}</div></div>'
                   for i, (a, b) in enumerate(lst))


def coins(copper):
    """FormatCopperAsCoinString: gold and silver amounts with coin icons."""
    g, s, c = copper // 10000, copper // 100 % 100, copper % 100
    out = []
    if g:
        out.append(f'{g}<span class="coin g"></span>')
    if s:
        out.append(f'{s}<span class="coin s"></span>')
    if c:
        out.append(f'{c}<span class="coin" style="background:#b87333"></span>')
    return "".join(out)


def fmt_time(L, sec, recorded):
    """FormatFlightDurationText: estimates are whole minutes with the APPROX prefix."""
    if not recorded:
        return L["APPROX"].replace("%s", L["MIN"].replace("%d", str(max(1, math.floor(sec / 60 + 0.5)))))
    if sec < 60:
        return L["SEC"].replace("%d", str(sec))
    m, s = divmod(sec, 60)
    if s == 0:
        return L["MIN"].replace("%d", str(m))
    return L["MIN_SEC"].replace("%d", str(m), 1).replace("%d", str(s), 1)


class Box:
    """Places children in game px inside a frame drawn at scale k."""

    def __init__(self, k):
        self.k = k
        self.parts = []

    def p(self, v):
        return f"{v * self.k:.2f}px"

    def box(self, x, y, w, h, style="", inner=""):
        self.parts.append(f'<div class="abs" style="left:{self.p(x)};top:{self.p(y)};width:{self.p(w)};height:{self.p(h)};{style}">{inner}</div>')

    def text(self, x, y, s, size, color, extra="", anchor=""):
        self.parts.append(f'<div class="t" style="left:{self.p(x)};top:{self.p(y)};font-size:{self.p(size)};color:{color};{anchor}{SHADOW}{extra}">{s}</div>')

    def img(self, x, y, w, h, src, extra=""):
        self.parts.append(f'<img class="abs" src="{src}" style="left:{self.p(x)};top:{self.p(y)};width:{self.p(w)};height:{self.p(h)};{extra}">')

    def html(self):
        return "".join(self.parts)


def btn(b, th, x, y, w, h, label, accent=False, size=11):
    acc = th["accent"]
    bg = css([acc[0] * .22, acc[1] * .22, acc[2] * .22], .96) if accent else css(th["bgSecondary"], .96)
    bd = css(acc) if accent else css(th["border"])
    col = css(acc) if accent else css(th["textBody"])
    b.box(x, y, w, h, f"background:{bg};border:1px solid {bd};display:flex;align-items:center;justify-content:center",
          f'<span class="fit" data-fit="{(w - 8) * b.k:.1f}" style="font-size:{b.p(size)};color:{col};white-space:nowrap;{SHADOW}">{esc(label)}</span>')


# ---------------------------------------------------------------------------
# Flight map window (UI/FlightMapWindow.lua)
# ---------------------------------------------------------------------------
TERRAIN = ('<path d="M38 2 Q50 0 60 4 Q70 3 74 10 Q70 18 68 26 Q72 34 70 42 Q74 50 68 58 Q72 66 66 72 Q68 80 64 88 '
           'Q56 92 50 90 Q44 96 36 99 Q28 98 30 90 Q22 84 20 76 Q16 68 26 62 Q30 56 34 50 Q30 44 34 38 Q30 30 36 24 '
           'Q32 14 38 2 Z" fill="url(#land)" stroke="#c9a96a" stroke-opacity=".55" stroke-width=".35"/>'
           '<path d="M40 30 Q46 33 44 40" fill="none" stroke="#3f6f8c" stroke-width="1.6" opacity=".8"/>'
           '<g fill="#5d6f37" opacity=".55"><ellipse cx="38" cy="70" rx="7" ry="5"/><ellipse cx="36" cy="86" rx="6" ry="6"/>'
           '<ellipse cx="60" cy="20" rx="7" ry="5"/></g>'
           '<g fill="#7a5638" opacity=".5"><ellipse cx="55" cy="60" rx="6" ry="4"/><ellipse cx="60" cy="84" rx="6" ry="4"/></g>')


def flight_map(ctx, lang, x0, y0, k):
    th, L, c = ctx["style"], ctx["L"][lang], ctx["consts"]
    PAD, TITLE_H, FOOT_H, LIST_W, LIST_GAP = c["PAD"], c["TITLE_H"], c["FOOT_H"], c["LIST_W"], c["LIST_GAP"]
    VW, VH = 640, 540
    W = VW + 2 * PAD + LIST_W + LIST_GAP
    H = VH + TITLE_H + FOOT_H
    b = Box(k)
    acc, body, mut = css(th["accent"]), css(th["textBody"]), css(th["textMuted"])
    nodes = {n[0]: n for n in NODES}
    lname = lambda n: n[1] if lang == "ko" else n[3]
    lzone = lambda n: n[2] if lang == "ko" else n[4]
    affordable = lambda n: n[8] is None or n[8] <= PLAYER_COPPER

    # title bar: gear, list, centred title, close
    for i, icon in enumerate((ctx["gear"], ctx["list"])):
        b.box(8 + i * 28, 5, 22, 22, f"background:{css(th['bgSecondary'], .96)};border:1px solid {css(th['border'])}")
        b.img(8 + i * 28 + 3, 8, 16, 16, icon)
    b.text(W / 2, 9, esc(L["TITLE"]), 12.5, acc, anchor="transform:translateX(-50%);")
    btn(b, th, W - 8 - 22, 5, 22, 22, "X")

    # map viewport
    mx = PAD + ((W - 2 * PAD - LIST_W - LIST_GAP) - VW) / 2
    my = TITLE_H
    b.parts.append(f'<svg class="abs" style="left:{b.p(mx)};top:{b.p(my)}" width="{VW * k:.1f}" height="{VH * k:.1f}" viewBox="0 0 100 100" preserveAspectRatio="none">'
                   '<defs><radialGradient id="land" cx="45%" cy="55%" r="70%"><stop offset="0" stop-color="#7c6a45"/><stop offset="1" stop-color="#4d4029"/></radialGradient>'
                   '<pattern id="sea" width="4" height="4" patternUnits="userSpaceOnUse" patternTransform="rotate(35)"><rect width="4" height="4" fill="#15273a"/>'
                   '<rect width="1" height="4" fill="#1a3049"/></pattern></defs>'
                   f'<rect width="100" height="100" fill="url(#sea)"/>{TERRAIN}</svg>')

    def V(n):
        return mx + n[5] / 100 * VW, my + n[6] / 100 * VH

    # route of the hovered destination: glow 11 (accent .34) and core 3
    pts = [V(nodes[key]) for key in ROUTE]
    segs = "".join(f'<line x1="{a[0] * k:.1f}" y1="{a[1] * k:.1f}" x2="{c2[0] * k:.1f}" y2="{c2[1] * k:.1f}" stroke="{css(th["accent"], .34)}" stroke-width="{11 * k:.1f}" stroke-linecap="round"/>'
                   f'<line x1="{a[0] * k:.1f}" y1="{a[1] * k:.1f}" x2="{c2[0] * k:.1f}" y2="{c2[1] * k:.1f}" stroke="rgb(191,224,255)" stroke-width="{3 * k:.1f}"/>'
                   for a, c2 in zip(pts, pts[1:]))
    b.parts.append(f'<svg class="abs" style="left:0;top:0;overflow:visible" width="1" height="1">{segs}</svg>')
    # moving lights on the path
    for f, s in ((0.62, 16), (0.52, 11), (0.42, 11)):
        a, c2 = pts[1], pts[2]
        sx, sy = a[0] + (c2[0] - a[0]) * f, a[1] + (c2[1] - a[1]) * f
        b.img(sx - s / 2, sy - s / 2, s, s, ctx["glow"], "mix-blend-mode:screen")

    # pins (22, current 26) with the location pulse and the hover ring
    anchors = {}
    for n in NODES:
        x, y = V(n)
        size = c["PIN_SIZE_CURRENT"] if n[7] == "CURRENT" else c["PIN_SIZE"]
        if n[7] == "CURRENT":
            b.box(x - 21, y - 21, 42, 42, "border-radius:50%;border:2px solid rgba(107,255,161,.55);box-shadow:0 0 8px rgba(107,255,161,.45)")
        if n[0] == HOVER:
            b.img(x - 26, y - 26, 52, 52, ctx["glow"], "mix-blend-mode:screen")
            b.img(x - 21.5, y - 21.5, 43, 43, ctx["ring"], "filter:sepia(1) hue-rotate(180deg) saturate(3)")
        alpha = 0.8 if n[7] == "DISTANT" else 1
        b.img(x - size / 2, y - size / 2, size, size, ctx["pins"][n[7]], f"opacity:{alpha}")
        anchors[n[0]] = (x, y)

    # one-line labels centred under each pin (labelCompact, default on)
    size = int(ctx["defaults"]["labelSize"])
    for n in NODES:
        x, y = V(n)
        r = (c["PIN_SIZE_CURRENT"] if n[7] == "CURRENT" else c["PIN_SIZE"]) / 2
        sel = n[0] == HOVER
        name = ("★ " if n[0] == FAVORITE else "") + esc(lname(n))
        extra = ""
        if n[7] == "CURRENT":
            extra = f'&nbsp;&nbsp;<span style="color:#8cffa6">{esc(L["CURRENT"])}</span>'
        elif n[7] == "REACHABLE":
            extra = f'&nbsp;&nbsp;<span style="color:#d9dbe0">{esc(fmt_time(L, n[9], n[10]))}</span>'
        text = name + extra
        # width of the text (rough, refined in the browser): CJK ~1 em, latin ~.55 em
        plain = re.sub(r"<[^>]+>|&nbsp;", " ", text)
        tw = sum(size * (1.0 if ord(ch) > 0x2e80 else .56) for ch in plain)
        bw = min(tw + 12, VW * .42)
        bx = max(mx, min(mx + VW - bw, x - bw / 2))
        by = y + r + 2
        if n[7] == "CURRENT":
            bar, ncol = "rgba(89,219,133,.95)", "rgb(140,255,166)"
        elif n[7] == "DISTANT":
            bar, ncol = css(th["disabled"], .6), mut
        else:
            bar, ncol = css(th["accent"], .95), "rgb(166,209,255)"
        if sel:
            bg, bd, bar, ncol, aw = css(th["bgSecondary"], .98), css(th["accent"]), css(th["accent"]), "rgb(255,245,204)", 4
        else:
            bg = css(th["bgPrimary"], .72 if n[7] == "DISTANT" else .88)
            bd = css(th["border"], .35 if n[7] == "DISTANT" else .65)
            aw = 2
        z = 30 if sel else 20
        b.parts.append(f'<div class="abs" style="left:{b.p(bx)};top:{b.p(by)};height:{b.p(size + 8)};background:{bg};border:1px solid {bd};'
                       f'display:flex;align-items:center;padding:0 {b.p(5)} 0 {b.p(7)};z-index:{z};white-space:nowrap">'
                       f'<div class="abs" style="left:0;top:0;bottom:0;width:{b.p(aw)};background:{bar}"></div>'
                       f'<span style="font-size:{b.p(size * .92)};color:{ncol};{SHADOW}">{text}</span></div>')
        if sel:
            anchors["label"] = (bx + bw, by + (size + 8) / 2)
        if n[0] == "menethil":
            anchors["labelEx"] = (bx, by + (size + 8) / 2)

    # tooltip of the hovered destination (pinOnenter)
    n = nodes[HOVER]
    hx, hy = anchors["label"]
    tip = [f'<div style="color:{acc};font-size:15px">{esc(lname(n))}, {esc(lzone(n))}</div>',
           f'<div style="color:#fff">{coins(n[8])}</div>']
    if n[10]:
        tip.append(f'<div style="color:#fff">{esc(L["TT_TIME"].replace("%s", fmt_time(L, n[9], True)))}</div>')
    else:
        tip.append(f'<div style="color:rgb(219,214,191)">{esc(L["TT_EST"].replace("%s", fmt_time(L, n[9], False)))}</div>')
        tip.append(f'<div style="color:#999">{esc(L["TT_EST_NOTE"])}</div>')
    tip.append(f'<div style="color:#ccc">{esc(L["STOPS"].replace("%d", str(len(ROUTE) - 2)))}</div>')
    tip.append(f'<div style="color:rgb(102,204,255)">{esc(L["CLICK"])}</div>')
    b.parts.append(f'<div class="tip" style="left:{b.p(hx + 12)};top:{b.p(hy + 6)};transform:translateY(-100%)">{"".join(tip)}</div>')

    # destination list (buildList / fillRow)
    lx, ly, lh = W - PAD - LIST_W, TITLE_H, VH
    b.box(lx, ly, LIST_W, lh, f"background:{css(th['bgSecondary'], .94)};border:1px solid {css(th['border'], .85)}")
    b.box(lx + 8, ly + 6, LIST_W - 16, 20, f"background:rgba(12,17,22,.96);border:1px solid {css(th['border'])};display:flex;align-items:center;padding-left:{b.p(6)}",
          f'<span style="font-size:{b.p(10)};color:#808080">{esc(L["LIST_SEARCH"])}</span>')
    tab_w = (LIST_W - 16) // 3
    for i, key in enumerate(("NAME", "TIME", "FARE")):
        active = key.lower() == ctx["defaults"]["listSort"]
        a3 = th["accent"]
        bg = css([a3[0] * .25, a3[1] * .25, a3[2] * .25], .96) if active else css(th["bgPrimary"], .92)
        b.box(lx + 8 + i * tab_w, ly + 30, tab_w - 2, 20, f"background:{bg};border:1px solid {acc if active else css(th['border'])};display:flex;align-items:center;justify-content:center",
              f'<span style="font-size:{b.p(10)};color:{acc if active else mut}">{esc(L["SORT_" + key])}</span>')

    def group(n):
        if n[0] == RECENT and n[7] == "REACHABLE":
            return 0
        if n[0] == FAVORITE:
            return 1
        return 2 if n[7] == "REACHABLE" else 3
    items = sorted((n for n in NODES if n[7] != "CURRENT"), key=lambda n: (group(n), lname(n)))
    ROW_H, HEAD = 34, 54
    visible = (lh - HEAD - 6) // ROW_H
    for i, n in enumerate(items[:visible]):
        ry = ly + HEAD + i * ROW_H
        rw = LIST_W - 12
        bg = "rgba(255,255,255,.03)" if (i + 1) % 2 == 0 else "transparent"
        if n[0] == HOVER:
            bg = css(th["accent"], .20)
            anchors["row"] = (lx + LIST_W, ry + ROW_H / 2)
        b.box(lx + 4, ry, rw, ROW_H, f"background:{bg}")
        b.img(lx + 8, ry + 9, 16, 16, ctx["starOn"] if n[0] == FAVORITE else ctx["starOff"], f"opacity:{1 if n[0] == FAVORITE else .45}")
        region = esc(lzone(n))
        if n[0] == RECENT:
            region = f'<span style="color:#85b9ff">{esc(L["RECENT"])}</span> · ' + region
        if n[7] == "REACHABLE":
            ncol = acc
            tcol = "rgb(255,240,184)" if n[10] else mut
            time_s = esc(fmt_time(L, n[9], n[10]))
            fare = coins(n[8])
            fcol = "rgb(255,77,77)" if not affordable(n) else body
        else:
            ncol, tcol, time_s = css(th["disabled"]), mut, ""
            fare, fcol = esc(L["UNDISCOVERED"]), css(th["disabled"])
        if n[7] == "REACHABLE" and not affordable(n):
            anchors["poor"] = (lx + LIST_W, ry + ROW_H / 2)
        b.text(lx + 4 + 24, ry + 3, esc(lname(n)), 12, ncol)
        b.text(lx + 4 + rw - 6, ry + 4, time_s, 10.5, tcol, anchor="transform:translateX(-100%);")
        # region width leaves room for the fare (fillRow)
        fare_plain = re.sub(r"<[^>]+>", "", fare)
        fare_w = sum(10.5 * (1.0 if ord(ch) > 0x2e80 else .55) for ch in fare_plain) + (12 if "coin" in fare else 0)
        b.text(lx + 4 + 24, ry + 19, region, 10, "#808080",
               extra=f"width:{b.p(rw - 24 - 6 - 6 - fare_w)};overflow:hidden;text-overflow:ellipsis;")
        b.text(lx + 4 + rw - 6, ry + 18, fare, 10.5, fcol, anchor="transform:translateX(-100%);")
    if len(items) > visible:
        track = lh - HEAD - 8
        b.box(lx + LIST_W - 5, ly + HEAD, 3, max(16, track * visible / len(items)), f"background:{css(th['accent'], .65)}")

    # hint at the bottom
    b.text(W / 2, H - 7 - 12, esc(L["HINT"]).replace(" ", "&nbsp;"), 10, mut, anchor="transform:translateX(-50%);")

    frame = (f'<div class="abs" style="left:{x0}px;top:{y0}px;width:{W * k:.1f}px;height:{H * k:.1f}px;background:{css(th["bgPrimary"], .96)};'
             f'border:1px solid {css(th["border"])}">{b.html()}</div>')
    ab = {key: (x0 + v[0] * k, y0 + v[1] * k) for key, v in anchors.items()}
    ab["title"] = (x0 + 64 * k, y0 + 16 * k)
    ab["search"] = (x0 + (lx + LIST_W) * k, y0 + (ly + 16) * k)
    ab["tabs"] = (x0 + lx * k, y0 + (ly + 40) * k)
    return frame, ab, (W * k, H * k)


def timer_bar(ctx, lang, x0, y0, k):
    """330 x 32 bar: icon 22, status bar inset 32/7, mini games button 24 high on the right."""
    th, L, MG = ctx["style"], ctx["L"][lang], ctx["MG"][lang]
    b = Box(k)
    b.img(6, 5, 22, 22, ctx["pins"]["REACHABLE"])
    fill = 0.38
    sw = 330 - 32 - 7
    b.box(32, 7, sw, 18, f"background:{css(th['bgSecondary'], .75)}")
    b.box(32, 7, sw * fill, 18, f"background:linear-gradient({css(th['accent'])},{css([v * .7 for v in th['accent'][:3]])})")
    dest = "네더가드 요새" if lang == "ko" else "Nethergarde Keep"
    stops = L["BAR_STOPS"].replace("%d", "1", 1).replace("%d", "2", 1)
    b.text(37, 10, f'{esc(dest)}&nbsp;&nbsp;<span style="color:#aaa">{esc(stops)}</span>', 10.5, css(th["textBody"]))
    eta = L["BAR_ETA"].replace("%s", "21:41")
    b.text(330 - 7 - 5, 10, f'1:42&nbsp;&nbsp;<span style="color:#bbb">{esc(eta)}</span>', 10.5, css(th["textBody"]), anchor="transform:translateX(-100%);")
    gw = len(MG["title"]) * (10.5 if lang == "ko" else 6) + 18
    b.box(334, 4, gw, 24, f"background:{css(th['bgPrimary'], .94)};border:1px solid {css(th['border'])};display:flex;align-items:center;justify-content:center",
          f'<span style="font-size:{b.p(10.5)};color:{css(th["accent"])};white-space:nowrap">{esc(MG["title"])}</span>')
    frame = (f'<div class="abs" style="left:{x0}px;top:{y0}px;width:{330 * k:.1f}px;height:{32 * k:.1f}px;background:{css(th["bgPrimary"], .94)};'
             f'border:1px solid {css(th["border"])};overflow:visible">{b.html()}</div>')
    return frame, (x0 + (334 + gw) * k, y0 + 16 * k)


# ---------------------------------------------------------------------------
# Mini games window (Libs/EzWoWMiniGames/MiniGames.lua, Games/Minesweeper.lua)
# ---------------------------------------------------------------------------
MINES = {4, 6, 15, 17, 25, 33, 43, 52, 62, 70}
NUMBER_COLORS = [(0.45, 0.70, 1.00), (0.40, 0.85, 0.45), (1.00, 0.45, 0.40), (0.70, 0.50, 1.00),
                 (1.00, 0.70, 0.30), (0.40, 0.85, 0.85), (0.90, 0.90, 0.90), (0.60, 0.60, 0.60)]


def mines_board():
    cols = rows = 9

    def nb(i):
        r, c = divmod(i, cols)
        return [(r + dr) * cols + c + dc for dr in (-1, 0, 1) for dc in (-1, 0, 1)
                if (dr or dc) and 0 <= r + dr < rows and 0 <= c + dc < cols]
    counts = [sum(1 for j in nb(i) if j in MINES) for i in range(81)]
    shown, stack = set(), [72]
    while stack:
        i = stack.pop()
        if i in shown or i in MINES:
            continue
        shown.add(i)
        if counts[i] == 0:
            stack.extend(nb(i))
    return counts, shown, {15, 33}


def minigames_window(ctx, lang, x0, y0, k):
    th, MG = ctx["style"], ctx["MG"][lang]
    W, H = 460, 600
    b = Box(k)
    acc, mut, body = css(th["accent"]), css(th["textMuted"]), css(th["textBody"])

    def mbtn(x, y, w, h, label, active=False):
        bg = "rgba(26,43,66,.96)" if active else css(th["bgSecondary"], .96)
        b.box(x, y, w, h, f"background:{bg};border:1px solid {acc if active else css(th['border'])};display:flex;align-items:center;justify-content:center",
              f'<span class="fit" data-fit="{(w - 6) * k:.1f}" style="font-size:{b.p(10.5)};color:{acc if active else body};white-space:nowrap">{esc(label)}</span>')
    b.box(1, 1, W - 2, 56, f"background:{css(th['bgSecondary'])}")
    b.box(1, 55, W - 2, 2, f"background:{acc}")
    b.img(14, 15, 28, 28, ctx["mgIcon"])
    b.text(52, 13, esc(MG["title"]), 14, acc)
    b.text(52, 33, esc(MG["sub"]), 10, mut)
    mbtn(W - 12 - 24, 16, 24, 24, "X")
    for i, key in enumerate(("mines", "memory", "puzzle", "solitaire")):
        mbtn(12 + i * 110, 66, 106, 26, MG[key], i == 0)
    mbtn(12, 100, 90, 24, MG["easy"], True)
    mbtn(106, 100, 90, 24, MG["normal"])
    mbtn(W - 12 - 110, 100, 110, 24, MG["new"])
    AW, AH = 436, 400
    b.box(12, 132, AW, AH, f"background:rgba(12,17,22,.9);border:1px solid {css(th['border'])}")
    counts, shown, flags = mines_board()
    size = min(math.floor(min((AW - 8) / 9, (AH - 8) / 9)), 40)
    ox, oy = 12 + 4 + ((AW - 8) - size * 9) / 2, 132 + 4 + ((AH - 8) - size * 9) / 2
    for i in range(81):
        r, c = divmod(i, 9)
        x, y = ox + c * size, oy + r * size
        inner = ""
        if i in shown:
            bg = "rgb(18,23,31)"
            if counts[i]:
                col = NUMBER_COLORS[counts[i] - 1]
                inner = f'<span style="font-size:{b.p(17)};font-weight:700;color:{css(col)};{SHADOW}">{counts[i]}</span>'
        else:
            bg = "rgb(41,56,71)"
            if i in flags:
                inner = f'<span style="font-size:{b.p(18)};color:#ff5a4d;{SHADOW}">✖</span>'
        b.box(x, y, size, size, f"background:{bg};border:1px solid rgb(13,18,23);display:flex;align-items:center;justify-content:center", inner)
    status = MG["st_mines"].replace("%d", str(len(MINES) - len(flags)), 1).replace("%s", "1:24", 1)
    b.text(14, 540, esc(status).replace(" ", "&nbsp;"), 12, body)
    b.text(W - 14, 542, esc(MG["best"].replace("%s", "1:52")), 10.5, mut, anchor="transform:translateX(-100%);")
    b.parts.append(f'<div class="t" style="left:{b.p(14)};top:{b.p(560)};width:{b.p(432)};white-space:normal;font-size:{b.p(10)};color:{mut};{SHADOW}">{esc(MG["h_mines"])}</div>')
    b.box(10, H - 4 - 22, 22, 22, "", CHECK.format(mark=MARK))
    b.text(34, H - 4 - 16, esc(MG["autoOpen"]), 10.5, body)
    b.parts.append(f'<svg class="abs" style="left:{b.p(W - 18)};top:{b.p(H - 18)}" width="{16 * k:.0f}" height="{16 * k:.0f}" viewBox="0 0 16 16">'
                   '<path d="M15 3 L3 15 M15 8 L8 15 M15 12 L12 15" stroke="#8a99a6" stroke-width="1.4"/></svg>')
    frame = (f'<div class="abs" style="left:{x0}px;top:{y0}px;width:{W * k:.1f}px;height:{H * k:.1f}px;background:{css(th["bgPrimary"])};'
             f'border:1px solid {css(th["border"])}">{b.html()}</div>')
    return frame, (W * k, H * k), (x0, y0 + 79 * k)


def ui_page(lang, ctx):
    t = T[lang]
    parts = []
    k = 1.1
    mx, my = 40, 150
    frame, ab, (fw, fh) = flight_map(ctx, lang, mx, my, k)
    parts.append(frame)
    bar_y = my + fh + 26
    bar, bar_end = timer_bar(ctx, lang, mx, bar_y, k)
    parts.append(bar)
    gx = mx + fw + 30
    mg, (gw, gh), mg_anchor = minigames_window(ctx, lang, gx, my, 1.0)
    parts.append(mg)
    calls = [
        (ab["title"][0] + 22, ab["title"][1]),                 # 1 title buttons
        (ab["labelEx"][0] - 20, ab["labelEx"][1]),             # 2 labels
        (ab["search"][0] + 2, ab["search"][1]),                # 3 search
        (ab["tabs"][0] - 18, ab["tabs"][1]),                   # 4 sort / favourites
        (ab["row"][0] + 2, ab["row"][1]),                      # 5 route / tooltip (hovered row)
        (bar_end[0] + 22, bar_end[1]),                         # 6 timer bar
        (mg_anchor[0] - 2, mg_anchor[1] - 50),                 # 7 mini games
    ]
    for i, (x, y) in enumerate(calls, 1):
        parts.append(f'<div class="call" style="left:{x - 15:.0f}px;top:{y - 15:.0f}px">{i}</div>')
    notes_top = max(bar_y + 32 * k, my + gh) + 36
    half = 4
    parts.append(f'<div class="notes" style="left:50px;top:{notes_top:.0f}px;width:720px">{note_html(1, t["notes"][:half])}</div>')
    parts.append(f'<div class="notes" style="left:820px;top:{notes_top:.0f}px;width:730px">{note_html(half + 1, t["notes"][half:])}</div>')
    nh = max(notes_height(t["notes"][:half], 680), notes_height(t["notes"][half:], 690))
    page_h = notes_top + nh + 70
    parts.append(f'<div class="abs foot" style="left:50px;top:{page_h - 58:.0f}px;width:1500px">{esc(t["foot"])}</div>')
    head = f'<div class="page"><h1>EzWoW - Flight Map</h1><div class="lead">{esc(t["lead"])}</div></div>'
    return head + "".join(parts), page_h


# ---------------------------------------------------------------------------
# Settings window (UI/OptionsWindow.lua switchSettingsPopup / assembleSettings)
# ---------------------------------------------------------------------------
CHECK = ('<svg viewBox="0 0 22 22" width="100%" height="100%"><rect x="3.5" y="3.5" width="15" height="15" rx="1.5" fill="#15130f" stroke="#8a7a50" stroke-width="1.4"/>'
         '{mark}</svg>')
MARK = '<path d="M5.5 11.5 L9.5 15.5 L17.5 5.5" fill="none" stroke="#ffd100" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/>'


def opt_value(d, key):
    if key == "scale":
        return round(d["scale"] * 100)
    if key == "alpha":
        return round((1 - d["alpha"]) * 100)
    if key == "labelSize":
        return int(d["labelSize"])
    if key == "labelCompact":
        return d.get("labelCompact") is not False
    return bool(d.get(key))


def settings_window(ctx, lang, x0, y0, k):
    th, L, d = ctx["style"], ctx["L"][lang], ctx["defaults"]
    acc, body, mut = css(th["accent"]), css(th["textBody"]), css(th["textMuted"])
    W = 420
    b = Box(k)
    x, width, y = 20, 380, 68
    spans = {}
    for r in ctx["settings"]:
        top = y
        if r["kind"] == "header":
            b.text(x, y + 4, esc(L[r["label"]]), 12.5, acc)
            b.box(x, y + 20, width, 1, f"background:{css(th['border'], .7)}")
            y += 26
        elif r["kind"] == "lang":
            b.text(x + 2, y + 4, esc(L[r["label"]]), 12, body)
            btn(b, th, x + width - 200, y, 200, 22, f'{L["LANG_AUTO"]} ▼')
            y += 30
        elif r["kind"] == "check":
            b.box(x - 2, y, 24, 24, "", CHECK.format(mark=MARK if opt_value(d, r["key"]) else ""))
            b.text(x + 24, y + 5, f'<span class="fit" data-fit="{(width - 30) * k:.1f}">{esc(L[r["label"]])}</span>', 12, body)
            y += 26
            if r["sub"]:
                b.text(x + 24, y - 6, f'<span class="fit" data-fit="{(width - 30) * k:.1f}">{esc(L[r["sub"]])}</span>', 10, "#808080")
                y += 12
            if r["key"] == "worldMapFlights":
                fac = (("alliance", (0.2, 0.6, 1.0), True), ("horde", (1.0, 0.2, 0.15), False), ("neutral", (1.0, 0.82, 0.2), True))
                for i, (fk, col, on) in enumerate(fac):
                    b.box(x + 18 + i * 116, y - 2, 22, 22, "", CHECK.format(mark=MARK if on else ""))
                    b.text(x + 18 + i * 116 + 24, y + 2, esc(L["WM"][fk]), 10.5, css(col))
                y += 24
        elif r["kind"] == "slider":
            v = opt_value(d, r["key"])
            b.text(x + 2, y + 4, esc(L[r["label"]]), 12, body)
            b.text(x + width - 2, y + 4, esc(r["fmt"].replace("%%", "%").replace("%d", str(v))), 12, acc, anchor="transform:translateX(-100%);")
            sw = width - 8
            b.box(x + 4, y + 22, sw, 12, f"background:rgba(12,17,22,.96);border:1px solid {css(th['border'])}")
            f = (v - r["min"]) / (r["max"] - r["min"])
            b.box(x + 4 + f * (sw - 16), y + 19, 16, 18, "background:linear-gradient(#f0f0f0,#9a9a9a);border:1px solid #333;border-radius:3px")
            y += 46
        spans[r.get("key") or r["label"]] = (top, y)
    bottom = y
    btn(b, th, 20, bottom + 10, 184, 28, T[lang]["reset"])
    btn(b, th, W - 20 - 184, bottom + 10, 184, 28, L["BTN_DONATE"], accent=True)
    H = bottom + 66
    b.text(W - 20, H - 10 - 11, "EzWoW - Flight Map · /ezfl", 10, mut, anchor="transform:translateX(-100%);")
    # header 56: icon 28, title, subtitle, close
    b.box(1, 1, W - 2, 56, f"background:{css(th['bgSecondary'], .96)}")
    b.box(1, 55, W - 2, 2, f"background:{css(th['accent'], .95)}")
    b.img(14, 14, 28, 28, ctx["icon"])
    b.text(48, 11, "EzWoW - Flight Map", 15, acc)
    b.text(48, 32, esc(L["SETTINGS"]), 10, mut)
    btn(b, th, W - 10 - 24, 11, 24, 24, "X")
    frame = (f'<div class="abs" style="left:{x0}px;top:{y0}px;width:{W * k:.1f}px;height:{H * k:.1f}px;background:{css(th["bgPrimary"], .97)};'
             f'border:1px solid {css(th["border"])}">{b.html()}</div>')
    return frame, H, spans, bottom


def settings_page(lang, ctx):
    t = T[lang]
    k = 1.25
    ox, oy = 60, 150
    win, H, sp, bottom = settings_window(ctx, lang, ox, oy, k)
    groups = [sp["OPT_LANG"], (sp["enabled"][0], sp["confirmFlight"][1]),
              (sp["worldMapFlights"][0], sp["worldMapAutoAlign"][1]), (sp["labels"][0], sp["autoSearch"][1]),
              (sp["scale"][0], sp["labelSize"][1]), (sp["flightBar"][0], sp["soonAlert"][1]), (bottom + 10, bottom + 38)]
    calls = "".join(f'<div class="call" style="left:{ox + 420 * k + 18:.0f}px;top:{oy + (a + b2) / 2 * k - 15:.0f}px">{i}</div>'
                    for i, (a, b2) in enumerate(groups, 1))
    nx = ox + 420 * k + 80
    nw = PAGE_W - nx - 50
    page_h = max(oy + H * k, oy + 10 + notes_height(t["sNotes"], nw - 40)) + 80
    body = (f'<div class="page"><h1>EzWoW - Flight Map <span class="badge">{esc(t["sTitle"])}</span></h1>'
            f'<div class="lead">{esc(t["sLead"])}</div></div>' + win + calls
            + f'<div class="notes" style="left:{nx:.0f}px;top:{oy + 10}px;width:{nw:.0f}px">{note_html(1, t["sNotes"])}</div>'
            + f'<div class="abs foot" style="left:50px;top:{page_h - 44:.0f}px">{esc(t["sFoot"])}</div>')
    return body, page_h


# ---------------------------------------------------------------------------
def find_chrome():
    cands = [os.environ.get("CHROME"), r"C:\Program Files\Google\Chrome\Application\chrome.exe",
             r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
             shutil.which("chrome"), shutil.which("google-chrome"), shutil.which("chromium")]
    for c in cands:
        if c and Path(c).exists():
            return c
    sys.exit("Chrome not found (set CHROME=<path to chrome>)")


def render(chrome, html_text, out_png, height, tmp):
    page = Path(tmp) / (out_png.stem + ".html")
    page.write_text(html_text, encoding="utf-8")
    shot = Path(tmp) / out_png.name
    proc = subprocess.Popen([chrome, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
                             f"--user-data-dir={Path(tmp) / ('profile_' + out_png.stem)}", f"--window-size={PAGE_W},{int(height)}",
                             "--virtual-time-budget=2000", f"--screenshot={shot}", page.as_uri()],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    # Chrome sometimes keeps running after writing the screenshot: wait for the file, then stop it
    deadline, last = time.time() + 120, -1
    while time.time() < deadline:
        if shot.exists() and shot.stat().st_size == last and last > 0:
            break
        last = shot.stat().st_size if shot.exists() else -1
        if proc.poll() is not None and shot.exists():
            break
        time.sleep(0.5)
    if proc.poll() is None:
        proc.kill()
        proc.wait()
    if not shot.exists():
        sys.exit(f"Chrome did not write {out_png.name}")
    shutil.copyfile(shot, out_png)


def main(root: Path):
    out = root / "docs" / "images"
    out.mkdir(parents=True, exist_ok=True)
    init_src = read(root, "Core/Init.lua")
    media = root / "Media"
    ctx = {
        "style": parse_style(init_src),
        "defaults": parse_defaults(init_src),
        "consts": parse_consts(init_src),
        "L": parse_locales(read(root, "Core/Locales.lua")),
        "MG": parse_minigame_strings(read(root, "Libs/EzWoWMiniGames/MiniGames.lua")),
        "settings": parse_settings(read(root, "UI/OptionsWindow.lua")),
        "version": parse_version(read(root, "EzWoW-FlightMap.toc")),
        "icon": tga_uri(media / "Icon.tga", circle_svg("#2b3a4a")),
        "mgIcon": tga_uri(root / "Libs" / "EzWoWMiniGames" / "Icon.tga", circle_svg("#2b3a4a")),
        "gear": tga_uri(media / "Gear.tga", circle_svg("#d9a441")),
        "list": tga_uri(media / "List.tga", circle_svg("#d9a441")),
        "glow": tga_uri(media / "Pin-Glow.tga", circle_svg("rgba(255,230,150,.4)")),
        "ring": tga_uri(media / "Pin-Selected.tga", circle_svg("none")),
        "starOn": tga_uri(media / "Star-On.tga", circle_svg("#ffcc33")),
        "starOff": tga_uri(media / "Star-Off.tga", circle_svg("none")),
        "pins": {"CURRENT": tga_uri(media / "Pin-Current.tga", circle_svg("#2f9d4b")),
                 "REACHABLE": tga_uri(media / "Pin-Flight.tga", circle_svg("#1f4f9a")),
                 "DISTANT": tga_uri(media / "Pin-Distant.tga", circle_svg("#777"))},
    }
    chrome = find_chrome()
    tmp = tempfile.mkdtemp(prefix="ezfl_readme_")
    try:
        for lang in ("ko", "en"):
            for name, fn in (("ui", ui_page), ("settings", settings_page)):
                body, h = fn(lang, ctx)
                html_text = (f'<!doctype html><html><head><meta charset="utf-8"><style>{CSS}</style></head>'
                             f'<body style="height:{int(h)}px">{body}{FIT_JS}</body></html>')
                png = out / f"{name}_{lang}.png"
                render(chrome, html_text, png, h, tmp)
                print("wrote", png, int(h))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main(Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve())
