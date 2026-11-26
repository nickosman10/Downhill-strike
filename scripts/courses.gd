class_name Courses
extends RefCounted
## The downhill courses. Eight are the real roads, traced from OpenStreetMap
## with real elevation ("data": tracks/<id>.json). Two have no map data yet
## and are hand-built from segments:
##   ["S", length_m, grade_pct?]                 straight
##   ["L"|"R", angle_deg, radius_m, grade_pct?]  left / right arc
## grade_pct is negative for downhill; when omitted the course default is used.


static func all() -> Array:
	return [
		{
			"id": "haruna",
			"name": "Mt. Haruna",
			"region": "Gunma",
			"data": "res://tracks/haruna.json",
			"blurb": "The real Route 33, from the pass by Lake Haruna down to the hot-spring town of Ikaho. Built from OpenStreetMap and real elevation data. Deep gutters line the inside of the hairpins.",
			"width": 7.0, "grade": -7.0, "time": "night",
			"rival": {"name": "Haruto Inaba", "car": "ae86", "skill": 0.93},
		},
		{
			"id": "myogi",
			"name": "Mt. Myogi",
			"region": "Gunma",
			"data": "res://tracks/myogi.json",
			"blurb": "The real Route 196 under the jagged peaks of Mt. Myogi, built from OpenStreetMap and survey data. Narrow, technical and never quite straight.",
			"width": 5.8, "grade": -7.5, "time": "night",
			"rival": {"name": "Sora Kaneda", "car": "r32", "skill": 0.97},
		},
		{
			"id": "akagi",
			"name": "Mt. Akagi",
			"region": "Gunma",
			"data": "res://tracks/akagi.json",
			"blurb": "The real Route 4 down Mt. Akagi toward Maebashi: wide two-lane road, fast straights and runs of numbered hairpins. Built from OpenStreetMap and survey data.",
			"width": 7.6, "grade": -6.5, "time": "night",
			"rival": {"name": "Ren Ishikawa", "car": "fd3s", "skill": 1.00},
		},
		{
			"id": "usui",
			"name": "Usui Pass",
			"region": "Gunma / Nagano",
			"data": "res://tracks/usui.json",
			"blurb": "The real old Route 18 over Usui Pass, from Karuizawa down to Yokokawa: 184 numbered corners, narrow and endlessly twisting. Built from OpenStreetMap and survey data.",
			"width": 5.6, "grade": -6.0, "time": "night",
			"rival": {"name": "Aoi Shimizu", "car": "sil80", "skill": 1.00},
		},
		{
			"id": "irohazaka",
			"name": "Irohazaka",
			"region": "Tochigi",
			"data": "res://tracks/irohazaka.json",
			"blurb": "The real First Irohazaka (Route 120), one-way downhill from Lake Chuzenji: 28 hairpins, each named after a character of the iroha alphabet. Built from OpenStreetMap and survey data.",
			"width": 7.0, "grade": -8.0, "time": "night",
			"rival": {"name": "Daichi Mori", "car": "evo3", "skill": 1.02},
		},
		{
			"id": "shomaru",
			"name": "Shomaru Pass",
			"region": "Saitama",
			"blurb": "Long, rough mountain road with tight mid-speed corners stacked one after another.",
			"width": 6.0, "grade": -6.5, "time": "night",
			"rival": {"name": "Yuto Sakamoto", "car": "ek9", "skill": 1.00},
			"segments": [
				["S", 100, -3], ["R", 100, 30], ["L", 80, 35], ["S", 120], ["R", 60, 50],
				["L", 140, 20], ["S", 90], ["R", 160, 17], ["L", 50, 60], ["S", 160, -8],
				["R", 90, 30], ["L", 90, 30], ["R", 120, 22], ["S", 110], ["L", 165, 15],
				["S", 80], ["R", 70, 40], ["L", 40, 80], ["S", 140], ["R", 150, 18],
				["S", 90], ["L", 100, 28], ["R", 80, 35], ["S", 130, -5],
			],
		},
		{
			"id": "tsuchisaka",
			"name": "Tsuchisaka",
			"region": "Gunma",
			"data": "res://tracks/tsuchisaka.json",
			"blurb": "The real Route 71 over Tsuchisaka Pass between Gunma and Saitama: long forest descents and tight hairpins. Built from OpenStreetMap and survey data.",
			"width": 7.8, "grade": -6.0, "time": "night",
			"rival": {"name": "Minato Kuroda", "car": "s13", "skill": 1.02},
		},
		{
			"id": "tsukuba",
			"name": "Mt. Tsukuba",
			"region": "Ibaraki",
			"blurb": "Fruit-line style descent: tight ups and downs through forest, with grip-sapping off-camber hairpins.",
			"width": 6.2, "grade": -7.0, "time": "night",
			"rival": {"name": "Itsuki Hara", "car": "eg6", "skill": 1.03},
			"segments": [
				["S", 90, -3], ["L", 90, 30], ["S", 110], ["R", 170, 14], ["S", 90],
				["L", 60, 55], ["R", 60, 55], ["S", 150, -9], ["L", 165, 15], ["S", 100],
				["R", 90, 32], ["L", 50, 70], ["S", 120], ["R", 175, 13], ["S", 80],
				["L", 175, 13], ["S", 130], ["R", 60, 60], ["L", 80, 40], ["S", 120, -4],
			],
		},
		{
			"id": "nanamagari",
			"name": "Hakone Nanamagari",
			"region": "Kanagawa",
			"data": "res://tracks/nanamagari.json",
			"blurb": "The real Route 732 through Hakone: the staircase of linked hairpins called the seven bends, then fast sweepers. Built from OpenStreetMap and survey data.",
			"width": 6.8, "grade": -8.5, "time": "night",
			"rival": {"name": "Hayato Ozawa", "car": "fc3s", "skill": 1.05},
		},
		{
			"id": "tsubaki",
			"name": "Tsubaki Line",
			"region": "Kanagawa",
			"data": "res://tracks/tsubaki.json",
			"blurb": "The real Route 75, the Tsubaki Line from Hakone down toward Yugawara and the sea: ridge-top switchbacks into long sweeping bends. Built from OpenStreetMap and survey data.",
			"width": 6.6, "grade": -7.0, "time": "night",
			"rival": {"name": "Riku Onodera", "car": "r34", "skill": 1.07},
		},
	]
