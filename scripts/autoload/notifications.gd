extends Node
## Generic on-screen notification queue. Autoloaded as "Notifications". See
## docs/engine_roadmap.md, Phase 8.
##
## No state lives here beyond the signal itself -- push() just re-broadcasts
## to whoever's listening (NotificationFeed, wired into hud.gd). Generalizes
## ItemToastFeed's ingredient-gained-only toasts to any event: level-ups,
## quest completion, Resolve strain/collapse, and everything else that used
## to be console-only via hud.gd's log_message().

signal pushed(text: String, icon: Texture2D, tint: Color)


func push(text: String, icon: Texture2D = null, tint: Color = Color.WHITE) -> void:
	pushed.emit(text, icon, tint)
