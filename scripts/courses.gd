class_name Courses
extends RefCounted
## Downhill courses modelled on the real Japanese mountain passes.
## Layouts are hand-built approximations of each road's character
## (hairpin sequences, fast sections, width, gradient), not survey data.
##
## Segment format:
##   ["S", length_m, grade_pct?]                straight
##   ["L"|"R", angle_deg, radius_m, grade_pct?]  left / right arc
## grade_pct is negative for downhill; when omitted the course default is used.


static func all() -> Array:
	return [
		{
			"id": "haruna",
			"name": "Mt. Haruna",
			"region": "Gunma",
			"blurb": "Lakeside start, fast sweepers, then the famous run of five consecutive hairpins. Deep gutters line the inside of the hairpins.",
			"width": 6.6, "grade": -7.0, "time": "night",
			"rival": {"name": "Haruto Inaba", "car": "coupe", "color": Color(0.95, 0.85, 0.1), "skill": 1.0},
			"segments": [
				["S", 120, -3], ["R", 35, 140], ["S", 90], ["L", 60, 90], ["S", 70],
				["R", 90, 45], ["S", 140, -8], ["L", 40, 120], ["R", 30, 150], ["S", 160, -8],
				["L", 175, 14], ["S", 110], ["R", 50, 80], ["L", 35, 110], ["S", 150, -8],
				# five consecutive hairpins
				["R", 170, 13], ["S", 65], ["L", 175, 12], ["S", 60], ["R", 175, 12],
				["S", 60], ["L", 175, 12], ["S", 65], ["R", 170, 13],
				["S", 120], ["L", 45, 70], ["R", 60, 60], ["L", 40, 90], ["S", 160, -6],
				["R", 120, 30], ["S", 120], ["L", 70, 55], ["S", 140, -5],
			],
		},
		{
			"id": "myogi",
			"name": "Mt. Myogi",
			"region": "Gunma",
			"blurb": "Narrow and technical. Rocky walls, blind kinks and a long downhill straight into a vicious left-hander.",
			"width": 5.8, "grade": -7.5, "time": "night",
			"rival": {"name": "Sora Kaneda", "car": "sedan", "color": Color(0.2, 0.22, 0.26), "skill": 1.0},
			"segments": [
				["S", 80, -4], ["L", 70, 40], ["R", 80, 35], ["L", 60, 45], ["S", 90],
				["R", 140, 18], ["S", 70], ["L", 90, 25], ["R", 60, 40], ["S", 230, -9],
				["L", 120, 22], ["S", 60], ["R", 45, 60], ["L", 45, 60], ["R", 165, 15],
				["S", 90], ["L", 80, 30], ["R", 40, 70], ["S", 120], ["L", 160, 16],
				["S", 80], ["R", 100, 28], ["L", 50, 50], ["R", 50, 50], ["S", 150, -6],
				["L", 90, 35], ["S", 100, -4],
			],
		},
		{
			"id": "akagi",
			"name": "Mt. Akagi",
			"region": "Gunma",
			"blurb": "Wide two-lane road built for speed. Long straights punctuated by heavy-braking hairpins.",
			"width": 7.6, "grade": -6.5, "time": "night",
			"rival": {"name": "Ren Ishikawa", "car": "coupe", "color": Color(0.95, 0.95, 0.97), "skill": 1.06},
			"segments": [
				["S", 160, -4], ["R", 40, 160], ["S", 200, -7], ["L", 170, 18], ["S", 220, -8],
				["R", 170, 18], ["S", 180, -7], ["L", 50, 120], ["S", 120], ["R", 90, 40],
				["S", 240, -8], ["L", 175, 16], ["S", 160], ["R", 30, 200], ["L", 30, 200],
				["S", 140], ["R", 175, 17], ["S", 230, -8], ["L", 80, 50], ["R", 60, 70],
				["S", 150], ["L", 165, 20], ["S", 200, -6], ["R", 45, 120], ["S", 120, -4],
			],
		},
		{
			"id": "usui",
			"name": "Usui Pass",
			"region": "Gunma / Nagano",
			"blurb": "The old road with 184 numbered corners. Narrow, endlessly twisting, and almost never straight.",
			"width": 5.6, "grade": -6.0, "time": "night",
			"rival": {"name": "Aoi Shimizu", "car": "coupe", "color": Color(0.9, 0.9, 0.92), "skill": 1.04},
			"segments": [
				["S", 70, -3], ["L", 80, 30], ["R", 90, 28], ["L", 110, 22], ["R", 70, 35],
				["L", 60, 40], ["R", 130, 20], ["L", 90, 26], ["S", 40], ["R", 100, 24],
				["L", 120, 20], ["R", 80, 32], ["L", 70, 30], ["R", 150, 17], ["S", 50],
				["L", 100, 25], ["R", 90, 28], ["L", 80, 30], ["R", 60, 45], ["L", 140, 18],
				["S", 60], ["R", 110, 22], ["L", 90, 26], ["R", 80, 30], ["L", 70, 35],
				["R", 120, 20], ["S", 50], ["L", 100, 24], ["R", 60, 40], ["S", 90, -4],
			],
		},
		{
			"id": "irohazaka",
			"name": "Irohazaka",
			"region": "Tochigi",
			"blurb": "A one-way descent famous for its hairpins, each named after a character of the old iroha alphabet.",
			"width": 7.0, "grade": -8.0, "time": "night",
			"rival": {"name": "Daichi Mori", "car": "hatch", "color": Color(0.85, 0.1, 0.1), "skill": 1.03},
			"segments": [
				["S", 110, -4], ["R", 60, 80], ["S", 120], ["L", 170, 13], ["S", 70],
				["R", 170, 13], ["S", 90], ["L", 150, 15], ["S", 140, -9], ["R", 175, 12],
				["S", 60], ["L", 175, 12], ["S", 60], ["R", 170, 13], ["S", 110],
				["L", 60, 60], ["R", 50, 70], ["S", 120], ["L", 175, 13], ["S", 70],
				["R", 175, 13], ["S", 70], ["L", 170, 14], ["S", 120], ["R", 90, 35],
				["S", 100], ["L", 175, 12], ["S", 60], ["R", 175, 12], ["S", 140, -5],
			],
		},
		{
			"id": "shomaru",
			"name": "Shomaru Pass",
			"region": "Saitama",
			"blurb": "Long, rough mountain road with tight mid-speed corners stacked one after another.",
			"width": 6.0, "grade": -6.5, "time": "night",
			"rival": {"name": "Yuto Sakamoto", "car": "sedan", "color": Color(0.1, 0.3, 0.75), "skill": 1.05},
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
			"blurb": "Wide, fast and flowing. High-speed sweepers where horsepower and nerve matter most.",
			"width": 7.8, "grade": -6.0, "time": "night",
			"rival": {"name": "Minato Kuroda", "car": "sedan", "color": Color(0.55, 0.55, 0.6), "skill": 1.04},
			"segments": [
				["S", 180, -4], ["L", 50, 150], ["S", 160], ["R", 70, 110], ["S", 140],
				["L", 90, 70], ["S", 200, -8], ["R", 120, 45], ["S", 150], ["L", 60, 130],
				["R", 60, 130], ["S", 180], ["L", 150, 28], ["S", 160], ["R", 80, 90],
				["S", 220, -7], ["L", 100, 55], ["S", 120, -4],
			],
		},
		{
			"id": "tsukuba",
			"name": "Mt. Tsukuba",
			"region": "Ibaraki",
			"blurb": "Fruit-line style descent: tight ups and downs through forest, with grip-sapping off-camber hairpins.",
			"width": 6.2, "grade": -7.0, "time": "night",
			"rival": {"name": "Itsuki Hara", "car": "hatch", "color": Color(0.1, 0.55, 0.3), "skill": 1.05},
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
			"blurb": "\"Seven bends\": a staircase of linked hairpins carved into the Hakone hillside.",
			"width": 6.8, "grade": -8.5, "time": "night",
			"rival": {"name": "Hayato Ozawa", "car": "coupe", "color": Color(0.1, 0.1, 0.12), "skill": 1.08},
			"segments": [
				["S", 120, -4], ["R", 45, 120], ["S", 150], ["L", 70, 60], ["S", 100],
				# the seven bends
				["R", 160, 15], ["S", 45], ["L", 165, 14], ["S", 45], ["R", 165, 14],
				["S", 45], ["L", 165, 14], ["S", 45], ["R", 165, 14], ["S", 45],
				["L", 165, 14], ["S", 45], ["R", 160, 15],
				["S", 160, -7], ["L", 80, 50], ["R", 60, 70], ["S", 140, -5],
			],
		},
		{
			"id": "tsubaki",
			"name": "Tsubaki Line",
			"region": "Kanagawa",
			"blurb": "Hakone's long ridge road: tight switchbacks up high, opening into fast, sweeping bends toward the coast.",
			"width": 6.6, "grade": -7.0, "time": "night",
			"rival": {"name": "Riku Onodera", "car": "coupe", "color": Color(0.75, 0.05, 0.08), "skill": 1.1},
			"segments": [
				["S", 100, -4], ["L", 160, 16], ["S", 70], ["R", 165, 15], ["S", 70],
				["L", 120, 22], ["S", 120], ["R", 80, 40], ["L", 60, 60], ["S", 180, -8],
				["R", 45, 130], ["S", 160], ["L", 70, 80], ["S", 150], ["R", 100, 50],
				["S", 200, -7], ["L", 40, 160], ["R", 60, 90], ["S", 130], ["L", 170, 15],
				["S", 140, -5],
			],
		},
	]
