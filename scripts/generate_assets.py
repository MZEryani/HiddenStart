#!/usr/bin/env python3
import os
from PIL import Image, ImageDraw, ImageFont

ASSETS_DIR = "HiddenStart/Assets.xcassets"
APPICON_DIR = os.path.join(ASSETS_DIR, "AppIcon.appiconset")
MENUBAR_DIR = os.path.join(ASSETS_DIR, "MenuBarIcon.imageset")
SCRIPTS_DIR = "scripts"
DOCS_ASSETS_DIR = "docs/assets"

os.makedirs(APPICON_DIR, exist_ok=True)
os.makedirs(MENUBAR_DIR, exist_ok=True)
os.makedirs(DOCS_ASSETS_DIR, exist_ok=True)

# 1. Assets.xcassets root Contents.json
with open(os.path.join(ASSETS_DIR, "Contents.json"), "w") as f:
    f.write('{\n  "info" : {\n    "version" : 1,\n    "author" : "xcode"\n  }\n}\n')

# 2. Generate Base App Icon (1024x1024)
def create_app_icon():
    size = 1024
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # macOS squircle approximation
    # Margin ~100px so it fits nicely inside Apple icon grid
    margin = 100
    rect = [margin, margin, size - margin, size - margin]
    radius = 180

    # Gradient background simulation (Dark slate / deep indigo)
    # Draw rounded rectangle with deep charcoal/blue
    draw.rounded_rectangle(rect, radius=radius, fill=(28, 30, 42, 255), outline=(60, 64, 85, 255), width=8)

    # Inner decorative rounded card
    inner_margin = 130
    draw.rounded_rectangle(
        [inner_margin, inner_margin, size - inner_margin, size - inner_margin],
        radius=radius - 20,
        outline=(80, 88, 120, 100),
        width=4
    )

    # Center motif: Stylized "Eye" with diagonal slash (Stand-in)
    center_x, center_y = size // 2, size // 2

    # Eye shape: two intersecting curves (ellipse)
    eye_w, eye_h = 240, 140
    eye_box = [center_x - eye_w, center_y - eye_h, center_x + eye_w, center_y + eye_h]
    draw.ellipse(eye_box, outline=(220, 225, 240, 255), width=24)

    # Pupil
    pupil_r = 60
    draw.ellipse(
        [center_x - pupil_r, center_y - pupil_r, center_x + pupil_r, center_y + pupil_r],
        fill=(220, 225, 240, 255)
    )

    # Inner pupil core (accent)
    core_r = 28
    draw.ellipse(
        [center_x - core_r, center_y - core_r, center_x + core_r, center_y + core_r],
        fill=(99, 130, 255, 255)
    )

    # Diagonal slash line
    slash_len = 280
    draw.line(
        [center_x - slash_len, center_y + slash_len, center_x + slash_len, center_y - slash_len],
        fill=(99, 130, 255, 255),
        width=32
    )

    return img

base_icon = create_app_icon()

# Generate AppIcon sizes
sizes = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for s, filename in sizes:
    resized = base_icon.resize((s, s), Image.Resampling.LANCZOS)
    resized.save(os.path.join(APPICON_DIR, filename), "PNG")

# AppIcon Contents.json
appicon_contents = """{
  "images" : [
    { "size" : "16x16", "idiom" : "mac", "filename" : "icon_16x16.png", "scale" : "1x" },
    { "size" : "16x16", "idiom" : "mac", "filename" : "icon_16x16@2x.png", "scale" : "2x" },
    { "size" : "32x32", "idiom" : "mac", "filename" : "icon_32x32.png", "scale" : "1x" },
    { "size" : "32x32", "idiom" : "mac", "filename" : "icon_32x32@2x.png", "scale" : "2x" },
    { "size" : "128x128", "idiom" : "mac", "filename" : "icon_128x128.png", "scale" : "1x" },
    { "size" : "128x128", "idiom" : "mac", "filename" : "icon_128x128@2x.png", "scale" : "2x" },
    { "size" : "256x256", "idiom" : "mac", "filename" : "icon_256x256.png", "scale" : "1x" },
    { "size" : "256x256", "idiom" : "mac", "filename" : "icon_256x256@2x.png", "scale" : "2x" },
    { "size" : "512x512", "idiom" : "mac", "filename" : "icon_512x512.png", "scale" : "1x" },
    { "size" : "512x512", "idiom" : "mac", "filename" : "icon_512x512@2x.png", "scale" : "2x" }
  ],
  "info" : {
    "version" : 1,
    "author" : "xcode"
  }
}
"""
with open(os.path.join(APPICON_DIR, "Contents.json"), "w") as f:
    f.write(appicon_contents)

# 3. Generate Menu Bar Icon (@1x 18x18, @2x 36x36 template)
def create_menubar_icon(size):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Black monochrome silhouette (template)
    cx, cy = size / 2.0, size / 2.0
    w = size * 0.44
    h = size * 0.26
    line_w = max(1, int(size * 0.08))

    # Outer eye outline
    draw.ellipse([cx - w, cy - h, cx + w, cy + h], outline=(0, 0, 0, 255), width=line_w)

    # Pupil center
    pr = size * 0.12
    draw.ellipse([cx - pr, cy - pr, cx + pr, cy + pr], fill=(0, 0, 0, 255))

    # Diagonal slash
    sl = size * 0.40
    draw.line([cx - sl, cy + sl, cx + sl, cy - sl], fill=(0, 0, 0, 255), width=line_w)

    return img

mb_1x = create_menubar_icon(18)
mb_2x = create_menubar_icon(36)
mb_1x.save(os.path.join(MENUBAR_DIR, "MenuBarIcon.png"), "PNG")
mb_2x.save(os.path.join(MENUBAR_DIR, "MenuBarIcon@2x.png"), "PNG")

menubar_contents = """{
  "images" : [
    {
      "idiom" : "universal",
      "filename" : "MenuBarIcon.png",
      "scale" : "1x"
    },
    {
      "idiom" : "universal",
      "filename" : "MenuBarIcon@2x.png",
      "scale" : "2x"
    }
  ],
  "info" : {
    "version" : 1,
    "author" : "xcode"
  },
  "properties" : {
    "template-rendering-intent" : "template"
  }
}
"""
with open(os.path.join(MENUBAR_DIR, "Contents.json"), "w") as f:
    f.write(menubar_contents)

# 4. Generate Minimal DMG Background (540x360 @1x and 1080x720 @2x)
def create_dmg_background(scale=1):
    w = 540 * scale
    h = 360 * scale
    img = Image.new("RGBA", (w, h), (245, 245, 247, 255)) # Apple clean light gray
    draw = ImageDraw.Draw(img)

    # Load system font if available, else default
    try:
        font_large = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 28 * scale)
        font_small = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 13 * scale)
    except Exception:
        try:
            font_large = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 28 * scale)
            font_small = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 13 * scale)
        except Exception:
            font_large = ImageFont.load_default()
            font_small = ImageFont.load_default()

    # Center Drag Arrow between left (x=140) and right (x=400), center y=170
    arrow_y = 170 * scale
    arrow_left = 240 * scale
    arrow_right = 300 * scale
    arrow_width = 3 * scale

    # Arrow shaft
    draw.line([arrow_left, arrow_y, arrow_right, arrow_y], fill=(160, 160, 168, 255), width=arrow_width)
    # Arrow head
    head_len = 10 * scale
    draw.line([arrow_right, arrow_y, arrow_right - head_len, arrow_y - head_len], fill=(160, 160, 168, 255), width=arrow_width)
    draw.line([arrow_right, arrow_y, arrow_right - head_len, arrow_y + head_len], fill=(160, 160, 168, 255), width=arrow_width)

    # Footnote at bottom
    footnote = "If macOS warns on first launch: System Settings \u2192 Privacy & Security \u2192 Open Anyway"
    bbox = draw.textbbox((0, 0), footnote, font=font_small)
    text_w = bbox[2] - bbox[0]
    text_x = (w - text_w) // 2
    text_y = 310 * scale

    # Subtle pill container behind footnote
    pad_x = 14 * scale
    pad_y = 6 * scale
    pill_box = [text_x - pad_x, text_y - pad_y, text_x + text_w + pad_x, text_y + (bbox[3] - bbox[1]) + pad_y]
    draw.rounded_rectangle(pill_box, radius=8 * scale, fill=(235, 235, 238, 255), outline=(215, 215, 220, 255), width=1 * scale)

    draw.text((text_x, text_y), footnote, fill=(110, 110, 118, 255), font=font_small)

    return img

dmg_bg_1x = create_dmg_background(1)
dmg_bg_2x = create_dmg_background(2)

dmg_bg_1x.save(os.path.join(DOCS_ASSETS_DIR, "dmg-background.png"), "PNG")
dmg_bg_2x.save(os.path.join(DOCS_ASSETS_DIR, "dmg-background@2x.png"), "PNG")

print("All asset sets generated successfully.")
