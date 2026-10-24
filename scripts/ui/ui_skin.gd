extends RefCounted

# Shared UI theme; all typography stays editable in the scene inspector.
const PAPER = Color("e3d2ad")
const DARK = Color("191818")
const LIGHT = Color("f0eadb")
const MUTED = Color("a29c91")
const RED = Color("c84c4c")
const INK = Color("342c26")

static func box(bg: Color, border: Color, thickness: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(thickness)
	style.set_content_margin_all(9.0)
	style.set_corner_radius_all(0)
	return style

static func label(node: Label, size: int, color: Color = LIGHT) -> void:
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	node.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

static func main_hotspot(node: Button) -> void:
	var empty := StyleBoxEmpty.new()
	node.add_theme_stylebox_override("normal", empty)
	node.add_theme_stylebox_override("pressed", box(Color(1.0, 0.72, 0.2, 0.20), Color.TRANSPARENT, 0))
	node.add_theme_stylebox_override("hover", box(Color(1.0, 0.87, 0.48, 0.17), Color.TRANSPARENT, 0))
	node.add_theme_stylebox_override("focus", box(Color.TRANSPARENT, Color(0.96, 0.81, 0.52, 0.7), 1))
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

static func paper_button(node: Button) -> void:
	node.add_theme_stylebox_override("normal", box(Color("d8c6aa"), Color("8a775d"), 1))
	node.add_theme_stylebox_override("hover", box(Color("e9c573"), Color("80603a"), 1))
	node.add_theme_stylebox_override("pressed", box(Color("bfa37b"), Color("6d5134"), 1))
	node.add_theme_stylebox_override("focus", box(Color.TRANSPARENT, Color("c28b42"), 1))
	node.add_theme_font_size_override("font_size", 13)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		node.add_theme_color_override(key, INK)
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

static func paper_panel(node: PanelContainer) -> void:
	node.add_theme_stylebox_override("panel", box(Color("e8dcc3"), Color("806747"), 2))

static func game_panel(node: PanelContainer) -> void:
	node.add_theme_stylebox_override("panel", box(Color(0.045, 0.05, 0.052, 0.90), Color("6a6862"), 1))

# Main-menu labels are actual Buttons, not hotspots over baked-in writing.
# The paper images are high-resolution assets; Godot scales them once.
static func dossier_button(node: Button) -> void:
	var normal := StyleBoxTexture.new()
	normal.texture = preload("res://assets/ui/paper_button_off.png")
	var hover := StyleBoxTexture.new()
	hover.texture = preload("res://assets/ui/paper_button.png")
	var pressed := StyleBoxTexture.new()
	pressed.texture = preload("res://assets/ui/paper_button.png")
	node.add_theme_stylebox_override("normal", normal)
	node.add_theme_stylebox_override("hover", hover)
	node.add_theme_stylebox_override("pressed", pressed)
	node.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	node.add_theme_font_size_override("font_size", 15)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		node.add_theme_color_override(key, INK)
	node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
