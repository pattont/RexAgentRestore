#!/usr/bin/env python3
"""Draw the README images as SVG, in Rex's light and dark looks.

Run from anywhere: python3 .github/assets/make-images.py
Writes hero-{light,dark}.svg and restart-{light,dark}.svg next to this file.
"""
from pathlib import Path
from xml.sax.saxutils import escape

OUT = Path(__file__).resolve().parent

SANS = "-apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Segoe UI', 'Helvetica Neue', Arial, sans-serif"
MONO = "'SF Mono', ui-monospace, SFMono-Regular, Menlo, Consolas, 'DejaVu Sans Mono', monospace"

THEMES = {
    "light": dict(
        win_top="#F3E9F2", win_bottom="#EEE2C9", win_stroke="#D9CFD6",
        pane="#FFFFFF", pane_dim="#F7F6F5", pane_stroke="#E4E0E2",
        tabgroup="#000000", tabgroup_op="0.045", tab_active="#FFFFFF",
        chrome_fg="#2A2D35", chrome_dim="#6E7076", icon="#8A8C91",
        fg="#272D35", dim="#7A7C81", faint="#B4B6BA",
        blue="#2F6FD6", green="#3E8E3A", red="#CF4B57", orange="#B7791F",
        purple="#8F63D2", teal="#2F8AA3", claude="#C2643F",
        add_bg="#E4F3E2", del_bg="#FBE5E7", box="#C9CBCF",
        label="#1F2328", label_dim="#59636E", shadow="0.16",
    ),
    "dark": dict(
        win_top="#1F1F2D", win_bottom="#1B1B28", win_stroke="#33354A",
        pane="#252636", pane_dim="#222331", pane_stroke="#323447",
        tabgroup="#FFFFFF", tabgroup_op="0.05", tab_active="#34364A",
        chrome_fg="#D5D8E5", chrome_dim="#8E92AA", icon="#8E92AA",
        fg="#C9CEDD", dim="#7C819B", faint="#4C5068",
        blue="#7AA2F7", green="#9ECE6A", red="#F7768E", orange="#E0AF68",
        purple="#BB9AF7", teal="#7DCFFF", claude="#E08A65",
        add_bg="#253328", del_bg="#3A2630", box="#4C5068",
        label="#E6EDF3", label_dim="#9198A1", shadow="0.5",
    ),
}


def t(x, y, s, fill, size, family=SANS, weight=400, anchor="start", extra=""):
    return (f'<text x="{x}" y="{y}" fill="{fill}" font-family="{family}" font-size="{size}" '
            f'font-weight="{weight}" text-anchor="{anchor}"{extra}>{escape(s)}</text>')


# ---------- icons (drawn, so they don't depend on fonts) ----------

def icon(kind, x, y, c, s=14):
    """Small program icon with its top-left corner at x, y."""
    cx, cy, r = x + s / 2, y + s / 2, s / 2
    if kind == "claude":  # eight-armed spark
        arms = []
        for i in range(8):
            import math
            a = math.pi * i / 4
            ln = r * (0.95 if i % 2 == 0 else 0.7)
            arms.append(f'<line x1="{cx:.1f}" y1="{cy:.1f}" x2="{cx + ln * math.cos(a):.1f}" '
                        f'y2="{cy + ln * math.sin(a):.1f}"/>')
        return f'<g stroke="{c["claude"]}" stroke-width="1.9" stroke-linecap="round">{"".join(arms)}</g>'
    if kind == "codex":  # rounded hexagon
        import math
        pts = " ".join(f"{cx + r * 0.92 * math.cos(math.pi / 6 + i * math.pi / 3):.1f},"
                       f"{cy + r * 0.92 * math.sin(math.pi / 6 + i * math.pi / 3):.1f}" for i in range(6))
        return (f'<polygon points="{pts}" fill="none" stroke="{c["chrome_fg"]}" stroke-width="1.5" '
                f'stroke-linejoin="round"/><circle cx="{cx}" cy="{cy}" r="1.8" fill="{c["chrome_fg"]}"/>')
    if kind == "opencode":  # square in a square
        return (f'<rect x="{x + 1}" y="{y + 1}" width="{s - 2}" height="{s - 2}" rx="2.5" fill="none" '
                f'stroke="{c["chrome_fg"]}" stroke-width="1.5"/>'
                f'<rect x="{x + 4.5}" y="{y + 4.5}" width="{s - 9}" height="{s - 9}" rx="1" fill="{c["chrome_fg"]}"/>')
    if kind == "shell":  # dark tile with a prompt
        return (f'<rect x="{x}" y="{y}" width="{s}" height="{s}" rx="3.5" fill="#24262C"/>'
                f'<path d="M{x + 3.5} {y + 4.5} l3 2.5 l-3 2.5" fill="none" stroke="#E8E8E8" '
                f'stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round"/>'
                f'<line x1="{x + 7.5}" y1="{y + 10}" x2="{x + 10.5}" y2="{y + 10}" stroke="#E8E8E8" '
                f'stroke-width="1.3" stroke-linecap="round"/>')
    if kind == "node":
        import math
        pts = " ".join(f"{cx + r * math.cos(math.pi / 2 + i * math.pi / 3):.1f},"
                       f"{cy + r * math.sin(math.pi / 2 + i * math.pi / 3):.1f}" for i in range(6))
        return f'<polygon points="{pts}" fill="{c["chrome_dim"]}"/>'
    raise ValueError(kind)


def host_icon(x, y, c):
    return (f'<rect x="{x}" y="{y}" width="16" height="10" rx="2" fill="none" stroke="{c["chrome_dim"]}" stroke-width="1.3"/>'
            f'<line x1="{x + 3.5}" y1="{y + 5}" x2="{x + 8}" y2="{y + 5}" stroke="{c["chrome_dim"]}" stroke-width="1.3"/>')


def pane_buttons(x, y, c):
    """Split right, split down, zoom, close: the controls on a focused pane."""
    k = c["icon"]
    g = f'<g fill="none" stroke="{k}" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round">'
    g += f'<rect x="{x}" y="{y}" width="13" height="11" rx="2"/><line x1="{x + 6.5}" y1="{y}" x2="{x + 6.5}" y2="{y + 11}"/>'
    x += 24
    g += f'<rect x="{x}" y="{y}" width="13" height="11" rx="2"/><line x1="{x}" y1="{y + 5.5}" x2="{x + 13}" y2="{y + 5.5}"/>'
    x += 24
    g += (f'<path d="M{x + 8} {y} h4 v4 M{x + 12} {y} l-4.5 4.5 M{x + 1} {y + 11} h4 M{x + 1} {y + 11} v-4 '
          f'M{x + 1} {y + 11} l4.5 -4.5"/>')
    x += 24
    g += f'<path d="M{x + 1} {y} l10 10 M{x + 11} {y} l-10 10"/>'
    return g + "</g>"


# ---------- terminal text ----------

def term_lines(lines, x, y, c, fs, lh, width):
    """lines: list of rows; a row is a list of (text, style) or a dict for special rows.

    style is a colour key, optionally with "+b" for bold.
    """
    out = []
    cw = fs * 0.6
    lines = wrap(lines, max(10, int(width / cw)))
    for i, row in enumerate(lines):
        ly = y + i * lh
        if isinstance(row, dict):
            kind = row["kind"]
            if kind == "box":  # an agent's input box with a cursor
                out.append(f'<rect x="{x}" y="{ly - fs + 1}" width="{width}" height="{lh + 10}" rx="5" '
                           f'fill="none" stroke="{c["box"]}"/>')
                out.append(_spans(row["text"], x + 10, ly + 5, c, fs))
                n = sum(len(s) for s, _ in row["text"])
                out.append(f'<rect x="{x + 11 + n * cw:.1f}" y="{ly - fs + 5}" width="{cw:.1f}" height="{fs + 2}" fill="{c["fg"]}"/>')
            continue
        bg = None
        if row and row[0][1] in ("add", "del"):
            bg = c["add_bg"] if row[0][1] == "add" else c["del_bg"]
            out.append(f'<rect x="{x - 4}" y="{ly - fs + 1}" width="{width + 8}" height="{lh}" fill="{bg}"/>')
            row = [(s, "green" if st == "add" else "red") for s, st in row]
        cursor = row and row[-1][1] == "cursor"
        if cursor:
            row = row[:-1]
        out.append(_spans(row, x, ly, c, fs))
        if cursor:
            n = sum(len(s) for s, _ in row)
            out.append(f'<rect x="{x + n * cw:.1f}" y="{ly - fs + 2}" width="{cw:.1f}" height="{fs + 2}" fill="{c["fg"]}"/>')
    return "\n".join(out)


def wrap(lines, cols):
    """Wrap long rows at the pane's width, breaking between words."""
    out = []
    for row in lines:
        if isinstance(row, dict) or not row or row[0][1] in ("add", "del"):
            out.append(row)
            continue
        chars = [(ch, st) for text, st in row for ch in text]
        tail = [("", "cursor")] if row[-1][1] == "cursor" else []
        while len(chars) > cols:
            cut = max((i for i in range(1, cols + 1) if chars[i - 1][0] == " "), default=cols)
            out.append(_group(chars[:cut]))
            chars = chars[cut:]
        out.append(_group(chars) + tail)
    return out


def _group(chars):
    row = []
    for ch, st in chars:
        if row and row[-1][1] == st:
            row[-1] = (row[-1][0] + ch, st)
        else:
            row.append((ch, st))
    return row


def _spans(row, x, y, c, fs):
    parts = []
    for s, style in row:
        bold = style.endswith("+b")
        key = style.removesuffix("+b")
        w = ' font-weight="700"' if bold else ""
        parts.append(f'<tspan fill="{c[key]}"{w}>{escape(s)}</tspan>')
    return (f'<text x="{x}" y="{y}" font-family="{MONO}" font-size="{fs}" xml:space="preserve">'
            + "".join(parts) + "</text>")


# ---------- the Rex window ----------

def window(x, y, w, h, c, uid, session, host, tabs, panes, fs=12.5, lh=18.5, compact=False):
    """Draw a Rex window.

    tabs: list of (icon, title); the first is the active tab.
    panes: list of dicts with rel box (px, py, pw, ph as fractions), icon, title, lines, focused.
    """
    bar = 40 if compact else 46
    o = [f'<g transform="translate({x} {y})">']
    o.append(f'<rect width="{w}" height="{h}" rx="12" fill="url(#win-{uid})" stroke="{c["win_stroke"]}" filter="url(#shadow-{uid})"/>')
    # traffic lights
    for i, col in enumerate(("#FF5F57", "#FEBC2E", "#28C840")):
        o.append(f'<circle cx="{20 + i * 20}" cy="{bar / 2}" r="6" fill="{col}"/>')
    # session chip
    hx = 92
    o.append(host_icon(hx, bar / 2 - 9, c))
    o.append(t(hx + 24, bar / 2 - 1, session, c["chrome_fg"], 12.5, weight=600))
    o.append(t(hx + 24, bar / 2 + 12, host, c["chrome_dim"], 10.5))
    # tabs
    tx = hx + 24 + max(len(session) * 7.6, len(host) * 6) + 22
    tab_h = 30 if not compact else 26
    ty = (bar - tab_h) / 2
    widths = [min(230, 46 + len(title) * 7.2) for _, title in tabs]
    if len(tabs) > 1:
        gw = sum(widths[1:]) + 8 * (len(tabs) - 1)
        o.append(f'<rect x="{tx + widths[0] - 6}" y="{ty}" width="{gw + 12}" height="{tab_h}" rx="10" '
                 f'fill="{c["tabgroup"]}" fill-opacity="{c["tabgroup_op"]}"/>')
    cx = tx
    for i, ((ic, title), tw) in enumerate(zip(tabs, widths)):
        if i == 0:
            o.append(f'<rect x="{cx}" y="{ty}" width="{tw}" height="{tab_h}" rx="10" fill="{c["tab_active"]}" filter="url(#tabshadow-{uid})"/>')
        else:
            if i > 1:
                o.append(f'<line x1="{cx - 4}" y1="{ty + 8}" x2="{cx - 4}" y2="{ty + tab_h - 8}" stroke="{c["chrome_dim"]}" stroke-opacity="0.4"/>')
        o.append(icon(ic, cx + 12, ty + tab_h / 2 - 7, c))
        col = c["chrome_fg"] if i == 0 else c["chrome_dim"]
        o.append(f'<clipPath id="tabclip-{uid}-{i}"><rect x="{cx}" y="{ty}" width="{tw - 10}" height="{tab_h}"/></clipPath>')
        o.append(f'<g clip-path="url(#tabclip-{uid}-{i})">' + t(cx + 34, ty + tab_h / 2 + 4.5, title, col, 13, weight=500 if i == 0 else 400) + "</g>")
        cx += tw + 8
    # right-side controls: command palette and new tab
    k = c["icon"]
    o.append(t(w - 54, bar / 2 + 6, "⌘", k, 17, anchor="middle"))
    o.append(f'<path d="M{w - 26} {bar / 2 - 7} v14 M{w - 33} {bar / 2} h14" stroke="{k}" stroke-width="1.6" stroke-linecap="round"/>')

    # panes
    m, gap = 8, 8
    ax, ay, aw, ah = m, bar, w - 2 * m, h - bar - m
    hh = 30 if compact else 34
    for j, p in enumerate(panes):
        px, py, pw, ph = p["box"]
        X = ax + px * aw + (gap / 2 if px > 0 else 0)
        Y = ay + py * ah + (gap / 2 if py > 0 else 0)
        W = pw * aw - (gap / 2 if px > 0 else 0) - (gap / 2 if px + pw < 1 else 0)
        H = ph * ah - (gap / 2 if py > 0 else 0) - (gap / 2 if py + ph < 1 else 0)
        fill = c["pane"] if p.get("focused") else c["pane_dim"]
        filt = f' filter="url(#paneshadow-{uid})"' if p.get("focused") else ""
        o.append(f'<rect x="{X:.1f}" y="{Y:.1f}" width="{W:.1f}" height="{H:.1f}" rx="10" fill="{fill}" stroke="{c["pane_stroke"]}"{filt}/>')
        o.append(f'<clipPath id="pc-{uid}-{j}"><rect x="{X:.1f}" y="{Y:.1f}" width="{W - 6:.1f}" height="{H - 4:.1f}" rx="10"/></clipPath>')
        o.append(f'<g clip-path="url(#pc-{uid}-{j})">')
        o.append(icon(p["icon"], X + 14, Y + hh / 2 - 7, c))
        title = p["title"]
        o.append(f'<text x="{X + 36:.1f}" y="{Y + hh / 2 + 4.5:.1f}" font-family="{SANS}" font-size="{12.5 if compact else 13}" '
                 f'font-weight="600" fill="{c["chrome_fg"]}">{escape(title[0])}'
                 f'<tspan font-weight="400" fill="{c["chrome_dim"]}">{escape(title[1])}</tspan></text>')
        if p.get("focused") and not compact:
            o.append(pane_buttons(X + W - 108, Y + hh / 2 - 5.5, c))
        o.append(term_lines(p["lines"], X + 16, Y + hh + fs + 6, c, fs, lh, W - 32))
        o.append("</g>")
    o.append("</g>")
    return "\n".join(o)


def defs(c, uid):
    return f'''<linearGradient id="win-{uid}" x1="0" y1="0" x2="0.35" y2="1">
  <stop offset="0" stop-color="{c["win_top"]}"/><stop offset="1" stop-color="{c["win_bottom"]}"/>
</linearGradient>
<filter id="shadow-{uid}" x="-10%" y="-10%" width="120%" height="130%">
  <feDropShadow dx="0" dy="10" stdDeviation="12" flood-color="#000" flood-opacity="{c["shadow"]}"/>
</filter>
<filter id="tabshadow-{uid}" x="-10%" y="-30%" width="120%" height="170%">
  <feDropShadow dx="0" dy="1" stdDeviation="1.5" flood-color="#000" flood-opacity="0.14"/>
</filter>
<filter id="paneshadow-{uid}" x="-5%" y="-5%" width="110%" height="115%">
  <feDropShadow dx="0" dy="2" stdDeviation="4" flood-color="#000" flood-opacity="0.08"/>
</filter>'''


# ---------- content ----------

def restored(agent, chat, folder):
    return [("rex-agent-restore: resuming ", "dim"), (agent, "dim"), (f" chat {chat} in {folder}", "dim")]


CLAUDE = [
    restored("claude", "3f9a2c1e", "~/api"),
    [],
    [("> ", "dim"), ("refactor session auth to use rotating refresh tokens", "fg")],
    [],
    [("● ", "green"), ("Read", "fg+b"), (" 12 files", "dim")],
    [],
    [("● ", "green"), ("Update", "fg+b"), ("(src/auth/session.ts)", "fg")],
    [("  └ ", "dim"), ("Updated with 48 additions and 31 removals", "dim")],
    [("    88 -   const token = sign(user.id, { expiresIn: '30d' })", "del")],
    [("    88 +   const token = await rotate(session, { ttl: '15m' })", "add")],
    [("    89 +   await revoke(session.previousToken)", "add")],
    [],
    [("● ", "green"), ("Bash", "fg+b"), ("(npm test -- auth)", "fg")],
    [("  └ ", "dim"), ("✓ 38 passed", "green"), (" (2.1s)", "dim")],
    [],
    [("● ", "fg"), ("Sessions now rotate their refresh token on every use, and", "fg")],
    [("  ", "fg"), ("the old token is revoked right away. All 38 auth tests pass.", "fg")],
    [],
    [("✻ ", "claude"), ("Writing the migration for existing sessions…", "claude")],
    [],
    {"kind": "box", "text": [("> ", "dim"), ("also log a warning when a revoked token is used", "fg")]},
    [],
    [],
    [("  ⏵⏵ accept edits on", "purple"), (" (shift+tab to cycle)", "dim")],
]

CODEX = [
    restored("codex", "7b21e0d4", "~/api"),
    [],
    [("› ", "dim"), ("add tests for the token parser", "fg")],
    [],
    [("• ", "dim"), ("Ran ", "fg+b"), ("pytest tests/parser -q", "blue")],
    [("  └ ", "dim"), ("42 passed", "green"), (" in 1.84s", "dim")],
    [("• ", "dim"), ("Added 6 cases for expired and malformed tokens.", "fg")],
    [],
    [("› ", "fg+b"), ("", "cursor")],
    [("  82% context left · ? for shortcuts", "dim")],
]

OPENCODE = [
    restored("opencode", "ses_9c4f", "~/web"),
    [],
    [("┃ ", "teal"), ("fix the flaky login test in CI", "fg")],
    [],
    [("→ ", "dim"), ("Read ", "fg"), ("e2e/login.spec.ts", "dim")],
    [("← ", "dim"), ("Edit ", "fg"), ("e2e/login.spec.ts", "dim")],
    [("$ ", "dim"), ("npx playwright test login --repeat-each=20", "fg")],
    [("  20 passed", "green"), (" (31.4s)", "dim")],
    [],
    [("┃ ", "teal"), ("", "cursor")],
    [("  Build", "teal+b"), ("  ·  ctrl+p commands", "dim")],
]


def hero(theme):
    c = THEMES[theme]
    W, H = 1280, 650
    panes = [
        dict(box=(0, 0, 0.55, 1), icon="claude", title=("Refactor session auth", "  ~/api"), lines=CLAUDE, focused=True),
        dict(box=(0.55, 0, 0.45, 0.5), icon="codex", title=("Add token parser tests", "  ~/api"), lines=CODEX),
        dict(box=(0.55, 0.5, 0.45, 0.5), icon="opencode", title=("Fix flaky login test", "  ~/web"), lines=OPENCODE),
    ]
    tabs = [("claude", "Refactor session auth"), ("node", "Node ~/web"), ("shell", "zsh ~/infra")]
    body = window(24, 14, W - 48, H - 50, c, "h", "api", "This Mac", tabs, panes)
    return svg(W, H, defs(c, "h"), body,
               "Rex Agent Restore",
               "A Rex window after a restart. Claude Code, Codex and OpenCode each resumed their chat in "
               "their own pane, under a line reading 'rex-agent-restore: resuming ... chat'.")


def restart(theme):
    c = THEMES[theme]
    W, H = 1280, 536
    fs, lh = 11, 16
    fresh = lambda folder: [
        [("Last login: Fri Nov 7 09:12", "dim")],
        [(f"{folder} ", "blue"), ("❯ ", "green"), ("", "cursor")],
    ]
    left = [
        dict(box=(0, 0, 0.55, 1), icon="shell", title=("zsh", "  ~/api"), lines=fresh("~/api"), focused=True),
        dict(box=(0.55, 0, 0.45, 0.5), icon="shell", title=("zsh", "  ~/api"), lines=fresh("~/api")),
        dict(box=(0.55, 0.5, 0.45, 0.5), icon="shell", title=("zsh", "  ~/web"), lines=fresh("~/web")),
    ]
    right = [
        dict(box=(0, 0, 0.55, 1), icon="claude", title=("Refactor session auth", ""), focused=True, lines=[
            restored("claude", "3f9a2c1e", "~/api"), [],
            [("> ", "dim"), ("refactor session auth to use rotating refresh tokens", "fg")], [],
            [("● ", "green"), ("Read", "fg+b"), (" 12 files", "dim")],
            [("● ", "green"), ("Update", "fg+b"), ("(src/auth/session.ts)", "fg")],
            [("  └ ", "dim"), ("+48", "green"), (" ", "dim"), ("-31", "red")],
            [("● ", "green"), ("Bash", "fg+b"), ("(npm test -- auth)", "fg")],
            [("  └ ", "dim"), ("✓ 38 passed", "green")], [],
            [("● ", "fg"), ("Sessions now rotate their refresh token on every use. All 38 auth tests pass.", "fg")], [],
            [("✻ ", "claude"), ("Writing the migration…", "claude")],
        ]),
        dict(box=(0.55, 0, 0.45, 0.5), icon="codex", title=("Add token parser tests", ""), lines=[
            restored("codex", "7b21e0d4", "~/api"), [],
            [("› ", "dim"), ("add tests for the token parser", "fg")], [],
            [("• ", "dim"), ("Ran ", "fg+b"), ("pytest tests/parser", "blue")],
            [("  └ ", "dim"), ("42 passed", "green"), (" in 1.84s", "dim")],
        ]),
        dict(box=(0.55, 0.5, 0.45, 0.5), icon="opencode", title=("Fix flaky login test", ""), lines=[
            restored("opencode", "ses_9c4f", "~/web"), [],
            [("┃ ", "teal"), ("fix the flaky login test in CI", "fg")], [],
            [("$ ", "dim"), ("npx playwright test login", "fg")],
            [("  20 passed", "green"), (" (31.4s)", "dim")],
        ]),
    ]
    ww, wh, top = 596, 410, 92
    body = []
    for i, (label, sub, mark, col, panes, tab) in enumerate([
        ("Without Rex Agent Restore", "Rex brings back your panes, but each one is a new shell.", "✕", c["red"], left,
         ("shell", "zsh ~/api")),
        ("With Rex Agent Restore", "Each pane picks up the chat it was running.", "✓", c["green"], right,
         ("claude", "Refactor session auth")),
    ]):
        x = 30 + i * (ww + 28)
        body.append(f'<circle cx="{x + 12}" cy="34" r="12" fill="{col}"/>')
        body.append(t(x + 12, 39.5, mark, "#FFFFFF", 14, weight=700, anchor="middle"))
        body.append(t(x + 34, 40, label, c["label"], 19, weight=700))
        body.append(t(x + 34, 64, sub, c["label_dim"], 14))
        body.append(window(x, top, ww, wh, c, f"r{i}", "api", "This Mac", [tab], panes, fs=fs, lh=lh, compact=True))
    return svg(W, H, defs(c, "r0") + defs(c, "r1"), "\n".join(body),
               "What a Rex restart does to your agent chats",
               "Two Rex windows after the Rex server restarts. Without Rex Agent Restore, all three panes are "
               "empty shell prompts. With it, Claude Code, Codex and OpenCode are back in the chats they were running.")


def svg(w, h, d, body, title, desc):
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}" role="img" aria-labelledby="t d">
<title id="t">{escape(title)}</title>
<desc id="d">{escape(desc)}</desc>
<defs>
{d}
</defs>
{body}
</svg>
'''


if __name__ == "__main__":
    for theme in THEMES:
        (OUT / f"hero-{theme}.svg").write_text(hero(theme))
        (OUT / f"restart-{theme}.svg").write_text(restart(theme))
    print("wrote", ", ".join(sorted(p.name for p in OUT.glob("*-*.svg"))))
