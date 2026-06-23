#!/usr/bin/env python3
"""Generate a QuotaFloat promotional intro image."""

import math
import os
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

WIDTH, HEIGHT = 1600, 900

def hex_color(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i+2], 16) for i in (0, 2, 4)) + (255,)

def interpolate(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

def draw_gradient_background(draw, width, height, c1, c2):
    c1_rgb = hex_color(c1)[:3]
    c2_rgb = hex_color(c2)[:3]
    for y in range(height):
        t = y / height
        color = interpolate(c1_rgb, c2_rgb, t)
        draw.line([(0, y), (width, y)], fill=color)

def load_font(path, size):
    try:
        return ImageFont.truetype(path, size)
    except Exception:
        return ImageFont.load_default()

# Try to use nice system fonts
font_paths = [
    '/System/Library/Fonts/PingFang.ttc',
    '/Library/Fonts/Arial Unicode.ttf',
    '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
    '/System/Library/Fonts/Helvetica.ttc',
]

chinese_font = None
latin_font_bold = None
latin_font_regular = None

for p in font_paths:
    if os.path.exists(p):
        if chinese_font is None:
            chinese_font = load_font(p, 24)
        if latin_font_bold is None and 'Helvetica' in p:
            latin_font_bold = load_font(p, 40)
            latin_font_regular = load_font(p, 24)

# Fallbacks
if chinese_font is None:
    chinese_font = ImageFont.load_default()
if latin_font_bold is None:
    latin_font_bold = load_font('/Library/Fonts/Arial Unicode.ttf', 48)
if latin_font_regular is None:
    latin_font_regular = load_font('/Library/Fonts/Arial Unicode.ttf', 24)

# Prefer macOS system fonts for Chinese + Latin mixed text
STHEITI = '/System/Library/Fonts/STHeiti Medium.ttc'
uni_bold = load_font(STHEITI, 48)
uni_regular = load_font(STHEITI, 22)
uni_small = load_font(STHEITI, 18)
uni_tiny = load_font(STHEITI, 14)
uni_large = load_font(STHEITI, 64)
uni_medium = load_font(STHEITI, 26)

def text_size(draw, text, font):
    bbox = draw.textbbox((0, 0), text, font=font)
    return bbox[2] - bbox[0], bbox[3] - bbox[1]

def draw_rounded_rect(draw, xy, radius, fill, outline=None, width=1):
    draw.rounded_rectangle(xy, radius=radius, fill=fill, outline=outline, width=width)

def draw_circle(draw, center, radius, fill):
    x, y = center
    draw.ellipse([x-radius, y-radius, x+radius, y+radius], fill=fill)

# Create canvas
img = Image.new('RGBA', (WIDTH, HEIGHT), (255, 255, 255, 255))
draw = ImageDraw.Draw(img)

# Background gradient
draw_gradient_background(draw, WIDTH, HEIGHT, '#F8F8FA', '#EDE9FE')

# Decorative blurred circles (bokeh)
def draw_blur_circle(img, center, radius, color):
    cimg = Image.new('RGBA', (radius*2, radius*2), (0,0,0,0))
    cd = ImageDraw.Draw(cimg)
    cd.ellipse([0, 0, radius*2, radius*2], fill=color)
    cimg = cimg.filter(ImageFilter.GaussianBlur(radius=radius//2))
    img.paste(cimg, (center[0]-radius, center[1]-radius), cimg)

draw_blur_circle(img, (180, 220), 160, (107, 92, 231, 30))
draw_blur_circle(img, (1420, 720), 200, (245, 99, 61, 25))
draw_blur_circle(img, (1300, 150), 120, (120, 180, 240, 25))

# Title area
qf_logo_size = 52
logo_x, logo_y = 120, 80
# QF gradient logo
def draw_qf_logo(draw, x, y, size):
    # Create a small image for the gradient logo
    limg = Image.new('RGBA', (size, size), (0,0,0,0))
    ld = ImageDraw.Draw(limg)
    # Draw rounded rect
    ld.rounded_rectangle([0, 0, size-1, size-1], radius=size//4, fill=(107, 92, 231, 255))
    # Simpler gradient approximation: top-left lighter, bottom-right darker overlay
    overlay = Image.new('RGBA', (size, size), (0,0,0,0))
    od = ImageDraw.Draw(overlay)
    od.rounded_rectangle([0, 0, size-1, size-1], radius=size//4, fill=(245, 99, 61, 120))
    limg = Image.alpha_composite(limg, overlay)
    # Text QF
    font = load_font('/Library/Fonts/Arial Unicode.ttf', size//2)
    bbox = ld.textbbox((0,0), 'QF', font=font)
    tw, th = bbox[2]-bbox[0], bbox[3]-bbox[1]
    ld.text(((size-tw)//2, (size-th)//2 - 2), 'QF', font=font, fill=(255,255,255,255))
    img.paste(limg, (x, y), limg)

draw_qf_logo(draw, logo_x, logo_y, qf_logo_size)

# Title text
title_x = logo_x + qf_logo_size + 18
title_y = logo_y + 2
draw.text((title_x, title_y), 'QuotaFloat', font=uni_large, fill=(29, 29, 31, 255))

# Version badge
version_x = title_x + text_size(draw, 'QuotaFloat', uni_large)[0] + 18
version_y = title_y + 18
draw.rounded_rectangle([version_x, version_y, version_x+80, version_y+28], radius=6, fill=(29,29,31,255))
draw.text((version_x+12, version_y+4), 'v0.1.0', font=uni_tiny, fill=(255,255,255,255))

# Tagline
tagline_y = title_y + 72
draw.text((title_x, tagline_y), '原生 macOS 悬浮额度工具', font=uni_regular, fill=(80, 80, 84, 255))

# Sub-tagline
draw.text((title_x, tagline_y+34), '在桌面一角实时掌握 Codex、Claude、Kimi 的 5 小时 / 周额度与重置倒计时', font=uni_small, fill=(110, 110, 116, 255))

# Floating window mockup
panel_w, panel_h = 360, 210
panel_x, panel_y = 120, 260

# Panel shadow
shadow = Image.new('RGBA', (panel_w+40, panel_h+40), (0,0,0,0))
sd = ImageDraw.Draw(shadow)
sd.rounded_rectangle([10, 10, panel_w+30, panel_h+30], radius=18, fill=(0,0,0,40))
shadow = shadow.filter(ImageFilter.GaussianBlur(radius=12))
img.paste(shadow, (panel_x-10, panel_y-10), shadow)

# Panel background
draw.rounded_rectangle([panel_x, panel_y, panel_x+panel_w, panel_y+panel_h], radius=14, fill=(255,255,255,245), outline=(0,0,0,18), width=1)

providers = [
    ('Codex', '#6B5CE7', 0.62, 0.41, True, 2),
    ('Claude', '#D97757', 0.78, 0.33, False, 0),
    ('Kimi', '#333333', 0.45, 0.82, False, 0),
]

row_h = 52
start_y = panel_y + 22
for i, (name, color, s5, sw, has_credit, credit_count) in enumerate(providers):
    y = start_y + i * row_h
    cx = panel_x + 28
    cy = y + 18
    # Provider icon rounded square
    draw.rounded_rectangle([cx-12, cy-12, cx+12, cy+12], radius=6, fill=(255,255,255,255), outline=(0,0,0,20), width=1)
    # Initial letter
    init_font = load_font(STHEITI, 14)
    draw.text((cx-5, cy-7), name[0], font=init_font, fill=hex_color(color)[:3])

    # Provider name
    draw.text((cx+24, cy-8), name, font=uni_small, fill=(60,60,64,255))

    # 5h label
    bar_x = cx + 24
    bar_y = cy + 14
    draw.text((bar_x, bar_y), '5h', font=uni_tiny, fill=(130,130,136,255))
    # 5h bar bg
    draw.rounded_rectangle([bar_x+22, bar_y+5, bar_x+22+50, bar_y+10], radius=2.5, fill=(0,0,0,30))
    # 5h bar fill
    draw.rounded_rectangle([bar_x+22, bar_y+5, bar_x+22+int(50*s5), bar_y+10], radius=2.5, fill=hex_color(color)[:3])

    # Weekly label
    draw.text((bar_x+84, bar_y), '周', font=uni_tiny, fill=(130,130,136,255))
    draw.rounded_rectangle([bar_x+100, bar_y+5, bar_x+100+50, bar_y+10], radius=2.5, fill=(0,0,0,30))
    draw.rounded_rectangle([bar_x+100, bar_y+5, bar_x+100+int(50*sw), bar_y+10], radius=2.5, fill=hex_color(color)[:3])

    # Percentage
    pct = f'{int((1-s5)*100)}%'
    draw.text((bar_x+162, bar_y-2), pct, font=uni_small, fill=(40,40,44,255))

    # Credit badge for Codex
    if has_credit:
        badge_x, badge_y = cx + 8, cy - 14
        draw.rounded_rectangle([badge_x, badge_y, badge_x+14, badge_y+12], radius=4, fill=(107,92,231,200))
        draw.text((badge_x+3, badge_y-1), str(credit_count), font=uni_tiny, fill=(255,255,255,255))

# Controls mockup (close + refresh)
ctrl_x, ctrl_y = panel_x + 14, panel_y + 14
for icon, dx in [('×', 0), ('↻', 16)]:
    draw.rounded_rectangle([ctrl_x+dx, ctrl_y, ctrl_x+dx+13, ctrl_y+13], radius=6.5, fill=(0,0,0,20))
    draw.text((ctrl_x+dx+3, ctrl_y-1), icon, font=uni_tiny, fill=(80,80,84,255))

# Reset countdown hover mockup (small card)
hover_w, hover_h = 200, 76
hover_x, hover_y = panel_x + panel_w + 30, panel_y + 40
draw.rounded_rectangle([hover_x, hover_y, hover_x+hover_w, hover_y+hover_h], radius=10, fill=(255,255,255,235), outline=(0,0,0,12), width=1)
draw.text((hover_x+14, hover_y+12), '鼠标悬停查看重置倒计时', font=uni_tiny, fill=(80,80,84,255))
draw.text((hover_x+14, hover_y+34), '5h  2h15m  正常', font=uni_small, fill=(60,60,64,255))
draw.text((hover_x+14, hover_y+56), '周   3天4h   充裕', font=uni_small, fill=(60,60,64,255))

# Vertical divider between mockup and features
draw.line([(580, 260), (580, 780)], fill=(0,0,0,18), width=1)
features = [
    ('原生 macOS 14+', 'Swift 6.2 构建，SwiftUI + AppKit，无 Dock 图标，窗口置顶悬浮。'),
    ('三端额度聚合', 'Codex、Claude、Kimi Coding Plan 的 5h / 周额度一窗尽览。'),
    ('自动 + 手动刷新', '每 2 分钟自动同步，失败保留缓存并标记过期，支持一键手动刷新。'),
    ('OAuth / CLI 双链路', '优先本机 OAuth，失败自动回退到 codex / claude CLI。'),
    ('隐私优先', '凭证只用于官方额度接口，不含遥测、广告或行为统计。'),
    ('零额外依赖', 'CodexBarCore 编译进应用，无需安装 CodexBar 或启动 codexbar serve。'),
]

feat_x = 620
feat_y = 270
feat_line_h = 82
for i, (title, desc) in enumerate(features):
    y = feat_y + i * feat_line_h
    # Bullet dot
    draw_circle(draw, (feat_x+8, y+10), 5, (107, 92, 231, 255))
    draw.text((feat_x+24, y), title, font=uni_regular, fill=(29,29,31,255))
    draw.text((feat_x+24, y+30), desc, font=uni_small, fill=(70,70,76,255))

# Bottom call-to-action
cta_y = HEIGHT - 90
draw.rounded_rectangle([120, cta_y, 420, cta_y+46], radius=10, fill=(29,29,31,255))
draw.text((140, cta_y+12), 'swift run QuotaFloat', font=uni_regular, fill=(255,255,255,255))

draw.text((460, cta_y+12), '或运行 ./Scripts/package_app.sh 生成 .app', font=uni_small, fill=(90,90,96,255))

# Save
output_path = Path(__file__).resolve().parent / 'quotafloat-intro.png'
img.save(output_path, 'PNG')
print(f'Saved: {output_path}')
