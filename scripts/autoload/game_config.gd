## 全局数值与内容配置（只读数据表）。
## 来源：docs/gdd.md 第 5、7、8 章。所有数值均为 GDD v0.9「首轮可玩性测试初值」。
## @trace MECH-004 MECH-005 MECH-007 NUM-001 NUM-002 NUM-003 NUM-004 NUM-005
extends Node

# ---------- 物品 ----------
const ITEMS := {
	"wood": {"name": "木材", "stack": 20, "tag": "material"},
	"stone": {"name": "石头", "stack": 20, "tag": "material"},
	"fiber": {"name": "纤维", "stack": 20, "tag": "material"},
	"metal": {"name": "金属", "stack": 20, "tag": "material"},
	"scrap": {"name": "废料", "stack": 10, "tag": "material"},
	"hide": {"name": "兽皮", "stack": 20, "tag": "material"},
	"berry": {"name": "浆果", "stack": 5, "tag": "food"},
	"raw_meat": {"name": "生肉", "stack": 5, "tag": "food"},
	"cooked_meat": {"name": "熟肉", "stack": 5, "tag": "food"},
	"coconut": {"name": "椰子", "stack": 5, "tag": "food"},
	"dirty_water": {"name": "淡水", "stack": 5, "tag": "drink"},
	"clean_water": {"name": "净水", "stack": 5, "tag": "drink"},
	"herb": {"name": "药草", "stack": 20, "tag": "material"},
	"bandage": {"name": "绷带", "stack": 5, "tag": "med"},
	"splint": {"name": "夹板", "stack": 5, "tag": "med"},
	"lens": {"name": "火台透镜", "stack": 1, "tag": "quest"},
	"guard_emblem": {"name": "守卫徽记", "stack": 1, "tag": "quest"},
	"axe_l1": {"name": "石斧 Lv1", "stack": 1, "tag": "tool"},
	"axe_l2": {"name": "石斧 Lv2", "stack": 1, "tag": "tool"},
	"pick_l1": {"name": "石镐 Lv1", "stack": 1, "tag": "tool"},
	"pick_l2": {"name": "石镐 Lv2", "stack": 1, "tag": "tool"},
	"spear_l1": {"name": "石矛 Lv1", "stack": 1, "tag": "tool"},
	"spear_l2": {"name": "石矛 Lv2", "stack": 1, "tag": "tool"},
}

# 食物/饮品效果（GDD 7.1）
const CONSUMABLE := {
	"berry": {"hunger": 10.0, "thirst": 4.0},
	"raw_meat": {"hunger": 8.0, "bleed": 1},
	"cooked_meat": {"hunger": 32.0},
	"coconut": {"hunger": 8.0, "thirst": 16.0},
	"dirty_water": {"thirst": 25.0},
	"clean_water": {"thirst": 40.0},
	"bandage": {"heal": 8.0, "cure_bleed": true},
	"splint": {"cure_fracture": true},
}

# 工具数值（GDD 7.4）
const TOOLS := {
	"axe_l1": {"gather": 1, "damage": 12.0, "reach": 2.2, "kind": "axe"},
	"axe_l2": {"gather": 2, "damage": 18.0, "reach": 2.2, "kind": "axe"},
	"pick_l1": {"gather": 1, "damage": 14.0, "reach": 2.2, "kind": "pick"},
	"pick_l2": {"gather": 2, "damage": 20.0, "reach": 2.2, "kind": "pick"},
	"spear_l1": {"gather": 1, "damage": 18.0, "reach": 2.2, "kind": "spear"},
	"spear_l2": {"gather": 2, "damage": 28.0, "reach": 2.4, "kind": "spear"},
}

# 制作 / 升级配方（GDD 7.2）。station: "" = 徒手菜单， "campfire" / "workbench"
const RECIPES := [
	{"id": "axe_l1", "name": "石斧 Lv1", "cost": {"wood": 3, "stone": 3, "fiber": 2}, "station": "", "out": "axe_l1", "kind": "craft"},
	{"id": "pick_l1", "name": "石镐 Lv1", "cost": {"wood": 3, "stone": 4, "fiber": 2}, "station": "", "out": "pick_l1", "kind": "craft"},
	{"id": "spear_l1", "name": "石矛 Lv1", "cost": {"wood": 4, "stone": 2, "fiber": 2}, "station": "", "out": "spear_l1", "kind": "craft"},
	{"id": "bandage", "name": "绷带", "cost": {"fiber": 2, "herb": 1}, "station": "", "out": "bandage", "kind": "craft"},
	{"id": "splint", "name": "夹板", "cost": {"wood": 2, "fiber": 2, "herb": 1}, "station": "", "out": "splint", "kind": "craft"},
	{"id": "clean_water", "name": "净水", "cost": {"dirty_water": 1}, "station": "campfire", "out": "clean_water", "kind": "craft"},
	{"id": "cooked_meat", "name": "熟肉", "cost": {"raw_meat": 1, "wood": 1}, "station": "campfire", "out": "cooked_meat", "kind": "craft"},
	{"id": "axe_l2", "name": "斧 Lv2", "cost": {"metal": 3, "scrap": 4, "wood": 2}, "station": "workbench", "out": "axe_l2", "kind": "upgrade", "requires": "axe_l1"},
	{"id": "pick_l2", "name": "镐 Lv2", "cost": {"metal": 3, "scrap": 4, "stone": 2}, "station": "workbench", "out": "pick_l2", "kind": "upgrade", "requires": "pick_l1"},
	{"id": "spear_l2", "name": "矛 Lv2", "cost": {"metal": 2, "scrap": 4, "hide": 2}, "station": "workbench", "out": "spear_l2", "kind": "upgrade", "requires": "spear_l1"},
]

# 建筑（GDD 6.5 / 7.3）
const BUILDINGS := {
	"campfire": {"name": "营火", "cost": {"wood": 5, "stone": 4}, "limit": 4, "range": 6.0, "size": 1.0},
	"workbench": {"name": "工作台", "cost": {"wood": 8, "stone": 4, "fiber": 4}, "limit": 1, "range": 4.0, "size": 1.4},
	"shelter": {"name": "庇护所", "cost": {"wood": 12, "fiber": 8, "hide": 2}, "limit": 2, "range": 0.0, "size": 2.2},
	"signal_tower": {"name": "信号火台", "cost": {"wood": 16, "stone": 10, "scrap": 4}, "limit": 1, "range": 0.0, "size": 2.0, "quest_items": ["lens", "guard_emblem"]},
}

# 资源节点（GDD 5.4）。tool: "" = 徒手
const NODES := {
	"tree": {"name": "树木", "item": "wood", "amount": 6, "durability": 3, "tool": "axe", "respawn": 480.0, "count": 22, "region": "forest"},
	"driftwood": {"name": "浮木", "item": "wood", "amount": 2, "durability": 2, "tool": "", "respawn": 600.0, "count": 10, "region": "beach"},
	"rock": {"name": "石堆", "item": "stone", "amount": 5, "durability": 3, "tool": "pick", "respawn": 480.0, "count": 16, "region": "rocky"},
	"pebble": {"name": "碎石", "item": "stone", "amount": 2, "durability": 2, "tool": "", "respawn": 600.0, "count": 12, "region": "beach"},
	"fiber_bush": {"name": "纤维丛", "item": "fiber", "amount": 4, "durability": 2, "tool": "", "respawn": 420.0, "count": 18, "region": "forest"},
	"berry_bush": {"name": "浆果丛", "item": "berry", "amount": 3, "durability": 2, "tool": "", "respawn": 420.0, "count": 8, "region": "forest"},
	"herb": {"name": "药草", "item": "herb", "amount": 2, "durability": 2, "tool": "", "respawn": 600.0, "count": 8, "region": "wetland"},
	"metal_ore": {"name": "金属矿", "item": "metal", "amount": 3, "durability": 3, "tool": "pick", "respawn": 0.0, "count": 6, "region": "rocky"},
	"scrap_box": {"name": "废料箱", "item": "scrap", "amount": 4, "durability": 2, "tool": "", "respawn": 0.0, "count": 5, "region": "mixed"},
	"water_source": {"name": "取水点", "item": "dirty_water", "amount": 1, "durability": 1, "tool": "", "respawn": 8.0, "count": 6, "region": "wetland"},
}

# 区域（GDD 5.2）：温度基准、色板
const REGIONS := {
	"beach": {"name": "搁浅海滩", "temp": 27.0, "color": "#D8C58F"},
	"forest": {"name": "纤维森林", "temp": 25.0, "color": "#4F7A4A"},
	"rocky": {"name": "低温岩地", "temp": 19.5, "color": "#72777C"},
	"wetland": {"name": "积水湿地", "temp": 23.0, "color": "#4F6B5B"},
}

# 色板（GDD 9.3）
const PALETTE := {
	"sea": "#2E6F8E",
	"shallow": "#3E8AA8",
	"sand": "#D8C58F",
	"forest": "#4F7A4A",
	"rocky": "#72777C",
	"wetland": "#4F6B5B",
	"interactable": "#F2C14E",
	"danger": "#D95555",
	"build_ok": "#68C3A3",
}

# 敌人（GDD 6.8 / 8.4）
const ENEMIES := {
	"boar": {"name": "野猪", "hp": 60.0, "damage": 16.0, "windup": 0.65, "recover": 1.4, "speed": 3.8, "aggro": 11.0, "leash": 22.0, "resistance": 0.0, "drop": {"raw_meat": 2, "hide": 1}, "fracture": 0.2, "slow": 0.55},
	"wolf": {"name": "狼", "hp": 80.0, "damage": 12.0, "windup": 0.45, "recover": 0.9, "speed": 4.6, "aggro": 13.0, "leash": 26.0, "resistance": 0.0, "drop": {"raw_meat": 1, "hide": 1}, "bleed": 0.35, "slow": 0.35},
	"guardian": {"name": "遗迹守卫", "hp": 280.0, "damage": 18.0, "heavy_damage": 26.0, "windup": 0.80, "recover": 1.2, "speed": 3.0, "aggro": 14.0, "leash": 24.0, "resistance": 0.25, "drop": {"guard_emblem": 1}, "fracture": 0.35, "slow": 0.2},
}

# 生存数值（GDD 8.1–8.3）
const SURVIVAL := {
	"hunger_rate": 0.0370,
	"thirst_rate": 0.0556,
	"hunger_zero_damage": 0.3,
	"thirst_zero_damage": 0.6,
	"comfort_min": 35.0,
	"comfort_max": 38.5,
	"clothing_bonus": 0.3,
	"campfire_bonus": 2.0,
	"campfire_heat_range": 6.0,
	"shelter_bonus": 0.4,
	"temp_tau": 90.0,
	"temp_max_rate": 0.03,
	"bleed_dps": 0.25,
	"max_bleed": 2,
	"stamina_sprint": 20.0,
	"stamina_regen": 15.0,
	"stamina_attack": 15.0,
	"stamina_dodge": 25.0,
	"walk_speed": 4.5,
	"sprint_speed": 7.0,
	"day_length": 1440.0,
}

const START_STATS := {"health": 100.0, "stamina": 100.0, "hunger": 80.0, "thirst": 75.0, "temperature": 37.0}

const RESPAWN_STATS := {"health": 50.0, "stamina": 100.0, "hunger": 45.0, "thirst": 40.0, "temperature": 37.0}

# 碰撞层（6.1 / 11.4）：1地形 2玩家 4敌人 8攻击 16交互 32建筑
const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_ENEMY := 4
const LAYER_ATTACK := 8
const LAYER_INTERACT := 16
const LAYER_BUILDING := 32


func item_name(id: String) -> String:
	if ITEMS.has(id):
		return ITEMS[id]["name"]
	return id


func item_stack(id: String) -> int:
	if ITEMS.has(id):
		return int(ITEMS[id]["stack"])
	return 1


func tool_kind(id: String) -> String:
	if TOOLS.has(id):
		return TOOLS[id]["kind"]
	return ""


func building_name(id: String) -> String:
	if BUILDINGS.has(id):
		return BUILDINGS[id]["name"]
	return id


## 依 GDD 8.4：Damage = max(1, round(Base × MoveMultiplier × (1 - Resistance)))
func damage_formula(base: float, move_mult: float, resistance: float) -> int:
	return max(1, int(round(base * move_mult * (1.0 - resistance))))
