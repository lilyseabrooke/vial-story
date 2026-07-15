class_name QuestEntry
extends VBoxContainer
## One quest's header/description block in GameMenu's Journal tab.
##
## Node refs are resolved and the button connected inside populate() rather
## than @onready/_ready(): see the note in item_slot.gd — GameMenu builds its
## tab tree detached from the SceneTree, so _ready() would never fire here.
## Safe to connect per-populate() since update_journal() rebuilds a fresh
## QuestEntry instance every time rather than reusing one.

signal turn_in_pressed(quest_id: String)

var _quest_id: String = ""


func populate(quest_id: String, display_name: String, description: String, color: Color, show_turn_in: bool) -> void:
	_quest_id = quest_id

	var name_label: Label = $HeaderRow/NameLabel
	name_label.text = display_name
	name_label.add_theme_color_override("font_color", color)

	var description_label: Label = $DescriptionLabel
	description_label.text = description

	var turn_in_button: Button = $HeaderRow/TurnInButton
	turn_in_button.visible = show_turn_in
	turn_in_button.pressed.connect(func() -> void: turn_in_pressed.emit(_quest_id))
