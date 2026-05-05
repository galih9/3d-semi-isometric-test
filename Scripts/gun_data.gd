@tool
extends Resource
class_name GunData

# ─── Identity ────────────────────────────────────────────────────────────────
@export var gun_name: String = "Pistol"

# ─── Firing ──────────────────────────────────────────────────────────────────
@export_group("Firing")
## Seconds between shots (lower = faster fire rate)
@export var fire_rate: float = 0.25
@export var clip_size: int = 12
@export var reload_time: float = 1.8
@export var damage: float = 30.0
@export var bullet_speed: float = 120.0

# ─── Spread / Recoil ─────────────────────────────────────────────────────────
@export_group("Spread / Recoil")
## Minimum spread cone even when standing still (degrees)
@export var base_spread: float = 0.5
## Hard cap on spread (degrees)
@export var max_spread: float = 6.0
## Spread added per shot fired (degrees)
@export var spread_per_shot: float = 1.5
## Spread recovered per second (degrees)
@export var spread_recovery: float = 6.0

# ─── Aim ─────────────────────────────────────────────────────────────────────
@export_group("Aim")
## Degrees to pitch the bullet down (compensates for isometric camera angle)
@export var vertical_aim_bias: float = -10.0

# ─── Mobility ────────────────────────────────────────────────────────────────
@export_group("Mobility")
## Multiplier on walk/sprint speed while this weapon is equipped.
## 1.0 = no penalty. 0.8 = 20% slower.
@export_range(0.1, 1.0, 0.01) var move_speed_multiplier: float = 1.0
## Extra spread added per unit of horizontal player velocity.
## Set to 0 to disable movement-inaccuracy simulation.
@export var movement_spread_penalty: float = 0.0
