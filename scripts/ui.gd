class_name Ui
extends RefCounted
## Shared look of the menus and HUD: manga-panel boxes with ink borders,
## slanted buttons and bold display type.

const INK := Color(0.03, 0.03, 0.08)
const PAPER := Color(0.98, 0.97, 0.92)
const YELLOW := Color(1.0, 0.83, 0.12)
const RED := Color(0.96, 0.16, 0.24)
const CYAN := Color(0.2, 0.85, 1.0)
const NAVY := Color(0.07, 0.09, 0.24)

static var _fonts := {}


## "display": heavy slanted headline type. "body": rounded bold text.
static func font(kind: String) -> Font:
	if not _fonts.has(kind):
		if kind == "display":
			var fv := FontVariation.new()
			fv.base_font = load("res://assets/fonts/DelaGothicOne-Regular.ttf")
			fv.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(0.2, 1.0), Vector2.ZERO)
			_fonts[kind] = fv
		else:
			_fonts[kind] = load("res://assets/fonts/MPLUSRounded1c-ExtraBold.ttf")
	return _fonts[kind]


## Makes the rounded bold face the default for every label and button.
static func install(root: Window) -> void:
	var th := Theme.new()
	th.default_font = font("body")
	th.default_font_size = 18
	root.theme = th


## A flat box with an ink border and a hard drop shadow; `skew` slants it.
static func box(bg: Color, border := 4, skew := 0.0, margin := 14, border_col := INK, shadow := true) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(border)
	sb.border_color = border_col
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(margin)
	sb.skew = Vector2(skew, 0.0)
	sb.anti_aliasing = true
	if shadow:
		sb.shadow_color = Color(INK, 0.85)
		sb.shadow_size = 1
		sb.shadow_offset = Vector2(5, 6)
	return sb


## Headline text: display face, thick ink outline, coloured drop shadow.
static func title(l: Control, size: int, color := YELLOW, outline := 12, shadow := RED) -> void:
	l.add_theme_font_override("font", font("display"))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", outline)
	l.add_theme_color_override("font_shadow_color", shadow)
	l.add_theme_constant_override("shadow_offset_x", maxi(2, size / 18))
	l.add_theme_constant_override("shadow_offset_y", maxi(2, size / 14))
	l.add_theme_constant_override("shadow_outline_size", outline)


## Small text that must read over the moving picture: ink outline.
static func inked(l: Control, size: int, color := PAPER, outline := 7) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", outline)
