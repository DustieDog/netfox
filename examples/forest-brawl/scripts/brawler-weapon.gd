extends NetworkWeapon3D
class_name BrawlerWeapon

@export var projectile: PackedScene
@export var fire_cooldown: float = 0.15

@export var input: BrawlerInput

var last_fire: int = -1

func _ready():
	if not input:
		input = $"../Input"
	
	NetworkTime.on_tick.connect(_tick)

func _can_fire() -> bool:
	return NetworkTime.seconds_between(last_fire, NetworkTime.tick) >= fire_cooldown

func _can_peer_use(peer_id: int) -> bool:
	return peer_id == input.get_multiplayer_authority()

func _after_fire(projectile: Node3D):
	last_fire = NetworkTime.tick

func _spawn() -> Node3D:
	var p = projectile.instantiate() as BombProjectile
	get_tree().root.add_child(p, true)
	p.global_transform = global_transform
	p.fired_by = get_parent()
	
	return p

func _tick(delta, tick):
	if input.is_firing:
		fire()
