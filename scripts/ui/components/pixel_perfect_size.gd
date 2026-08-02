class_name PixelPerfectSize
extends Control
## Pins a Control's rendered size to a fixed real screen-pixel count,
## independent of the window's canvas_items stretch scale.
##
## window/stretch/mode="canvas_items" applies one uniform transform to the
## whole rendered frame — there's no built-in per-node exemption, so any
## Control's size (specified in base-1920x1080 design units) gets scaled by
## whatever factor the current window size implies. World tiles/characters
## hide the resulting non-integer texel misalignment well; small, hard-edged
## pixel art icons show it as visible shimmer/aliasing. Counter-scaling the
## design-unit size here (so it nets out to a constant real-pixel size after
## the engine's transform is applied) keeps icons always sampled 1:1 against
## their source texture, at any window size.

@export var native_pixel_size := Vector2(48, 48)


func _ready() -> void:
	WindowScale.pin_size(self, native_pixel_size)
