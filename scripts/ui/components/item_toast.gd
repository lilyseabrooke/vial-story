class_name ItemToast
extends PanelContainer
## One row in ItemToastFeed (scripts/ui/components/item_toast_feed.gd) --
## icon-with-quantity-badge, same corner-badge look as ItemSlot's inventory
## grid cells, plus the ingredient's name, so a received-item pops in the
## same visual language the player already reads in their satchel. Pops in,
## sits for LINGER_SECONDS, fades out, then frees itself -- the feed doesn't
## track its children's lifetimes, it just appends and lets each entry clean
## up on its own (see docs/design/systems.md system 16).
##
## Hover tooltip (name/quality/type) is composed via ItemTooltip
## (scripts/ui/item_tooltip.gd), the same shared builder ItemSlot's inventory
## grid cells use, so the two stay in sync by construction rather than by two
## copies of the same formatting. mouse_filter is STOP (rather than every
## other HUD overlay's IGNORE) specifically so this control is hit-testable
## for that tooltip -- and for _hovering below: while the mouse is over a
## toast it's pinned fully visible with no countdown running at all, so
## reading the tooltip never races the fade-out: countdown resumes fresh
## only once the mouse actually leaves.
##
## ingredient_id is public so ItemToastFeed can find a still-showing toast
## for the same ingredient and bump its quantity (add_quantity()) instead of
## spawning a second row.

const BADGE_OUTLINE_SIZE := 6
const POP_IN_SECONDS := 0.2
const SETTLE_SECONDS := 0.1
const LINGER_SECONDS := 2.6
const FADE_OUT_SECONDS := 0.45

enum _LifetimeMode { POP_IN, BUMP, PLAIN }

var ingredient_id: String
var _quantity := 0
var _tween: Tween
var _hovering := false


func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func populate(id: String, item_name: String, quality_label: String, type_label: String, quantity: int, tint: Color, icon: Texture2D = null) -> void:
	ingredient_id = id
	_quantity = quantity
	tooltip_text = ItemTooltip.compose(item_name, quality_label, type_label)

	var name_label: Label = $HBox/NameLabel
	name_label.text = item_name

	_update_badge()

	var icon_rect: TextureRect = $HBox/IconWrap/Icon
	var fallback_dot: Label = $HBox/IconWrap/FallbackDot
	if icon != null:
		icon_rect.texture = icon
		icon_rect.visible = true
		fallback_dot.visible = false
	else:
		icon_rect.texture = null
		icon_rect.visible = false
		fallback_dot.visible = true
		fallback_dot.add_theme_color_override("font_color", tint)

	UiFx.add_drop_shadow(self, 0.35, 6, Vector2(0, 4))
	_play_lifetime(_LifetimeMode.POP_IN)


## Called by ItemToastFeed when another unit of the same ingredient arrives
## while this toast is still showing, instead of spawning a second row.
## Restarts the linger/fade timer (with a small acknowledgment bump rather
## than a full pop-in) so the updated total gets a fresh read -- unless the
## mouse is currently over it, in which case _on_mouse_exited() is what
## starts the countdown, same as any other hover.
func add_quantity(delta: int) -> void:
	_quantity += delta
	_update_badge()
	if not _hovering:
		_play_lifetime(_LifetimeMode.BUMP)


func _on_mouse_entered() -> void:
	_hovering = true
	if _tween:
		_tween.kill()
	modulate.a = 1.0
	scale = Vector2.ONE


func _on_mouse_exited() -> void:
	_hovering = false
	_play_lifetime(_LifetimeMode.PLAIN)


func _update_badge() -> void:
	var badge: Label = $HBox/IconWrap/QuantityBadge
	badge.text = "%d" % _quantity
	badge.add_theme_color_override("font_color", UiPalette.CREAM_PAGE)
	badge.add_theme_color_override("font_outline_color", UiPalette.COCOA_INK)
	badge.add_theme_constant_override("outline_size", BADGE_OUTLINE_SIZE)


func _play_lifetime(mode: _LifetimeMode) -> void:
	if _tween:
		_tween.kill()

	_tween = create_tween()
	if mode == _LifetimeMode.POP_IN:
		modulate.a = 0.0
		scale = Vector2(0.85, 0.85)
	if mode != _LifetimeMode.PLAIN:
		_tween.tween_property(self, "modulate:a", 1.0, POP_IN_SECONDS)
		_tween.parallel().tween_property(self, "scale", Vector2(1.05, 1.05), POP_IN_SECONDS) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_tween.tween_property(self, "scale", Vector2.ONE, SETTLE_SECONDS)
	_tween.tween_interval(LINGER_SECONDS)
	_tween.tween_property(self, "modulate:a", 0.0, FADE_OUT_SECONDS)
	_tween.tween_callback(queue_free)
