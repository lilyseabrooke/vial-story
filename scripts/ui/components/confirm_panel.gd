class_name ConfirmPanel
extends VBoxContainer
## Generic confirm/cancel prompt -- the general-purpose ConfirmationDialog
## ArtStudioDiscardConfirm's own docstring noted didn't exist yet. Owns the
## message label + two buttons + confirmed/cancelled signals + its own
## MenuKeyNav, so a host only needs to instance it, call set_message(), and
## connect the two signals. See docs/engine_roadmap.md, Phase 7.

signal confirmed
signal cancelled

@export var confirm_text: String = "Confirm"
@export var cancel_text: String = "Cancel"

var _message_label: Label
var _confirm_button: Button
var _cancel_button: Button


## Called once right after instantiate(), NOT @onready -- a host may call
## set_message() before this panel is ever added to the scene tree (it's
## only reparented into MenuScene on first open), so node refs and confirm_
## text/cancel_text must be resolved eagerly instead of waiting for _ready().
func setup() -> void:
	_message_label = $MessageLabel
	_confirm_button = $ConfirmButton
	_cancel_button = $CancelButton
	_confirm_button.text = confirm_text
	_cancel_button.text = cancel_text
	_confirm_button.pressed.connect(func() -> void: confirmed.emit())
	_cancel_button.pressed.connect(func() -> void: cancelled.emit())


func set_message(text: String) -> void:
	_message_label.text = text
