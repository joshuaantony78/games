extends CharacterBody2D

@export var speed := 90.0
@export var chase_speed := 150.0
@export var health := 3

@export var patrol_range := 160.0
@export var attack_range := 140.0
@export var attack_cooldown := 1.2

@export var hover_height := 30.0
@export var hover_distance := 80.0

# How close the player must be (x / y) for the claw to land
@export var reach_x := 130.0
@export var reach_y := 90.0

enum State { PATROL, CHASE, ATTACK, HURT, DEAD }

var state := State.PATROL
var origin: Vector2
var dir := 1.0
var target: Node2D = null

var can_attack := true
var claw_hit_player := false
var claw_offset := 0.0
var attack_id := 0
var attack_anim := ""

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var detect: Area2D = $DetectArea
@onready var claw_area: Area2D = $ClawArea


func _ready():
	origin = global_position
	claw_offset = absf(claw_area.position.x)

	for anim in sprite.sprite_frames.get_animation_names():
		var anim_name := String(anim).to_lower()
		if anim_name == "attack":
			attack_anim = String(anim)
		if anim_name in ["attack", "hurt", "die"]:
			sprite.sprite_frames.set_animation_loop(anim, false)
		if anim_name in ["idle", "fly"]:
			sprite.sprite_frames.set_animation_loop(anim, true)

	if attack_anim == "":
		push_error("Enemy attack animation was not found!")

	detect.body_entered.connect(_on_detect_entered)
	detect.body_exited.connect(_on_detect_exited)

	claw_area.monitoring = false
	claw_area.body_entered.connect(_on_claw_area_entered)

	sprite.play("fly")


func _physics_process(delta):
	if target != null and not is_instance_valid(target):
		target = null

	match state:
		State.PATROL:
			_patrol(delta)
		State.CHASE:
			_chase(delta)
		State.ATTACK:
			velocity = Vector2.ZERO
		State.HURT:
			velocity = velocity.move_toward(Vector2.ZERO, 600.0 * delta)
		State.DEAD:
			velocity = Vector2.ZERO

	move_and_slide()


func _patrol(_delta):
	if absf(global_position.x - origin.x) >= patrol_range:
		dir *= -1.0

	velocity.x = dir * speed
	velocity.y = sin(Time.get_ticks_msec() * 0.002) * 25.0

	sprite.flip_h = dir < 0.0
	_update_claw_position()
	_play("fly")

	if target != null:
		state = State.CHASE


func _chase(_delta):
	if target == null:
		state = State.PATROL
		return

	var to_player := target.global_position - global_position

	# Face player
	sprite.flip_h = to_player.x < 0.0
	_update_claw_position()

	# Attack only when the claw can actually reach the player
	if absf(to_player.x) <= reach_x and absf(to_player.y) <= reach_y:
		velocity = Vector2.ZERO
		if can_attack:
			_attack()
		return

	# Move to a spot beside and slightly above the player
	var side := signf(global_position.x - target.global_position.x)
	if side == 0.0:
		side = 1.0

	var goal := target.global_position + Vector2(
		side * minf(hover_distance, attack_range * 0.5),
		-hover_height
	)

	var offset := goal - global_position
	var distance := offset.length()

	if distance > 5.0:
		velocity = offset.normalized() * minf(chase_speed, distance * 4.0)
		_play("fly")
	else:
		velocity = Vector2.ZERO
		_play("idle")


func _update_claw_position():
	claw_area.position.x = -claw_offset if sprite.flip_h else claw_offset


func _play(anim: String):
	for n in sprite.sprite_frames.get_animation_names():
		if String(n).to_lower() == anim.to_lower():
			if sprite.animation != String(n):
				sprite.play(String(n))
			return


func _anim_length(anim: String) -> float:
	if not sprite.sprite_frames.has_animation(anim):
		return 0.5
	var frames := sprite.sprite_frames.get_frame_count(anim)
	var fps := sprite.sprite_frames.get_animation_speed(anim)
	if fps <= 0.0:
		return 0.5
	return float(frames) / fps


func _in_reach() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var d := target.global_position - global_position
	return absf(d.x) <= reach_x + 20.0 and absf(d.y) <= reach_y + 20.0


func _attack():
	if state != State.CHASE or not can_attack or attack_anim == "":
		return

	state = State.ATTACK
	can_attack = false
	claw_hit_player = false
	attack_id += 1
	var current_attack := attack_id

	velocity = Vector2.ZERO
	claw_area.set_deferred("monitoring", false)

	print("BOSS ATTACK STARTED")
	sprite.play(attack_anim)

	var duration := _anim_length(attack_anim)

	# Wind-up
	await get_tree().create_timer(duration * 0.35).timeout
	if state != State.ATTACK or current_attack != attack_id:
		return

	# Strike: enable claw area AND do a direct reach check
	claw_area.set_deferred("monitoring", true)
	await get_tree().physics_frame
	if state != State.ATTACK or current_attack != attack_id:
		claw_area.set_deferred("monitoring", false)
		return

	for body in claw_area.get_overlapping_bodies():
		_damage_player(body)

	if _in_reach():
		_damage_player(target)

	await get_tree().create_timer(duration * 0.35).timeout
	claw_area.set_deferred("monitoring", false)

	await get_tree().create_timer(duration * 0.3).timeout
	if current_attack != attack_id:
		return

	if state == State.ATTACK:
		state = State.CHASE if (target != null and is_instance_valid(target)) else State.PATROL

	await get_tree().create_timer(attack_cooldown).timeout
	if current_attack == attack_id and state != State.DEAD:
		can_attack = true


func _on_claw_area_entered(body):
	_damage_player(body)


func _damage_player(body):
	if claw_hit_player:
		return
	if not body.is_in_group("player"):
		return
	if body.has_method("take_hit"):
		claw_hit_player = true
		print("BOSS HIT PLAYER")
		body.take_hit(global_position)


func take_damage(amount := 1, from_pos := Vector2.ZERO):
	if state == State.DEAD:
		return

	health -= amount
	attack_id += 1
	claw_area.set_deferred("monitoring", false)
	can_attack = true

	if health <= 0:
		state = State.DEAD
		set_deferred("collision_layer", 0)
		set_deferred("collision_mask", 0)
		velocity = Vector2.ZERO
		_play("die")
		await sprite.animation_finished
		if is_inside_tree():
			queue_free()
		return

	state = State.HURT

	var knockback_direction := (global_position - from_pos).normalized()
	if knockback_direction == Vector2.ZERO:
		knockback_direction = Vector2.RIGHT
	velocity = knockback_direction * 220.0

	_play("hurt")
	await sprite.animation_finished

	if state != State.HURT:
		return
	state = State.CHASE if (target != null and is_instance_valid(target)) else State.PATROL


func _on_detect_entered(body):
	if not body.is_in_group("player"):
		return
	target = body
	if state == State.PATROL:
		state = State.CHASE


func _on_detect_exited(body):
	if body == target:
		target = null
		if state == State.CHASE:
			state = State.PATROL


# TEMPORARY: press Enter to damage the enemy (delete when done testing)
func _unhandled_input(event):
	if event.is_action_pressed("ui_accept"):
		take_damage(1, global_position + Vector2(-50, 0))
