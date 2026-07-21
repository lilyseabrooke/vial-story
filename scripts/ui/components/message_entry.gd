class_name MessageEntry
extends PanelContainer
## One row in MessageWall's scrollback -- fades in, lingers, then dims down
## to a translucent resting state rather than disappearing, so scrolling the
## wall back still finds it (see message_wall.gd). Hovering brightens a row
## back to full opacity and reveals its detail line (empty detail = nothing
## further to expand). Node refs are looked up on demand rather than cached
## via @onready, same reasoning as scripts/ui/components/item_slot.gd.

const FADE_IN_SECONDS := 0.25
const LINGER_SECONDS := 4.0
const FADE_OUT_SECONDS := 1.2
const REST_ALPHA := 0.55
const DIM_ALPHA := 0.12
const HOVER_ALPHA := 1.0

var _fade_tween: Tween


func _ready() -> void:
	modulate.a = 0.0
	(($VBox/HeaderLabel) as Label).autowrap_mode = TextServer.AUTOWRAP_WORD
	(($VBox/DetailLabel) as Label).autowrap_mode = TextServer.AUTOWRAP_WORD
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


## detail: shown only while hovered; pass "" for a row with nothing to expand.
func populate(header: String, detail: String, accent: Color = Color.WHITE) -> void:
	var header_label: Label = $VBox/HeaderLabel
	var detail_label: Label = $VBox/DetailLabel
	header_label.text = header
	header_label.modulate = accent
	detail_label.text = detail
	detail_label.visible = false
	_play_fade_in_then_dim()


func _play_fade_in_then_dim() -> void:
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", REST_ALPHA, FADE_IN_SECONDS)
	_fade_tween.tween_interval(LINGER_SECONDS)
	_fade_tween.tween_property(self, "modulate:a", DIM_ALPHA, FADE_OUT_SECONDS)


func _on_mouse_entered() -> void:
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", HOVER_ALPHA, 0.15)
	var detail_label: Label = $VBox/DetailLabel
	if detail_label.text != "":
		detail_label.visible = true


func _on_mouse_exited() -> void:
	($VBox/DetailLabel as Label).visible = false
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", DIM_ALPHA, 0.3)
