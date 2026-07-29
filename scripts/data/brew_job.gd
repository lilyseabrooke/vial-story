class_name BrewJob
extends TimedJobBase
## A single brewing job in progress at a station. See docs/design/systems.md, system 4.

enum Status { BREWING, READY, COLLECTED }

var recipe: RecipeDef
var rolled_potency: float
var rolled_ease: float
var status: Status = Status.BREWING
var potion_count: int = 1
