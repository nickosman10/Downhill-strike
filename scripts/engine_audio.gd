class_name EngineAudio
extends AudioStreamPlayer
## Procedural 4-cylinder engine note plus tyre squeal, no audio files needed.

const RATE := 22050.0

var car: PlayerCar
var _pb: AudioStreamGeneratorPlayback
var _phase := 0.0
var _phase2 := 0.0
var _noise_lp := 0.0
var _rpm := 900.0
var _squeal := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.12
	stream = gen
	volume_db = -8.0
	play()
	_pb = get_stream_playback()


func _process(dt: float) -> void:
	if _pb == null or car == null:
		return
	_rpm = lerpf(_rpm, car.rpm, 1.0 - exp(-10.0 * dt))
	var squeal_target := 0.0
	if car.drifting and car.speed > 8.0:
		squeal_target = clampf(absf(car.slip) * 2.0, 0.2, 1.0)
	_squeal = lerpf(_squeal, squeal_target, 1.0 - exp(-8.0 * dt))
	var freq := _rpm / 60.0 * 2.0          # firing frequency
	var load := 0.35 + car.throttle * 0.65
	var frames := _pb.get_frames_available()
	for f in frames:
		_phase = fmod(_phase + freq / RATE, 1.0)
		_phase2 = fmod(_phase2 + (1150.0 + _rpm * 0.05) / RATE, 1.0)
		var saw := _phase * 2.0 - 1.0
		var pulse := 1.0 if _phase < 0.3 else -0.4
		var eng := (saw * 0.45 + pulse * 0.35 + sin(_phase * TAU * 0.5) * 0.3) * load * 0.35
		_noise_lp = lerpf(_noise_lp, _rng.randf_range(-1.0, 1.0), 0.25)
		var tyre := (sin(_phase2 * TAU) * 0.5 + _noise_lp * 0.5) * _squeal * 0.22
		var smp := clampf(eng + tyre, -1.0, 1.0)
		_pb.push_frame(Vector2(smp, smp))
