class_name Level01Def
extends RefCounted
##
## 关卡 01《钟械工坊·前厅》**权威数据定义**。
## 数值逐格照抄 design/level/level_01_design.md §3 ASCII 图 与 §5 真值表。
##
## ⚠ 布局改版（v4 · 房间放大）：网格由 **10×5 扩到 13×8**。
##   · 西侧「工匠前厅」由 3×3 扩成 **6×6 大厅**（房间真的变大、更宽敞）；
##   · 中隔断墙变为 **2 宽 × 5 高**，顶层 y=1 仍是「大门 → 藤蔓」的**唯一咽喉**；
##   · 东侧「出口厅」由 3×3 扩成 **3×6**（压力板凹室 + 闸门后的小厅）。
##   4 个谜题与真值表**语义完全不变** —— 只有坐标平移/放大，通路拓扑已逐条重验。
##
## 本文件是关卡的「代码化真值表」：tools/gen_level_res.gd 会把它序列化为
## levels/level_01_data.tres；运行时由 LevelLoader 优先加载 .tres，失败则回退本定义。
##

const LEVEL_ID := &"L01_FORGE_HALL"

## GDD §3.4 标签表在本关用到的取值
const T_UNLOCKS_GATE := "UNLOCKS:GATE"
const T_PRESSER := "PRESSER"
const T_BLOCKING := "BLOCKING"
const T_HOT := "HOT"
const T_IMMOVABLE := "IMMOVABLE"
const T_OCCLUDED := "OCCLUDED"
const T_TOO_THICK := "TOO_THICK"
const T_PULLABLE := "PULLABLE"
const T_FRAGILE := "FRAGILE"
const T_JUNK := "JUNK"
const T_HEAVY := "HEAVY"
const T_NO_TAKE := "NO_TAKE"
const T_LOCKED_GATE := "LOCKED:GATE"

const FREE_FIELDS := ["pos", "form", "available", "removed"]


static func build() -> LevelData:
	var lv := LevelData.new()
	lv.level_id = LEVEL_ID
	lv.display_name = "钟械工坊 · 前厅"
	lv.grid_size = Vector2i(13, 8)
	lv.walls = _walls()
	lv.player_start = Vector2i(3, 5)
	lv.plate_pos = Vector2i(9, 3)
	lv.start_t = 2
	lv.unlocked = [0, 1, 2, 3]
	lv.hourglass_cap = 12
	lv.backpack_cap = 2
	lv.win_t = 2
	lv.win_pos = Vector2i(11, 1)
	lv.requirements = [{"tag": T_UNLOCKS_GATE, "target": "GATE"}]
	lv.hints = _hints()
	lv.timepoints = _timepoints()
	lv.entities = _entities()
	return lv


# ------------------------------------------------------------------ 地形 ---

## 13×8 网格（x=0..12，y=0..7）：
##   · 外圈一圈墙；
##   · **中隔断墙** x=7,8（y=2..6）—— 把整张图切成「西厅 / 东厅」两半；
##     顶层 y=1 只留 (7,1) 大门 与 (8,1) 藤蔓 —— 这是两厅之间**唯一的连接**；
##   · (10,1) 堵住出口的北邻 → 出口只能从闸门侧的 (11,2) 进入；
##   · (10,3)(11,3) 是闸门后的隔墙，把压力板 (9,3) 关成一个只从南北进出的凹室。
static func _walls() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in 13:
		out.append(Vector2i(x, 0))
		out.append(Vector2i(x, 7))
	for y in 8:
		out.append(Vector2i(0, y))
		out.append(Vector2i(12, y))
	var inner := [
		Vector2i(7, 2), Vector2i(8, 2), Vector2i(7, 3), Vector2i(8, 3),
		Vector2i(7, 4), Vector2i(8, 4), Vector2i(7, 5), Vector2i(8, 5),
		Vector2i(7, 6), Vector2i(8, 6),
		Vector2i(10, 1), Vector2i(10, 3), Vector2i(11, 3),
	]
	for c in inner:
		if not out.has(c):
			out.append(c)
	return out


# ------------------------------------------------------------------ 时刻 ---

static func _timepoints() -> Array[TimepointDef]:
	var defs := [
		{"id": "T0_CAST",   "label": "铸造·晨", "roman": "Ⅰ",
		 "tint": Color("#7C8DA0"), "light": 15.0,  "sfx": "低频嗡鸣 + 金属滴答",
		 "particle": "SPARK", "brightness": 0.78},
		{"id": "T1_BRIGHT", "label": "新光·昼", "roman": "Ⅱ",
		 "tint": Color("#E8C56A"), "light": 90.0,  "sfx": "明亮木琴 + 齿轮咬合",
		 "particle": "DUST",  "brightness": 1.0},
		{"id": "T2_RUST",   "label": "锈时·昏", "roman": "Ⅲ",
		 "tint": Color("#B5743A"), "light": 300.0, "sfx": "沙沙摩擦 + 低沉风声",
		 "particle": "RUST",  "brightness": 0.66},
		{"id": "T3_STILL",  "label": "沉寂·夜", "roman": "Ⅳ",
		 "tint": Color("#9A9A96"), "light": 350.0, "sfx": "极静，心跳般低频",
		 "particle": "ASH",   "brightness": 0.5},
	]
	var out: Array[TimepointDef] = []
	for i in defs.size():
		var d: Dictionary = defs[i]
		var tp := TimepointDef.new()
		tp.id = StringName(String(d["id"]))
		tp.index = i
		tp.label = String(d["label"])
		tp.roman = String(d["roman"])
		tp.tint = d["tint"]
		tp.light_angle = float(d["light"])
		tp.ambient_sfx = String(d["sfx"])
		tp.particle = String(d["particle"])
		tp.brightness = float(d["brightness"])
		out.append(tp)
	return out


# ------------------------------------------------------------------ 实体 ---

static func _entities() -> Array[TimeEntityData]:
	var out: Array[TimeEntityData] = []

	# ---- KEY 钥匙（自由）------------------------------------------------
	# T0 金属锭(HOT) → T1 崭新钥匙(UNLOCKS:GATE) → T2 生锈钥匙(FRAGILE) → T3 锈块(JUNK)
	# 注：钥匙很小，可以从上面跨过去（solid = false）—— 否则「钥匙留在锁孔里」
	# 会把刚打开的门格重新堵死，关卡直接不可解。
	out.append(_free(&"KEY", "钥匙", &"KEY", false, [
		_frame(&"INGOT",     Vector2i(3, 2), false, [T_HOT, T_HEAVY], "熔炉刚熄，它还只是一块锭。"),
		_frame(&"KEY_NEW",   Vector2i(3, 2), true,  [T_UNLOCKS_GATE], "柄上刻着一个名字，已经磨得看不清了。"),
		_frame(&"KEY_RUSTY", Vector2i(3, 2), true,  [T_FRAGILE],      "齿口发脆，一拧就会断。"),
		_frame(&"RUST_LUMP", Vector2i(2, 2), true,  [T_JUNK],         "它终于是块锈了。"),
	]))

	# ---- WEIGHT 黄铜砝码（自由）----------------------------------------
	# T0 熔融(HOT) → T1 完好(可取) → T2 锈死(IMMOVABLE) → T3 掩埋(OCCLUDED)
	# ★ 四个形态**都带 PRESSER**：形态锁只影响能否持取，绝不影响压感。
	out.append(_free(&"WEIGHT", "黄铜砝码", &"WEIGHT", true, [
		_frame(&"MOLTEN",        Vector2i(1, 2), false, [T_HOT, T_NO_TAKE, T_PRESSER], "一汪还没凝的铜液。"),
		_frame(&"WEIGHT_OK",     Vector2i(1, 2), true,  [T_HEAVY, T_PRESSER],          "沉甸甸的，压得住东西。"),
		_frame(&"WEIGHT_SEIZED", Vector2i(1, 2), false, [T_IMMOVABLE, T_PRESSER],      "它与地面锈成了一体。"),
		_frame(&"WEIGHT_BURIED", Vector2i(1, 2), false, [T_OCCLUDED, T_PRESSER],       "落灰把它埋了大半。"),
	]))

	# ---- VINE 藤蔓（锚定，PULLABLE 可被 USE 拔除）----------------------
	# 两厅之间的唯一咽喉（中隔断墙顶层，紧挨大门东侧）。
	#
	# ⚠ **四形态一律带 BLOCKING** —— 它是硬性咽喉，任何时刻都过不去，只有拔掉才通。
	#   曾经 T0/T1 的 SPROUT/YOUNG 只带 PULLABLE（不阻挡），本意是「幼苗细、能钻过去」，
	#   结果被玩家找到漏洞：切到「新光·昼」直接穿过咽喉，切回「现在」人已在东区，
	#   全程不必拔藤 → P3 谜题被架空，§7 的「步 7 拔藤」沦为多余步骤。
	#   现已改为**始终阻挡**：T0/T1 仍是「可拔」（PULLABLE），但不再是「可过」。
	#   保留 PULLABLE 与 BLOCKING 并存，正是 P3 的教学点 ——
	#   「这一刻你拔得动它，但此刻你必须拔掉它才能过去」。
	out.append(_anchored(&"VINE", "藤蔓", &"VINE", false, ["removed"], [
		_frame(&"SPROUT",   Vector2i(8, 1), false, [T_PULLABLE, T_BLOCKING],  "刚冒头的幼苗，却已爬满了整个门洞。"),
		_frame(&"YOUNG",    Vector2i(8, 1), false, [T_PULLABLE, T_BLOCKING],  "柔弱的幼藤，一把就能拔掉，但它确实堵着路。"),
		_frame(&"THICK",    Vector2i(8, 1), false, [T_TOO_THICK, T_BLOCKING], "茂密的藤墙，堵死了整个咽喉。"),
		_frame(&"WITHERED", Vector2i(8, 1), false, [T_BLOCKING],              "枯藤硬得像铁网。"),
	]))

	# ---- GATE 铁栅门（锚定锁具，open 可被 Override 写入）--------------
	out.append(_anchored(&"GATE", "铁栅门", &"GATE", true, ["open"], [
		_frame(&"BARRED",        Vector2i(7, 1), false, [T_BLOCKING, T_LOCKED_GATE], ""),
		_frame(&"BARRED",        Vector2i(7, 1), false, [T_BLOCKING, T_LOCKED_GATE], ""),
		_frame(&"BARRED_RUSTY",  Vector2i(7, 1), false, [T_BLOCKING, T_LOCKED_GATE], ""),
		_frame(&"BARRED_ROTTEN", Vector2i(7, 1), false, [T_BLOCKING, T_LOCKED_GATE], ""),
	], true))

	# ---- GRATE 闸门（锚定，派生：open(t) = plate.pressed(t)）----------
	out.append(_anchored(&"GRATE", "闸门", &"GRATE", true, [], [
		_frame(&"GRATE", Vector2i(10, 2), false, [T_BLOCKING], ""),
		_frame(&"GRATE", Vector2i(10, 2), false, [T_BLOCKING], ""),
		_frame(&"GRATE", Vector2i(10, 2), false, [T_BLOCKING], ""),
		_frame(&"GRATE", Vector2i(10, 2), false, [T_BLOCKING], ""),
	]))

	# ---- PLATE 压力板（锚定，派生：pressed(t) = ∃ PRESSER @ (9,3)）----
	# ★ is_receptacle = true：本关唯一的容器格（末位实参）
	out.append(_anchored(&"PLATE", "压力板", &"PLATE", false, [], [
		_frame(&"PLATE", Vector2i(9, 3), false, [], ""),
		_frame(&"PLATE", Vector2i(9, 3), false, [], ""),
		_frame(&"PLATE", Vector2i(9, 3), false, [], ""),
		_frame(&"PLATE", Vector2i(9, 3), false, [], ""),
	], false, true))     # lock=false, receptacle=true

	# ---- EXIT 出口门（锚定；只有 T2 INTACT 可通行）--------------------
	out.append(_anchored(&"EXIT", "出口门", &"EXIT", true, [], [
		_frame(&"NOT_BUILT", Vector2i(11, 1), false, [T_BLOCKING], "这里以后会是出口。"),
		_frame(&"NO_HANDLE", Vector2i(11, 1), false, [T_BLOCKING], "门扇还没装把手。"),
		_frame(&"INTACT",    Vector2i(11, 1), false, [],           "完好的出口门 —— 就是现在。"),
		_frame(&"COLLAPSED", Vector2i(11, 1), false, [T_BLOCKING], "它塌了，封死了。"),
	]))

	# ---- STAND 钥匙台（锚定静态）--------------------------------------
	out.append(_anchored(&"STAND", "钥匙台", &"STAND", true, [], [
		_frame(&"STAND", Vector2i(3, 2), false, [T_BLOCKING], "工匠放钥匙的台子。"),
		_frame(&"STAND", Vector2i(3, 2), false, [T_BLOCKING], "工匠放钥匙的台子。"),
		_frame(&"STAND", Vector2i(3, 2), false, [T_BLOCKING], "工匠放钥匙的台子。"),
		_frame(&"STAND", Vector2i(3, 2), false, [T_BLOCKING], "工匠放钥匙的台子。"),
	]))

	# ---- FORGE 熔炉（锚定静态，观察条目）------------------------------
	out.append(_anchored(&"FORGE", "熔炉", &"FORGE", true, [], [
		_frame(&"FORGE", Vector2i(1, 1), false, [T_BLOCKING], "壁上刻着：『凡物皆有其时。』"),
		_frame(&"FORGE", Vector2i(1, 1), false, [T_BLOCKING], "壁上刻着：『凡物皆有其时。』"),
		_frame(&"FORGE", Vector2i(1, 1), false, [T_BLOCKING], "壁上刻着：『凡物皆有其时。』"),
		_frame(&"FORGE", Vector2i(1, 1), false, [T_BLOCKING], "壁上刻着：『凡物皆有其时。』"),
	]))

	return out


# ------------------------------------------------------------------ 工具 ---

static func _frame(
	form: StringName,
	pos: Vector2i,
	available: bool,
	tags: Array,
	note: String
) -> StateFrame:
	var f := StateFrame.new()
	f.form = form
	f.pos = pos
	f.available = available
	f.tags = PackedStringArray(tags)
	f.note = note
	return f


static func _free(
	id: StringName,
	display: String,
	sil: StringName,
	solid: bool,
	chain: Array
) -> TimeEntityData:
	var e := TimeEntityData.new()
	e.id = id
	e.display_name = display
	e.anchored = false
	e.silhouette = sil
	e.solid = solid
	e.is_lock = false
	e.is_receptacle = false      # 自由道具永不是容器格
	e.writable_fields = PackedStringArray(FREE_FIELDS)
	e.chain = _to_state_array(chain)
	return e


static func _anchored(
	id: StringName,
	display: String,
	sil: StringName,
	solid: bool,
	writable: Array,
	chain: Array,
	lock: bool = false,
	receptacle: bool = false
) -> TimeEntityData:
	var e := TimeEntityData.new()
	e.id = id
	e.display_name = display
	e.anchored = true
	e.silhouette = sil
	e.solid = solid
	e.is_lock = lock
	e.is_receptacle = receptacle
	e.writable_fields = PackedStringArray(writable)
	e.chain = _to_state_array(chain)
	return e


static func _to_state_array(arr: Array) -> Array[StateFrame]:
	var out: Array[StateFrame] = []
	for f in arr:
		out.append(f as StateFrame)
	return out


static func _hints() -> Array[Dictionary]:
	return [
		{"level": 1, "text": "留意钥匙台上那把钥匙。"},
		{"level": 2, "text": "这把钥匙，并不是一直都是锈的。"},
		{"level": 3, "text": "切到『新光·昼』，取走那把崭新的钥匙。"},
	]
