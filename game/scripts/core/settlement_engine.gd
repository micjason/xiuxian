class_name SettlementEngine
extends RefCounted


static func settle_long_term(
	state: CultivationState,
	config: LongTermConfig,
	elapsed_seconds: int,
	expedition_base_power: int = 0
) -> SettlementDelta:
	var delta := SettlementDelta.new()
	if state == null or state.long_term == null or config == null or elapsed_seconds <= 0:
		return delta
	var progress := state.long_term
	LongTermRules.initialize(config, progress.economy, progress.cave, progress.craft)
	delta.applied_seconds = elapsed_seconds
	var gained := LongTermRules.apply_cave_elapsed(
		progress.economy,
		progress.cave,
		progress.sect,
		progress.beast,
		progress.expedition,
		config,
		float(elapsed_seconds)
	)
	for resource_id in gained.keys():
		delta.add_resource(str(resource_id), float(gained[resource_id]))
	var completed := LongTermRules.apply_craft_elapsed(
		progress.economy,
		progress.craft,
		progress.sect,
		config,
		float(elapsed_seconds)
	)
	for recipe_id in completed:
		delta.completed_jobs.append(recipe_id)
	var expeditions := LongTermRules.apply_auto_expeditions(
		progress.economy,
		progress.expedition,
		progress.sect,
		progress.beast,
		config,
		float(elapsed_seconds),
		expedition_base_power,
		progress.run_seconds + progress.expedition.encounter_index
	)
	if not expeditions.is_empty():
		delta.messages.append("自动委托完成 %d 次。" % expeditions.size())
	progress.lifetime_seconds += elapsed_seconds
	progress.run_seconds += elapsed_seconds
	progress.last_summary = _summary_lines(delta, config)
	return delta


static func _summary_lines(delta: SettlementDelta, config: LongTermConfig) -> PackedStringArray:
	var lines := PackedStringArray()
	if not delta.resources.is_empty():
		var parts := PackedStringArray()
		var ids: Array = delta.resources.keys()
		ids.sort()
		for resource_id in ids:
			var display_name := str(config.resource_names.get(str(resource_id), resource_id))
			parts.append("%s +%s" % [
				display_name,
				CultivationFormat.amount(float(delta.resources[resource_id])),
			])
		lines.append("洞府产出：%s。" % "、".join(parts))
	if not delta.completed_jobs.is_empty():
		lines.append("丹器完成 %d 项，可在洞府查看。" % delta.completed_jobs.size())
	for message in delta.messages:
		lines.append(message)
	return lines
