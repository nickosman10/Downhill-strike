class_name Cars
extends RefCounted
## The garage: the cars and their stats, from their real specs as tuned in
## the story. Each car's shape is its Blender model, cars/<id>.glb.
##
## stats:  hp, weight kg, drive (FR / FF / 4WD / MR)
## unlock: beat this car's driver in a downhill battle on its home course

const ROSTER := {
	"ae85": {"name": "Eight-Five (AE85)", "hp": 83, "kg": 940, "drive": "FR",
		"note": "The humble starter. Same body as the Eight-Six, a lot less engine.",
		"paint": Color(0.72, 0.06, 0.07), "lower": Color(0.03, 0.03, 0.035)},
	"ae86": {"name": "Eight-Six (AE86)", "hp": 150, "kg": 925, "drive": "FR",
		"note": "Light, balanced and legendary downhill. Corners like nothing else.",
		"paint": Color(0.96, 0.96, 0.94), "lower": Color(0.05, 0.05, 0.06)},
	"s13": {"name": "S13 Silvia", "hp": 220, "kg": 1200, "drive": "FR",
		"note": "Turbo FR coupe. Easy to slide, good all-rounder.",
		"paint": Color(0.9, 0.9, 0.92), "lower": Color(0.45, 0.46, 0.5)},
	"180sx": {"name": "180SX", "hp": 225, "kg": 1220, "drive": "FR",
		"note": "Pop-up lights and a long fastback. Drifts willingly.",
		"paint": Color(0.92, 0.92, 0.94), "lower": Color(0.8, 0.8, 0.82)},
	"eg6": {"name": "EG6 Civic", "hp": 170, "kg": 1050, "drive": "FF",
		"note": "High-revving front-driver. Grips hard, hates to slide.",
		"paint": Color(0.78, 0.06, 0.06), "lower": Color(0.6, 0.04, 0.04)},
	"sil80": {"name": "Sil-Eighty", "hp": 230, "kg": 1170, "drive": "FR",
		"note": "180SX body with a Silvia nose. Light and pointy, built for two.",
		"paint": Color(0.15, 0.3, 0.75), "lower": Color(0.9, 0.9, 0.92)},
	"r32": {"name": "R32 GT-R", "hp": 500, "kg": 1430, "drive": "4WD",
		"note": "Twin-turbo four-wheel drive monster. Brutal out of corners, heavy into them.",
		"paint": Color(0.06, 0.06, 0.07), "lower": Color(0.04, 0.04, 0.05)},
	"fc3s": {"name": "FC3S RX-7", "hp": 260, "kg": 1270, "drive": "FR",
		"note": "Rotary wedge with pop-ups. Precise, fast and very well balanced.",
		"paint": Color(0.95, 0.95, 0.96), "lower": Color(0.85, 0.85, 0.87)},
	"fd3s": {"name": "FD3S RX-7", "hp": 350, "kg": 1250, "drive": "FR",
		"note": "Sequential-turbo rotary. Fast everywhere, needs a firm hand.",
		"paint": Color(0.98, 0.84, 0.05), "lower": Color(0.85, 0.7, 0.03)},
	"evo3": {"name": "Evo III", "hp": 270, "kg": 1260, "drive": "4WD",
		"note": "Rally-bred four-door. Huge grip, launches like a rocket.",
		"paint": Color(0.94, 0.94, 0.95), "lower": Color(0.1, 0.1, 0.12)},
	"ek9": {"name": "EK9 Civic Type R", "hp": 185, "kg": 1050, "drive": "FF",
		"note": "Screaming VTEC hatch. Sharp front end, stable but grippy.",
		"paint": Color(0.96, 0.96, 0.96), "lower": Color(0.9, 0.9, 0.9)},
	"s2000": {"name": "S2000", "hp": 250, "kg": 1250, "drive": "FR",
		"note": "High-revving roadster. Light steering, snappy when pushed.",
		"paint": Color(0.92, 0.92, 0.93), "lower": Color(0.85, 0.85, 0.86)},
	"r34": {"name": "R34 GT-R", "hp": 600, "kg": 1560, "drive": "4WD",
		"note": "The final boss. Enormous power and grip, carries a lot of weight.",
		"paint": Color(0.32, 0.12, 0.45), "lower": Color(0.2, 0.08, 0.3)},
}

const ORDER := ["ae85", "ae86", "s13", "eg6", "180sx", "sil80", "r32", "fc3s", "fd3s", "evo3", "ek9", "s2000", "r34"]
const START := "ae85"


static func get_car(id: String) -> Dictionary:
	return ROSTER.get(id, ROSTER[START])


## 0..10 bars for the garage screen, from the real numbers.
static func bars(id: String) -> Dictionary:
	var c := get_car(id)
	var pw: float = float(c.hp) / float(c.kg) * 1000.0   # hp per tonne
	var light := clampf((1600.0 - c.kg) / 70.0, 0.0, 10.0)
	var drift: float = {"FR": 8.5, "MR": 6.5, "4WD": 4.5, "FF": 3.0}[c.drive] + (light - 5.0) * 0.2
	if id == "ae86":
		drift += 1.5
	var handling: float = clampf(light * 0.6 + {"FR": 3.0, "FF": 3.4, "4WD": 3.6, "MR": 3.2}[c.drive] + (1.5 if id == "ae86" else 0.0), 0.0, 10.0)
	return {
		"Power": clampf(pw / 40.0, 0.5, 10.0),
		"Acceleration": clampf(pw / 40.0 + {"4WD": 1.5, "FR": 0.0, "FF": -0.3, "MR": 0.5}[c.drive], 0.5, 10.0),
		"Handling": handling,
		"Drift": clampf(drift, 0.5, 10.0),
		"Top speed": clampf(3.0 + c.hp / 85.0, 0.5, 10.0),
	}


## Physics parameters for PlayerCar / the AI.
static func physics(id: String) -> Dictionary:
	var c := get_car(id)
	var pw: float = c.hp * 745.7 * 0.85 / c.kg     # W/kg at the wheels
	var light := clampf((1600.0 - c.kg) / 700.0, 0.0, 1.0)
	var drive: String = c.drive
	return {
		"power": pw,
		"traction": {"FR": 5.6, "FF": 5.2, "4WD": 7.6, "MR": 6.0}[drive],
		"grip": 0.96 + light * 0.14 + {"4WD": 0.06, "FF": 0.02, "FR": 0.0, "MR": 0.03}[drive] + (0.05 if id == "ae86" else 0.0),
		"drift_g": {"FR": 1.0, "MR": 0.95, "4WD": 0.88, "FF": 0.78}[drive] + light * 0.1 + (0.08 if id == "ae86" else 0.0),
		"drift_angle": {"FR": 1.0, "MR": 0.85, "4WD": 0.75, "FF": 0.6}[drive],
		"drag": 0.00045 * (1.0 + (1.0 - light) * 0.3),
	}
