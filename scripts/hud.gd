class_name GameHud
extends CanvasLayer
## Owns the debug HUD (status labels for clock/inventory/skills/Resolve),
## the Escape menu shell, and the brew/supply panels — the
## "presenting information and menu chrome" half of what used to be
## main.gd. Connects directly to every autoload signal whose only effect is
## a label/log update; signals whose effect also touches world geometry
## (e.g. Herbalism harvest signals updating a grow-plot Interactable) stay
## wired in main.gd instead, which orchestrates both this and RoomBuilder.

const END_REASON_NAMES := ["slept", "collapsed from staying up too late", "collapsed (Resolve hit zero)"]
const MAX_ROLL_LOG_ENTRIES := 20
const ROLL_DISPLAY_SCENE := preload("res://scenes/ui/components/RollDisplay.tscn")
const ITEM_TOAST_FEED_SCENE := preload("res://scenes/ui/components/ItemToastFeed.tscn")
const NOTIFICATION_FEED_SCENE := preload("res://scenes/ui/components/NotificationFeed.tscn")
const RESOLVE_VIAL_SCENE := preload("res://scenes/ui/hud/ResolveVial.tscn")
const LEY_LINE_MINIGAME_PANEL_SCENE := preload("res://scenes/ui/LeyLineMinigamePanel.tscn")
const PLANAR_RIFT_MINIGAME_PANEL_SCENE := preload("res://scenes/ui/PlanarRiftMinigamePanel.tscn")

var brew_panel: BrewMenu
var discover_panel: VBoxContainer
var supply_panel: VBoxContainer
var class_panel: ChoiceListMenu
var alchemy_lab_panel: AlchemyLabMenu
var garden_panel: GardenMenu
var pantry_storage_panel: PantryStorageMenu
var art_studio_picker_panel: ArtStudioPicker
var art_studio_discard_confirm_panel: ArtStudioDiscardConfirm
var curse_panel: CursePanel

var _station_id: String = ""
var _pantry_menu_id: String = ""
var _art_studio_menu_id: String = ""
var _curse_menu_id: String = ""
var _starting_ingredients: Dictionary = {}

var _almanac: AlmanacClock
var _screen_fade: ScreenFade
var _materials_pouch: MaterialsPouch
var _resolve_vial: ResolveVial
var _game_over_label: Label
var _interact_prompt: PanelContainer
var _interact_prompt_label: Label
var _prompt_tween: Tween
var _game_menu: GameMenu
var _menu_scene: MenuScene
var _pantry_window: PantryWindow
var _pantry_tween: Tween
var _curse_inventory_window: CurseInventoryWindow
var _curse_inventory_tween: Tween
var _roll_display: RollDisplay
var _item_toast_feed: ItemToastFeed
var _notification_feed: NotificationFeed
var _roll_log: Array[Dictionary] = []   # most-recent-first, capped at MAX_ROLL_LOG_ENTRIES
var _attempt_puzzle_panel: AttemptPuzzlePanel
var _ley_line_panel: LeyLineMinigamePanel
var _ley_line_overlay: LeyLineArenaOverlay
var _rift_panel: PlanarRiftMinigamePanel

var _upgrade_buttons: Dictionary = {}   # upgrade_id -> Button


func build(starting_ingredients: Dictionary) -> void:
	_starting_ingredients = starting_ingredients

	_screen_fade = ScreenFade.new()
	_screen_fade.build()
	add_child(_screen_fade)

	# Resolve meter — top-left, drawn as a filling potion vial. Doubled in
	# size to match the 2x world-camera zoom; pivot stays at the default
	# top-left corner (already the pinned corner here) so it grows down-right
	# in place.
	_resolve_vial = RESOLVE_VIAL_SCENE.instantiate()
	_resolve_vial.position = Vector2(16, 16)
	_resolve_vial.scale = Vector2(2.0, 2.0)
	add_child(_resolve_vial)
	UiFx.add_drop_shadow(_resolve_vial, 0.4, 5, Vector2(0, 4))

	# Almanac clock + materials pouch — top-right, stacked in a right-pinned
	# column (fixed 400px wide — doubled to match the 2x world-camera zoom via
	# AlmanacClock/MaterialsPouch's own real font sizes, not a Control.scale
	# transform, which just stretches already-rasterized glyphs and blurs —
	# 16px from the top/right corner, growing down).
	var top_right := VBoxContainer.new()
	top_right.anchor_left = 1.0
	top_right.anchor_right = 1.0
	top_right.offset_left = -416.0
	top_right.offset_right = -16.0
	top_right.offset_top = 16.0
	top_right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	top_right.grow_vertical = Control.GROW_DIRECTION_END
	top_right.add_theme_constant_override("separation", 8)
	add_child(top_right)

	_almanac = AlmanacClock.new()
	_almanac.build()
	top_right.add_child(_almanac)
	UiFx.add_drop_shadow(_almanac, 0.4, 5, Vector2(0, 4))

	_materials_pouch = MaterialsPouch.new()
	_materials_pouch.build()
	top_right.add_child(_materials_pouch)
	UiFx.add_drop_shadow(_materials_pouch, 0.4, 5, Vector2(0, 4))

	# Controls hint moved off the always-on HUD into a "?" help toggle,
	# bottom-left, so the corner stays uncluttered.
	var help_button := Button.new()
	help_button.text = "?"
	help_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	help_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	help_button.position = Vector2(16, -52)
	help_button.custom_minimum_size = Vector2(36, 36)
	# Doubled in size to match the 2x world-camera zoom. Pivot is set to the
	# button's bottom-left corner (its fixed anchor point) so it grows
	# up-right in place instead of drifting past the bottom of the screen.
	help_button.pivot_offset = Vector2(0.0, 36.0)
	help_button.scale = Vector2(2.0, 2.0)
	add_child(help_button)

	var help_popover := PanelContainer.new()
	help_popover.theme_type_variation = &"SmallFramedPanel"
	help_popover.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	help_popover.grow_vertical = Control.GROW_DIRECTION_BEGIN
	help_popover.visible = false
	add_child(help_popover)
	UiFx.add_drop_shadow(help_popover, 0.4, 5, Vector2(0, 4))

	var help_label := Label.new()
	help_label.theme_type_variation = &"CaptionLabel"
	help_label.text = "WASD move · E interact · Esc/Q menu · Space pause · 1/2/3 speed · R drain Resolve (debug)"
	help_label.custom_minimum_size = Vector2(480, 0)
	help_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	help_popover.add_child(help_label)

	# Doubled to match the help button, and repositioned from the button's
	# actual (already-doubled) top edge rather than a hardcoded offset — the
	# old fixed "-96" was tuned for the button's pre-doubling height and
	# started overlapping once the button grew. Pivoted at its own bottom-left
	# corner (get_combined_minimum_size() is synchronous, so this is valid
	# immediately, no need to wait a frame) so it grows upward from a fixed
	# gap above the button instead of drifting into it.
	const BUTTON_POPOVER_GAP := 16.0
	var button_top := help_button.position.y - help_button.pivot_offset.y * (help_button.scale.y - 1.0)
	var popover_size := help_popover.get_combined_minimum_size()
	help_popover.position = Vector2(16, button_top - BUTTON_POPOVER_GAP - popover_size.y)
	help_popover.pivot_offset = Vector2(0.0, popover_size.y)
	help_popover.scale = Vector2(2.0, 2.0)

	help_button.pressed.connect(func() -> void:
		help_popover.visible = not help_popover.visible
	)

	# Game Over — stays directly on screen (terminal state), not in the menu.
	_game_over_label = Label.new()
	# Not CaptionLabel -- that variation's font_color has reduced alpha, which
	# would fight the DANGER modulate below and mute this message instead of
	# making it read as urgent. Font size just happens to match CaptionLabel's
	# (24) coincidentally, so it's a plain override rather than a shared type.
	_game_over_label.add_theme_font_size_override("font_size", 24)
	_game_over_label.modulate = UiPalette.DANGER
	_game_over_label.visible = false
	_game_over_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_game_over_label.position = Vector2(-250, 16)
	_game_over_label.custom_minimum_size = Vector2(500, 0)
	_game_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_game_over_label)

	# Interact prompt — a cozy pill at bottom-center, hidden when there's nothing
	# to interact with.
	_interact_prompt = PanelContainer.new()
	_interact_prompt.theme_type_variation = &"SmallFramedPanel"
	_interact_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_interact_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_interact_prompt.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_interact_prompt.position = Vector2(0, -72)
	_interact_prompt.visible = false
	add_child(_interact_prompt)
	UiFx.add_drop_shadow(_interact_prompt, 0.4, 5, Vector2(0, 4))

	_interact_prompt_label = Label.new()
	_interact_prompt_label.theme_type_variation = &"SubheadingLabel"
	_interact_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Doubled via font size rather than Control.scale — this pill already
	# uses scale.y for its unfurl/collapse animation (see set_prompt()) and
	# resizes width to fit its text each time, so a transform scale would
	# fight both the animation and the anchor-centered pivot math.
	_interact_prompt.add_child(_interact_prompt_label)

	# Everything else lives in the Escape menu instead of the HUD. Not added
	# as a child here — MenuScene.open() reparents it into its body on first
	# open (same as brew_panel/supply_panel), and a Control only needs to be
	# in the tree for its own logic (Save/Return button handlers) to run.
	_game_menu = GameMenu.new()
	_game_menu.build()

	_attempt_puzzle_panel = AttemptPuzzlePanel.new()
	_attempt_puzzle_panel.build()

	# Instanced from a scene (not .new()) so its minigame tunables are
	# editable in the inspector on LeyLineMinigamePanel.tscn; build() still
	# constructs the panel's children in code, same as the other HUD panels.
	# Hosted in its own chromeless LeyLineArenaOverlay rather than MenuScene --
	# see that class's doc header for why.
	_ley_line_panel = LEY_LINE_MINIGAME_PANEL_SCENE.instantiate()
	_ley_line_panel.build()
	_ley_line_overlay = LeyLineArenaOverlay.new()
	_ley_line_overlay.build(_ley_line_panel)
	add_child(_ley_line_overlay)

	# Instanced from a scene (not .new()) so its portal-timer tunables are
	# editable in the inspector on PlanarRiftMinigamePanel.tscn, same as the
	# ley line panel above.
	_rift_panel = PLANAR_RIFT_MINIGAME_PANEL_SCENE.instantiate()
	_rift_panel.build()

	brew_panel = BrewMenu.new()
	brew_panel.build()
	brew_panel.brew_confirmed.connect(_on_brew_confirmed)
	brew_panel.notice.connect(log_message)

	# The pantry is its own detached window (see PantryWindow) that rides
	# alongside the brew menu rather than nesting inside its frame. Lives on the
	# HUD layer, hidden until the brew menu opens.
	_pantry_window = PantryWindow.new()
	_pantry_window.build()
	_pantry_window.visible = false
	add_child(_pantry_window)
	UiFx.add_drop_shadow(_pantry_window)

	discover_panel = VBoxContainer.new()
	discover_panel.add_child(MenuKeyNav.new())
	_rebuild_discover_panel()

	supply_panel = VBoxContainer.new()
	supply_panel.add_child(MenuKeyNav.new())
	for ingredient in ContentRegistry.ingredients:
		var ingredient_button := Button.new()
		ingredient_button.text = "Buy %s (%d)" % [ingredient.display_name, ingredient.buy_price]
		ingredient_button.pressed.connect(on_buy_ingredient_button_pressed.bind(ingredient))
		supply_panel.add_child(ingredient_button)
	for seed_def in ContentRegistry.seeds:
		var seed_button := Button.new()
		seed_button.text = "Buy %s (%d)" % [seed_def.display_name, seed_def.buy_price]
		seed_button.pressed.connect(on_buy_seed_button_pressed.bind(seed_def))
		supply_panel.add_child(seed_button)
	for upgrade in ContentRegistry.upgrades:
		var upgrade_button := Button.new()
		upgrade_button.text = "Buy upgrade: %s (%d)" % [upgrade.display_name, upgrade.cost]
		upgrade_button.pressed.connect(on_buy_upgrade_button_pressed.bind(upgrade))
		_upgrade_buttons[upgrade.id] = upgrade_button
		supply_panel.add_child(upgrade_button)

	alchemy_lab_panel = AlchemyLabMenu.new()
	alchemy_lab_panel.build()
	alchemy_lab_panel.notice.connect(log_message)

	garden_panel = GardenMenu.new()
	garden_panel.build()
	garden_panel.notice.connect(log_message)

	pantry_storage_panel = PantryStorageMenu.new()
	pantry_storage_panel.build()
	pantry_storage_panel.notice.connect(log_message)

	art_studio_picker_panel = ArtStudioPicker.new()
	art_studio_picker_panel.build()
	art_studio_picker_panel.chosen.connect(_on_art_studio_chosen)
	art_studio_picker_panel.cancelled.connect(_on_art_studio_picker_cancelled)

	art_studio_discard_confirm_panel = ArtStudioDiscardConfirm.new()
	art_studio_discard_confirm_panel.build()
	art_studio_discard_confirm_panel.discard_confirmed.connect(_on_art_studio_discard_confirmed)
	art_studio_discard_confirm_panel.kept.connect(func(_studio_id: String) -> void: close_menu())

	curse_panel = preload("res://scenes/ui/CursePanel.tscn").instantiate()
	curse_panel.setup()

	# Same detached-window-riding-alongside-a-MenuScene-panel pattern as
	# _pantry_window/BrewMenu — split out so the curse panel itself stays
	# short instead of a full inventory grid pushing it off-screen. The two
	# panels talk to each other through GameHud: a picked ingredient flows
	# straight into the tray, and any tray change flows back into a refresh.
	_curse_inventory_window = CurseInventoryWindow.new()
	_curse_inventory_window.build()
	_curse_inventory_window.visible = false
	_curse_inventory_window.slot_pressed.connect(curse_panel.add_to_tray)
	curse_panel.tray_changed.connect(_refresh_curse_inventory_window)
	add_child(_curse_inventory_window)
	UiFx.add_drop_shadow(_curse_inventory_window)

	class_panel = preload("res://scenes/ui/components/ChoiceListMenu.tscn").instantiate()
	class_panel.add_child(MenuKeyNav.new())
	var effort_options: Array[ChoiceOption] = []
	for effort in [Academy.Effort.LOW, Academy.Effort.NORMAL, Academy.Effort.HIGH]:
		effort_options.append(ChoiceOption.make(str(effort), "%s (-%d Resolve)" % [
			Academy.EFFORT_NAMES[effort], Academy.EFFORT_RESOLVE_COST[effort]
		]))
	class_panel.populate(effort_options)
	class_panel.selected.connect(func(id: String) -> void: on_attend_class_button_pressed(int(id) as Academy.Effort))

	_menu_scene = MenuScene.new()
	add_child(_menu_scene)
	# The Ley Line minigame no longer goes through MenuScene at all (see
	# LeyLineArenaOverlay) -- it has no Esc/close-button route to walk away
	# from once started, so there's nothing for this handler to guard for it.
	_menu_scene.closed.connect(func() -> void:
		# Same walk-away guard for the Planar Rift minigame: closing the menu
		# by any route while a session is still open (i.e. the player hadn't
		# matched a sequence or timed out yet) counts as leaving it.
		if Summoning.is_minigame_active():
			Summoning.abort_rift_minigame()
			log_message("You step back from the rift — the portal fades without a summoning.")
		# The pantry window only ever rides with the brew menu, so hiding it on
		# any menu close is correct (and covers every close route — Esc, walking
		# away, a confirmed brew). Same reasoning for the curse inventory
		# window riding with curse_panel.
		_hide_pantry()
		_hide_curse_inventory()
	)

	_roll_display = ROLL_DISPLAY_SCENE.instantiate()
	# Doubled in size to match the 2x world-camera zoom. Pivot is set to the
	# card's own bottom-right corner (its fixed anchor point, per its .tscn
	# offsets) so it grows up-left in place instead of overshooting past the
	# bottom-right of the screen -- read from RollDisplay.CARD_SIZE itself
	# (not a duplicated literal) so the two can never drift out of sync again
	# the way a half-size pivot once did.
	_roll_display.pivot_offset = RollDisplay.CARD_SIZE
	_roll_display.scale = Vector2(2.0, 2.0)
	add_child(_roll_display)

	_item_toast_feed = ITEM_TOAST_FEED_SCENE.instantiate()
	# Mirror of the RollDisplay pivot fix above, but for a bottom-left anchor:
	# pivot at the box's own bottom-left corner so the doubled feed grows
	# up-right in place instead of overshooting past the screen's left edge.
	_item_toast_feed.pivot_offset = Vector2(0.0, ItemToastFeed.FEED_SIZE.y)
	_item_toast_feed.scale = Vector2(2.0, 2.0)
	add_child(_item_toast_feed)
	Inventory.ingredient_gained.connect(func(ingredient_id: String, quantity: int, tier: int) -> void:
		_item_toast_feed.show_item(ingredient_id, quantity, tier)
	)

	_notification_feed = NOTIFICATION_FEED_SCENE.instantiate()
	# Anchored top-center in its own .tscn and scaled to match the 2x
	# world-camera zoom, same convention as RollDisplay/ItemToastFeed above --
	# pivot at top-center so it grows down in place.
	_notification_feed.pivot_offset = Vector2(NotificationFeed.FEED_SIZE.x / 2.0, 0.0)
	_notification_feed.scale = Vector2(2.0, 2.0)
	add_child(_notification_feed)
	Notifications.pushed.connect(func(text: String, icon: Texture2D, tint: Color) -> void:
		_notification_feed.show_notification(text, icon, tint)
	)
	QuestManager.quest_completed.connect(func(id: String) -> void:
		var quest := ContentRegistry.get_quest(id)
		log_message("Quest complete: %s!" % (quest.display_name if quest != null else id))
	)

	_connect_autoload_signals()

	update_clock_label()
	update_ingredients_label()
	update_materials_label()
	update_skills_label()
	update_resolve_meter()


func _connect_autoload_signals() -> void:
	Clock.minute_tick.connect(func(_timestamp: int) -> void:
		update_clock_label()
	)
	Clock.day_started.connect(func(day_number: int, _day_type: int) -> void:
		log_message("Day %d (%s) begins." % [day_number, Clock.day_name()])
		update_clock_label()
		print("Day %d (%s) begins." % [day_number, Clock.day_name()])
	)
	Clock.day_ended.connect(func(reason: int) -> void:
		log_message("Day ended: %s" % END_REASON_NAMES[reason])
		print("Day ended: %s" % END_REASON_NAMES[reason])
	)
	Clock.speed_level_changed.connect(func(level: int) -> void:
		_almanac.sync_speed(level)
	)
	Clock.time_skip_started.connect(func() -> void:
		# Close whatever menu is open right away (e.g. class_panel when attending
		# class) instead of leaving it visible to close itself once the screen
		# fades back in. Also lets MenuScene.close()'s own `Clock.is_paused =
		# false` land before end_day()/skip_to() captures `was_paused` for the
		# skip, so the pause state they restore afterward is correct.
		close_menu()
		_screen_fade.play()
	)
	Brewing.brew_started.connect(func(station_id: String, recipe_id: String) -> void:
		log_message("Started brewing %s." % _potion_display_name(recipe_id))
		print("Brew started at %s: %s" % [station_id, recipe_id])
	)
	Brewing.brew_ready.connect(func(station_id: String, recipe_id: String) -> void:
		log_message("%s is ready at %s!" % [recipe_id, station_id])
		print("Brew ready at %s: %s" % [station_id, recipe_id])
	)
	Brewing.brew_collected.connect(func(_collected_station_id: String, recipe_id: String, potency: float, ease_value: float) -> void:
		log_message("Collected %s!" % _potion_display_name(recipe_id))
		print("Collected %s — potency %.1f, ease %.1f" % [recipe_id, potency, ease_value])
	)
	Brewing.brew_botched.connect(func(station_id: String, recipe_id: String) -> void:
		log_message("Brew botched at %s: %s! Resolve took a hit." % [station_id, recipe_id])
		print("Brew botched at %s: %s" % [station_id, recipe_id])
	)
	Brewing.brew_roll_resolved.connect(func(_brewing_station_id: String, _recipe_id: String, roll: Dictionary) -> void:
		_show_roll(roll, "alchemy")
	)
	Skills.leveled_up.connect(func(skill_id: String, new_level: int) -> void:
		log_message("%s leveled up to %d!" % [skill_id.capitalize(), new_level])
		print("%s leveled up to %d." % [skill_id, new_level])
	)
	Resolve.resolve_changed.connect(func(_current: int, _max_resolve: int) -> void:
		update_resolve_meter()
	)
	Resolve.strained_changed.connect(func(is_strained: bool) -> void:
		if is_strained:
			log_message("Resolve is strained — all skill bonuses are halved.")
		print("Strained: %s" % is_strained)
		update_resolve_meter()
	)
	Inventory.materials_changed.connect(func(_amount: int) -> void:
		update_materials_label()
	)
	Shop.potion_sold.connect(func(potion_id: String, price: int) -> void:
		log_message("Sold %s for %d Materials — waiting in the shop coffers." % [potion_id, price])
		print("Sold %s for %d Materials." % [potion_id, price])
	)
	Shop.coffers_collected.connect(func(amount: int) -> void:
		update_materials_label()
		print("Collected %d Materials from the shop coffers." % amount)
	)
	Curse.curse_activated.connect(func(_instance_id: String, curse_id: String) -> void:
		var curse := ContentRegistry.get_curse(curse_id)
		log_message("A curse takes hold: %s" % (curse.description if curse else curse_id))
		print("Curse activated: %s" % curse_id)
	)
	Curse.curse_dispelled.connect(func(_instance_id: String, curse_id: String) -> void:
		log_message("The curse has been dispelled!")
		print("Curse dispelled: %s" % curse_id)
		if has_menu_content(curse_panel):
			close_menu()
	)
	Economy.upgrade_purchased.connect(_on_upgrade_purchased)
	Academy.attended_class.connect(func() -> void:
		print("Attended class.")
	)
	Academy.absence_recorded.connect(func(absences: int) -> void:
		log_message("Missed class today. Absences: %d" % absences)
		print("Absence recorded. Total: %d" % absences)
	)
	Academy.exam_graded.connect(func(passed: bool, score: float, strikes: int) -> void:
		log_message("Exam %s! Score: %.0f, Strikes: %d" % ["passed" if passed else "FAILED", score, strikes])
		print("Exam %s. Score: %.1f, Strikes: %d" % ["passed" if passed else "failed", score, strikes])
	)
	Academy.class_performance_rolled.connect(func(result: Dictionary) -> void:
		_show_roll(result, "focus")
	)
	Academy.class_reward_rolled.connect(func(result: Dictionary) -> void:
		_show_roll(result, "focus")
	)
	Academy.class_reward_granted.connect(func(_reward_type: String, description: String) -> void:
		log_message("Class reward: %s" % description)
	)
	Academy.game_over.connect(func() -> void:
		_game_over_label.text = "GAME OVER — The Academy has revoked your selling privileges."
		_game_over_label.visible = true
		print("GAME OVER: strikes reached the limit.")
	)
	Demonology.writ_started.connect(func(_book_id: String) -> void:
		log_message("A new writ takes shape at the Contract Book.")
	)
	Demonology.writ_first_draft_done.connect(func(_book_id: String, quality: float) -> void:
		log_message("First draft of the writ finished (quality %.0f) -- revising automatically." % quality)
		print("Writ first draft done: quality %.1f" % quality)
	)
	Demonology.writ_revised.connect(func(book_id: String, revisions_completed: int, quality: float) -> void:
		print("Writ revised at %s: revision %d, quality %.1f" % [book_id, revisions_completed, quality])
	)
	Demonology.writ_submitted.connect(func(book_id: String, roll: Dictionary, ingredients: Dictionary, drawback_messages: Array) -> void:
		_show_roll(roll, "demonology")
		var ingredient_summary: Array[String] = []
		for id in ingredients:
			ingredient_summary.append("%d %s" % [ingredients[id], id])
		var drawback_summary := "; ".join(drawback_messages) if not drawback_messages.is_empty() else "no immediate drawbacks"
		log_message("Writ submitted! Received: %s. %s" % [", ".join(ingredient_summary), drawback_summary])
		print("Writ submitted at %s -- ingredients: %s, drawbacks: %s" % [book_id, ingredient_summary, drawback_messages])
		update_ingredients_label()
	)
	Demonology.consequence_triggered.connect(func(message: String) -> void:
		log_message(message)
		print("Delayed demonic consequence: %s" % message)
	)
	Draconology.stash_resolved.connect(func(stash_id: String, roll: Dictionary, ingredients: Dictionary) -> void:
		_show_roll(roll, "draconology")
		var ingredient_summary: Array[String] = []
		for id in ingredients:
			ingredient_summary.append("%d %s" % [ingredients[id], id])
		log_message("The Dragon's Stash gives up its hoard! Received: %s." % ", ".join(ingredient_summary))
		print("Dragon's Stash resolved at %s -- ingredients: %s" % [stash_id, ingredient_summary])
		update_ingredients_label()
	)
	LeyLines.meditation_started.connect(func(_node_id: String) -> void:
		log_message("You settle into meditation at the ley line...")
	)
	LeyLines.meditation_cancelled.connect(func(_node_id: String) -> void:
		log_message("You break from meditation -- the ley line's rhythm is lost.")
	)
	LeyLines.meditation_check_rolled.connect(func(_node_id: String, surge_id: String, roll: Dictionary) -> void:
		if surge_id == "none":
			return
		_show_roll(roll, "arcane_history")
		if not roll.get("passed", false):
			log_message("A surge of %s ripples through the ley line -- you can't quite grasp it. Meditation continues." % surge_id)
		print("Ley line Surge rolled: %s -- passed %s" % [surge_id, roll.get("passed", false)])
	)
	LeyLines.minigame_started.connect(func(node_id: String, difficulty: float, rounds: int, size: float, speed: float) -> void:
		_ley_line_panel.show_for(node_id, difficulty, rounds, size, speed)
		_ley_line_overlay.show_panel()
		log_message("The ley line surges, ready to resonate...")
	)
	LeyLines.minigame_resolved.connect(func(_node_id: String, _performance: float, tier: String, ingredients: Dictionary) -> void:
		_ley_line_overlay.hide_panel()
		var ingredient_summary: Array[String] = []
		for id in ingredients:
			ingredient_summary.append("%d %s" % [ingredients[id], id])
		if ingredient_summary.is_empty():
			log_message("The ley line settles (%s) -- nothing crystallized this time." % tier)
		else:
			log_message("The ley line settles (%s)! Received: %s." % [tier, ", ".join(ingredient_summary)])
		print("Ley line minigame resolved -- tier %s, ingredients: %s" % [tier, ingredient_summary])
		update_ingredients_label()
	)
	Summoning.rift_minigame_requested.connect(func(rift_id: String) -> void:
		_rift_panel.show_for(rift_id)
		open_menu(_rift_panel, "Planar Rift")
		log_message("The rift yawns open — trace a summoning sequence before it closes.")
	)
	Summoning.rift_quality_rolled.connect(func(_rift_id: String, _bundle_id: String, quality: float, roll: Dictionary) -> void:
		_show_roll(roll, "summoning")
		log_message("The summoning steadies at %s quality (%d%%)." % [Summoning.quality_word(quality), int(round(quality * 100.0))])
	)
	Summoning.rift_started.connect(func(rift_id: String, bundle_id: String, reward_multiplier: int) -> void:
		# start_rift() only fires from the minigame's success path now, so the
		# rift panel is what's open -- close it as the summon takes hold.
		if has_menu_content(_rift_panel):
			close_menu()
		var bundle := ContentRegistry.get_rift_bundle(bundle_id)
		var key_note := " (x%d, planar key%s!)" % [reward_multiplier, "s" if reward_multiplier - 1 != 1 else ""] if reward_multiplier > 1 else ""
		log_message("The rift begins drawing something through: %s%s." % [bundle.display_name if bundle else bundle_id, key_note])
		print("Rift started at %s: %s (x%d)" % [rift_id, bundle_id, reward_multiplier])
	)
	Summoning.rift_failed.connect(func(rift_id: String, resolve_cost: int) -> void:
		if has_menu_content(_rift_panel):
			close_menu()
		log_message("The Planar Rift collapses shut before the summoning takes — you lose %d Resolve." % resolve_cost)
		update_resolve_meter()
		print("Rift minigame failed at %s -- Resolve cost %d" % [rift_id, resolve_cost])
	)
	Summoning.rift_ready.connect(func(rift_id: String, bundle_id: String) -> void:
		log_message("The Planar Rift is ready to collect.")
		print("Rift ready at %s: %s" % [rift_id, bundle_id])
	)
	Summoning.rift_collected.connect(func(_rift_id: String, bundle_id: String, ingredients: Dictionary, material_delta: int, resolve_delta: int, quality: float, reward_multiplier: int) -> void:
		var bundle := ContentRegistry.get_rift_bundle(bundle_id)
		var ingredient_summary: Array[String] = []
		for id in ingredients:
			ingredient_summary.append("%d %s" % [ingredients[id], id])
		var outcome_parts: Array[String] = []
		if not ingredient_summary.is_empty():
			outcome_parts.append("received %s" % ", ".join(ingredient_summary))
		if material_delta != 0:
			outcome_parts.append("%s%d Materials" % ["+" if material_delta > 0 else "", material_delta])
		if resolve_delta != 0:
			outcome_parts.append("%s%d Resolve" % ["+" if resolve_delta > 0 else "", resolve_delta])
		var mult_note := " (x%d planar key bonus)" % reward_multiplier if reward_multiplier > 1 else ""
		log_message("%s [%s summon]%s %s" % [bundle.flavor_text if bundle else "", Summoning.quality_word(quality), mult_note, "; ".join(outcome_parts)])
		print("Rift collected: %s (quality %.2f, x%d) -- %s" % [bundle_id, quality, reward_multiplier, outcome_parts])
		update_ingredients_label()
		update_materials_label()
	)
	Transmutation.scrap_broken_down.connect(func(roll: Dictionary, ingredients: Dictionary) -> void:
		_show_roll(roll, "transmutation")
		var ingredient_summary: Array[String] = []
		for id in ingredients:
			ingredient_summary.append("%d %s" % [ingredients[id], id])
		log_message("Broke down Scrap! Received: %s." % ", ".join(ingredient_summary))
		print("Scrap broken down -- ingredients: %s" % [ingredient_summary])
		update_ingredients_label()
	)
	Transmutation.heap_resolved.connect(func(heap_id: String, roll: Dictionary, scrap_granted: int, ingredients: Dictionary) -> void:
		_show_roll(roll, "transmutation")
		var outcome_parts: Array[String] = ["%d Scrap" % scrap_granted]
		for id in ingredients:
			outcome_parts.append("%d %s" % [ingredients[id], id])
		log_message("The Scrap Heap gives up its haul! Received: %s." % ", ".join(outcome_parts))
		print("Scrap Heap resolved at %s -- %s" % [heap_id, outcome_parts])
		update_ingredients_label()
	)
	Alchemy.recipe_learned.connect(func(recipe_id: String) -> void:
		var recipe := Alchemy.get_learned_recipe(recipe_id)
		if recipe != null:
			var potion := ContentRegistry.get_potion(recipe.output_potion_id)
			log_message("Learned a new way to brew %s: %s!" % [potion.display_name if potion else recipe.output_potion_id, recipe.display_name])
		print("Learned recipe: %s" % recipe_id)
		brew_panel.refresh()
	)
	Alchemy.recipe_unlearned.connect(func(_recipe_id: String) -> void:
		brew_panel.refresh()
	)
	Alchemy.puzzle_attempted.connect(func(potion_id: String, success: bool) -> void:
		if not success:
			var potion := ContentRegistry.get_potion(potion_id)
			log_message("That combination didn't work for %s." % (potion.display_name if potion else potion_id))
		print("Puzzle attempted for %s: %s" % [potion_id, "success" if success else "failure"])
	)
	ArtStudio.session_started.connect(func(_studio_id: String) -> void:
		log_message("You settle in at the Art Studio, waiting for inspiration to strike...")
	)
	ArtStudio.roll_rolled.connect(func(_studio_id: String, roll: Dictionary) -> void:
		_show_roll(roll, "creativity")
	)
	ArtStudio.inspirations_offered.connect(func(_studio_id: String, offered_ids: Array) -> void:
		log_message("Inspiration strikes! %d idea(s) are waiting at the Art Studio." % offered_ids.size())
	)
	ArtStudio.no_inspiration.connect(func(_studio_id: String) -> void:
		log_message("Nothing comes to you this time -- the well needs a rest.")
	)
	ArtStudio.session_cancelled.connect(func(_studio_id: String) -> void:
		print("Art Studio session cancelled.")
	)
	ArtStudio.work_started.connect(func(_studio_id: String, inspiration_id: String) -> void:
		var def := ContentRegistry.get_inspiration(inspiration_id)
		log_message("You begin work on %s." % (def.display_name if def else inspiration_id))
	)
	ArtStudio.work_discarded.connect(func(_studio_id: String) -> void:
		log_message("You set the unfinished piece aside for good.")
	)
	ArtStudio.work_completed.connect(func(_studio_id: String, inspiration_id: String, roll: Dictionary, xp_gained: int) -> void:
		var def := ContentRegistry.get_inspiration(inspiration_id)
		_show_roll(roll, "creativity")
		log_message("Finished %s! Gained %d Creativity XP." % [def.display_name if def else inspiration_id, xp_gained])
		print("Art Studio work completed: %s, xp %d" % [inspiration_id, xp_gained])
	)


## Fans a roll out to both its transient callout (RollDisplay) and the
## persistent Escape-menu roll log (GameMenu's Rolls section) — every roll
## site in _connect_autoload_signals() goes through here instead of calling
## _roll_display directly, so the two never drift out of sync.
func _show_roll(roll: Dictionary, skill_id: String) -> void:
	_roll_display.show_roll(roll, skill_id)
	_roll_log.push_front({"skill_id": skill_id, "roll": roll})
	if _roll_log.size() > MAX_ROLL_LOG_ENTRIES:
		_roll_log.resize(MAX_ROLL_LOG_ENTRIES)
	_game_menu.update_rolls(_roll_log)


## Was routed to the MessageWall scrollback; playtesting showed rolls were the
## only part of that wall players actually tracked (see RollDisplay). Now
## routes to the Notifications queue (docs/engine_roadmap.md, Phase 8)
## instead of being console-only -- every level-up/quest/writ/dragon/ley
## line/summoning/scrap/alchemy/Art Studio message that already called this
## gets an on-screen toast for free.
func log_message(text: String) -> void:
	print(text)
	Notifications.push(text)


## The potion's own display name for a learned recipe id, falling back to the
## raw id if the recipe is somehow gone — recipe.display_name alone is just
## the method (e.g. "Ember Dust + Rift Glass"), not the potion's name.
func _potion_display_name(recipe_id: String) -> String:
	var recipe := Alchemy.get_learned_recipe(recipe_id)
	if recipe == null:
		return recipe_id
	var potion := ContentRegistry.get_potion(recipe.output_potion_id)
	return potion.display_name if potion != null else recipe.display_name


## The pill unfurls downward on appear and rolls back up on clear, matching the
## MenuScene windows' motion (default top-left pivot, scale.y). A text change
## while already showing just swaps the label with no animation.
func set_prompt(text: String) -> void:
	if text != "":
		_interact_prompt_label.text = text
		var was_hidden := not _interact_prompt.visible
		if _prompt_tween:
			_prompt_tween.kill()
		_interact_prompt.visible = true
		if was_hidden:
			_interact_prompt.scale = Vector2(1.0, 0.0)
			_interact_prompt.modulate.a = 0.0
		if _interact_prompt.scale.y < 1.0 or _interact_prompt.modulate.a < 1.0:
			_prompt_tween = create_tween().set_parallel(true)
			_prompt_tween.tween_property(_interact_prompt, "scale:y", 1.0, 0.15).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			_prompt_tween.tween_property(_interact_prompt, "modulate:a", 1.0, 0.12)
	elif _interact_prompt.visible:
		if _prompt_tween:
			_prompt_tween.kill()
		_prompt_tween = create_tween().set_parallel(true)
		_prompt_tween.tween_property(_interact_prompt, "scale:y", 0.0, 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		_prompt_tween.tween_property(_interact_prompt, "modulate:a", 0.0, 0.12)
		_prompt_tween.chain().tween_callback(func() -> void:
			_interact_prompt.visible = false
			_interact_prompt.scale = Vector2.ONE
			_interact_prompt.modulate.a = 1.0
		)


func is_menu_open() -> bool:
	return _menu_scene.is_open()


func has_menu_content(content: Control) -> bool:
	return _menu_scene.has_content(content)


func open_menu(content: Control, title: String) -> void:
	_menu_scene.open(content, title)


func close_menu() -> void:
	_menu_scene.close()


func toggle_menu(content: Control, title: String) -> void:
	if _menu_scene.has_content(content) and _menu_scene.is_open():
		_menu_scene.close()
	else:
		_menu_scene.open(content, title)


func toggle_game_menu() -> void:
	if _menu_scene.is_open():
		_menu_scene.close()
	else:
		_menu_scene.open(_game_menu, "Menu")


## Opens (refreshing first) or closes the brew menu for a specific station —
## multiple Alembics each need their own start_brew() target, so the station
## being managed is tracked per-open rather than fixed at boot. The brew
## station only lets the menu open when it has no job running, so there's no
## collect action here — a finished brew is auto-collected on interact
## instead (BrewStationInteractable).
func toggle_brew_menu(station_id: String) -> void:
	if _menu_scene.has_content(brew_panel) and _menu_scene.is_open() and _station_id == station_id:
		_menu_scene.close()
	else:
		_station_id = station_id
		brew_panel.set_station(station_id)
		brew_panel.refresh()
		open_menu(brew_panel, "Brewing")
		_show_pantry()


## Opens the Alchemy Lab menu (refreshing first) for the given manager's
## linked Alembics/Pantries. No toggle-to-close: re-entering the interactable
## and pressing E again just re-opens with fresh data.
func open_alchemy_lab_menu(items: Array[Dictionary]) -> void:
	alchemy_lab_panel.open_for(items)
	open_menu(alchemy_lab_panel, "Alchemy Lab")


## Opens the Garden menu (refreshing first) for the given manager's linked
## Grow Plots/Water Pumps. No toggle-to-close, same as open_alchemy_lab_menu().
func open_garden_menu(items: Array[Dictionary]) -> void:
	garden_panel.open_for(items)
	open_menu(garden_panel, "Garden")


## Opens (refreshing first) or closes the Pantry storage menu for a specific
## Pantry — same per-open station-context shape as toggle_brew_menu(), since
## multiple Pantries can exist.
func toggle_pantry_menu(pantry_id: String) -> void:
	if _menu_scene.has_content(pantry_storage_panel) and _menu_scene.is_open() and _pantry_menu_id == pantry_id:
		_menu_scene.close()
	else:
		_pantry_menu_id = pantry_id
		pantry_storage_panel.open_for(pantry_id)
		open_menu(pantry_storage_panel, "Pantry")


## Opens (refreshing first) or closes the curse-dispel panel for a specific
## CurseInteractable instance — same per-open instance-context shape as
## toggle_pantry_menu(), since more than one curse can be active at once.
func toggle_curse_menu(instance_id: String) -> void:
	if _menu_scene.has_content(curse_panel) and _menu_scene.is_open() and _curse_menu_id == instance_id:
		_menu_scene.close()
	else:
		_curse_menu_id = instance_id
		curse_panel.open_for(instance_id)
		open_menu(curse_panel, "Curse")
		_show_curse_inventory()


## Reveals the detached pantry window and parks it just to the left of the brew
## window. Positioning is deferred a frame so the brew window's rect has settled
## (get_window_rect() is deterministic, but the panel's min size can be dirty on
## the same frame the content was swapped in).
func _show_pantry() -> void:
	_pantry_window.refresh(_station_id)
	_pantry_window.visible = true
	_pantry_window.modulate.a = 0.0
	_position_pantry.call_deferred()


func _position_pantry() -> void:
	if not _pantry_window.visible:
		return
	var window_rect := _menu_scene.get_window_rect()
	var pantry_size := _pantry_window.get_combined_minimum_size()
	const GAP := 24.0
	_pantry_window.position = Vector2(
		window_rect.position.x - GAP - pantry_size.x,
		window_rect.position.y + (window_rect.size.y - pantry_size.y) * 0.5)

	if _pantry_tween:
		_pantry_tween.kill()
	_pantry_tween = create_tween()
	_pantry_tween.tween_property(_pantry_window, "modulate:a", 1.0, 0.14)


## Reveals the detached curse-ingredient-picker window and parks it just to
## the left of the curse window — same positioning trick as _show_pantry()/
## _position_pantry() above, deferred a frame for the same get_combined_
## minimum_size() staleness reason.
func _show_curse_inventory() -> void:
	_refresh_curse_inventory_window()
	_curse_inventory_window.visible = true
	_curse_inventory_window.modulate.a = 0.0
	_position_curse_inventory.call_deferred()


func _position_curse_inventory() -> void:
	if not _curse_inventory_window.visible:
		return
	var window_rect := _menu_scene.get_window_rect()
	var inventory_size := _curse_inventory_window.get_combined_minimum_size()
	const GAP := 24.0
	_curse_inventory_window.position = Vector2(
		window_rect.position.x - GAP - inventory_size.x,
		window_rect.position.y + (window_rect.size.y - inventory_size.y) * 0.5)

	if _curse_inventory_tween:
		_curse_inventory_tween.kill()
	_curse_inventory_tween = create_tween()
	_curse_inventory_tween.tween_property(_curse_inventory_window, "modulate:a", 1.0, 0.14)


## curse_panel.tray_changed's handler — keeps the inventory window's
## available counts in sync with whatever's currently sitting in the tray.
func _refresh_curse_inventory_window() -> void:
	_curse_inventory_window.refresh(curse_panel.get_tray_ids(), Curse.MAX_DISPEL_INGREDIENTS)


## Opens (refreshing first) or closes the Art Studio's Inspiration picker for
## a specific studio -- same per-open station-context shape as
## toggle_pantry_menu(). Only reachable while the studio's job is CHOOSING
## (ArtStudioInteractable.interact() is what routes here).
func toggle_art_studio_picker(studio_id: String) -> void:
	if _menu_scene.has_content(art_studio_picker_panel) and _menu_scene.is_open() and _art_studio_menu_id == studio_id:
		_menu_scene.close()
	else:
		_art_studio_menu_id = studio_id
		art_studio_picker_panel.open_for(studio_id)
		open_menu(art_studio_picker_panel, "Inspiration")


## Opens (refreshing first) or closes the Art Studio's discard-progress
## confirm prompt for a specific studio -- only reachable while the studio's
## job is WORKING (ArtStudioInteractable.interact() is what routes here).
func toggle_art_studio_discard_confirm(studio_id: String) -> void:
	if _menu_scene.has_content(art_studio_discard_confirm_panel) and _menu_scene.is_open() and _art_studio_menu_id == studio_id:
		_menu_scene.close()
	else:
		_art_studio_menu_id = studio_id
		art_studio_discard_confirm_panel.open_for(studio_id)
		open_menu(art_studio_discard_confirm_panel, "Discard Progress?")


func _on_art_studio_chosen(studio_id: String, inspiration_id: String) -> void:
	ArtStudio.choose_inspiration(studio_id, inspiration_id)
	close_menu()


func _on_art_studio_picker_cancelled(studio_id: String) -> void:
	ArtStudio.cancel_choice(studio_id)
	close_menu()
	log_message("You let the inspiration pass, for now.")


func _on_art_studio_discard_confirmed(studio_id: String) -> void:
	ArtStudio.discard_work(studio_id)
	close_menu()


func _hide_pantry() -> void:
	if not _pantry_window.visible:
		return
	if _pantry_tween:
		_pantry_tween.kill()
	_pantry_tween = create_tween()
	_pantry_tween.tween_property(_pantry_window, "modulate:a", 0.0, 0.12)
	_pantry_tween.tween_callback(func() -> void: _pantry_window.visible = false)


func _hide_curse_inventory() -> void:
	if not _curse_inventory_window.visible:
		return
	if _curse_inventory_tween:
		_curse_inventory_tween.kill()
	_curse_inventory_tween = create_tween()
	_curse_inventory_tween.tween_property(_curse_inventory_window, "modulate:a", 0.0, 0.12)
	_curse_inventory_tween.tween_callback(func() -> void: _curse_inventory_window.visible = false)


## Rebuilds discover_panel's buttons in place — one "Discover" button per
## potion that has puzzle criteria, for the Potion Book. Shown regardless of
## whether the player already knows a recipe for that potion — discovery
## always finds a *new* combination, never gated on prior progress — so this
## only needs building once (there's no learned-state dependency to react to,
## unlike the old per-recipe version). (The brewing side of this pairing now
## lives in BrewMenu, which owns its own refresh.)
func _rebuild_discover_panel() -> void:
	for child in discover_panel.get_children():
		if child is Control:   # keep the panel's MenuKeyNav (a plain Node) alive
			child.queue_free()

	for potion in ContentRegistry.potions:
		if potion.has_puzzle():
			var discover_button := Button.new()
			discover_button.text = "Discover: %s" % potion.display_name
			discover_button.pressed.connect(_on_discover_button_pressed.bind(potion))
			discover_panel.add_child(discover_button)


func _on_discover_button_pressed(potion: PotionDef) -> void:
	_attempt_puzzle_panel.show_for(potion)
	open_menu(_attempt_puzzle_panel, "Discover: %s" % potion.display_name)


## Runs a brew requested from BrewMenu. Success/botch feedback comes from the
## brew_started/brew_botched signal listeners above — start_brew() emits those
## synchronously before returning — so only the failure-to-start case is logged
## here. On an accepted attempt (a real brew *or* a botch, both of which consume
## the ingredients and leave nothing more to choose) the menu closes; on a
## rejection (e.g. a stale quick slot the player no longer has ingredients for)
## it stays open with the reason logged.
func _on_brew_confirmed(recipe: RecipeDef) -> void:
	var error := Brewing.start_brew(_station_id, recipe)
	if error != "":
		log_message("Couldn't brew %s: %s" % [recipe.display_name, error])
	else:
		close_menu()


func on_stock_button_pressed() -> void:
	var stocked_count := Shop.stock_all_potions()
	var collected := Shop.collect_coffers()

	var messages: Array[String] = []
	if stocked_count > 0:
		messages.append("Stocked %d potion(s)." % stocked_count)
	if collected > 0:
		messages.append("Collected %d Materials from the coffers." % collected)
	log_message(" ".join(messages) if not messages.is_empty() \
		else "Nothing to stock or collect.")


func on_buy_ingredient_button_pressed(ingredient: IngredientDef) -> void:
	var error := Economy.buy_ingredient(ingredient)
	log_message("Couldn't buy %s: %s" % [ingredient.display_name, error] if error != "" \
		else "Bought 1 %s." % ingredient.display_name)


func on_buy_upgrade_button_pressed(upgrade: UpgradeDef) -> void:
	var error := Economy.purchase_upgrade(upgrade)
	log_message("Couldn't buy %s: %s" % [upgrade.display_name, error] if error != "" \
		else "Purchased upgrade: %s." % upgrade.display_name)


func on_buy_seed_button_pressed(seed_def: SeedDef) -> void:
	var error := Economy.buy_seed(seed_def)
	log_message("Couldn't buy %s: %s" % [seed_def.display_name, error] if error != "" \
		else "Bought 1 %s." % seed_def.display_name)


func open_class_menu() -> void:
	toggle_menu(class_panel, "Attend Class")


func on_attend_class_button_pressed(effort: Academy.Effort) -> void:
	var error: String = await Academy.attend_class(effort)
	if error != "":
		log_message("Couldn't attend class: %s" % error)
		return
	# Already closed by the Clock.time_skip_started handler above, right as
	# the fade-out began.
	log_message("Attended class (%s) — running score up, Focus XP gained." % Academy.EFFORT_NAMES[effort])
	update_clock_label()


func _on_upgrade_purchased(upgrade_id: String) -> void:
	var button: Button = _upgrade_buttons.get(upgrade_id)
	if button:
		button.disabled = true
		button.text += " [OWNED]"


func update_clock_label() -> void:
	_almanac.update_time()


func update_ingredients_label() -> void:
	_game_menu.update_inventory()


func update_materials_label() -> void:
	_materials_pouch.set_amount(Inventory.materials)


func update_skills_label() -> void:
	_game_menu.update_skills()


func update_resolve_meter() -> void:
	_resolve_vial.set_values(Resolve.current, Resolve.max_resolve, Resolve.is_strained())
