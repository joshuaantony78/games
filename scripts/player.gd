
extends CharacterBody2D

# =====================================
# PLAYER SETTINGS
# =====================================

const SPEED = 250.0
const JUMP_VELOCITY = -400.0
const KNOCKBACK = Vector2(220, -220)

@export var max_health := 5

signal health_changed(current)

var health := 5

var attacking := false
var hurt := false
var invulnerable := false
var dead := false

var attack_anim := ""
var attack_offset := 0.0

var hit_ids: Dictionary = {}
var attack_id := 0


# =====================================
# NODE REFERENCES
# =====================================

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var attack_area: Area2D = $AttackArea


# =====================================
# READY
# =====================================

func _ready():

	health = max_health

	# Find attack animation.
	for n in sprite.sprite_frames.get_animation_names():

		if String(n).to_lower() == "attack":
			attack_anim = String(n)

	if attack_anim != "":
		sprite.sprite_frames.set_animation_loop(attack_anim, false)

	# Configure animation loops.
	for anim in ["jump", "hurt", "die"]:

		if sprite.sprite_frames.has_animation(anim):
			sprite.sprite_frames.set_animation_loop(anim, false)

	if sprite.sprite_frames.has_animation("fall"):
		sprite.sprite_frames.set_animation_loop("fall", true)

	# Remember attack area position.
	attack_offset = absf(attack_area.position.x)

	# Disable attack hitbox initially.
	attack_area.monitoring = false

	# Connect attack detection.
	attack_area.body_entered.connect(_on_attack_area_body_entered)


# =====================================
# PLAYER MOVEMENT
# =====================================

func _physics_process(delta):

	# Gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Dead state.
	if dead:
		velocity.x = move_toward(velocity.x, 0, 800 * delta)
		move_and_slide()
		return

	# Hurt state.
	if hurt:
		velocity.x = move_toward(velocity.x, 0, 600 * delta)
		move_and_slide()
		return

	# Start sword attack.
	if Input.is_action_just_pressed("attack") and not attacking:
		_start_attack()

	# Jump.
	if Input.is_action_just_pressed("jump") and is_on_floor() and not attacking:
		velocity.y = JUMP_VELOCITY
		sprite.play("jump")

	# Horizontal movement.
	var dir := Input.get_axis("move_left", "move_right")

	if attacking:

		velocity.x = move_toward(velocity.x, 0, SPEED)

	else:

		velocity.x = dir * SPEED

		if dir != 0:

			sprite.flip_h = dir < 0

			# Face attack hitbox in movement direction.
			attack_area.position.x = (
				-attack_offset if dir < 0 else attack_offset
			)

		# Animation handling.
		var in_air := not is_on_floor() or velocity.y < 0.0

		if in_air:

			if velocity.y < 0.0:

				if sprite.animation != "jump":
					sprite.play("jump")

			else:

				if sprite.animation != "fall":
					sprite.play("fall")

		elif dir != 0:

			sprite.play("run")

		else:

			sprite.play("idle")

	move_and_slide()


# =====================================
# SWORD ATTACK
# =====================================

func _start_attack():

	if attack_anim == "":
		return

	attacking = true
	attack_id += 1

	var current_attack := attack_id

	hit_ids.clear()

	sprite.play(attack_anim)

	var duration := _anim_length(attack_anim)

	# Wait until sword strike frames.
	await get_tree().create_timer(duration * 0.35).timeout

	if not attacking or current_attack != attack_id:
		return

	# Enable sword hitbox.
	attack_area.set_deferred("monitoring", true)

	await get_tree().physics_frame

	if not attacking or current_attack != attack_id:
		attack_area.set_deferred("monitoring", false)
		return

	# Check enemies already inside hitbox.
	for body in attack_area.get_overlapping_bodies():
		_damage_enemy(body)

	# Keep hitbox active during strike.
	await get_tree().create_timer(duration * 0.3).timeout

	if not attacking or current_attack != attack_id:
		attack_area.set_deferred("monitoring", false)
		return

	# Disable sword hitbox.
	attack_area.set_deferred("monitoring", false)

	await get_tree().create_timer(duration * 0.35).timeout

	if current_attack == attack_id:
		attacking = false


# =====================================
# ANIMATION LENGTH
# =====================================

func _anim_length(anim: String) -> float:

	var frames := sprite.sprite_frames.get_frame_count(anim)
	var fps := sprite.sprite_frames.get_animation_speed(anim)

	return float(frames) / fps if fps > 0.0 else 0.5


# =====================================
# ENEMY DETECTION
# =====================================

func _on_attack_area_body_entered(body):

	_damage_enemy(body)


# =====================================
# ENEMY DAMAGE
# =====================================

func _damage_enemy(body: Node2D):

	if not is_instance_valid(body):
		return

	if not body.has_method("take_damage"):
		return

	var id := body.get_instance_id()

	# Prevent multiple hits in one swing.
	if hit_ids.has(id):
		return

	hit_ids[id] = true

	body.take_damage(1, global_position)


# =====================================
# PLAYER GETTING HIT
# =====================================

func take_hit(from_pos: Vector2 = Vector2.ZERO):

	if invulnerable or dead:
		return

	health -= 1
	health_changed.emit(health)

	# Cancel current attack.
	attacking = false
	attack_id += 1

	attack_area.set_deferred("monitoring", false)

	if health <= 0:
		_die()
		return

	invulnerable = true
	hurt = true

	# Knockback direction.
	var away := signf(global_position.x - from_pos.x)

	if away == 0.0:
		away = -1.0 if sprite.flip_h else 1.0

	velocity = Vector2(
		KNOCKBACK.x * away,
		KNOCKBACK.y
	)

	sprite.play("hurt")

	await get_tree().create_timer(0.35).timeout

	if dead:
		return

	hurt = false

	# Invulnerability blinking.
	for i in 6:

		sprite.modulate.a = 0.35

		await get_tree().create_timer(0.07).timeout

		if dead:
			return

		sprite.modulate.a = 1.0

		await get_tree().create_timer(0.07).timeout

		if dead:
			return

	invulnerable = false


# =====================================
# PLAYER DEATH
# =====================================

func _die():

	dead = true
	hurt = false
	invulnerable = true

	attacking = false
	attack_id += 1

	attack_area.set_deferred("monitoring", false)

	sprite.modulate.a = 1.0

	if sprite.sprite_frames.has_animation("die"):

		sprite.play("die")
		await sprite.animation_finished

	await get_tree().create_timer(0.8).timeout

	get_tree().reload_current_scene()
