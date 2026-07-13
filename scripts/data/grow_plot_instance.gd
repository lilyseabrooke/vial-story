class_name GrowPlotInstance
extends RefCounted
## Runtime grow plot. See docs/design/systems.md, system 7.

enum Status { EMPTY, GROWING, READY_TO_HARVEST }

var id: String
var status: Status = Status.EMPTY
var planted_seed: SeedDef = null
var planted_timestamp: int = 0
var ready_timestamp: int = 0
