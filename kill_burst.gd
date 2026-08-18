class_name KillBurst
extends CPUParticles2D
## One-shot burst of palette-colored pixel chunks at an enemy death.
## No texture: each particle is the default 1px quad scaled up, tinted
## purple or peach via a constant-interpolation gradient (no blending,
## so no off-palette colors). Frees itself when the burst finishes.


func _init() -> void:
	one_shot = true
	emitting = false
	amount = 14
	lifetime = 0.45
	explosiveness = 1.0
	spread = 180.0
	gravity = Vector2.ZERO
	initial_velocity_min = 40.0
	initial_velocity_max = 90.0
	damping_min = 60.0
	damping_max = 120.0
	scale_amount_min = 1.0
	scale_amount_max = 3.0
	var ramp := Gradient.new()
	ramp.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	ramp.set_color(0, Palette.PURPLE)
	ramp.set_color(1, Palette.PEACH)
	ramp.set_offset(1, 0.5)
	color_initial_ramp = ramp
	finished.connect(queue_free)


func _ready() -> void:
	emitting = true
