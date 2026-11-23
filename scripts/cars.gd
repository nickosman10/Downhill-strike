class_name Cars
extends RefCounted
## The garage: cars from the anime with stats from their real specs
## (as tuned in the story). Bodies are built procedurally by CarModel from
## each car's dimensions and body style.
##
## stats: hp, weight kg, drive (FR / FF / 4WD / MR)
## body:  length, width, height (m), kind (hatch / notch / fastback / wedge /
##        roadster), lamps (popup / fixed), wing, tail, colours
## unlock: beat this car's driver in a downhill battle on its home course

const ROSTER := {
	"ae85": {"name": "Eight-Five (AE85)", "hp": 83, "kg": 940, "drive": "FR",
		"note": "The humble starter. Same body as the Eight-Six, a lot less engine.",
		"body": {"table": [[0, .60, .62, .74, .66], [0.05, .66, .69, .80, .74], [0.25, .70, .74, .81, .77], [0.7, .75, .80, .81, .77], [1.30, .80, .86, .81, .76], [1.40, .81, .92, .81, .72], [2.05, .84, 1.30, .81, .64], [2.75, .86, 1.31, .81, .63], [3.35, .88, 1.00, .81, .70], [3.50, .89, .94, .81, .74], [4.10, .89, .93, .80, .76], [4.18, .82, .85, .76, .70]],
		"glass": [1.40, 3.35], "roof": [2.05, 2.75], "side": [1.45, 3.25], "b": [2.45, 2.55], "wb": 2.40, "fo": 0.85, "tire": 0.28, "bumper": "black", "L": 4.18, "W": 1.625, "H": 1.335, "kind": "notch", "lamps": "fixed", "wing": "none", "tail": "bar"},
		"paint": Color(0.72, 0.06, 0.07), "lower": Color(0.03, 0.03, 0.035), "panda": true},
	"ae86": {"name": "Eight-Six (AE86)", "hp": 150, "kg": 925, "drive": "FR",
		"note": "Light, balanced and legendary downhill. Corners like nothing else.",
		"body": {"kind": "ae86"},
		"paint": Color(0.96, 0.96, 0.94), "lower": Color(0.05, 0.05, 0.06), "panda": true},
	"s13": {"name": "S13 Silvia", "hp": 220, "kg": 1200, "drive": "FR",
		"note": "Turbo FR coupe. Easy to slide, good all-rounder.",
		"body": {"table": [[0, .56, .58, .78, .70], [0.06, .62, .66, .83, .78], [0.4, .66, .71, .845, .80], [1.45, .76, .80, .845, .78], [1.55, .77, .86, .845, .74], [2.25, .80, 1.26, .845, .65], [3.05, .82, 1.27, .845, .64], [3.70, .86, .96, .845, .74], [3.85, .87, .92, .845, .78], [4.40, .87, .91, .83, .78], [4.47, .80, .83, .79, .72]],
		"glass": [1.55, 3.70], "roof": [2.25, 3.05], "side": [1.6, 3.55], "b": [2.75, 2.85], "wb": 2.475, "fo": 0.95, "tire": 0.30, "bumper": "body", "L": 4.47, "W": 1.69, "H": 1.29, "kind": "notch", "lamps": "fixed", "wing": "lip", "tail": "bar"},
		"paint": Color(0.9, 0.9, 0.92), "lower": Color(0.45, 0.46, 0.5), "panda": true},
	"180sx": {"name": "180SX", "hp": 225, "kg": 1220, "drive": "FR",
		"note": "Pop-up lights and a long fastback. Drifts willingly.",
		"body": {"table": [[0, .52, .54, .78, .70], [0.06, .58, .62, .83, .78], [0.4, .63, .68, .845, .80], [1.5, .75, .79, .845, .78], [1.6, .76, .85, .845, .74], [2.3, .79, 1.26, .845, .65], [2.95, .81, 1.27, .845, .64], [4.15, .86, .94, .845, .78], [4.45, .87, .90, .83, .80], [4.54, .78, .82, .79, .74]],
		"glass": [1.6, 4.15], "roof": [2.3, 2.95], "side": [1.65, 3.6], "b": [2.95, 3.05], "wb": 2.475, "fo": 0.95, "tire": 0.30, "bumper": "body", "L": 4.54, "W": 1.69, "H": 1.29, "kind": "fastback", "lamps": "popup", "wing": "duck", "tail": "wide"},
		"paint": Color(0.92, 0.92, 0.94), "lower": Color(0.8, 0.8, 0.82), "panda": false},
	"eg6": {"name": "EG6 Civic", "hp": 170, "kg": 1050, "drive": "FF",
		"note": "High-revving front-driver. Grips hard, hates to slide.",
		"body": {"table": [[0, .52, .56, .78, .70], [0.06, .60, .64, .83, .78], [0.35, .66, .72, .85, .80], [0.95, .76, .82, .85, .78], [1.05, .77, .88, .85, .74], [1.85, .80, 1.32, .85, .66], [3.05, .84, 1.33, .85, .66], [3.85, .88, 1.05, .84, .72], [4.00, .86, .95, .82, .76], [4.07, .78, .82, .78, .72]],
		"glass": [1.05, 3.85], "roof": [1.85, 3.05], "side": [1.1, 3.6], "b": [2.55, 2.65], "wb": 2.57, "fo": 0.80, "tire": 0.29, "bumper": "body", "L": 4.07, "W": 1.695, "H": 1.35, "kind": "hatch", "lamps": "fixed", "wing": "roof", "tail": "bar"},
		"paint": Color(0.78, 0.06, 0.06), "lower": Color(0.6, 0.04, 0.04), "panda": false},
	"sil80": {"name": "Sil-Eighty", "hp": 230, "kg": 1170, "drive": "FR",
		"note": "180SX body with a Silvia nose. Light and pointy, built for two.",
		"body": {"table": [[0, .56, .58, .78, .70], [0.06, .62, .66, .83, .78], [0.4, .66, .71, .845, .80], [1.5, .75, .79, .845, .78], [1.6, .76, .85, .845, .74], [2.3, .79, 1.26, .845, .65], [2.95, .81, 1.27, .845, .64], [4.15, .86, .94, .845, .78], [4.42, .87, .90, .83, .80], [4.50, .78, .82, .79, .74]],
		"glass": [1.6, 4.15], "roof": [2.3, 2.95], "side": [1.65, 3.6], "b": [2.95, 3.05], "wb": 2.475, "fo": 0.92, "tire": 0.30, "bumper": "body", "L": 4.5, "W": 1.69, "H": 1.29, "kind": "fastback", "lamps": "fixed", "wing": "duck", "tail": "wide"},
		"paint": Color(0.15, 0.3, 0.75), "lower": Color(0.9, 0.9, 0.92), "panda": true},
	"r32": {"name": "R32 GT-R", "hp": 500, "kg": 1430, "drive": "4WD",
		"note": "Twin-turbo four-wheel drive monster. Brutal out of corners, heavy into them.",
		"body": {"table": [[0, .58, .62, .82, .74], [0.06, .66, .70, .86, .80], [0.4, .70, .75, .877, .84], [1.45, .80, .85, .877, .82], [1.55, .81, .91, .877, .76], [2.25, .84, 1.31, .877, .68], [3.15, .86, 1.32, .877, .68], [3.65, .88, 1.00, .877, .78], [3.85, .90, .97, .877, .82], [4.47, .90, .96, .86, .82], [4.545, .82, .86, .82, .76]],
		"glass": [1.55, 3.65], "roof": [2.25, 3.15], "side": [1.6, 3.55], "b": [2.8, 2.9], "wb": 2.615, "fo": 0.90, "tire": 0.32, "bumper": "body", "L": 4.55, "W": 1.755, "H": 1.34, "kind": "notch", "lamps": "fixed", "wing": "big", "tail": "round"},
		"paint": Color(0.06, 0.06, 0.07), "lower": Color(0.04, 0.04, 0.05), "panda": false},
	"fc3s": {"name": "FC3S RX-7", "hp": 260, "kg": 1270, "drive": "FR",
		"note": "Rotary wedge with pop-ups. Precise, fast and very well balanced.",
		"body": {"table": [[0, .46, .48, .78, .70], [0.08, .52, .56, .83, .78], [0.5, .60, .65, .845, .80], [1.55, .74, .78, .845, .78], [1.65, .75, .84, .845, .72], [2.35, .78, 1.24, .845, .64], [2.95, .80, 1.25, .845, .63], [3.85, .85, .96, .845, .76], [4.25, .86, .90, .83, .80], [4.335, .78, .82, .79, .74]],
		"glass": [1.65, 3.85], "roof": [2.35, 2.95], "side": [1.7, 3.5], "b": [9.0, 9.0], "wb": 2.43, "fo": 0.95, "tire": 0.30, "bumper": "body", "L": 4.335, "W": 1.69, "H": 1.27, "kind": "wedge", "lamps": "popup", "wing": "duck", "tail": "wide"},
		"paint": Color(0.95, 0.95, 0.96), "lower": Color(0.85, 0.85, 0.87), "panda": false},
	"fd3s": {"name": "FD3S RX-7", "hp": 350, "kg": 1250, "drive": "FR",
		"note": "Sequential-turbo rotary. Fast everywhere, needs a firm hand.",
		"body": {"table": [[0, .42, .44, .80, .70], [0.1, .50, .54, .86, .80], [0.55, .58, .64, .88, .82], [1.55, .72, .77, .88, .80], [1.65, .73, .82, .88, .72], [2.35, .76, 1.20, .88, .62], [2.85, .78, 1.21, .88, .62], [3.75, .84, .95, .88, .80], [4.2, .86, .90, .86, .82], [4.285, .78, .82, .82, .76]],
		"glass": [1.65, 3.75], "roof": [2.35, 2.85], "side": [1.7, 3.45], "b": [9.0, 9.0], "wb": 2.425, "fo": 0.93, "tire": 0.32, "bumper": "body", "L": 4.28, "W": 1.76, "H": 1.23, "kind": "wedge", "lamps": "popup", "wing": "big", "tail": "round"},
		"paint": Color(0.98, 0.84, 0.05), "lower": Color(0.85, 0.7, 0.03), "panda": false},
	"evo3": {"name": "Evo III", "hp": 270, "kg": 1260, "drive": "4WD",
		"note": "Rally-bred four-door. Huge grip, launches like a rocket.",
		"body": {"table": [[0, .58, .62, .80, .72], [0.06, .66, .72, .84, .78], [0.4, .72, .78, .847, .80], [1.25, .82, .87, .847, .78], [1.35, .83, .93, .847, .72], [2.05, .86, 1.40, .847, .66], [3.05, .88, 1.41, .847, .66], [3.55, .92, 1.04, .847, .76], [3.75, .94, 1.00, .847, .80], [4.25, .94, .99, .83, .80], [4.31, .86, .90, .79, .74]],
		"glass": [1.35, 3.55], "roof": [2.05, 3.05], "side": [1.4, 3.45], "b": [2.65, 2.75], "wb": 2.50, "fo": 0.92, "tire": 0.31, "bumper": "body", "L": 4.31, "W": 1.695, "H": 1.42, "kind": "notch", "lamps": "fixed", "wing": "big", "tail": "bar"},
		"paint": Color(0.94, 0.94, 0.95), "lower": Color(0.1, 0.1, 0.12), "panda": false},
	"ek9": {"name": "EK9 Civic Type R", "hp": 185, "kg": 1050, "drive": "FF",
		"note": "Screaming VTEC hatch. Sharp front end, stable but grippy.",
		"body": {"table": [[0, .52, .56, .78, .70], [0.08, .60, .65, .83, .78], [0.4, .66, .72, .85, .80], [1.02, .76, .82, .85, .78], [1.12, .77, .88, .85, .74], [1.95, .80, 1.33, .85, .66], [3.15, .84, 1.34, .85, .66], [3.95, .88, 1.05, .84, .72], [4.10, .86, .95, .82, .76], [4.18, .78, .82, .78, .72]],
		"glass": [1.12, 3.95], "roof": [1.95, 3.15], "side": [1.17, 3.7], "b": [2.65, 2.75], "wb": 2.62, "fo": 0.83, "tire": 0.29, "bumper": "body", "L": 4.18, "W": 1.695, "H": 1.36, "kind": "hatch", "lamps": "fixed", "wing": "roof", "tail": "bar"},
		"paint": Color(0.96, 0.96, 0.96), "lower": Color(0.9, 0.9, 0.9), "panda": false},
	"s2000": {"name": "S2000", "hp": 250, "kg": 1250, "drive": "FR",
		"note": "High-revving roadster. Light steering, snappy when pushed.",
		"body": {"table": [[0, .50, .52, .80, .72], [0.08, .58, .62, .86, .80], [0.5, .65, .70, .875, .82], [1.75, .78, .82, .875, .80], [1.85, .79, .86, .875, .76], [2.25, .80, 1.20, .875, .70], [2.32, .80, .86, .875, .80], [3.30, .84, .90, .875, .82], [4.05, .86, .90, .86, .82], [4.135, .78, .82, .82, .76]],
		"glass": [1.85, 2.25], "roof": [0.0, 0.0], "side": [9.0, 9.0], "b": [9.0, 9.0], "cockpit": [2.35, 3.25], "wb": 2.40, "fo": 0.85, "tire": 0.31, "bumper": "body", "L": 4.135, "W": 1.75, "H": 1.285, "kind": "roadster", "lamps": "fixed", "wing": "none", "tail": "bar"},
		"paint": Color(0.92, 0.92, 0.93), "lower": Color(0.85, 0.85, 0.86), "panda": false},
	"r34": {"name": "R34 GT-R", "hp": 600, "kg": 1560, "drive": "4WD",
		"note": "The final boss. Enormous power and grip, carries a lot of weight.",
		"body": {"table": [[0, .60, .64, .84, .76], [0.06, .68, .72, .88, .82], [0.4, .72, .77, .892, .85], [1.45, .82, .87, .892, .83], [1.55, .83, .93, .892, .77], [2.25, .86, 1.33, .892, .69], [3.2, .88, 1.34, .892, .69], [3.70, .90, 1.02, .892, .79], [3.9, .92, .99, .892, .83], [4.52, .92, .98, .875, .83], [4.60, .84, .88, .83, .77]],
		"glass": [1.55, 3.70], "roof": [2.25, 3.2], "side": [1.6, 3.6], "b": [2.85, 2.95], "wb": 2.665, "fo": 0.90, "tire": 0.33, "bumper": "body", "L": 4.6, "W": 1.785, "H": 1.36, "kind": "notch", "lamps": "fixed", "wing": "big", "tail": "round"},
		"paint": Color(0.32, 0.12, 0.45), "lower": Color(0.2, 0.08, 0.3), "panda": false},
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
