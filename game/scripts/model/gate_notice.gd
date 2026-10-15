class_name GateNotice
extends RefCounted
## 开战前背包已满时的一行提示（不拦挑战）。


static func text(gate: Dictionary) -> String:
	var head := "背包已满（%d/%d）：" % [int(gate.get("used", 0)), int(gate.get("capacity", 0))]
	if bool(gate.get("auto_decompose", false)):
		return head + "新掉的装备不会入包，白/绿装备会直接分解成强化经验"
	return head + "新掉的装备不会入包，可以先去背包分解装备"
