#!/usr/bin/python3
"""Edit Omarchy's Hyprland Lua config (~/.config/hypr/*.lua) in place.

Panacea's settings pages call this so a change lands in the files Omarchy
loads and documents, next to the user's own comments, instead of in a private
data file that nothing reads:

  hyprconf.py monitor DP-1 mode=3440x1440@119.99 scale=1.25 vrr=1
  hyprconf.py set input input.sensitivity 0.3
  hyprconf.py set input input.touchpad.natural_scroll true
  hyprconf.py set looknfeel general.gaps_out 6
  hyprconf.py get input input.sensitivity
  hyprconf.py unset looknfeel decoration.screen_shader
  hyprconf.py getmonitor DP-1
  hyprconf.py apply-monitor DP-1 mode=3440x1440@119.99 position=auto-down
  hyprconf.py live input:sensitivity general:gaps_out
  hyprconf.py binds-get
  hyprconf.py binds-set '{"github": "SUPER + I", "agents": "SUPER + U"}'

Values are Lua literals: numbers, true/false, or "double-quoted strings".
Every write keeps a backup in ~/.local/state/panacea/hypr-backups, reloads
Hyprland and checks `hyprctl configerrors`; on any error the file is restored
and the command exits 1 with the error on stderr.

The editor only understands what it needs: it masks comments and strings,
then finds tables by brace matching. It edits a value where it already is and
otherwise inserts a new line into the right table, matching the file's indent.
"""

import json
import os
import re
import subprocess
import sys
import time

HOME = os.path.expanduser("~")
HYPR = os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.join(HOME, ".config")), "hypr")
BACKUPS = os.path.join(os.environ.get("XDG_STATE_HOME", os.path.join(HOME, ".local", "state")),
                       "panacea", "hypr-backups")
KEEP_BACKUPS = 20

# Files Panacea may write. Anything else is refused.
FILES = {"monitors", "input", "looknfeel", "bindings", "autostart"}

MONITOR_KEYS = {"mode", "position", "scale", "transform", "vrr", "disabled", "mirror",
                "bitdepth", "cm", "sdrbrightness", "sdrsaturation", "supports_hdr",
                "supports_wide_color"}

NAME_RE = re.compile(r"^[A-Za-z0-9._-]+$")
NUM_RE = re.compile(r"^-?\d+(\.\d+)?$")
STR_RE = re.compile(r'^"[^"\\\n]*"$')


class EditError(Exception):
    pass


# ------------------------------------------------------------------ lexing

def mask(src):
    """Copy of src with comments and string contents blanked to spaces.

    Offsets are preserved, so searches and brace matching on the mask are
    safe and every hit maps straight back onto the original text. Quote
    characters stay, string bodies and comments become spaces (newlines kept).
    """
    out = list(src)
    i, n = 0, len(src)

    def blank(a, b):
        for k in range(a, b):
            if out[k] != "\n":
                out[k] = " "

    while i < n:
        c = src[i]
        if src.startswith("--", i):
            m = re.match(r"--\[(=*)\[", src[i:])
            if m:
                close = "]" + m.group(1) + "]"
                end = src.find(close, i + len(m.group(0)))
                end = n if end < 0 else end + len(close)
            else:
                end = src.find("\n", i)
                end = n if end < 0 else end
            blank(i, end)
            i = end
        elif c in "\"'":
            j = i + 1
            while j < n and src[j] != c and src[j] != "\n":
                j += 2 if src[j] == "\\" else 1
            blank(i + 1, min(j, n))
            i = j + 1
        elif c == "[" and re.match(r"\[(=*)\[", src[i:]):
            m = re.match(r"\[(=*)\[", src[i:])
            close = "]" + m.group(1) + "]"
            end = src.find(close, i + len(m.group(0)))
            end = n if end < 0 else end + len(close)
            blank(i, end)
            i = end
        else:
            i += 1
    return "".join(out)


def match_close(m, open_pos):
    """Index of the bracket closing the one at open_pos (in masked text)."""
    pairs = {"{": "}", "(": ")", "[": "]"}
    stack = []
    for k in range(open_pos, len(m)):
        ch = m[k]
        if ch in pairs:
            stack.append(pairs[ch])
        elif ch in ")}]":
            if not stack or stack.pop() != ch:
                raise EditError("unbalanced brackets near offset %d" % k)
            if not stack:
                return k
    raise EditError("unclosed bracket at offset %d" % open_pos)


def top_level_fields(src, m, open_pos, close_pos):
    """Fields `name = value` directly inside the table {open_pos..close_pos}.

    Returns [(name, key_start, value_start, value_end)], value_end exclusive
    and trimmed of whitespace.
    """
    fields = []
    k = open_pos + 1
    depth = 0
    seg_start = k
    pairs = {"{": 1, "(": 1, "[": 1, "}": -1, ")": -1, "]": -1}
    while k <= close_pos:
        ch = m[k]
        if k == close_pos or (depth == 0 and ch == ","):
            seg = m[seg_start:k]
            fm = re.match(r"\s*([A-Za-z_][A-Za-z0-9_]*)\s*=(?!=)\s*", seg)
            if fm:
                vs = seg_start + fm.end()
                ve = k
                while ve > vs and src[ve - 1].isspace():
                    ve -= 1
                fields.append((fm.group(1), seg_start + fm.start(1), vs, ve))
            seg_start = k + 1
        elif ch in pairs:
            depth += pairs[ch]
        k += 1
    return fields


def indent_unit(src):
    for line in src.splitlines():
        if line.startswith("\t"):
            return "\t"
    return "  "


def line_indent(src, pos):
    start = src.rfind("\n", 0, pos) + 1
    return re.match(r"[ \t]*", src[start:]).group(0)


# ------------------------------------------------------------------ values

def lua_literal(raw):
    raw = raw.strip()
    if raw in ("true", "false") or NUM_RE.match(raw) or STR_RE.match(raw):
        return raw
    raise EditError("not a plain Lua literal: %r" % raw)


def lua_to_py(text):
    text = text.strip()
    if text in ("true", "false"):
        return text == "true"
    if NUM_RE.match(text):
        return float(text) if "." in text else int(text)
    if len(text) >= 2 and text[0] == text[-1] and text[0] in "\"'":
        return text[1:-1]
    return text


# ------------------------------------------------------------- hl.config

def find_path(src, m, path):
    """Locate dotted path inside an hl.config({...}) call.

    Returns (table_open, table_close, field_or_None, depth_reached, missing)
    where the table is the deepest existing one along the path.
    """
    head = path[0]
    best = None
    for call in re.finditer(r"hl\.config\s*\(\s*\{", m):
        t_open = call.end() - 1
        t_close = match_close(m, t_open)
        for name, ks, vs, ve in top_level_fields(src, m, t_open, t_close):
            if name == head and m[vs] == "{":
                best = (vs, match_close(m, vs))
    if best is None:
        return None
    t_open, t_close = best
    for depth, part in enumerate(path[1:], start=1):
        last = depth == len(path) - 1
        found = None
        for name, ks, vs, ve in top_level_fields(src, m, t_open, t_close):
            if name == part:
                found = (ks, vs, ve)
        if found is None:
            return (t_open, t_close, None, depth, path[depth:])
        if last:
            return (t_open, t_close, found, depth, [])
        ks, vs, ve = found
        if m[vs] != "{":
            raise EditError("%s is not a table" % ".".join(path[: depth + 1]))
        t_open, t_close = vs, match_close(m, vs)
    raise EditError("path too short: %s" % ".".join(path))


def nested_lines(keys, value, indent, unit):
    """Lines for keys[0] = { keys[1] = { ... keys[-1] = value } } at indent."""
    if len(keys) == 1:
        return ["%s%s = %s," % (indent, keys[0], value)]
    inner = nested_lines(keys[1:], value, indent + unit, unit)
    return ["%s%s = {" % (indent, keys[0])] + inner + ["%s}," % indent]


def insert_into_table(src, t_open, t_close, keys, value):
    unit = indent_unit(src)
    close_indent = line_indent(src, t_close)
    inner_indent = close_indent + unit
    block = "\n".join(nested_lines(keys, value, inner_indent, unit))
    # Make sure the last existing entry ends with a comma.
    m = mask(src)
    k = t_close - 1
    while k > t_open and m[k].isspace():
        k -= 1
    if k > t_open and m[k] not in ",{":
        src = src[: k + 1] + "," + src[k + 1:]
        t_close += 1
    line_start = src.rfind("\n", 0, t_close) + 1
    if src[line_start:t_close].strip() == "":
        return src[:line_start] + block + "\n" + src[line_start:]
    return src[:t_close] + "\n" + block + "\n" + close_indent + src[t_close:]


def config_set(src, path, value):
    m = mask(src)
    hit = find_path(src, m, path)
    if hit is None:
        # No table for this section yet: add it to the file's last
        # hl.config({...}) call, or start one when the file has none.
        calls = list(re.finditer(r"hl\.config\s*\(\s*\{", m))
        if calls:
            t_open = calls[-1].end() - 1
            return insert_into_table(src, t_open, match_close(m, t_open), path, value)
        unit = indent_unit(src)
        body = "\n".join(nested_lines(path, value, unit, unit))
        sep = "" if src.endswith("\n\n") else ("\n" if src.endswith("\n") else "\n\n")
        return src + sep + "-- Set from Panacea's settings.\nhl.config({\n" + body + "\n})\n"
    t_open, t_close, field, depth, missing = hit
    if field is not None:
        ks, vs, ve = field
        if m[vs] == "{":
            raise EditError("%s is a table, not a value" % ".".join(path))
        return src[:vs] + value + src[ve:]
    return insert_into_table(src, t_open, t_close, missing, value)


def config_unset(src, path):
    """Remove path's `key = value,` entry, and its line when it stands alone."""
    m = mask(src)
    hit = find_path(src, m, path)
    if hit is None or hit[2] is None:
        return src
    ks, vs, ve = hit[2]
    end = ve
    while end < len(src) and src[end] in " \t":
        end += 1
    if end < len(src) and src[end] == ",":
        end += 1
    line_start = src.rfind("\n", 0, ks) + 1
    line_end = src.find("\n", end)
    line_end = len(src) if line_end < 0 else line_end
    if src[line_start:ks].strip() == "" and mask(src[end:line_end]).strip() == "":
        return src[:line_start] + src[line_end + 1:]
    return src[:ks] + src[end:].lstrip(" \t")


def config_get(src, path):
    m = mask(src)
    hit = find_path(src, m, path)
    if hit is None or hit[2] is None:
        return None
    ks, vs, ve = hit[2]
    return lua_to_py(src[vs:ve])


# ------------------------------------------------------------ hl.monitor

def monitor_calls(src, m):
    calls = []
    for call in re.finditer(r"hl\.monitor\s*\(\s*\{", m):
        t_open = call.end() - 1
        t_close = match_close(m, t_open)
        p_close = match_close(m, call.start() + m[call.start():].index("("))
        fields = top_level_fields(src, m, t_open, t_close)
        out = None
        for name, ks, vs, ve in fields:
            if name == "output":
                out = lua_to_py(src[vs:ve])
        calls.append({"start": call.start(), "open": t_open, "close": t_close,
                      "end": p_close + 1, "fields": fields, "output": out})
    return calls


def monitor_get(src, output):
    m = mask(src)
    rule = {}
    for c in monitor_calls(src, m):
        if c["output"] == output:
            rule = {name: lua_to_py(src[vs:ve]) for name, ks, vs, ve in c["fields"]}
    return rule


def monitor_set(src, output, updates):
    """Apply updates ({field: lua literal, or None to drop the field})."""
    m = mask(src)
    calls = [c for c in monitor_calls(src, m) if c["output"] == output]
    drops = [k for k, v in updates.items() if v is None]
    updates = {k: v for k, v in updates.items() if v is not None}
    if calls and drops:
        c = calls[-1]
        for name, ks, vs, ve in sorted(c["fields"], key=lambda f: -f[1]):
            if name not in drops:
                continue
            # Drop ", name = value" (or "name = value," when it comes first).
            a = ks
            while a > c["open"] + 1 and src[a - 1] in " \t\n":
                a -= 1
            if src[a - 1] == ",":
                src = src[: a - 1] + src[ve:]
            else:
                b = ve
                while b < len(src) and src[b] in " \t":
                    b += 1
                if b < len(src) and src[b] == ",":
                    b += 1
                src = src[:ks] + src[b:].lstrip(" \t")
        m = mask(src)
        calls = [c for c in monitor_calls(src, m) if c["output"] == output]
    if not updates:
        return src
    if calls:
        # Later rules win in Hyprland, so edit the last one for this output.
        c = calls[-1]
        names = [f[0] for f in c["fields"]]
        new = src
        # Replace existing values back to front so offsets stay valid.
        for name, ks, vs, ve in sorted(c["fields"], key=lambda f: -f[2]):
            if name in updates:
                new = new[:vs] + updates[name] + new[ve:]
        missing = [(k, v) for k, v in updates.items() if k not in names]
        if not missing:
            return new
        m2 = mask(new)
        c2 = [x for x in monitor_calls(new, m2) if x["output"] == output][-1]
        if "\n" in new[c2["open"]:c2["close"]]:
            for k, v in missing:
                m2 = mask(new)
                c2 = [x for x in monitor_calls(new, m2) if x["output"] == output][-1]
                new = insert_into_table(new, c2["open"], c2["close"], [k], v)
            return new
        # Single-line rule: append the new fields before the closing brace.
        k = c2["close"] - 1
        while new[k] == " ":
            k -= 1
        extra = "".join(", %s = %s" % (key, val) for key, val in missing)
        if new[k] == ",":
            extra = extra[1:]
        return new[: k + 1] + extra + new[k + 1:]
    # No rule for this output yet: add one before the catch-all rule, or at
    # the end of the file.
    parts = ['output = "%s"' % output] + ["%s = %s" % kv for kv in updates.items()]
    line = "hl.monitor({ %s })" % ", ".join(parts)
    catch_all = [c for c in monitor_calls(src, m) if c["output"] == ""]
    if catch_all:
        pos = src.rfind("\n", 0, catch_all[0]["start"]) + 1
        # Step above the comment block that introduces the catch-all.
        lines_before = src[:pos].split("\n")
        while len(lines_before) > 1 and lines_before[-2].lstrip().startswith("--"):
            lines_before.pop()
        pos = len("\n".join(lines_before[:-1])) + 1 if len(lines_before) > 1 else 0
        return src[:pos] + "-- Added from Panacea's display settings.\n" + line + "\n\n" + src[pos:]
    sep = "" if src.endswith("\n") else "\n"
    return src + sep + "\n-- Added from Panacea's display settings.\n" + line + "\n"


# ---------------------------------------------------------- keybindings
#
# Panacea's shortcuts live in one managed block of ~/.config/hypr/bindings.lua
# (between the BLOCK_START/BLOCK_END markers), as ordinary Omarchy o.bind()
# lines. Choosing a combo Omarchy already uses adds an hl.unbind() for it
# first, with a note of what it was, as Omarchy's own guide asks.

BLOCK_START = "-- >>> panacea-omarchy >>>"
BLOCK_END = "-- <<< panacea-omarchy <<<"
GLASS = "$HOME/.config/omarchy/plugins/isaqdn.panacea/scripts/glass.sh"

# id, label, group, pill IPC method (or a full command), default combo
ACTIONS = [
    ("launcher", "App launcher", "Panacea", "launcher", ""),
    ("controls", "Control Center", "Panacea", "controls", ""),
    ("settings", "Panacea settings", "Panacea", "settings", ""),
    ("shortcuts", "These shortcuts", "Panacea", "shortcuts", ""),
    ("wifi", "Wi-Fi networks", "Panacea", "wifi", ""),
    ("bluetooth", "Bluetooth devices", "Panacea", "bluetooth", ""),
    ("audio", "Sound", "Panacea", "audio", ""),
    ("clipboard", "Clipboard", "Panacea", "clipboard", ""),
    ("notifications", "Notifications", "Panacea", "notifications", ""),
    ("calendar", "Calendar", "Panacea", "calendar", ""),
    ("files", "Files", "Panacea", "files", ""),
    ("powermenu", "Power menu", "Panacea", "powermenu", ""),
    ("github", "GitHub inbox", "More", "github", "SUPER + I"),
    ("agents", "Agent usage", "More", "agents", "SUPER + U"),
    ("peek", "Peek at the rail", "More", "peek", ""),
    ("overview", "Workspace overview", "More", "overview", ""),
    ("weather", "Weather forecast", "More", "weather", ""),
    ("theme", "Wallpapers", "More", "theme", ""),
    ("record", "Screen recorder", "More", "record", ""),
    ("recordToggle", "Start or stop recording", "More", "recordToggle", ""),
    ("dnd", "Do not disturb", "More", "dnd", ""),
    ("glass", "Glass mode", "More", GLASS, "SUPER + SHIFT + T"),
]
MODS = [(64, "SUPER"), (4, "CTRL"), (8, "ALT"), (1, "SHIFT")]
COMBO_RE = re.compile(r"^((SUPER|CTRL|ALT|SHIFT) \+ )*[A-Za-z0-9_]+$")


def norm_combo(combo):
    parts = [p.strip() for p in str(combo).split("+") if p.strip()]
    if not parts:
        return ""
    mods = {p.upper() for p in parts[:-1]}
    order = [name for _, name in MODS if name in mods]
    return " + ".join(order + [parts[-1]])


def combo_key(combo):
    """Comparable form: canonical modifier order, key case-folded."""
    mods, _, key = norm_combo(combo).rpartition(" + ")
    return mods + "|" + key.lower()


def command_for(target):
    return target if target.startswith("$") or "/" in target else "omarchy-shell pill " + target


def block_span(src):
    a = src.find(BLOCK_START)
    b = src.find(BLOCK_END)
    if a < 0 or b < a:
        return None
    return a, b + len(BLOCK_END)


def parse_block(src):
    """(binds {id: combo}, unbinds {combo_key: note}) from the managed block."""
    binds, unbinds = {}, {}
    span = block_span(src)
    if not span:
        return binds, unbinds
    text = src[span[0]:span[1]]
    for m in re.finditer(r'hl\.unbind\("([^"]+)"\)(?:\s*--\s*was:\s*(.*))?', text):
        unbinds[combo_key(m.group(1))] = (m.group(2) or "").strip()
    for m in re.finditer(r'o\.bind\("([^"]+)",\s*"[^"]*",\s*"([^"]+)"', text):
        combo, cmd = m.group(1), m.group(2)
        for aid, label, group, target, default in ACTIONS:
            method = re.search(r"(?:pill|panacea-ipc)\s+(\w+)\s*$", cmd)
            if (target == GLASS and cmd.endswith("/glass.sh")) or (method and method.group(1) == target):
                binds[aid] = norm_combo(combo)
    return binds, unbinds


def hypr_binds():
    """[(combo, description)] for every bind Hyprland has now."""
    r = hyprctl("binds", "-j")
    out = []
    for b in json.loads(r.stdout or "[]"):
        if b.get("submap") or b.get("mouse"):
            continue
        mods = [name for bit, name in MODS if b.get("modmask", 0) & bit]
        out.append((" + ".join(mods + [b.get("key", "")]), b.get("description", "")))
    return out


def binds_get(src):
    ours, unbinds = parse_block(src)
    if block_span(src) is None:
        ours = {aid: default for aid, _, _, _, default in ACTIONS if default}
    mine = {combo_key(c) for c in ours.values()}
    taken = {}
    for combo, desc in hypr_binds():
        k = combo_key(combo)
        if k not in mine and not desc.startswith("Panacea: "):
            taken[k] = desc
    # A default we unbound for one of our binds no longer shows in Hyprland's
    # list; remember what it was from the note on the unbind line.
    for k, note in unbinds.items():
        taken.setdefault(k, note)
    return {
        "actions": [{"id": aid, "label": label, "group": group,
                     "combo": ours.get(aid, ""), "default": default}
                    for aid, label, group, target, default in ACTIONS],
        "taken": taken,
    }


def binds_render(chosen, taken, old_unbinds):
    lines = [
        BLOCK_START,
        "-- Panacea shortcuts, written by Panacea's Shortcuts window; hand edits",
        "-- here are replaced on its next save. Actions go through the pill's IPC",
        "-- target inside omarchy-shell: `omarchy-shell pill <method>`.",
        "",
        "-- The Shortcuts window's key recorder: while it listens, Hyprland passes",
        "-- every key to it. SUPER + Escape gets out if Panacea ever stops answering.",
        'hl.define_submap("panacea-capture", function()',
        '  hl.bind("SUPER + escape", hl.dsp.submap("reset"))',
        "end)",
    ]
    for aid, label, group, target, default in ACTIONS:
        combo = chosen.get(aid, "")
        if not combo:
            continue
        k = combo_key(combo)
        lines.append("")
        if k in taken or k in old_unbinds:
            was = taken.get(k) or old_unbinds.get(k) or ""
            lines.append('hl.unbind("%s")%s' % (combo, " -- was: " + was if was else ""))
        lines.append('o.bind("%s", "Panacea: %s", "%s")' % (combo, label, command_for(target)))
    lines.append(BLOCK_END)
    return "\n".join(lines)


def binds_set(src, chosen):
    known = {a[0] for a in ACTIONS}
    clean = {}
    for aid, combo in chosen.items():
        if aid not in known:
            raise EditError("unknown action %r" % aid)
        combo = norm_combo(combo)
        if combo and not COMBO_RE.match(combo):
            raise EditError("bad combo %r" % combo)
        if combo:
            clean[aid] = combo
    seen = {}
    for aid, combo in clean.items():
        k = combo_key(combo)
        if k in seen:
            raise EditError("%s is used twice (%s, %s)" % (combo, seen[k], aid))
        seen[k] = aid
    info = binds_get(src)
    _, old_unbinds = parse_block(src)
    block = binds_render(clean, info["taken"], old_unbinds)
    span = block_span(src)
    if span:
        return src[:span[0]] + block + src[span[1]:]
    sep = "" if src.endswith("\n") else "\n"
    return src + sep + "\n" + block + "\n"


# ------------------------------------------------- monitor, live + saved

def clean_scale(scale, width, height):
    """Round scale up to one Hyprland accepts for this mode.

    Same rule as omarchy-hyprland-monitor-scaling: the mode must divide into
    whole logical pixels in 1/120 steps, so valid scales are divisors of
    gcd(w*120, h*120).
    """
    from math import gcd
    g = gcd(width * 120, height * 120)
    k = min(int(scale * 120 + 0.5), g)
    while g % k:
        k += 1
    return k / 120


def fmt_num(x):
    s = ("%.6f" % x).rstrip("0").rstrip(".")
    return s or "0"


def live_monitor(name):
    r = hyprctl("monitors", "all", "-j")
    for mon in json.loads(r.stdout or "[]"):
        if mon.get("name") == name:
            return mon
    raise EditError("no monitor named %s" % name)


def apply_monitor(name, changes):
    """Apply changes to output `name` now, then save just those fields.

    changes: mode="WxH@RR", scale=S, transform=T, position=<XxY|auto-right|
    auto-left|auto-up|auto-down>, vrr=<0|1|2|""> ("" = drop, use the global
    misc:vrr). Unchanged fields keep their live value for the live call and
    stay as they are in monitors.lua.
    """
    mon = live_monitor(name)
    mode = changes.get("mode") or "%dx%d@%s" % (mon["width"], mon["height"],
                                                 fmt_num(round(mon["refreshRate"], 2)))
    mm = re.match(r"^(\d+)x(\d+)@(\d+(?:\.\d+)?)$", mode)
    if not mm:
        raise EditError("bad mode %r" % mode)
    w, h = int(mm.group(1)), int(mm.group(2))
    mode = "%dx%d@%s" % (w, h, fmt_num(round(float(mm.group(3)), 2)))
    save = {}
    if "mode" in changes:
        save["mode"] = '"%s"' % mode
    scale = float(changes.get("scale", mon["scale"]))
    scale = clean_scale(scale, w, h) if "scale" in changes or "mode" in changes else scale
    if "scale" in changes:
        save["scale"] = fmt_num(scale)
    transform = int(changes.get("transform", mon["transform"]))
    if "transform" in changes:
        save["transform"] = str(transform)
    position = changes.get("position") or "%dx%d" % (mon["x"], mon["y"])
    if not re.match(r"^(\d+x\d+|-?\d+x-?\d+|auto(-right|-left|-up|-down)?)$", position):
        raise EditError("bad position %r" % position)
    vrr = changes.get("vrr")
    if vrr not in (None, "", "0", "1", "2"):
        raise EditError("bad vrr %r" % vrr)

    lua = 'hl.monitor({ output = "%s", mode = "%s", position = "%s", scale = %s, transform = %d%s })' % (
        name, mode, position, fmt_num(scale), transform,
        ", vrr = %s" % vrr if vrr else "")
    r = hyprctl("eval", lua)
    if r.returncode != 0 or (r.stdout.strip() and not r.stdout.strip().startswith("ok")):
        raise EditError("Hyprland refused %s: %s" % (lua, (r.stdout + r.stderr).strip()))

    if "position" in changes:
        if position.startswith("auto"):
            # Save where Hyprland actually put it, in the file's own style.
            time.sleep(0.4)
            mon = live_monitor(name)
            position = "%dx%d" % (mon["x"], mon["y"])
        save["position"] = '"%s"' % position
    if "vrr" in changes:
        save["vrr"] = vrr or None

    path = path_for("monitors")
    src = open(path).read()
    commit(path, src, monitor_set(src, name, save))


# --------------------------------------------------------------- live

def live_options(keys):
    """Current values of Hyprland options ("input:sensitivity", ...) as a dict.

    One `hyprctl --batch` call for all of them. Gaps come back as the first
    side of their CSS value; options Hyprland doesn't know map to None.
    """
    keys = [k for k in keys if re.match(r"^[A-Za-z0-9_:.-]+$", k)]
    if not keys:
        return {}
    r = hyprctl("--batch", "; ".join("getoption " + k for k in keys))
    out = {}
    blocks = re.split(r"\n(?=\S)", r.stdout.strip()) if r.stdout.strip() else []
    # Plain-text replies, one or two lines each, in request order:
    #   "int: 40\nset: true"  /  "css gap data: 6 6 6 6\nset: true"
    values = [b for b in blocks if not b.startswith("set:")]
    for key, block in zip(keys, values):
        line = block.splitlines()[0] if block else ""
        kind, _, val = line.partition(": ")
        val = val.strip()
        if kind == "int":
            out[key] = int(val)
        elif kind == "float":
            out[key] = float(val)
        elif kind == "str":
            out[key] = val.strip('"')
        elif kind == "css gap data":
            out[key] = int(val.split()[0]) if val else None
        elif kind in ("bool",):
            out[key] = val == "true"
        else:
            out[key] = None
    return out


# ---------------------------------------------------------------- I/O

def path_for(name):
    if name not in FILES:
        raise EditError("refusing to edit %s.lua" % name)
    return os.path.join(HYPR, name + ".lua")


def backup(path, text):
    os.makedirs(BACKUPS, exist_ok=True)
    base = os.path.basename(path)
    dest = os.path.join(BACKUPS, "%s.%d" % (base, int(time.time() * 1000)))
    with open(dest, "w") as f:
        f.write(text)
    olds = sorted(p for p in os.listdir(BACKUPS) if p.startswith(base + "."))
    for p in olds[:-KEEP_BACKUPS]:
        os.unlink(os.path.join(BACKUPS, p))


def atomic_write(path, text):
    tmp = path + ".panacea-tmp"
    with open(tmp, "w") as f:
        f.write(text)
    os.replace(tmp, path)


def hyprctl(*args):
    return subprocess.run(["hyprctl", *args], capture_output=True, text=True, timeout=10)


def config_errors():
    r = hyprctl("configerrors", "-j")
    try:
        errs = json.loads(r.stdout or "[]")
    except ValueError:
        return [r.stdout.strip()] if r.stdout.strip() else []
    return [e for e in errs if str(e).strip()]


def commit(path, old, new):
    """Write new, reload Hyprland, and roll back if it reports errors."""
    if new == old:
        return
    if os.environ.get("PANACEA_HYPRCONF_DRY"):
        atomic_write(path, new)
        return
    before = set(config_errors())
    backup(path, old)
    atomic_write(path, new)
    hyprctl("reload")
    errors = [e for e in config_errors() if e not in before]
    if errors:
        atomic_write(path, old)
        hyprctl("reload")
        raise EditError("Hyprland rejected the change, restored %s: %s"
                        % (os.path.basename(path), "; ".join(errors)))


def main(argv):
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    cmd = argv[1]
    try:
        if cmd in ("set", "get", "unset"):
            if len(argv) != (5 if cmd == "set" else 4):
                raise EditError("usage: %s <file> <dotted.path>%s" % (cmd, " <value>" if cmd == "set" else ""))
            path = path_for(argv[2])
            keys = argv[3].split(".")
            if not all(NAME_RE.match(k) and "." not in k for k in keys) or len(keys) < 2:
                raise EditError("bad path %r" % argv[3])
            src = open(path).read() if os.path.exists(path) else ""
            if cmd == "get":
                print(json.dumps(config_get(src, keys)))
                return 0
            if cmd == "unset":
                commit(path, src, config_unset(src, keys))
                return 0
            commit(path, src, config_set(src, keys, lua_literal(argv[4])))
            return 0
        if cmd in ("monitor", "getmonitor"):
            if len(argv) < 3 or not NAME_RE.match(argv[2]):
                raise EditError("bad output name")
            path = path_for("monitors")
            src = open(path).read()
            if cmd == "getmonitor":
                print(json.dumps(monitor_get(src, argv[2])))
                return 0
            updates = {}
            for arg in argv[3:]:
                key, _, raw = arg.partition("=")
                if key not in MONITOR_KEYS:
                    raise EditError("unknown monitor field %r" % key)
                if raw == "":
                    updates[key] = None   # `vrr=` drops the field
                    continue
                # mode/position/mirror/cm are strings; quote bare words.
                if key in ("mode", "position", "mirror", "cm") and not raw.startswith('"'):
                    raw = '"%s"' % raw
                updates[key] = lua_literal(raw)
            if not updates:
                raise EditError("nothing to change")
            commit(path, src, monitor_set(src, argv[2], updates))
            return 0
        if cmd == "apply-monitor":
            if len(argv) < 4 or not NAME_RE.match(argv[2]):
                raise EditError("usage: apply-monitor <output> field=value...")
            changes = {}
            for arg in argv[3:]:
                key, sep, raw = arg.partition("=")
                if not sep or key not in ("mode", "scale", "transform", "position", "vrr"):
                    raise EditError("bad change %r" % arg)
                changes[key] = raw
            apply_monitor(argv[2], changes)
            return 0
        if cmd == "binds-get":
            print(json.dumps(binds_get(open(path_for("bindings")).read())))
            return 0
        if cmd == "binds-set":
            if len(argv) != 3:
                raise EditError("usage: binds-set '<json {action: combo}>'")
            try:
                chosen = json.loads(argv[2])
            except ValueError:
                raise EditError("binds-set wants a JSON object")
            if not isinstance(chosen, dict):
                raise EditError("binds-set wants a JSON object")
            path = path_for("bindings")
            src = open(path).read()
            commit(path, src, binds_set(src, chosen))
            return 0
        if cmd == "monitors":
            # Every output's effective rule in monitors.lua (later wins).
            src = open(path_for("monitors")).read()
            rules = {}
            for c in monitor_calls(src, mask(src)):
                if c["output"]:
                    rules[c["output"]] = {n: lua_to_py(src[vs:ve]) for n, ks, vs, ve in c["fields"]}
            print(json.dumps(rules))
            return 0
        if cmd == "live":
            print(json.dumps(live_options(argv[2:])))
            return 0
        raise EditError("unknown command %r" % cmd)
    except EditError as e:
        print("hyprconf: %s" % e, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
