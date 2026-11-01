"""Writes project/theme.tres: the web game's "paper" look (style.css) as a Godot theme.
Run: python3 tools/make_theme.py"""

def c(hexs, a=1.0):
    hexs = hexs.lstrip('#')
    r, g, b = (int(hexs[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return f"Color({r:.4f}, {g:.4f}, {b:.4f}, {a})"

PAPER, CHIP, CHIP2, INK = '#fbf9f4', '#efeae0', '#e4ded1', '#262626'
RED, DANGER, DIM, FAINT, WHITE = '#e4572e', '#a3341a', '#6b6b6b', '#a8a59f', '#ffffff'
EDGE = c('#000000', 0.35)
EDGE_OFF = c('#000000', 0.15)
HOVER = c('#000000', 0.05)
CLEAR = c('#000000', 0.0)

subs = []   # (id, body)
def box(id, bg, border=None, bw=0, radius=3, mx=9, my=4, radii=None):
    lines = [f"content_margin_left = {mx}.0", f"content_margin_top = {my}.0",
             f"content_margin_right = {mx}.0", f"content_margin_bottom = {my}.0", f"bg_color = {bg}"]
    if border and bw:
        lines += [f"border_width_{s} = {bw}" for s in ('left', 'top', 'right', 'bottom')]
        lines.append(f"border_color = {border}")
    tl, tr, br, bl = radii or (radius,) * 4
    lines += [f"corner_radius_top_left = {tl}", f"corner_radius_top_right = {tr}",
              f"corner_radius_bottom_right = {br}", f"corner_radius_bottom_left = {bl}",
              "corner_detail = 12", "anti_aliasing = true"]
    subs.append((id, "\n".join(lines)))
    return f'SubResource("{id}")'

props = []
def p(k, v):
    props.append(f"{k} = {v}")

def button(name, normal, hover, pressed, disabled, font, font_pressed, font_disabled, size=None, hover_pressed=None, font_hover=None):
    p(f"{name}/styles/normal", normal)
    p(f"{name}/styles/hover", hover)
    p(f"{name}/styles/pressed", pressed)
    p(f"{name}/styles/hover_pressed", hover_pressed or pressed)
    p(f"{name}/styles/disabled", disabled)
    p(f"{name}/styles/focus", 'SubResource("none")')
    p(f"{name}/colors/font_color", font)
    p(f"{name}/colors/font_hover_color", font_hover or font)
    p(f"{name}/colors/font_focus_color", font)
    p(f"{name}/colors/font_pressed_color", font_pressed)
    p(f"{name}/colors/font_hover_pressed_color", font_pressed)
    p(f"{name}/colors/font_disabled_color", font_disabled)
    if size:
        p(f"{name}/font_sizes/font_size", size)

subs.append(("none", None))

# Plain button: thin grey outline, ink when switched on.
button("Button",
       box("b_n", CLEAR, EDGE, 1, my=5), box("b_h", HOVER, EDGE, 1, my=5),
       box("b_p", c(INK), c(INK), 1, my=5), box("b_d", CLEAR, EDGE_OFF, 1, my=5),
       c(INK), c(WHITE), c(FAINT), size=12, hover_pressed=box("b_hp", c('#444444'), c('#444444'), 1, my=5))
# Rounded pill (play, hold).
for v in ("PillButton",):
    p(f"{v}/base_type", '&"Button"')
button("PillButton",
       box("pl_n", CLEAR, EDGE, 1, radius=14, mx=4, my=6), box("pl_h", HOVER, EDGE, 1, radius=14, mx=4, my=6),
       box("pl_p", c(INK), c(INK), 1, radius=14, mx=4, my=6), box("pl_d", CLEAR, EDGE_OFF, 1, radius=14, mx=4, my=6),
       c(INK), c(WHITE), c(FAINT), size=12)
# Record: a red pill, ink while recording.
p("RecordButton/base_type", '&"Button"')
button("RecordButton",
       box("r_n", c(RED), c(RED), 1, radius=14, mx=4, my=6), box("r_h", c('#cf4a23'), c('#cf4a23'), 1, radius=14, mx=4, my=6),
       box("r_p", c(INK), c(INK), 1, radius=14, mx=4, my=6), box("r_d", c(RED, 0.4), c(RED, 0.4), 1, radius=14, mx=4, my=6),
       c(WHITE), c(WHITE), c(WHITE), size=12)
p("RecordButton/fonts/font", 'ExtResource("bold")')
# Big dark button (say!, loop on beat): red while on.
p("BigButton/base_type", '&"Button"')
button("BigButton",
       box("bg_n", c(INK), my=10, mx=4), box("bg_h", c('#444444'), my=10, mx=4),
       box("bg_p", c(RED), my=10, mx=4), box("bg_d", c(INK, 0.35), my=10, mx=4),
       c(WHITE), c(WHITE), c(PAPER), size=13)
# Letter buttons.
p("ChipButton/base_type", '&"Button"')
button("ChipButton",
       box("ch_n", c(CHIP), mx=0, my=11), box("ch_h", c(CHIP2), mx=0, my=11),
       box("ch_p", c(INK), mx=0, my=11), box("ch_d", c(CHIP, 0.6), mx=0, my=11),
       c(INK), c(WHITE), c(FAINT), size=15)
# The ? and × buttons, and the snap box.
p("IconButton/base_type", '&"Button"')
button("IconButton",
       box("ic_n", c(CHIP), mx=8, my=5), box("ic_h", c(CHIP2), mx=8, my=5),
       box("ic_p", c(CHIP2), mx=8, my=5), box("ic_d", c(CHIP, 0.6), mx=8, my=5),
       c(INK), c(INK), c(FAINT), size=13)
# Clear all: red text.
p("DangerButton/base_type", '&"Button"')
button("DangerButton",
       box("d_n", CLEAR, EDGE, 1, my=8), box("d_h", HOVER, EDGE, 1, my=8),
       box("d_p", c(INK), c(INK), 1, my=8), box("d_d", CLEAR, EDGE_OFF, 1, my=8),
       c(DANGER), c(WHITE), c(FAINT), size=12)
# Undo / redo row height.
p("TallButton/base_type", '&"Button"')
button("TallButton",
       box("t_n", CLEAR, EDGE, 1, my=8), box("t_h", HOVER, EDGE, 1, my=8),
       box("t_p", c(INK), c(INK), 1, my=8), box("t_d", CLEAR, EDGE_OFF, 1, my=8),
       c(INK), c(WHITE), c(FAINT), size=12)

# Cards.
p("PanelContainer/styles/panel", box("card", c(PAPER), c(INK), 1, mx=10, my=10))
p("ControlsCard/base_type", '&"PanelContainer"')
p("ControlsCard/styles/panel", box("controls", c(PAPER), c(INK), 1, mx=9, my=9))
p("VoiceCard/base_type", '&"PanelContainer"')
p("VoiceCard/styles/panel", box("voice", c(PAPER), c(INK), 1, mx=0, my=0, radii=(100, 100, 3, 3)))
p("TopBar/base_type", '&"PanelContainer"')
p("TopBar/styles/panel", box("top", c(WHITE), mx=12, my=6))
p("Backdrop/base_type", '&"PanelContainer"')
p("Backdrop/styles/panel", box("backdrop", c('#000000', 0.25), radius=0, mx=0, my=0))

# Text.
p("Label/colors/font_color", c(INK))
p("Label/font_sizes/font_size", 12)
p("DimLabel/base_type", '&"Label"')
p("DimLabel/colors/font_color", c(DIM))
p("BoldLabel/base_type", '&"Label"')
p("BoldLabel/fonts/font", 'ExtResource("bold")')
p("BrandLabel/base_type", '&"Label"')
p("BrandLabel/fonts/font", 'ExtResource("bold")')
p("BrandLabel/font_sizes/font_size", 13)
p("LineEdit/styles/normal", box("say_n", c(CHIP), mx=12, my=10))
p("LineEdit/styles/read_only", box("say_ro", c(CHIP), mx=12, my=10))
p("LineEdit/styles/focus", 'SubResource("none")')
p("LineEdit/colors/font_color", c(INK))
p("LineEdit/colors/font_uneditable_color", c(INK))
p("LineEdit/colors/font_placeholder_color", c(DIM))
p("LineEdit/font_sizes/font_size", 14)
p("PopupMenu/styles/panel", box("menu", c(PAPER), c(INK), 1, mx=4, my=4))
p("PopupMenu/styles/hover", box("menu_h", c(CHIP2), mx=8, my=4))
p("PopupMenu/colors/font_color", c(INK))
p("PopupMenu/colors/font_hover_color", c(INK))
p("PopupMenu/font_sizes/font_size", 13)
p("TooltipPanel/styles/panel", box("tip", c(INK), mx=8, my=4))
p("TooltipLabel/colors/font_color", c(WHITE))
p("TooltipLabel/font_sizes/font_size", 12)

out = ['[gd_resource type="Theme" load_steps=%d format=3]' % (len(subs) + 3), '',
       '[ext_resource type="FontFile" path="res://fonts/Inter-Regular.otf" id="regular"]',
       '[ext_resource type="FontFile" path="res://fonts/Inter-SemiBold.otf" id="bold"]', '']
for id, body in subs:
    if body is None:
        out += [f'[sub_resource type="StyleBoxEmpty" id="{id}"]', '']
    else:
        out += [f'[sub_resource type="StyleBoxFlat" id="{id}"]', body, '']
out += ['[resource]', 'default_font = ExtResource("regular")', 'default_font_size = 13'] + props
open('project/theme.tres', 'w').write("\n".join(out) + "\n")
print("wrote", len(subs), "styles")
