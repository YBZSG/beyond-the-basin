class_name PoolPreparationStatus
extends RefCounted
## Honest task stages, never a fabricated percentage or an estimated countdown.
const LABELS := {
	"starting_solver":"初始化原版水体 / STARTING WATER",
	"streaming_geometry":"装配房间 / BUILDING ROOMS",
	"reading_exact_snapshot":"校验静态场景 / VALIDATING SCENE CACHE",
	"collecting_geometry":"读取碰撞与模型 / READING GEOMETRY",
	"transforming_geometry":"转换静态模型 / PREPARING GEOMETRY",
	"queued":"排队准备水体 / QUEUED",
	"translate":"定位水域 / LOCATING WATER",
	"depth":"计算水深与边界 / WATER DEPTH",
	"wet_mask":"计算湿区 / WET REGIONS",
	"bvh":"构建光线路径 / OPTICAL GEOMETRY",
	"masks":"计算光照遮挡 / LIGHT OCCLUSION",
	"complete":"应用水体数据 / APPLYING WATER DATA",
	"prewarming":"后台准备相邻空间 / PREPARING NEARBY ROOMS",
	"suspended":"等待房间装配 / WAITING FOR ROOMS"
}
static func describe(status: Dictionary) -> String:
	var error := str(status.get("error", ""))
	if not error.is_empty(): return "水体初始化失败 / WATER ERROR\n" + error.left(180)
	if bool(status.get("ready", false)):
		var probe: Dictionary = status.get("probe", {})
		if not bool(probe.get("texture_ready", true)):
			return "可开始探索，倒影正在准备 / READY; REFLECTIONS PREPARING"
		return ""
	var stage := str(status.get("stage", "queued"))
	var text: String = str(LABELS.get(stage, "准备水体 / PREPARING WATER"))
	if stage == "collecting_geometry":
		text += " · %d / %d 间" % [int(status.get("rooms_collected",0)),int(status.get("rooms_total",0))]
	var seconds := float(status.get("elapsed_ms",0.0)) / 1000.0
	if seconds >= 3.0: text += "\n已用 %.0f 秒 / ELAPSED %.0f s" % [seconds,seconds]
	return text
