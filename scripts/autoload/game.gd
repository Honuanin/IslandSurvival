## 全局会话状态与流程控制（Autoload）。
## 职责：流程状态、世界时间、主线目标、统计数据、读写存档、跨场景信号广播。
## 世界数据（玩家/建筑/资源节点）由 Island 汇聚，不在本单例里保存玩法逻辑。
## @trace FLOW-001 FLOW-002 FLOW-003 MECH-009 SIG-001
extends Node

signal game_flow_changed(new_state: int)
signal objective_updated(objectives: Array)
signal save_completed(ok: bool, message: String)
signal toast_requested(text: String)

enum Flow { BOOT, MAIN_MENU, LOADING, PLAYING, PAUSED, DEAD, VICTORY }

const SAVE_PATH := "user://save_slot0.json"
const SAVE_TMP := "user://save_slot0.tmp"
const SAVE_VERSION := 1

var flow: int = Flow.BOOT
var world_time: float = 480.0          # 游戏内秒，一天 1440 秒
var main_objectives: Dictionary = {}
var stats: Dictionary = {"deaths": 0, "kills": 0, "buildings": 0, "play_time": 0.0}
var pending_save: Dictionary = {}
var has_corrupt_save_notice: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_reset_objectives()


func set_flow(new_flow: int) -> void:
	if flow == new_flow:
		return
	flow = new_flow
	game_flow_changed.emit(flow)
	get_tree().paused = (flow == Flow.PAUSED)


func is_playing() -> bool:
	return flow == Flow.PLAYING


func toast(text: String) -> void:
	toast_requested.emit(text)


func _reset_objectives() -> void:
	main_objectives = {
		"workbench": false,
		"lens": false,
		"guardian": false,
		"tower_built": false,
		"tower_lit": false,
	}


func complete_objective(id: String) -> void:
	if not main_objectives.has(id) or main_objectives[id]:
		return
	main_objectives[id] = true
	objective_updated.emit(objective_list())
	var text := objective_text(id)
	if text != "":
		toast("主线推进：" + text)


func objective_list() -> Array:
	var order := ["workbench", "lens", "guardian", "tower_built", "tower_lit"]
	var out: Array = []
	for id in order:
		out.append({"id": id, "text": objective_text(id), "done": main_objectives.get(id, false)})
	return out


func objective_text(id: String) -> String:
	match id:
		"workbench":
			return "建造工作台"
		"lens":
			return "取得火台透镜（湿地深处）"
		"guardian":
			return "击败遗迹守卫"
		"tower_built":
			return "在信号点建造信号火台"
		"tower_lit":
			return "点燃信号火台"
	return id


func reset_session() -> void:
	world_time = 480.0
	stats = {"deaths": 0, "kills": 0, "buildings": 0, "play_time": 0.0}
	_reset_objectives()
	objective_updated.emit(objective_list())


func time_string() -> String:
	var t := fposmod(world_time, 1440.0)
	var hours := int(t / 60.0)
	var minutes := int(t) % 60
	return "%02d:%02d" % [hours, minutes]


## 0 = 深夜，1 = 正午。给 HUD 昼夜条与气温曲线共用。
func day_curve() -> float:
	var t := fposmod(world_time, 1440.0)
	return sin((t / 1440.0) * TAU - PI * 0.5) * 0.5 + 0.5


func is_night() -> bool:
	var h := fposmod(world_time, 1440.0) / 60.0
	return h < 6.0 or h >= 20.0


# ---------------- 存档 ----------------
func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func request_save(payload: Dictionary) -> void:
	pending_save = payload


## 原子写入：先写临时文件，成功后再替换正式存档（GDD 6.10）
func write_save(payload: Dictionary) -> bool:
	payload["version"] = SAVE_VERSION
	payload["world_time"] = world_time
	payload["objectives"] = main_objectives.duplicate()
	payload["stats"] = stats.duplicate()
	var text := JSON.stringify(payload)
	var f := FileAccess.open(SAVE_TMP, FileAccess.WRITE)
	if f == null:
		save_completed.emit(false, "无法写入临时存档")
		return false
	f.store_string(text)
	f.flush()
	f.close()
	var dir := DirAccess.open("user://")
	if dir == null:
		save_completed.emit(false, "存档目录不可用")
		return false
	if FileAccess.file_exists(SAVE_PATH):
		dir.remove(SAVE_PATH)
	var err := dir.rename(SAVE_TMP, SAVE_PATH)
	var ok := err == OK
	save_completed.emit(ok, "已保存" if ok else "存档替换失败")
	return ok


## 读取存档；坏档不静默覆盖，返回 {"ok":false,"error":...}
func read_save() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {"ok": false, "error": "没有存档"}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return {"ok": false, "error": "存档无法打开"}
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		has_corrupt_save_notice = true
		return {"ok": false, "error": "存档损坏（JSON 解析失败），未覆盖原文件"}
	var d: Dictionary = parsed
	var ver := int(d.get("version", 1))
	if ver > SAVE_VERSION:
		has_corrupt_save_notice = true
		return {"ok": false, "error": "存档版本 %d 高于当前支持版本 %d" % [ver, SAVE_VERSION]}
	return {"ok": true, "data": d}
