## 背包与装备（12 格背包 + 独立 3 格装备 + 任务栏，GDD 6.3）。
## 所有变更都走事务式接口：先校验再一次性扣除/发放，失败不改状态。
## @trace MECH-004 MECH-005 SIG-001
class_name Inventory
extends RefCounted

signal inventory_changed(version: int)

const SLOT_COUNT := 12
const EQUIP_SLOTS := ["weapon", "axe", "pick"]

var slots: Array = []          # 每格 {"id": String, "count": int} 或 null
var quest_items: Dictionary = {}   # 任务栏：不占格、不可丢弃、死亡保留
var equipped: Dictionary = {"weapon": "", "axe": "", "pick": ""}
var version: int = 0


func _init() -> void:
	slots.resize(SLOT_COUNT)
	for i in range(SLOT_COUNT):
		slots[i] = null


func _touch() -> void:
	version += 1
	inventory_changed.emit(version)


func count(item_id: String) -> int:
	var total := 0
	if quest_items.has(item_id):
		total += int(quest_items[item_id])
	for s in slots:
		if s != null and s["id"] == item_id:
			total += int(s["count"])
	return total


func used_slots() -> int:
	var n := 0
	for s in slots:
		if s != null:
			n += 1
	return n


func has_room_for(item_id: String, amount: int) -> bool:
	if item_id == "" or amount <= 0:
		return true
	if GameConfig.ITEMS.has(item_id) and GameConfig.ITEMS[item_id]["tag"] == "quest":
		return true
	var cap := GameConfig.item_stack(item_id)
	var remaining := amount
	for s in slots:
		if s != null and s["id"] == item_id:
			remaining -= (cap - int(s["count"]))
		elif s == null:
			remaining -= cap
		if remaining <= 0:
			return true
	return remaining <= 0


## 发放物品；任务物品直接进任务栏。返回实际放入数量（满包时可能少放）。
func add(item_id: String, amount: int) -> int:
	if amount <= 0:
		return 0
	if GameConfig.ITEMS.has(item_id) and GameConfig.ITEMS[item_id]["tag"] == "quest":
		quest_items[item_id] = int(quest_items.get(item_id, 0)) + amount
		_touch()
		return amount
	var cap := GameConfig.item_stack(item_id)
	var left := amount
	for i in range(SLOT_COUNT):
		if left <= 0:
			break
		var s = slots[i]
		if s != null and s["id"] == item_id and int(s["count"]) < cap:
			var put := mini(left, cap - int(s["count"]))
			s["count"] = int(s["count"]) + put
			left -= put
	for i in range(SLOT_COUNT):
		if left <= 0:
			break
		if slots[i] == null:
			var put := mini(left, cap)
			slots[i] = {"id": item_id, "count": put}
			left -= put
	if left != amount:
		_touch()
	return amount - left


func remove(item_id: String, amount: int) -> bool:
	if amount <= 0:
		return true
	if count(item_id) < amount:
		return false
	if GameConfig.ITEMS.has(item_id) and GameConfig.ITEMS[item_id]["tag"] == "quest":
		# 任务物品默认不可丢弃（GDD 6.3），只有点火消耗才走 consume_quest
		return false
	var left := amount
	for i in range(SLOT_COUNT - 1, -1, -1):
		if left <= 0:
			break
		var s = slots[i]
		if s != null and s["id"] == item_id:
			var take := mini(left, int(s["count"]))
			s["count"] = int(s["count"]) - take
			left -= take
			if int(s["count"]) <= 0:
				slots[i] = null
	_touch()
	return left <= 0


func consume_quest(item_id: String, amount: int = 1) -> bool:
	if int(quest_items.get(item_id, 0)) < amount:
		return false
	quest_items[item_id] = int(quest_items[item_id]) - amount
	if int(quest_items[item_id]) <= 0:
		quest_items.erase(item_id)
	_touch()
	return true


func can_afford(cost: Dictionary) -> bool:
	for id in cost:
		if count(id) < int(cost[id]):
			return false
	return true


func missing(cost: Dictionary) -> Dictionary:
	var out := {}
	for id in cost:
		var lack := int(cost[id]) - count(id)
		if lack > 0:
			out[id] = lack
	return out


## 事务式扣除：全部满足才扣（调用方先 can_afford）
func pay(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for id in cost:
		if GameConfig.ITEMS.has(id) and GameConfig.ITEMS[id]["tag"] == "quest":
			continue
		remove(id, int(cost[id]))
	return true


func equip(item_id: String) -> bool:
	var kind := GameConfig.tool_kind(item_id)
	if kind == "spear":
		equipped["weapon"] = item_id
	elif kind == "axe" or kind == "pick":
		equipped[kind] = item_id
	else:
		return false
	_touch()
	return true


func is_equipped(item_id: String) -> bool:
	return equipped.values().has(item_id)


func equipped_weapon() -> String:
	var w: String = equipped.get("weapon", "")
	if w != "" and count(w) > 0:
		return w
	return ""


func tool_of_kind(kind: String) -> String:
	var t: String = equipped.get(kind, "")
	if t != "" and count(t) > 0:
		return t
	return ""


## 首次持有工具时自动装备
func auto_equip(item_id: String) -> void:
	var kind := GameConfig.tool_kind(item_id)
	if kind == "":
		return
	if kind == "spear":
		if equipped_weapon() == "":
			equip(item_id)
	elif equipped.get(kind, "") == "":
		equip(item_id)


## 把所有非任务物品与工具转成可序列化列表（死亡掉落用）
func drain_all() -> Dictionary:
	var dropped := {"items": {}, "tools": []}
	for i in range(SLOT_COUNT):
		var s = slots[i]
		if s == null:
			continue
		var id: String = s["id"]
		var tag: String = GameConfig.ITEMS[id]["tag"]
		if tag == "tool":
			dropped["tools"].append(id)
		else:
			dropped["items"][id] = int(dropped["items"].get(id, 0)) + int(s["count"])
		slots[i] = null
	equipped = {"weapon": "", "axe": "", "pick": ""}
	_touch()
	return dropped


func to_dict() -> Dictionary:
	var out := []
	for s in slots:
		if s == null:
			out.append(null)
		else:
			out.append({"id": s["id"], "count": int(s["count"])})
	return {"slots": out, "equipped": equipped.duplicate(), "quest": quest_items.duplicate()}


func from_dict(d: Dictionary) -> void:
	slots.resize(SLOT_COUNT)
	for i in range(SLOT_COUNT):
		slots[i] = null
	var raw: Array = d.get("slots", [])
	for i in range(mini(raw.size(), SLOT_COUNT)):
		var s = raw[i]
		if s != null and typeof(s) == TYPE_DICTIONARY and GameConfig.ITEMS.has(str(s.get("id", ""))):
			slots[i] = {"id": str(s["id"]), "count": int(s.get("count", 1))}
	var eq: Dictionary = d.get("equipped", {})
	for k in equipped.keys():
		equipped[k] = str(eq.get(k, ""))
	quest_items.clear()
	var q: Dictionary = d.get("quest", {})
	for id in q:
		quest_items[str(id)] = int(q[id])
	_touch()
