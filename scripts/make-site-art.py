#!/usr/bin/env python3
"""Draw the website and README illustrations as SVG.

Writes docs/art/<name>-<lang>.svg for English and Japanese. The drawings
mirror the app's real UI (popover timeline, menubar, notification, start
alert, widget) with text kept as text, so both languages come from one
source and stay sharp at any size. Re-run after changing the UI or copy:

    python3 scripts/make-site-art.py
"""

from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "art"

SANS = ("-apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Helvetica Neue', "
        "'Hiragino Sans', 'Hiragino Kaku Gothic ProN', 'Noto Sans JP', sans-serif")
MONO = "'SF Mono', ui-monospace, Menlo, Monaco, monospace"

INK = "#1d1d1f"
TEXT = "#3a3a3c"
SECONDARY = "#86868b"
TERTIARY = "#b0b0b5"
RAIL = "#e3e3e8"
BLUE = "#0a6cff"
BLUE_TINT = "#eaf2fe"
GREEN = "#28b44c"
PANEL = "#ffffff"
DESKTOP = "#e8e4dc"
APP_GREEN = "#23a06f"

STRINGS = {
    "en": {
        "today": "Today",
        "all_day": "all-day",
        "allday_title": "Launch assets due",
        "run_time": "8:55 AM", "run_title": "Morning run", "run_place": "Riverside Park",
        "now": "9:53 AM",
        "next_time": "10:00 AM", "kicker": "NEXT", "count": "in 7m",
        "next_title": ["Design review: website", "screenshots"],
        "next_meta": "10:00 AM – 10:45 AM · Google Meet · Maya C…",
        "chips": ["Google Doc", "Figma", "PR #12"],
        "join": "Join", "open_notes": "Open notes",
        "gaps": [("45m free", "10:45 AM–11:30 AM"), ("30m free", "12:30 PM–1:00 PM"), ("60m free", "1:30 PM–2:30 PM")],
        "events": [("11:30 AM", "Project work block", "Desk", "#f0a35e"),
                   ("1:00 PM", "Product sync", "Google Meet", "#4caf50"),
                   ("2:30 PM", "Focus: Until copy polish", None, "#e57368")],
        "summary": "5 events · 4h30m booked · longest free 1h",
        "menubar": "in 7m Design review: website screenshots",
        "clock": "Wed Aug 12  9:53 AM",
        "time_col": 64,
        "notif_title": "Design review: website screenshots",
        "notif_body": "Starts at 10:00 AM · Google Meet",
        "notif_when": "now",
        "alert_kicker": "Starts in 7m", "alert_time": "10:00 AM",
        "alert_title": "Design review: website screenshots",
        "alert_meta": "10:00 AM – 10:45 AM · Google Meet",
        "snooze": "Snooze 1 min", "dismiss": "Dismiss",
        "widget_date": "Wed, Aug 12", "widget_count": "7 min", "widget_title": "Design review",
        "widget_range": "10:00 AM–10:45 AM", "widget_more": "+2 more",
    },
    "ja": {
        "today": "今日",
        "all_day": "終日",
        "allday_title": "ローンチ素材の締切",
        "run_time": "8:55", "run_title": "朝のランニング", "run_place": "河川敷の公園",
        "now": "9:53",
        "next_time": "10:00", "kicker": "次の予定", "count": "7m後",
        "next_title": ["デザインレビュー:", "サイトのスクリーンショット"],
        "next_meta": "10:00 – 10:45 · Google Meet · Maya Chen",
        "chips": ["Google Doc", "Figma", "PR #12"],
        "join": "参加", "open_notes": "議事録を開く",
        "gaps": [("45分の空き", "10:45–11:30"), ("30分の空き", "12:30–13:00"), ("60分の空き", "13:30–14:30")],
        "events": [("11:30", "プロジェクト作業", "デスク", "#f0a35e"),
                   ("13:00", "プロダクト定例", "Google Meet", "#4caf50"),
                   ("14:30", "集中: 文言の仕上げ", None, "#e57368")],
        "summary": "予定5件 · 計4h30m · 最長の空き1h",
        "menubar": "7m後 デザインレビュー: サイトのスクショ",
        "clock": "8月12日(水)  9:53",
        "time_col": 44,
        "notif_title": "デザインレビュー: サイトのスクショ",
        "notif_body": "10:00に開始 · Google Meet",
        "notif_when": "今",
        "alert_kicker": "7m後に開始", "alert_time": "10:00",
        "alert_title": "デザインレビュー: サイトのスクショ",
        "alert_meta": "10:00 – 10:45 · Google Meet",
        "snooze": "1分後に再通知", "dismiss": "閉じる",
        "widget_date": "8月12日(水)", "widget_count": "7分", "widget_title": "デザインレビュー",
        "widget_range": "10:00–10:45", "widget_more": "ほか2件",
    },
}


# ---- primitives -------------------------------------------------------------

def text_width(s, size):
    """Rough advance width, enough to size chips and lay out the menubar."""
    width = 0.0
    for ch in s:
        if ord(ch) > 0x2E80:
            width += 1.0
        elif ch in " ·":
            width += 0.3
        elif ch in "il.:,'|!":
            width += 0.28
        elif ch.isupper() or ch in "mwMW":
            width += 0.68
        elif ch.isdigit():
            width += 0.58
        else:
            width += 0.53
    # Real glyphs run a little wider than this table; err on the roomy side.
    return width * size * 1.05


def t(x, y, s, size=13, weight=400, fill=TEXT, anchor="start", family=SANS, extra=""):
    return (f'<text x="{x:g}" y="{y:g}" font-family="{family}" font-size="{size}" '
            f'font-weight="{weight}" fill="{fill}" text-anchor="{anchor}"{extra}>{escape(s)}</text>')


def glyph(x, y, scale, color):
    """The Until mark: a dot and a chevron (BrandIcon geometry, 24pt grid)."""
    return (f'<g transform="translate({x:g} {y:g}) scale({scale:g})">'
            f'<circle cx="7" cy="12" r="2.6" fill="{color}"/>'
            f'<path d="M12.5 7 17.5 12 12.5 17" fill="none" stroke="{color}" stroke-width="2.2" '
            f'stroke-linecap="round" stroke-linejoin="round"/></g>')


def icon_video(x, y, color):
    return (f'<g transform="translate({x:g} {y:g})" fill="{color}">'
            f'<rect x="0" y="1.5" width="10" height="8" rx="2"/><path d="M10.5 4.5 14 2.5v7l-3.5-2z"/></g>')


def icon_doc(x, y, color):
    return (f'<g transform="translate({x:g} {y:g})" fill="none" stroke="{color}" stroke-width="1.1" stroke-linejoin="round">'
            f'<path d="M1 .5h5.5L9.5 3.5v8.5H1z"/><path d="M6.5 .5v3h3M3 6.5h4.5M3 8.8h4.5"/></g>')


def icon_pin(x, y, color):
    return (f'<g transform="translate({x:g} {y:g})" fill="none" stroke="{color}" stroke-width="1.1" stroke-linecap="round">'
            f'<circle cx="4" cy="3.2" r="2.2"/><path d="M4 5.4v5M1 10.5h6"/></g>')


def icon_power(x, y, color):
    return (f'<g transform="translate({x:g} {y:g})" fill="none" stroke="{color}" stroke-width="1.4" stroke-linecap="round">'
            f'<path d="M4.2 3.3a5.2 5.2 0 1 0 5.6 0"/><path d="M7 1v5"/></g>')


def icon_refresh(x, y, color):
    return (f'<g transform="translate({x:g} {y:g})" fill="none" stroke="{color}" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round">'
            f'<path d="M11.5 7A5 5 0 1 1 9.8 3.2"/><path d="M8.3 1.2 10.4 3.4 8.1 5.3"/></g>')


def icon_gear(x, y, color):
    teeth = "".join(
        f'<rect x="6.2" y="0.2" width="1.6" height="3" rx=".6" transform="rotate({a} 7 7)"/>'
        for a in range(0, 360, 45)
    )
    return (f'<g transform="translate({x:g} {y:g})" fill="{color}">{teeth}'
            f'<circle cx="7" cy="7" r="4.6"/><circle cx="7" cy="7" r="2" fill="{PANEL}"/></g>')


def icon_chip(kind, x, y, color):
    if kind == "Figma":
        return (f'<g transform="translate({x:g} {y:g})" fill="none" stroke="{color}" stroke-width="1.1">'
                f'<circle cx="5.5" cy="5.5" r="4.5"/><circle cx="3.6" cy="4.2" r=".7" fill="{color}"/>'
                f'<circle cx="6.8" cy="3.4" r=".7" fill="{color}"/><circle cx="7.6" cy="6.4" r=".7" fill="{color}"/></g>')
    if kind.startswith("PR"):
        return (f'<g transform="translate({x:g} {y:g})" fill="none" stroke="{color}" stroke-width="1.1" stroke-linecap="round">'
                f'<circle cx="2.5" cy="2" r="1.4"/><circle cx="2.5" cy="9.5" r="1.4"/><circle cx="8.5" cy="9.5" r="1.4"/>'
                f'<path d="M2.5 3.4v4.7M8.5 8.1V5.3a2 2 0 0 0-2-2H5"/></g>')
    return icon_doc(x, y - 0.5, color)


def svg(width, height, body, defs=""):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width:g} {height:g}" '
            f'width="{width:g}" height="{height:g}" role="img">\n'
            f'<defs>{defs}</defs>\n{body}\n</svg>\n')


SHADOW = ('<filter id="shadow" x="-20%" y="-20%" width="140%" height="150%">'
          '<feDropShadow dx="0" dy="10" stdDeviation="14" flood-color="#1c1a17" flood-opacity=".18"/></filter>')


# ---- the popover ------------------------------------------------------------

def popover(s, x, y, width, height, arrow_x=None, footer=True):
    """The timeline popover as the app draws it, clipped to `height`."""
    tc = s["time_col"]
    time_right = x + 16 + tc
    rail = time_right + 14
    content = rail + 14
    right = x + width - 16
    parts = []
    parts.append(f'<clipPath id="pop"><rect x="{x}" y="{y}" width="{width}" height="{height}" rx="11"/></clipPath>')
    parts.append(f'<g filter="url(#shadow)">')
    if arrow_x is not None:
        parts.append(f'<path d="M{arrow_x - 11} {y + 1} L{arrow_x} {y - 10} L{arrow_x + 11} {y + 1} Z" fill="{PANEL}"/>')
    parts.append(f'<rect x="{x}" y="{y}" width="{width}" height="{height}" rx="11" fill="{PANEL}"/></g>')
    parts.append('<g clip-path="url(#pop)">')

    cy = y + 26
    parts.append(t(x + 16, cy, s["today"], 11.5, 700, TERTIARY))
    cy += 22

    def time_label(yy, label, color=SECONDARY, weight=400):
        return t(time_right, yy, label, 11, weight, color, "end", MONO)

    def rail_segment(y1, y2, dashed=False):
        dash = ' stroke-dasharray="3 3"' if dashed else ""
        return f'<line x1="{rail}" y1="{y1}" x2="{rail}" y2="{y2}" stroke="{RAIL}" stroke-width="2"{dash}/>'

    # all-day
    parts.append(rail_segment(cy - 12, cy + 8))
    parts.append(time_label(cy, s["all_day"]))
    parts.append(f'<circle cx="{rail}" cy="{cy - 4}" r="3.6" fill="#5b8def"/>')
    parts.append(t(content, cy, s["allday_title"], 13.5, 400, TEXT))
    cy += 30

    # finished event
    parts.append(rail_segment(cy - 14, cy + 22))
    parts.append(time_label(cy, s["run_time"], TERTIARY))
    parts.append(f'<circle cx="{rail}" cy="{cy - 4}" r="4.6" fill="#c9d7f4"/><circle cx="{rail}" cy="{cy - 4}" r="3" fill="#9db6e8"/>')
    parts.append(t(content, cy, s["run_title"], 13.5, 400, TERTIARY,
                   extra=' text-decoration="line-through"'))
    parts.append(icon_pin(content, cy + 8, TERTIARY))
    parts.append(t(content + 13, cy + 17, s["run_place"], 11.5, 400, TERTIARY))
    cy += 38

    # now line
    parts.append(time_label(cy, s["now"], GREEN, 700))
    parts.append(f'<line x1="{rail}" y1="{cy - 4}" x2="{right}" y2="{cy - 4}" stroke="{GREEN}" stroke-width="2" stroke-linecap="round"/>')
    parts.append(f'<circle cx="{rail}" cy="{cy - 4}" r="4" fill="{GREEN}"/>')
    cy += 24

    # next card
    card_top = cy - 14
    card_h = 150
    parts.append(rail_segment(card_top + 10, card_top + card_h + 4))
    parts.append(time_label(cy, s["next_time"], BLUE, 700))
    parts.append(f'<circle cx="{rail}" cy="{cy - 4}" r="6" fill="{BLUE}"/>')
    parts.append(f'<rect x="{content - 2}" y="{card_top}" width="{right - content + 2}" height="{card_h}" rx="10" fill="{BLUE_TINT}"/>')
    ix = content + 10
    parts.append(t(ix, card_top + 22, s["kicker"], 10.5, 800, BLUE, extra=' letter-spacing=".8"'))
    parts.append(t(right - 10, card_top + 22, s["count"], 12.5, 700, BLUE, "end"))
    ty = card_top + 44
    for line in s["next_title"]:
        parts.append(t(ix, ty, line, 15.5, 700, INK))
        ty += 19
    parts.append(t(ix, ty + 1, s["next_meta"], 11, 400, SECONDARY))
    chip_y = ty + 9
    cx = ix
    for chip in s["chips"]:
        w = text_width(chip, 11) + 34
        parts.append(f'<rect x="{cx:g}" y="{chip_y}" width="{w:g}" height="19" rx="9.5" fill="#1d1d1f" fill-opacity=".06"/>')
        parts.append(icon_chip(chip, cx + 8, chip_y + 4, TEXT))
        parts.append(t(cx + 23, chip_y + 13.5, chip, 11, 500, TEXT))
        cx += w + 6
    by = chip_y + 27
    join_w = text_width(s["join"], 12.5) + 42
    parts.append(f'<rect x="{ix}" y="{by}" width="{join_w:g}" height="24" rx="6" fill="{BLUE}"/>')
    parts.append(icon_video(ix + 11, by + 6.5, "#ffffff"))
    parts.append(t(ix + 31, by + 16.5, s["join"], 12.5, 600, "#ffffff"))
    nx = ix + join_w + 14
    parts.append(icon_doc(nx, by + 6, SECONDARY))
    parts.append(t(nx + 16, by + 16.5, s["open_notes"], 12.5, 500, SECONDARY))
    cy = card_top + card_h + 26

    # free gaps and later events
    for (gap_label, gap_range), (etime, etitle, esub, ecolor) in zip(s["gaps"], s["events"]):
        parts.append(rail_segment(cy - 18, cy + 8, dashed=True))
        parts.append(t(content, cy, gap_label, 10.5, 600, SECONDARY))
        parts.append(t(content + text_width(gap_label, 10.5) + 10, cy, gap_range, 10.5, 400, TERTIARY))
        cy += 30
        extra_h = 18 if esub else 0
        parts.append(rail_segment(cy - 16, cy + 10 + extra_h))
        parts.append(time_label(cy, etime))
        parts.append(f'<circle cx="{rail}" cy="{cy - 4}" r="3.6" fill="{ecolor}"/>')
        parts.append(t(content, cy, etitle, 13.5, 400, TEXT))
        if esub:
            parts.append(icon_pin(content, cy + 8, SECONDARY))
            parts.append(t(content + 13, cy + 17, esub, 11.5, 400, SECONDARY))
        cy += 30 + extra_h
    parts.append("</g>")

    if footer:
        fy = y + height - 38
        parts.append(f'<rect x="{x}" y="{fy}" width="{width}" height="38" fill="{PANEL}" clip-path="url(#pop)"/>')
        parts.append(f'<line x1="{x}" y1="{fy}" x2="{x + width}" y2="{fy}" stroke="#e5e5ea"/>')
        parts.append(icon_power(x + 14, fy + 12, SECONDARY))
        parts.append(t(x + 36, fy + 23, s["summary"], 11, 400, SECONDARY))
        parts.append(icon_refresh(right - 36, fy + 12, SECONDARY))
        parts.append(icon_gear(right - 12, fy + 12, SECONDARY))
    return "\n".join(parts)


# ---- drawings ---------------------------------------------------------------

def hero(s):
    w, h = 726, 402
    parts = [f'<rect width="{w}" height="{h}" fill="{DESKTOP}"/>',
             f'<rect width="{w}" height="25" fill="#f4f1ec"/>',
             f'<line x1="0" y1="25" x2="{w}" y2="25" stroke="#1d1d1f" stroke-opacity=".06"/>']
    clock_end = w - 12
    parts.append(t(clock_end, 17, s["clock"], 13, 500, INK, "end"))
    clock_start = clock_end - text_width(s["clock"], 13)
    cc = clock_start - 20
    parts.append(f'<g transform="translate({cc - 7} 7)" fill="none" stroke="{INK}" stroke-width="1.3">'
                 f'<rect x="0" y="0" width="14" height="5" rx="2.5"/><rect x="0" y="7" width="14" height="5" rx="2.5"/>'
                 f'<circle cx="10.5" cy="2.5" r="1.3" fill="{INK}"/><circle cx="3.5" cy="9.5" r="1.3" fill="{INK}"/></g>')
    search = cc - 28
    parts.append(f'<g transform="translate({search - 6} 6)" fill="none" stroke="{INK}" stroke-width="1.5" stroke-linecap="round">'
                 f'<circle cx="5" cy="5" r="4"/><path d="M8 8l3.5 3.5"/></g>')
    item_end = search - 24
    item_text_w = text_width(s["menubar"], 13)
    item_start = item_end - item_text_w - 20
    parts.append(glyph(item_start - 2, 3, 0.8, INK))
    parts.append(t(item_start + 18, 17, s["menubar"], 13, 500, INK))
    arrow_x = (item_start + item_end) / 2
    pop_w = 390
    pop_x = max(12, min(w - pop_w - 12, arrow_x - pop_w / 2))
    parts.append(popover(s, pop_x, 36, pop_w, 520, arrow_x=arrow_x, footer=False))
    return svg(w, h, "\n".join(parts), SHADOW)


def timeline(s):
    w, h = 422, 590
    body = popover(s, 16, 26, 390, 548, arrow_x=211)
    return svg(w, h, body, SHADOW)


def notification(s):
    w, h = 372, 92
    parts = [f'<g filter="url(#shadow)"><rect x="8" y="6" width="{w - 16}" height="72" rx="18" fill="#f2f2f2"/></g>',
             f'<rect x="8.5" y="6.5" width="{w - 17}" height="71" rx="17.5" fill="none" stroke="#1d1d1f" stroke-opacity=".08"/>',
             f'<rect x="22" y="22" width="40" height="40" rx="10" fill="{APP_GREEN}"/>',
             glyph(26, 26, 1.33, "#ffffff"),
             t(74, 38, s["notif_title"], 13.5, 700, INK),
             t(74, 56, s["notif_body"], 13, 400, TEXT),
             t(w - 24, 38, s["notif_when"], 11.5, 400, SECONDARY, "end")]
    return svg(w, h, "\n".join(parts), SHADOW)


def start_alert(s):
    w, h = 404, 156
    x, y, cw, ch = 12, 8, 380, 128
    parts = [f'<g filter="url(#shadow)"><rect x="{x}" y="{y}" width="{cw}" height="{ch}" rx="14" fill="{PANEL}"/></g>',
             f'<rect x="{x + .5}" y="{y + .5}" width="{cw - 1}" height="{ch - 1}" rx="13.5" fill="none" stroke="#1d1d1f" stroke-opacity=".08"/>',
             t(x + 16, y + 26, s["alert_kicker"], 11.5, 700, BLUE),
             t(x + cw - 16, y + 26, s["alert_time"], 11.5, 700, BLUE, "end"),
             t(x + 16, y + 50, s["alert_title"], 16, 700, INK),
             t(x + 16, y + 69, s["alert_meta"], 11.5, 400, SECONDARY)]
    by = y + 84
    bx = x + 16
    join_w = text_width(s["join"], 13) + 44
    parts.append(f'<rect x="{bx}" y="{by}" width="{join_w:g}" height="28" rx="7" fill="{BLUE}"/>')
    parts.append(icon_video(bx + 12, by + 8.5, "#ffffff"))
    parts.append(t(bx + 33, by + 18.5, s["join"], 13, 600, "#ffffff"))
    bx += join_w + 8
    for label in (s["snooze"], s["dismiss"]):
        bw = text_width(label, 13) + 26
        parts.append(f'<rect x="{bx:g}" y="{by}" width="{bw:g}" height="28" rx="7" fill="#1d1d1f" fill-opacity=".08"/>')
        parts.append(t(bx + 13, by + 18.5, label, 13, 600, INK))
        bx += bw + 8
    return svg(w, h, "\n".join(parts), SHADOW)


def widget(s):
    w, h = 344, 164
    tc = s["time_col"]
    time_right = 12 + tc
    rail = time_right + 12
    content = rail + 12
    right = w - 12
    parts = [f'<rect width="{w}" height="{h}" rx="22" fill="{PANEL}"/>',
             t(12, 20, s["today"], 11.5, 700, SECONDARY),
             t(right, 20, s["widget_date"], 11, 500, SECONDARY, "end"),
             f'<line x1="{rail}" y1="28" x2="{rail}" y2="136" stroke="{RAIL}" stroke-width="1.5"/>',
             t(time_right, 39, s["all_day"], 10.5, 400, SECONDARY, "end", MONO),
             f'<circle cx="{rail}" cy="35" r="3.3" fill="#5b8def"/>',
             t(content, 39, s["allday_title"], 12.5, 400, INK),
             t(time_right, 55, s["now"], 10.5, 700, GREEN, "end", MONO),
             f'<line x1="{rail}" y1="51" x2="{right}" y2="51" stroke="{GREEN}" stroke-width="2" stroke-linecap="round"/>',
             f'<circle cx="{rail}" cy="51" r="3.6" fill="{GREEN}"/>',
             t(time_right, 74, s["next_time"], 10.5, 700, BLUE, "end", MONO),
             f'<circle cx="{rail}" cy="88" r="5.5" fill="{BLUE}"/>',
             f'<rect x="{content - 2}" y="59" width="{right - content + 2}" height="56" rx="9" fill="{BLUE_TINT}"/>',
             t(content + 8, 75, s["kicker"], 10, 800, BLUE, extra=' letter-spacing=".7"'),
             t(right - 8, 75, s["widget_count"], 10.5, 700, BLUE, "end"),
             t(content + 8, 93, s["widget_title"], 14, 700, INK),
             t(content + 8, 108, s["widget_range"], 10.5, 400, SECONDARY),
             t(time_right, 131, s["events"][0][0], 10.5, 400, SECONDARY, "end", MONO),
             f'<circle cx="{rail}" cy="127" r="3.3" fill="{s["events"][0][3]}"/>',
             t(content, 131, s["events"][0][1], 12.5, 400, INK),
             t(content, 150, s["widget_more"], 10.5, 500, SECONDARY)]
    return svg(w, h, "\n".join(parts))


DRAWINGS = {
    "hero": hero,
    "timeline": timeline,
    "notification": notification,
    "start-alert": start_alert,
    "widget": widget,
}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for lang, strings in STRINGS.items():
        for name, draw in DRAWINGS.items():
            path = OUT / f"{name}-{lang}.svg"
            path.write_text(draw(strings), encoding="utf-8")
            print(path.relative_to(ROOT))


if __name__ == "__main__":
    main()
