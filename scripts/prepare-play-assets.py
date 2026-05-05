#!/usr/bin/env python3
"""prepare-play-assets.py — Play Store 등록 자산 자동 생성.

생성물:
  play-assets/icons/icon-512.png          (512x512 PNG, ≤1MB)
  play-assets/feature/feature-1024x500.png (1024x500, 피처 그래픽)
  play-assets/screenshots-phone/*.png      (1080x1920, 5장)
  play-assets/screenshots-tab7/*.png       (1024x600, 5장)
  play-assets/screenshots-tab10/*.png      (1920x1200, 5장)

소스:
  flutter_app/assets/icons/udi_icon.png (1024x1024)
  docs/screenshots/T-33BECF/mobile-*.png (390x844, 10장)
  docs/screenshots/T-33BECF/desktop-*.png (1668x1142, 10장)
"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent.parent
SRC_ICON = ROOT / "flutter_app/assets/icons/udi_icon.png"
SRC_MOBILE = ROOT / "docs/screenshots/T-33BECF"
OUT = ROOT / "play-assets"

BG_COLOR = (11, 15, 23)        # #0b0f17 (앱 다크 배경)
ACCENT = (31, 201, 232)         # #1FC9E8 (cyan)
ACCENT2 = (27, 150, 255)        # #1B96FF (blue)
TEXT = (226, 232, 240)          # #E2E8F0


def find_font(size):
    candidates = [
        "/usr/share/fonts/truetype/noto/NotoSansCJK-Bold.ttc",
        "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",
        "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    ]
    for c in candidates:
        if Path(c).exists():
            try:
                return ImageFont.truetype(c, size)
            except Exception:
                pass
    return ImageFont.load_default()


def make_icon():
    """512x512 PNG 아이콘."""
    src = Image.open(SRC_ICON).convert("RGBA")
    icon = src.resize((512, 512), Image.LANCZOS)
    out = OUT / "icons/icon-512.png"
    icon.save(out, "PNG", optimize=True)
    print(f"✅ {out} ({icon.size}, {out.stat().st_size//1024}KB)")


def make_feature():
    """1024x500 PNG 피처 그래픽 — 그라데이션 + 로고 + 제목."""
    img = Image.new("RGB", (1024, 500), BG_COLOR)
    draw = ImageDraw.Draw(img)

    # 그라데이션 배경 (좌→우)
    for x in range(1024):
        r = int(11 + (27 - 11) * x / 1024)
        g = int(15 + (150 - 15) * x / 1024)
        b = int(23 + (255 - 23) * (x / 1024) ** 2)
        draw.line([(x, 0), (x, 500)], fill=(r, g, b))

    # 로고 (왼쪽)
    icon = Image.open(SRC_ICON).convert("RGBA").resize((280, 280), Image.LANCZOS)
    img.paste(icon, (60, 110), icon)

    # 제목 (오른쪽)
    title_font = find_font(72)
    sub_font = find_font(28)
    desc_font = find_font(20)

    draw.text((400, 150), "U2DIA", font=title_font, fill=TEXT)
    draw.text((400, 230), "AI Kanban Board", font=sub_font, fill=ACCENT)
    draw.text((400, 285), "에이전트 팀 협업 · 실시간 모니터링", font=desc_font, fill=(150, 200, 220))
    draw.text((400, 320), "Sprint · Code Review · Mobile VSCode", font=desc_font, fill=(150, 200, 220))

    out = OUT / "feature/feature-1024x500.png"
    img.save(out, "PNG", optimize=True)
    print(f"✅ {out} ({img.size}, {out.stat().st_size//1024}KB)")


def fit_to_canvas(src_img, target_size, bg=BG_COLOR):
    """비율 유지하며 캔버스 가운데 배치 (letterbox)."""
    canvas = Image.new("RGB", target_size, bg)
    src_w, src_h = src_img.size
    target_w, target_h = target_size
    scale = min(target_w / src_w, target_h / src_h)
    new_w, new_h = int(src_w * scale), int(src_h * scale)
    resized = src_img.resize((new_w, new_h), Image.LANCZOS)
    if resized.mode == "RGBA":
        canvas.paste(resized, ((target_w - new_w) // 2, (target_h - new_h) // 2), resized)
    else:
        canvas.paste(resized, ((target_w - new_w) // 2, (target_h - new_h) // 2))
    return canvas


def make_phone_screenshots():
    """1080x1920 PNG 폰 스크린샷 (5장)."""
    sources = [
        ("mobile-home.png", "홈 — 프로젝트 개요"),
        ("mobile-teams-board.png", "팀 칸반보드"),
        ("mobile-sprints.png", "Sprint 관리"),
        ("mobile-history.png", "활동 히스토리"),
        ("mobile-archives.png", "아카이브"),
    ]
    for i, (name, _label) in enumerate(sources, 1):
        src_path = SRC_MOBILE / name
        if not src_path.is_file():
            print(f"⚠️ skip {name} (없음)", file=sys.stderr)
            continue
        src = Image.open(src_path).convert("RGB")
        canvas = fit_to_canvas(src, (1080, 1920))
        out = OUT / f"screenshots-phone/phone-{i:02d}.png"
        canvas.save(out, "PNG", optimize=True)
        print(f"✅ {out}")


def make_tablet_screenshots():
    """태블릿 7인치(1024x600) + 10인치(1920x1200) 스크린샷."""
    sources = [
        ("desktop-home.png", "홈"),
        ("desktop-teams-board.png", "팀 보드"),
        ("desktop-sprints.png", "Sprint"),
        ("desktop-history.png", "히스토리"),
        ("desktop-archives.png", "아카이브"),
    ]
    for i, (name, _label) in enumerate(sources, 1):
        src_path = SRC_MOBILE / name
        if not src_path.is_file():
            print(f"⚠️ skip {name}", file=sys.stderr)
            continue
        src = Image.open(src_path).convert("RGB")
        # 7인치 (1024x600 = 16:9.4 ≈ 16:9)
        c7 = fit_to_canvas(src, (1024, 600))
        out7 = OUT / f"screenshots-tab7/tab7-{i:02d}.png"
        c7.save(out7, "PNG", optimize=True)
        print(f"✅ {out7}")
        # 10인치 (1920x1200 = 16:10) — Play 요구 16:9 또는 9:16, 1080~7680
        c10 = fit_to_canvas(src, (1920, 1200))
        out10 = OUT / f"screenshots-tab10/tab10-{i:02d}.png"
        c10.save(out10, "PNG", optimize=True)
        print(f"✅ {out10}")


if __name__ == "__main__":
    print("📦 Play Store 자산 생성 시작\n")
    make_icon()
    make_feature()
    make_phone_screenshots()
    make_tablet_screenshots()
    print("\n🎉 모든 자산 생성 완료 →", OUT)
