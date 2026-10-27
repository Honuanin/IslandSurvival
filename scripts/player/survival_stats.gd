## 生存状态：生命/体力/饥渴/体温/湿润/流血/骨折（GDD 6.6、8.1–8.3）。
## 纯数据 + 公式，不碰节点；由 Player 每帧 tick 并广播给 HUD。
## @trace MECH-003 NUM-001 NUM-002 NUM-004
class_name SurvivalStats
extends RefCounted

signal stats_changed(snapshot: Dictionary)

const S := GameConfig.SURVIVAL

var health: float = 100.0
var stamina: float = 100.0
var hunger: float = 80.0
var thirst: float = 75.0
var body_temp: float = 37.0
var wetness: float = 0.0
var bleed: int = 0
var fractured: bool = false

var air_temp: float = 25.0
var current_region: String = "beach"
var campfire_bonus: float = 0.0      # 0..2，由最近营火计算
var shelter_bonus: float = 0.0       # 0 或 0.4
var _stamina_idle: float = 0.0

# HUD 用
var danger_level: int = 0            # 0 正常 1 注意 2 危险 3 持续伤害
var last_damage_source: String = ""
var _emit_acc: float = 0.0


func reset_to(values: Dictionary) -> void:
	health = float(values.get("health", 100.0))
	stamina = float(values.get("stamina", 100.0))
	hunger = float(values.get("hunger", 80.0))
	thirst = float(values.get("thirst", 75.0))
	body_temp = float(values.get("temperature", 37.0))
	wetness = 0.0
	bleed = 0
	fractured = false
	_emit()


func is_alive() -> bool:
	return health > 0.0


## 主更新。flags: {"sprinting":bool, "acting":bool}
func tick(delta: float, flags: Dictionary) -> void:
	if not is_alive():
		return
	var sprinting: bool = flags.get("sprinting", false)
	var acting: bool = flags.get("acting", false)

	# 饥渴消耗（8.1）
	var hunger_mult := 1.0
	if sprinting:
		hunger_mult *= 1.5
	if acting:
		hunger_mult *= 1.25
	hunger = maxf(0.0, hunger - S["hunger_rate"] * hunger_mult * delta)

	var thirst_mult := 1.0
	if sprinting:
		thirst_mult *= 2.0
	if body_temp > 38.0:
		thirst_mult *= 1.5
	thirst = maxf(0.0, thirst - S["thirst_rate"] * thirst_mult * delta)

	# 持续伤害
	var dot := 0.0
	if hunger <= 0.0:
		dot += S["hunger_zero_damage"]
	if thirst <= 0.0:
		dot += S["thirst_zero_damage"]
	dot += float(bleed) * S["bleed_dps"]

	# 体温（8.2）
	var t_eq := clampf(37.0 + 0.12 * (air_temp - 24.0) + S["clothing_bonus"] + campfire_bonus + shelter_bonus - 2.5 * wetness, 30.0, 41.0)
	var tau: float = S["temp_tau"]
	var target_change := (t_eq - body_temp) * (1.0 - exp(-delta / tau))
	var max_change: float = S["temp_max_rate"] * delta
	body_temp += clampf(target_change, -max_change, max_change)
	if body_temp < S["comfort_min"]:
		dot += minf(0.5, 0.1 + 0.08 * (S["comfort_min"] - body_temp))
	elif body_temp > S["comfort_max"]:
		dot += minf(0.5, 0.1 + 0.08 * (body_temp - S["comfort_max"]))

	if dot > 0.0:
		health = maxf(0.0, health - dot * delta)
		if last_damage_source == "":
			last_damage_source = "生存状态"

	# 体力恢复（8.3）：停止消耗 1 秒后 15/s
	_stamina_idle += delta
	if _stamina_idle > 1.0 and not sprinting:
		stamina = minf(100.0, stamina + S["stamina_regen"] * delta)

	_update_danger()
	_emit_acc += delta
	if _emit_acc >= 0.1:
		_emit_acc = 0.0
		_emit()


func _update_danger() -> void:
	var level := 0
	if hunger < 25.0 or thirst < 25.0 or body_temp < 35.5 or body_temp > 39.0 or bleed > 0 or fractured:
		level = 1
	if hunger <= 0.0 or thirst <= 0.0 or body_temp < 34.5 or body_temp > 39.8 or wetness > 0.85:
		level = 2
	if hunger <= 0.0 or thirst <= 0.0 or bleed >= 2 or body_temp < 34.0 or body_temp > 40.0:
		level = 3
	danger_level = level


func consume_stamina(amount: float) -> bool:
	if stamina < amount:
		return false
	stamina -= amount
	_stamina_idle = 0.0
	return true


func mark_stamina_used() -> void:
	_stamina_idle = 0.0


## 外部伤害（战斗/摔落），返回是否致死
func apply_damage(amount: float, source: String) -> bool:
	if not is_alive():
		return false
	health = maxf(0.0, health - amount)
	last_damage_source = source
	_emit()
	return health <= 0.0


func heal(amount: float) -> void:
	health = minf(100.0, health + amount)
	_emit()


func eat(item_id: String) -> String:
	if not GameConfig.CONSUMABLE.has(item_id):
		return ""
	var eff: Dictionary = GameConfig.CONSUMABLE[item_id]
	if eff.has("hunger"):
		hunger = minf(100.0, hunger + float(eff["hunger"]))
	if eff.has("thirst"):
		thirst = minf(100.0, thirst + float(eff["thirst"]))
	if eff.has("heal"):
		heal(float(eff["heal"]))
	if eff.get("cure_bleed", false):
		bleed = 0
	if eff.get("cure_fracture", false):
		fractured = false
	if eff.has("bleed"):
		bleed = mini(S["max_bleed"], bleed + int(eff["bleed"]))
	_emit()
	return GameConfig.item_name(item_id)


func add_bleed(layers: int) -> void:
	bleed = mini(S["max_bleed"], bleed + layers)
	_emit()


func apply_fracture() -> void:
	fractured = true
	_emit()


func move_speed(base: float) -> float:
	var v := base
	if fractured:
		v *= 0.65
	if wetness > 0.35:
		v *= 0.7
	return v


func snapshot() -> Dictionary:
	return {
		"health": health, "stamina": stamina, "hunger": hunger, "thirst": thirst,
		"temperature": body_temp, "wetness": wetness, "bleed": bleed, "fractured": fractured,
		"danger": danger_level, "air_temp": air_temp,
	}


func _emit() -> void:
	stats_changed.emit(snapshot())


func to_dict() -> Dictionary:
	return {"health": health, "stamina": stamina, "hunger": hunger, "thirst": thirst, "temperature": body_temp, "wetness": wetness, "bleed": bleed, "fractured": fractured}


func from_dict(d: Dictionary) -> void:
	health = float(d.get("health", 100.0))
	stamina = float(d.get("stamina", 100.0))
	hunger = float(d.get("hunger", 80.0))
	thirst = float(d.get("thirst", 75.0))
	body_temp = float(d.get("temperature", 37.0))
	wetness = float(d.get("wetness", 0.0))
	bleed = int(d.get("bleed", 0))
	fractured = bool(d.get("fractured", false))
	_emit()
