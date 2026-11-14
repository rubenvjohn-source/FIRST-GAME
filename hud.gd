class_name HUD2D5
extends CanvasLayer

## Scoreboard, match clock, hazard label and announcement banner.
## Built entirely in code; it finds the GameManager / ObstacleManager by name.

@export var game_manager: GameManager2D5
@export var obstacle_manager: ObstacleManager2D5

var _p1_label: Label
var _p2_label: Label
var _timer_label: Label
var _banner_label: Label
var _hazard_label: Label
var _hint_label: Label
var _banner_tween: Tween


func _ready() -> void:
	layer = 10
	_build_ui()

	var root: Node = get_parent()
	if not game_manager:
		game_manager = root.get_node_or_null("GameManager") as GameManager2D5
	if not obstacle_manager:
		obstacle_manager = root.get_node_or_null("ObstacleManager") as ObstacleManager2D5

	if game_manager:
		game_manager.score_updated.connect(_on_score_updated)
		game_manager.match_timer_updated.connect(_on_timer_updated)
		game_manager.announcement_banner.connect(_show_banner)
	if obstacle_manager:
		obstacle_manager.hazard_activated.connect(_on_hazard_activated)


func _make_label(size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 8)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


## Places a label with explicit anchors + offsets so it stays put at any window size
func _place(l: Label, anchors: Vector4, offsets: Vector4, align: HorizontalAlignment) -> void:
	l.anchor_left = anchors.x
	l.anchor_top = anchors.y
	l.anchor_right = anchors.z
	l.anchor_bottom = anchors.w
	l.offset_left = offsets.x
	l.offset_top = offsets.y
	l.offset_right = offsets.z
	l.offset_bottom = offsets.w
	l.horizontal_alignment = align


func _build_ui() -> void:
	_p1_label = _make_label(40, Color(0.45, 0.7, 1.0))
	_p1_label.text = "P1  0"
	_place(_p1_label, Vector4(0, 0, 0, 0), Vector4(30, 30, 280, 90), HORIZONTAL_ALIGNMENT_LEFT)

	_p2_label = _make_label(40, Color(1.0, 0.45, 0.4))
	_p2_label.text = "0  P2"
	_place(_p2_label, Vector4(1, 0, 1, 0), Vector4(-280, 30, -30, 90), HORIZONTAL_ALIGNMENT_RIGHT)

	_timer_label = _make_label(48, Color.WHITE)
	_timer_label.text = "1:30"
	_place(_timer_label, Vector4(0.5, 0, 0.5, 0), Vector4(-150, 26, 150, 90), HORIZONTAL_ALIGNMENT_CENTER)

	_hazard_label = _make_label(22, Color(1.0, 0.85, 0.3))
	_place(_hazard_label, Vector4(0.5, 0, 0.5, 0), Vector4(-300, 92, 300, 124), HORIZONTAL_ALIGNMENT_CENTER)

	_banner_label = _make_label(64, Color(1.0, 0.9, 0.2))
	_place(_banner_label, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-560, -130, 560, -50), HORIZONTAL_ALIGNMENT_CENTER)
	_banner_label.modulate.a = 0.0

	_hint_label = _make_label(16, Color(0.85, 0.9, 1.0))
	_hint_label.text = "P1: WASD  Space=Jump  E/Shift=Shoot/Steal      P2: Arrows  Enter=Jump  Ctrl=Shoot/Steal      R=Rematch"
	_place(_hint_label, Vector4(0, 1, 1, 1), Vector4(0, -48, 0, -20), HORIZONTAL_ALIGNMENT_CENTER)
	_hint_label.add_theme_constant_override("outline_size", 5)


func _on_score_updated(p1: int, p2: int, _scorer: int, _points: int, _banner: String) -> void:
	_p1_label.text = "P1  %d" % p1
	_p2_label.text = "%d  P2" % p2


func _on_timer_updated(seconds: float) -> void:
	var total: int = int(ceil(seconds))
	_timer_label.text = "%d:%02d" % [total / 60, total % 60]
	_timer_label.add_theme_color_override("font_color", Color(1, 0.35, 0.3) if seconds <= 10.0 else Color.WHITE)


func _on_hazard_activated(title: String) -> void:
	_hazard_label.text = title


func _show_banner(text: String, duration: float) -> void:
	_banner_label.text = text
	if _banner_tween:
		_banner_tween.kill()
	_banner_label.modulate.a = 1.0
	_banner_tween = create_tween()
	_banner_tween.tween_interval(max(0.1, duration - 0.4))
	_banner_tween.tween_property(_banner_label, "modulate:a", 0.0, 0.4)
