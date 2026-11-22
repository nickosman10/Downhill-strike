extends Node
## Switches between the course-select menu and a race.

var current: Node


func _ready() -> void:
	show_menu()


func _clear() -> void:
	if current:
		current.queue_free()
		current = null


func show_menu() -> void:
	_clear()
	var menu := Menu.new()
	menu.start_race.connect(start_race)
	add_child(menu)
	current = menu


func start_race() -> void:
	_clear()
	var race := Race.new()
	race.setup(Courses.all()[Game.course_index], Game.mode)
	race.exit_to_menu.connect(show_menu, CONNECT_DEFERRED)
	race.restart.connect(start_race, CONNECT_DEFERRED)
	add_child(race)
	current = race
