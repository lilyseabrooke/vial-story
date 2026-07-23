class_name CozyCard
extends PanelContainer
## A framed cozy panel with an optional header (Gabriela heading + optional
## flourish art slot) and a body VBoxContainer callers fill. The single shared
## "framed surface" object behind the HUD corner cards, the journal-menu
## sections, and the main-menu / character-creator panels, so every window in
## the game is literally the same chrome.
##
## The PanelContainer picks up theme/ui_theme.tres's cream-card StyleBox
## automatically. The header flourish (`$Root/Header/Flourish`) is an optional
## TextureRect that stays hidden until real art is assigned via set_flourish(),
## degrading to nothing — same graceful-fallback convention as the rest of the
## component library.
##
## Node refs are looked up on demand rather than cached via @onready, same
## reasoning as scripts/ui/components/item_slot.gd: callers may build a card
## detached from the SceneTree (e.g. a menu panel reparented in later), so
## @onready would never fire.

var body: VBoxContainer:
	get:
		return $Root/Body


func set_title(text: String) -> void:
	var title_label: Label = $Root/Header/TitleLabel
	title_label.text = text
	var has_title := text != ""
	($Root/Header as Control).visible = has_title
	($Root/HSep as Control).visible = has_title


func set_flourish(texture: Texture2D) -> void:
	var flourish: TextureRect = $Root/Header/Flourish
	flourish.texture = texture
	flourish.visible = texture != null
