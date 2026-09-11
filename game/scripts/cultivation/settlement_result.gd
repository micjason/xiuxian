class_name SettlementResult
extends RefCounted

var applied_seconds: int = 0
var gained: float = 0.0
var hit_cap: bool = false
var clock_rewound: bool = false
var combat_kills: int = 0
var combat_retreated: bool = false
var combat_loot: PackedStringArray = []
var combat_bag_skipped: int = 0
var long_term_resources: Dictionary[String, float] = {}
var long_term_summary: PackedStringArray = PackedStringArray()
