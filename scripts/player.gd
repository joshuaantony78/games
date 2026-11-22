extends CharacterBody2D

const SPEED = 250.0
const JUMP_VELOCITY = -500.0

var attacking := false
var attack_anim := ""

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready():
	for n in sprite.sprite_frames.get_animation_names():
		if String(n).to_lower() == "attack":
			attack_anim = n
	sprite.sprite_frames.set_animation_loop(attack_anim, false)

	# jump plays once and holds on its last frame
	if sprite.sprite_frames.has_animation("jump"):
		sprite.sprite_frames.set_animation_loop("jump", false)
	# fall loops while you're dropping
	if sprite.sprite_frames.has_animation("fall"):
		sprite.sprite_frames.set_animation_loop("fall", true)

	print("Animations: ", sprite.sprite_frames.get_animation_names())

func _physics_process(delta):
	# gravity
	if not is_on_floor():
		velocity += get_gravity() * delta

	# attack
	if Input.is_action_just_pressed("attack") and not attacking:
		_start_attack()

	# jump
	if Input.is_action_just_pressed("jump") and is_on_floor() and not attacking:
		velocity.y = JUMP_VELOCITY
		sprite.play("jump")   # restart jump anim from frame 0

	var dir := Input.get_axis("move_left", "move_right")

	if attacking:
		velocity.x = move_toward(velocity.x, 0, SPEED)
	else:
		velocity.x = dir * SPEED
		if dir != 0:
			sprite.flip_h = dir < 0

		if not is_on_floor():
			if velocity.y < 0:
				# rising
				if sprite.animation != "jump":
					sprite.play("jump")
			else:
				# falling
				if sprite.animation != "fall":
					sprite.play("fall")
		elif dir != 0:
			sprite.play("run")
		else:
			sprite.play("idle")

	move_and_slide()

func _start_attack():
	if attack_anim == "":
		print("No attack animation found")
		return
	attacking = true
	sprite.play(attack_anim)

	var frames := sprite.sprite_frames.get_frame_count(attack_anim)
	var fps := sprite.sprite_frames.get_animation_speed(attack_anim)
	var duration := 0.5
	if fps > 0:
		duration = frames / fps
	await get_tree().create_timer(duration).timeout
	attacking = false
