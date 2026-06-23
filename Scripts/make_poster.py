"""
QuotaFloat 介绍海报生成器
- 暖米白 + 莫兰迪米色系
- 6 个自绘几何图标(完全不用 lucide)
- 嵌入 3 张真实应用截图
"""
from PIL import Image, ImageDraw, ImageFont
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SHOT_DIR = ROOT / "screenshots" / "web"
OUT = ROOT / "quotafloat-poster.png"

S = 2

W = 880 * S
H = 1480 * S

BG = (244, 236, 217)
CARD = (239, 229, 207)
CARD2 = (234, 222, 195)
INK = (58, 46, 31)
INK2 = (123, 106, 82)
INK3 = (160, 142, 113)
LINE = (212, 200, 173)
ACC_GREEN = (141, 168, 135)
ACC_ORANGE = (201, 152, 119)
ACC_PURPLE = (155, 143, 176)
ACC_SAGE = (170, 175, 142)

FP = "/System/Volumes/Data/System/Library/AssetsV2/com_apple_MobileAsset_Font8/86ba2c91f017a3749571a82f2c6d890ac7ffb2fb.asset/AssetData/PingFang.ttc"

def font(size, weight="reg"):
    idx = 4 if weight == "med" else 3
    return ImageFont.truetype(FP, size * S, index=idx)

F_TITLE = font(56, "med")
F_TAGLINE = font(20)
F_SUB = font(18)
F_SECTION = font(18, "med")
F_CARD_T = font(20, "med")
F_CARD_B = font(15)
F_FOOT = font(14)
F_QF = font(28, "med")
F_LBL = font(14, "med")

img = Image.new("RGB", (W, H), BG)
d = ImageDraw.Draw(img)

def rr(box, r, fill=None, outline=None, width=1):
    d.rounded_rectangle([c * S for c in box], radius=r * S, fill=fill, outline=outline, width=width * S)

def line(x1, y1, x2, y2, color, w=1):
    d.line([x1 * S, y1 * S, x2 * S, y2 * S], fill=color, width=w * S)

def text(xy, t, f, fill=INK, anchor="la"):
    d.text((xy[0] * S, xy[1] * S), t, font=f, fill=fill, anchor=anchor)

def circle(cx, cy, r, fill=None, outline=None, width=1):
    d.ellipse([(cx - r) * S, (cy - r) * S, (cx + r) * S, (cy + r) * S],
              fill=fill, outline=outline, width=width * S)

PAD_X = 64
y = 70

logo_x, logo_y = PAD_X, y
rr([logo_x, logo_y, logo_x + 64, logo_y + 64], 14, fill=ACC_SAGE)
text((logo_x + 32, logo_y + 32), "QF", F_QF, fill=BG, anchor="mm")

text((PAD_X + 80, y + 6), "QuotaFloat", F_TITLE, fill=INK)
text((PAD_X + 80, y + 76), "桌面悬浮 · 三家 AI Coding 额度一窗掌握", F_TAGLINE, fill=INK2)

y += 130

cx = W // S // 2

dot_y = y + 8
text((cx, dot_y), "Codex  ·  Claude  ·  Kimi", F_SECTION, fill=INK, anchor="mm")
line(PAD_X, y + 36, cx - 130, y + 36, LINE, 1)
line(cx + 130, y + 36, W // S - PAD_X, y + 36, LINE, 1)

y += 68

def paste_shot(path, x, y, max_w):
    im = Image.open(path).convert("RGBA")
    iw, ih = im.size
    scale = (max_w * S) / iw
    nw, nh = int(iw * scale), int(ih * scale)
    im = im.resize((nw, nh), Image.LANCZOS)
    img.paste(im, (x * S, y * S), im)
    return nh // S

frame_x = PAD_X
frame_w = W // S - PAD_X * 2

rr([frame_x, y, frame_x + frame_w, y + 110], 16, fill=CARD)

text((frame_x + 24, y + 18), "完整模式", F_CARD_T, fill=INK)
text((frame_x + 24, y + 46), "5h 与周 双窗口 · 剩余时间 · 配速标记", F_CARD_B, fill=INK2)

text((frame_x + frame_w - 24, y + 18), "Full", F_LBL, fill=INK3, anchor="ra")

shot_h = paste_shot(SHOT_DIR / "all.png", frame_x + 24, y + 72, frame_w - 48)

y += 72 + shot_h + 26

half_w = (frame_w - 16) // 2

rr([frame_x, y, frame_x + half_w, y + 134], 16, fill=CARD)
text((frame_x + 20, y + 16), "迷你模式", F_CARD_T, fill=INK)
text((frame_x + 20, y + 42), "三服务 · 仅看百分比", F_CARD_B, fill=INK2)
text((frame_x + half_w - 18, y + 16), "Mini", F_LBL, fill=INK3, anchor="ra")
paste_shot(SHOT_DIR / "all-simple.png", frame_x + 20, y + 72, half_w - 40)

x2 = frame_x + half_w + 16
rr([x2, y, x2 + half_w, y + 134], 16, fill=CARD)
text((x2 + 20, y + 16), "单档模式", F_CARD_T, fill=INK)
text((x2 + 20, y + 42), "单服务 · 一行胶囊", F_CARD_B, fill=INK2)
text((x2 + half_w - 18, y + 16), "Solo", F_LBL, fill=INK3, anchor="ra")
paste_shot(SHOT_DIR / "codex-simple.png", x2 + 20, y + 72, half_w - 40)

y += 134 + 36

line(PAD_X, y, cx - 80, y, LINE, 1)
text((cx, y), "六大功能", F_SECTION, fill=INK, anchor="mm")
line(cx + 80, y, W // S - PAD_X, y, LINE, 1)

y += 32

card_w = (frame_w - 32) // 3
card_h = 196

def icon_three_one(cx0, cy0):
    rr([cx0 - 36, cy0 - 12, cx0 + 36, cy0 + 12], 8, outline=ACC_SAGE, width=2)
    circle(cx0 - 22, cy0, 6, fill=ACC_GREEN)
    circle(cx0,      cy0, 6, fill=ACC_ORANGE)
    circle(cx0 + 22, cy0, 6, fill=ACC_PURPLE)

def icon_capsule_native(cx0, cy0):
    rr([cx0 - 34, cy0 - 20, cx0 + 34, cy0 + 18], 7, outline=INK2, width=1)
    rr([cx0 - 34, cy0 - 20, cx0 + 34, cy0 - 12], 7, fill=ACC_SAGE)
    circle(cx0 - 28, cy0 - 16, 1.5, fill=BG)
    circle(cx0 - 23, cy0 - 16, 1.5, fill=BG)
    circle(cx0 - 18, cy0 - 16, 1.5, fill=BG)
    rr([cx0 - 26, cy0 - 4, cx0 + 26, cy0 + 10], 7, outline=ACC_SAGE, width=1)
    circle(cx0 - 16, cy0 + 3, 3, fill=ACC_GREEN)
    circle(cx0,      cy0 + 3, 3, fill=ACC_ORANGE)
    circle(cx0 + 16, cy0 + 3, 3, fill=ACC_PURPLE)

def icon_visibility(cx0, cy0):
    sz = 14
    gap = 6
    total = sz * 3 + gap * 2
    start_x = cx0 - total // 2
    for i in range(3):
        bx = start_x + i * (sz + gap)
        by = cy0 + 4
        if i == 1:
            rr([bx, by, bx + sz, by + sz], 3, fill=ACC_SAGE)
            rr([bx - 5, cy0 - 16, bx + sz + 5, cy0 - 8], 3, fill=ACC_ORANGE)
            line(bx + sz // 2, cy0 - 8, bx + sz // 2, by, INK3, 1)
        else:
            rr([bx, by, bx + sz, by + sz], 3, fill=BG, outline=INK3, width=1)

def icon_dual_window(cx0, cy0):
    rr([cx0 - 30, cy0 - 18, cx0 + 30, cy0 - 6], 4, fill=BG, outline=INK2, width=1)
    rr([cx0 - 30, cy0 - 18, cx0 - 30 + 26, cy0 - 6], 4, fill=ACC_GREEN)
    rr([cx0 - 30, cy0 + 6, cx0 + 30, cy0 + 18], 4, fill=BG, outline=INK2, width=1)
    rr([cx0 - 30, cy0 + 6, cx0 - 30 + 44, cy0 + 18], 4, fill=ACC_ORANGE)

def icon_gauge(cx0, cy0):
    d.arc([(cx0 - 28) * S, (cy0 - 18) * S, (cx0 + 28) * S, (cy0 + 38) * S],
          start=180, end=360, fill=INK2, width=2 * S)
    for ang_off in [-60, -30, 0, 30, 60]:
        import math
        a = math.radians(270 + ang_off)
        x1 = cx0 + math.cos(a) * 22
        y1 = cy0 + math.sin(a) * 22 + 10
        x2 = cx0 + math.cos(a) * 28
        y2 = cy0 + math.sin(a) * 28 + 10
        line(x1, y1, x2, y2, INK3, 1)
    import math
    a = math.radians(220)
    nx = cx0 + math.cos(a) * 22
    ny = cy0 + math.sin(a) * 22 + 10
    line(cx0, cy0 + 10, nx, ny, ACC_ORANGE, 2)
    circle(cx0, cy0 + 10, 3, fill=INK)

def icon_density(cx0, cy0):
    rr([cx0 - 32, cy0 - 18, cx0 + 32, cy0 - 8], 3, fill=ACC_PURPLE)
    rr([cx0 - 32, cy0 - 4, cx0 + 18, cy0 + 6], 3, fill=ACC_GREEN)
    rr([cx0 - 32, cy0 + 10, cx0 - 8, cy0 + 20], 3, fill=ACC_ORANGE)

def icon_offline(cx0, cy0):
    circle(cx0, cy0, 22, outline=INK2, width=2)
    circle(cx0, cy0, 14, outline=INK3, width=1)
    circle(cx0, cy0, 6, fill=ACC_ORANGE)
    line(cx0 - 22, cy0 + 22, cx0 + 22, cy0 - 22, INK2, 2)

def icon_native(cx0, cy0):
    rr([cx0 - 26, cy0 - 18, cx0 + 26, cy0 + 16], 10, outline=INK2, width=2)
    rr([cx0 - 26, cy0 - 18, cx0 + 26, cy0 - 8], 10, fill=ACC_SAGE)
    rr([cx0 - 26, cy0 - 10, cx0 + 26, cy0 - 8], 0, fill=ACC_SAGE)
    circle(cx0 - 20, cy0 - 13, 1.5, fill=BG)
    circle(cx0 - 15, cy0 - 13, 1.5, fill=BG)
    circle(cx0 - 10, cy0 - 13, 1.5, fill=BG)

cards = [
    ("一行胶囊置顶", "Codex、Claude、Kimi 多家额度\n原生 macOS · 置顶 · 记住位置", icon_capsule_native),
    ("按需显隐", "只在 Codex、Claude、终端等\n指定应用里现身,不抢屏幕", icon_visibility),
    ("双周期 + 倒计时", "5 小时窗口与周窗口分别\n显示已用百分比和重置时间", icon_dual_window),
    ("智能配速评估", "比对剩余时间和剩余额度\n标出宽裕 / 正常 / 偏快 / 告急", icon_gauge),
    ("内容密度可选", "完整 / 迷你 / 单档 三档显示\n按需选择要展示哪几项", icon_density),
    ("断网降级不断档", "2 分钟自动刷新,网络失败\n保留上次数据并标记缓存", icon_offline),
]

row_y = y
for i, (title, body, draw_icon) in enumerate(cards):
    col = i % 3
    row = i // 3
    cx0 = PAD_X + col * (card_w + 16)
    cy0 = row_y + row * (card_h + 16)

    rr([cx0, cy0, cx0 + card_w, cy0 + card_h], 16, fill=CARD)

    icon_cx = cx0 + card_w // 2
    icon_cy = cy0 + 48
    draw_icon(icon_cx, icon_cy)

    text((icon_cx, cy0 + 100), title, F_CARD_T, fill=INK, anchor="mm")

    lines = body.split("\n")
    for li, ln in enumerate(lines):
        text((icon_cx, cy0 + 130 + li * 24), ln, F_CARD_B, fill=INK2, anchor="mm")

y = row_y + 2 * (card_h + 16) - 16 + 40

line(PAD_X, y, W // S - PAD_X, y, LINE, 1)

y += 22

foot = "macOS 14+   ·   Swift 6.2   ·   CodexBarCore (MIT)   ·   本机 ad-hoc 签名"
text((cx, y), foot, F_FOOT, fill=INK2, anchor="mm")

y += 26
text((cx, y), "原生小工具 · 适合个人使用", F_FOOT, fill=INK3, anchor="mm")

final_h = (y + 50) * S
img = img.crop((0, 0, W, final_h))
img.save(OUT, "PNG", optimize=True)
print(f"saved: {OUT}  size={img.size}")
