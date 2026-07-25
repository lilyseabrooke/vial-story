class_name NPCInteractable
extends InteractableBase
## A hand-placed NPC the player can talk to. See docs/design/systems.md,
## system 13 ("NPC interaction").
##
## Static placement only -- movement/scheduling is future work. npc_id must
## match a registered CharacterDef.id and the npc_id used by the NPC's
## NPCLineSetDef entries.

@export var npc_id: String = ""


func interact(_main: MainScene) -> void:
	NPCDialogue.talk_to(npc_id)
