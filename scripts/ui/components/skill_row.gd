class_name SkillRow
extends HBoxContainer
## One skill's name/level/xp-progress row in GameMenu's Skills tab.
##
## Node refs are looked up on demand rather than cached via @onready: see
## the note in item_slot.gd — GameMenu builds its tab tree detached from the
## SceneTree, so @onready would never fire here.

func populate(display_name: String, level: int, current_xp: int, max_xp: int, icon: Texture2D = null) -> void:
	var icon_rect: TextureRect = $Icon
	icon_rect.texture = icon
	icon_rect.visible = icon != null

	var name_label: Label = $NameLabel
	name_label.text = display_name

	var level_label: Label = $LevelLabel
	level_label.text = "Lvl %d" % level

	var progress: ProgressBar = $Progress
	progress.max_value = max_xp
	progress.value = current_xp

	var progress_label: Label = $ProgressLabel
	progress_label.text = "%d / %d xp" % [current_xp, max_xp]
