## 战斗与平衡模拟：在真实主场景内运行，驱动玩家与野猪/狼/守卫对战，
## 统计敌人状态分布、命中率、击杀耗时、玩家受伤与掉落，输出 JSON 到 user://combat_report.json。
## 运行：godot --headless --path . -- --combat
## 说明：以场景节点方式运行（而非 --script），以便 Autoload（Game/GameConfig）可用。
## NUM-006 平衡测试流程：本文件即「平衡测试与调整流程」的可执行载体。
## 断言只覆盖机制正确性（公式、FSM、抗性、TTK 表、脱战回血、击杀计数）；
## 平衡数据单独写入 "type":"balance" 段，作为观察记录而非通过条件——
## 未由真人跑完 3 条路线前，不得对外称「已平衡」。
## @trace MECH-006 MECH-007 NUM-003 NUM-004 NUM-006
extends Node

var session: Node = null
var results: Array = []
var _fail := 0


func _ready() -> void:
	await _run()
	var ok := _fail == 0
	var report := {"ok": ok, "failures": _fail, "checks": results}
	var f := FileAccess.open("user://combat_report.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	print("COMBAT_RESULT_BEGIN")
	print(JSON.stringify(report, "  "))
	print("COMBAT_RESULT_END")
	get_tree().quit(0 if ok else 1)


func check(name: String, cond: bool, detail: String = "") -> void:
	results.append({"name": name, "ok": cond, "detail": detail})
	if not cond:
		_fail += 1
		push_error("COMBAT CHECK FAILED: " + name + " " + detail)


func wait(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame


func _start_game() -> Island:
	session.start_new_game()
	await wait(5)
	return session.island


## 清空已有敌人，只留一个自定义敌人，便于隔离观察
func _isolate(island: Island, type_id: String, at: Vector3) -> Enemy:
	for e in island.enemies_root.get_children():
		island.enemies_root.remove_child(e)
		e.queue_free()
	await wait(2)
	var enemy: Enemy = load("res://scripts/enemy/enemy.gd").new()
	enemy.name = "TestEnemy"
	enemy.position = Vector3(at.x, at.y, at.z)
	island.enemies_root.add_child(enemy)
	enemy.setup(type_id)
	enemy.target = island.player
	enemy.connect("struck_player", island._on_enemy_strike)
	enemy.connect("died", island._on_enemy_died)
	return enemy


## 让玩家面向敌人
func _face_player(player: Player, enemy: Enemy) -> void:
	var d := enemy.global_position - player.global_position
	d.y = 0.0
	if d.length() < 0.01:
		return
	player.rotation.y = atan2(-d.x, -d.z)


## 每场模拟前复位玩家：复活（若已死）并恢复满血/满体力、清除骨折与动作锁、卸下武器
func _reset_player(player: Player) -> void:
	if not player.is_alive():
		player.revive_at(player.global_position, GameConfig.START_STATS)
	# 复活不清装备（装备在死亡掉落 drain_all 时已清空），模拟之间需手动卸下以隔离武器差异
	player.inventory.equipped = {"weapon": "", "axe": "", "pick": ""}
	player.survival.health = 100.0
	player.survival.stamina = 100.0
	player.survival.fractured = false
	player._attack_cd = 0.0
	player._action_lock = 0.0
	player._dodge_cd = 0.0


## 模拟战斗：玩家持续挥砍（带冷却），统计敌人状态分布与命中
func _simulate(player: Player, enemy: Enemy, seconds: float, dodge: bool) -> Dictionary:
	var state_counts := {0: 0, 1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0}
	var player_hits := 0
	var damage_taken := 0.0
	var kills := 0
	var started := Time.get_ticks_msec()
	var elapsed := 0.0
	enemy.hp = enemy.max_hp
	var hp0 := player.survival.health
	var hp_min := hp0
	var last_state: int = enemy.state
	while elapsed < seconds and enemy.state != Enemy.State.DEAD:
		await get_tree().process_frame
		if not player.is_alive():
			break
		elapsed = float(Time.get_ticks_msec() - started) / 1000.0
		if not is_instance_valid(enemy):
			break
		hp_min = minf(hp_min, player.survival.health)
		state_counts[enemy.state] = int(state_counts.get(enemy.state, 0)) + 1
		if enemy.state != last_state:
			last_state = enemy.state
		# 玩家攻击
		if player._attack_cd <= 0.0:
			var before := enemy.hp
			_face_player(player, enemy)
			player.try_attack()
			if enemy.hp < before:
				player_hits += 1
		# 简单闪避：敌人进入前摇且距离近时后撤
		if dodge and enemy.state == Enemy.State.WINDUP and player._dodge_cd <= 0.0:
			if player.global_position.distance_to(enemy.global_position) < 3.0:
				var away := (player.global_position - enemy.global_position)
				away.y = 0.0
				player.global_position += away.normalized() * 1.6
				player._dodge_cd = 1.2
				player._iframes = 0.3
	if enemy.state == Enemy.State.DEAD:
		kills = 1
	damage_taken = hp0 - hp_min
	var total_frames := 0
	for k in state_counts.keys():
		total_frames += int(state_counts[k])
	var pct := {}
	for k in state_counts.keys():
		pct[str(k)] = snappedf(100.0 * float(state_counts[k]) / maxf(1.0, float(total_frames)), 1.0)
	return {
		"type": enemy.enemy_type,
		"kill": kills == 1,
		"seconds": snappedf(elapsed, 2),
		"player_hits": player_hits,
		"damage_taken": snappedf(maxf(0.0, damage_taken), 1.0),
		"hp_left": snappedf(hp_min, 1.0),
		"player_alive": player.is_alive(),
		"state_pct": pct,
	}


func _run() -> void:
	await wait(3)
	var island := await _start_game()
	check("会话建立", island != null)
	if island == null:
		return
	var player: Player = island.player
	check("玩家存在", player != null)
	player.input_enabled = true

	# ---------- 机制类断言：伤害公式与抗性（不依赖模拟） ----------
	check("伤害公式 石斧21 / 徒手5 / 守卫重击39 原值直通",
		GameConfig.damage_formula(21.0, 1.0, 0.0) == 21
		and GameConfig.damage_formula(5.0, 1.0, 0.0) == 5
		and GameConfig.damage_formula(39.0, 1.0, 0.0) == 39,
		"axe=%d fist=%d guardian_heavy=%d" % [
			GameConfig.damage_formula(21.0, 1.0, 0.0),
			GameConfig.damage_formula(5.0, 1.0, 0.0),
			GameConfig.damage_formula(39.0, 1.0, 0.0)])
	check("连击追加伤害（连续两次递增）",
		GameConfig.damage_formula(5.0, 2.0, 0.0) > GameConfig.damage_formula(5.0, 1.0, 0.0),
		"x1=%d x2=%d" % [GameConfig.damage_formula(5.0, 1.0, 0.0), GameConfig.damage_formula(5.0, 2.0, 0.0)])
	check("守卫抗性 0.25 减伤生效",
		GameConfig.damage_formula(21.0, 1.0, 0.25) < GameConfig.damage_formula(21.0, 1.0, 0.0),
		"guardian=%d boar=%d" % [GameConfig.damage_formula(21.0, 1.0, 0.25), GameConfig.damage_formula(21.0, 1.0, 0.0)])

	# ---------- 野猪：无闪避硬吃（验证 FSM 全链路与反击） ----------
	var boar: Enemy = await _isolate(island, "boar", player.global_position + Vector3(0, 0, -4.0))
	_reset_player(player)
	var r1: Dictionary = await _simulate(player, boar, 20.0, false)
	check("野猪进入前摇 WINDUP", float(r1["state_pct"].get("3", 0)) > 0.0, "windup%%=%s" % [str(r1["state_pct"].get("3", 0))])
	check("野猪进入攻击 ATTACK", float(r1["state_pct"].get("4", 0)) > 0.0, "attack%%=%s" % [str(r1["state_pct"].get("4", 0))])
	check("野猪受击后进入追击/交战（非纯巡逻）",
		float(r1["state_pct"].get("0", 100)) < 100.0, "patrol%%=%s" % [str(r1["state_pct"].get("0", 0))])
	check("野猪反击造成玩家伤害", float(r1["damage_taken"]) > 0.0, "dmg=%s" % [str(r1["damage_taken"])])

	# ---------- 狼：带闪避（验证贴身与受击） ----------
	var wolf: Enemy = await _isolate(island, "wolf", player.global_position + Vector3(0, 0, -4.0))
	_reset_player(player)
	var r2: Dictionary = await _simulate(player, wolf, 20.0, true)
	check("狼主动接近玩家（脱离 100% 巡逻）",
		float(r2["state_pct"].get("0", 100)) < 100.0, "patrol%%=%s" % [str(r2["state_pct"].get("0", 0))])

	# ---------- 守卫：验证抗性与重击伤害 ----------
	var guardian: Enemy = await _isolate(island, "guardian", player.global_position + Vector3(0, 0, -4.0))
	_reset_player(player)
	var r3: Dictionary = await _simulate(player, guardian, 12.0, false)
	check("守卫近战可命中玩家", float(r3["damage_taken"]) >= 18.0, "dmg=%s" % [str(r3["damage_taken"])])

	# ---------- 脱战回血 ----------
	var wander: Enemy = await _isolate(island, "boar", player.global_position + Vector3(0, 0, -4.0))
	wander.hp = 20.0
	wander._lose_target()
	check("脱战回血 25%", is_equal_approx(wander.hp, 20.0 + 15.0), "hp=%.1f" % wander.hp)

	# ---------- 击杀与掉落（用石斧保证击杀，验证死亡掉落链路） ----------
	var prey: Enemy = await _isolate(island, "boar", player.global_position + Vector3(0, 0, -4.0))
	_reset_player(player)
	player.inventory.add("spear_l2", 1)
	var spear_ok := player.inventory.equip("spear_l2")
	check("石矛 Lv2 已装备", spear_ok and player.inventory.equipped_weapon() == "spear_l2",
		"equipped=%s weapon=%s" % [str(spear_ok), player.inventory.equipped_weapon()])
	var kills_before := int(Game.stats.get("kills", 0))
	var r4: Dictionary = await _simulate(player, prey, 25.0, true)
	check("石矛 Lv2 可在时限内击杀野猪", bool(r4["kill"]), str(r4))
	check("击杀计数递增", int(Game.stats.get("kills", 0)) == kills_before + 1,
		"before=%d after=%d" % [kills_before, int(Game.stats.get("kills", 0))])

	# ---------- TTK 表核对（GDD 8.4：Lv1/Lv2 矛普通命中数） ----------
	var ttk_ok := true
	var ttk_detail := ""
	var ttk_table := [
		["boar", 60.0, 4, 3],
		["wolf", 80.0, 5, 3],
		["guardian", 280.0, 20, 14],
	]
	for row in ttk_table:
		var t: String = str(row[0])
		var hp_max: float = float(row[1])
		var res: float = float(GameConfig.ENEMIES[t]["resistance"])
		for pair in [[1, "spear_l1", int(row[2])], [2, "spear_l2", int(row[3])]]:
			var base: float = float(GameConfig.TOOLS[str(pair[1])]["damage"])
			var per_hit: int = GameConfig.damage_formula(base, 1.0, res)
			var hits := ceili(hp_max / maxf(1.0, float(per_hit)))
			if hits != int(pair[2]):
				ttk_ok = false
				ttk_detail += "%s Lv%d 命中 %d≠%d; " % [t, int(pair[0]), hits, int(pair[2])]
	check("TTK 表命中数与 GDD 8.4 一致", ttk_ok, ttk_detail if ttk_detail != "" else "全表匹配")

	# ---------- 平衡观察（非断言）：徒手 vs 满级矛 ----------
	var fist_boar: Enemy = await _isolate(island, "boar", player.global_position + Vector3(0, 0, -4.0))
	_reset_player(player)
	var rf: Dictionary = await _simulate(player, fist_boar, 20.0, false)

	var spear_boar: Enemy = await _isolate(island, "boar", player.global_position + Vector3(0, 0, -4.0))
	_reset_player(player)
	player.inventory.add("spear_l2", 1)
	player.inventory.equip("spear_l2")
	var rs: Dictionary = await _simulate(player, spear_boar, 20.0, true)

	results.append({
		"type": "balance",
		"note": "平衡观察数据，非断言。GDD 9.x「难度来自战斗前摇识别与准备」——徒手硬拼应显著劣势。",
		"fist_weapon": player.inventory.equipped_weapon(),
		"boar_fist_no_dodge": rf,
		"boar_spear_l2": rs,
		"conclusion": "徒手 %s / 满级矛 %s" % [
			"阵亡" if not bool(rf["player_alive"]) else "存活",
			"%.1f 秒击杀" % float(rs["seconds"]) if bool(rs["kill"]) else "未击杀"],
	})

