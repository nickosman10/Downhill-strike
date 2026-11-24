class_name Campaign
extends RefCounted
## Story mode: one-on-one downhill battles in order, the way a season of
## street racing plays out. The same mountain comes back with new challengers,
## the cars get faster, and every win puts the loser's car in your garage.
## All drivers and teams are original characters. In the campaign you are the
## hero, and the hero always drives the Eight-Six.
##
## course: index into Courses.all()

const STAGES := [
	{"course": 0, "title": "Gas Station Rival", "rival": {"name": "Kenta Wada", "car": "ae85", "skill": 0.88, "team": "local"},
		"intro": "A kid from the gas station says nobody can beat him down Haruna in his Levin. Prove him wrong."},
	{"course": 0, "title": "Speed Club Challenge", "rival": {"name": "Shota Hirano", "car": "s13", "skill": 0.9, "team": "Touge Speed Club"},
		"intro": "The local club's number two heard about you. Turbo against a light car: drift where he can't."},
	{"course": 0, "title": "Slide Works", "rival": {"name": "Ryo Kanzaki", "car": "180sx", "skill": 0.93, "team": "Slide Works"},
		"intro": "A visiting team wants Haruna's record. Their leader drives a pop-up fastback and loves long slides."},
	{"course": 0, "title": "Yellow Lightning", "rival": {"name": "Jun Takase", "car": "fd3s", "skill": 0.94, "team": "Rotary Lab"},
		"intro": "A yellow rotary is lapping the pass every night. Far more power than you. The hairpins are your only chance."},
	{"course": 1, "title": "Myogi's Twin Turbo", "rival": {"name": "Sora Kaneda", "car": "r32", "skill": 0.95, "team": "Thunderhead"},
		"intro": "Away race on Myogi against a four-wheel-drive monster. He wins the straights. Win the corners."},
	{"course": 1, "title": "Night Chargers", "rival": {"name": "Kaito Uemura", "car": "eg6", "skill": 0.96, "team": "Night Chargers"},
		"intro": "A front-drive Civic that grips like glue and plays dirty. Keep it clean, keep it fast."},
	{"course": 3, "title": "Usui's 184 Corners", "rival": {"name": "Aoi Shimizu", "car": "sil80", "skill": 0.98, "team": "Route 18 Garage"},
		"intro": "Endless corners on the old Usui road. One mistake and she's gone."},
	{"course": 0, "title": "The White Wedge", "rival": {"name": "Hayato Ozawa", "car": "fc3s", "skill": 1.0, "team": "Rotary Lab"},
		"intro": "The leader of Rotary Lab comes to Haruna himself. Precise, calculated, never makes a mistake."},
	{"course": 2, "title": "Akagi Rematch", "rival": {"name": "Jun Takase", "car": "fd3s", "skill": 1.0, "team": "Rotary Lab"},
		"intro": "The yellow rotary wants revenge on his home mountain, and he has learned from last time."},
	{"course": 4, "title": "Irohazaka Rally", "rival": {"name": "Daichi Mori", "car": "evo3", "skill": 1.02, "team": "Mountain Rally"},
		"intro": "Twenty-eight hairpins against a rally car. He brakes later than anyone you have met."},
	{"course": 6, "title": "Tsuchisaka Silvia", "rival": {"name": "Minato Kuroda", "car": "s13", "skill": 1.03, "team": "Touge Speed Club"},
		"intro": "The Speed Club's ace on the long, fast forest descents of Tsuchisaka."},
	{"course": 8, "title": "The Seven Bends", "rival": {"name": "Ren Ishikawa", "car": "fc3s", "skill": 1.05, "team": "Rotary Lab"},
		"intro": "Hakone's staircase of hairpins against a rotary that never lifts."},
	{"course": 9, "title": "Purple Storm", "rival": {"name": "Riku Onodera", "car": "r34", "skill": 1.06, "team": "Purple Storm"},
		"intro": "The fastest car on the coast. Six hundred horsepower down the Tsubaki Line."},
	{"course": 0, "title": "Legend of Haruna", "rival": {"name": "Haruto Inaba", "car": "s2000", "skill": 1.08, "team": "unknown"},
		"intro": "Back home. A silver roadster has been taking apart every record on Haruna, and its driver wants the last one: yours. Final battle."},
]


const HERO_CAR := "ae86"


static func stage(i: int) -> Dictionary:
	return STAGES[clampi(i, 0, STAGES.size() - 1)]


## Course dictionary for a stage: the real course, with this stage's rival.
static func course_for(i: int) -> Dictionary:
	var st := stage(i)
	var c: Dictionary = Courses.all()[st.course].duplicate(true)
	c.rival = st.rival.duplicate()
	c.campaign_stage = i
	return c
