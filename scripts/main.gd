extends Node
## Switches between the menu and a race, with a loading card while a course is built.

var current: Node
var _busy := false


func _ready() -> void:
	show_menu()


func show_menu() -> void:
	Music.play_menu()
	_switch("", func() -> Node:
		var menu := Menu.new()
		menu.start_race.connect(start_race)
		return menu)


func start_race() -> void:
	var c: Dictionary = Campaign.course_for(Game.campaign_stage) if Game.mode == Game.Mode.CAMPAIGN \
		else Courses.all()[Game.course_index]
	_switch(c.name, func() -> Node:
		var race := Race.new()
		race.setup(c, Game.mode)
		race.exit_to_menu.connect(show_menu, CONNECT_DEFERRED)
		return race)


## Building a course takes a moment: put up a card first, so the screen never just freezes.
func _switch(what: String, make: Callable) -> void:
	if _busy:
		return
	_busy = true
	if current:
		current.queue_free()
		current = null
	var card := _loading_card(what)
	add_child(card)
	await get_tree().process_frame
	await get_tree().process_frame
	current = make.call()
	add_child(current)
	card.queue_free()
	_busy = false


func _loading_card(what: String) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 90
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.13)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.grow_vertical = Control.GROW_DIRECTION_BOTH
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	layer.add_child(col)
	var title := Label.new()
	title.text = "LOADING"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Ui.title(title, 72, Ui.YELLOW, 14)
	col.add_child(title)
	if what != "":
		var sub := Label.new()
		sub.text = what
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		Ui.inked(sub, 26, Ui.PAPER, 8)
		col.add_child(sub)
	return layer
