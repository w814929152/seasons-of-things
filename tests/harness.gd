class_name TestHarness
extends RefCounted
##
## 极简 headless 断言器。所有断言走 ck()/eq()，失败收集进 _fails，
## 最后由 test_main.gd 汇总打印 PASS/FAIL 并返回退出码。
##

var _pass: int = 0
var _fails: Array[String] = []
var _suite: String = ""


func suite(name: String) -> void:
	_suite = name
	print("")
	print("── 用例组：", name)


func ck(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("   [ck] PASS  ", msg)
	else:
		_fails.append("[%s] %s" % [_suite, msg])
		print("   [ck] FAIL  ", msg)


func eq(a: Variant, b: Variant, msg: String) -> void:
	ck(a == b, "%s  (实际=%s / 期望=%s)" % [msg, str(a), str(b)])


func pass_count() -> int:
	return _pass


func fail_count() -> int:
	return _fails.size()


func failures() -> Array[String]:
	return _fails


## 开一局全新的关卡 01（T2 / (2,3) / 时砂 12）
static func new_game() -> TimeController:
	var lv := LevelLoader.load_level_01()
	var tc := TimeController.new()
	tc.setup(lv)
	return tc


## 逐字段比对两组「全时刻快照」，返回差异描述
static func diff_snapshots(a: Array, b: Array) -> Array[String]:
	var out: Array[String] = []
	if a.size() != b.size():
		out.append("snapshot 数量不同")
		return out
	for i in a.size():
		out.append_array((a[i] as WorldSnapshot).diff(b[i] as WorldSnapshot))
	return out
