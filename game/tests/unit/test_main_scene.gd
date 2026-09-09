extends GutTest

const REQUIRED_UNIQUE_NODES := [
	"Title",
	"VersionLabel",
	"UpgradeBadge",
	"DataMarker",
	"RealmLabel",
	"RealmPath",
	"CultivationLabel",
	"RateLabel",
	"NextCostLabel",
	"NextRealmLabel",
	"CultivationProgress",
	"BreakthroughButton",
	"BreakthroughBanner",
	"JournalLabel",
	"OfflineLabel",
	"StatusLabel",
	"DownloadProgress",
	"CheckButton",
	"InstallButton",
	"UpdateDialog",
	"OfflineDialog",
	"UpdateService",
	"Flash",
	"SealRing",
	"SealInner",
	"ProgressHint",
	"CultivationCard",
	"StatsCard",
	"JournalCard",
	"UpdateCard",
]


func test_main_scene_keeps_the_first_loop_unique_nodes() -> void:
	var scene := FileAccess.get_file_as_string("res://scenes/main.tscn")
	assert_false(scene.is_empty())
	for node_name in REQUIRED_UNIQUE_NODES:
		assert_true(scene.contains("name=\"%s\"" % node_name), "missing %s" % node_name)
		assert_true(scene.contains("unique_name_in_owner = true"))
