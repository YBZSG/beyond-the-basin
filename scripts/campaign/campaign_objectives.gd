extends RefCounted
## Pure, deterministic mechanics. Rendering and input never decide completion.
const Catalog = preload("res://scripts/campaign/campaign_catalog.gd")
const LIMITS := [480.0, 360.0, 300.0, 420.0, 300.0, 360.0]
const LABELS := [
	["主馈电复位杆", "浅池照明支路", "深池照明支路", "拱厅照明支路", "夜班照明支路", "跳台照明支路", "连池照明支路", "柱厅照明支路"],
	["淋浴旁通阀", "静浴回流阀", "天窗补水阀", "设备室压力验收"],
	["曲廊分流器", "双廊导流器", "圆池出口闸"],
	["阶厅起音踏板", "暗柱回音踏板", "青窗折返踏板", "八角终音踏板", "圆窗记忆验收"],
	["环庭噪声隔离闸", "穹廊排风百叶", "更衣间排风电机"],
	["主池采光总闸", "拱廊反射镜", "侧池消波排水阀", "天井反射镜", "穹顶日光出口"]
]
const KINDS := [
	["breaker","breaker","breaker","breaker","breaker","breaker","breaker","breaker"],
	["valve","valve","valve","pressure_panel"],
	["flow_selector","flow_selector","outlet"],
	["memory_tile","memory_tile","memory_tile","memory_tile","memory_tile"],
	["damper","vent","motor"],
	["shutter","mirror","drain","mirror","egress"]
]
const GOALS := ["隔离漏电支路，恢复其余照明，再拉下主馈电杆。", "调节相互牵制的三路水压，在设备室验收。", "让两段回水流向同一出口，再开启圆池闸门。", "按空间留下的回声顺序重演四拍，在圆窗房确认。", "先隔离噪声，再打开排风通路，最后启动电机。", "让拱廊与天井的光汇入主池，蓄光后开启穹顶。"]
const HINTS := [
	"注意配电柜的焦痕和支路名称；不要一味接通全部回路。",
	"转动一个阀门会影响两枚压力表。设备室铭牌标着安全刻度。",
	"沿着设备上的管线图比对外环与回水方向，闸门不会强行开启。",
	"阶厅留下了四幅空间图案。圆窗房只负责听完整段回声。",
	"电机、百叶与噪声闸有安全联锁，刻牌留下了维修次序。",
	"镜架上的方位刻线与采光总闸相连；水面安静时光会更稳。"
]
const CLUES := [
	"配电记录：只有夜班支路漏电。其余六路应保持通电，最后复位主馈电。",
	"铭牌：旁通 A、回流 B、补水 C 各有 0–3 档。验收须同时满足 A+B=3、B+C=4、A+C=5。",
	"水路刻线：曲廊通向外环（2），双廊通向回水（1）；圆池水位平稳后才可离开。",
	"墙上旧节目单：阶厅 → 青窗 → 暗柱 → 八角。圆窗是听众，不是第五拍。",
	"检修警示：关噪声闸 → 开百叶 → 启动电机。逆序联锁拒绝，操作仍可重试。",
	"日照刻线：拱廊镜朝东（1），天井镜向下（2），再开主池总闸；侧池消波可让蓄光更快。"
]

static func specs(chapter: int, seed_value: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var source: Dictionary = Catalog.chapter(chapter,seed_value)
	for i in range(source.items.size()):
		var spec: Dictionary = source.items[i].duplicate(true)
		spec.merge({"chapter":chapter,"index":i,"kind":KINDS[chapter][i],"label":LABELS[chapter][i],"clue":CLUES[chapter]},true)
		result.append(spec)
	return result

static func initial(chapter: int) -> Dictionary:
	var values: Array = []
	for i in range(LABELS[chapter].size()): values.append(1 if chapter==0 and i>0 else 0)
	return {"values":values,"sequence":[],"stable":0.0,"solved":false}

static func valid(chapter: int, data: Variant) -> bool:
	if not data is Dictionary or data.size()!=4: return false
	if not data.get("values") is Array or data.values.size()!=LABELS[chapter].size(): return false
	if not data.get("sequence") is Array or data.sequence.size()>4: return false
	if not data.get("solved") is bool: return false
	if not (data.get("stable") is float or data.get("stable") is int) or not is_finite(float(data.stable)) or float(data.stable)<0.0 or float(data.stable)>12.0: return false
	for i in range(data.values.size()):
		var v: Variant = data.values[i]
		var maximum: int = 3 if chapter==1 and i<3 else (2 if (chapter==2 and i<2) or (chapter==5 and i in [1,3]) else 1)
		if not (v is int or v is float) or not is_finite(float(v)) or float(v)!=floor(float(v)) or v<0 or v>maximum: return false
	var sequence: Array = [0,2,1,3]
	for i in range(data.sequence.size()):
		if chapter!=3 or data.sequence[i]!=sequence[i]: return false
	return true

static func _powered(v: Array) -> bool:
	if v[0]!=1 or v[4]!=0: return false
	for i in [1,2,3,5,6,7]:
		if v[i]!=1: return false
	return true

static func action(chapter: int, snapshot: Dictionary, index: int) -> Dictionary:
	if index<0 or index>=LABELS[chapter].size() or not valid(chapter,snapshot): return {"accepted":false,"message":"无效控制。","snapshot":snapshot}
	if snapshot.solved: return {"accepted":false,"message":"系统已稳定，无需再次操作。","snapshot":snapshot}
	var next: Dictionary = snapshot.duplicate(true)
	var v: Array = next.values
	var message := ""
	match chapter:
		0:
			v[index]=1-int(v[index]);next.stable=0.0
			message="支路已"+("接通" if v[index] else "隔离")
			if index==0: message="馈电复位："+("正在观察稳定性…" if _powered(v) else "保护联锁仍在报警。检查漏电支路与其余照明。")
		1:
			if index<3: v[index]=(int(v[index])+1)%4; message="阀门转至 %d 档；压力读数：%d / %d / %d"%[v[index],v[0]+v[1],v[1]+v[2],v[0]+v[2]]
			else:
				next.solved=v[0]+v[1]==3 and v[1]+v[2]==4 and v[0]+v[2]==5
				v[3]=1 if next.solved else 0
				message="三路压力验收通过。" if next.solved else "压力不平衡。目标读数 3 / 4 / 5；阀门互相影响，请继续调节。"
		2:
			if index<2: v[index]=(int(v[index])+1)%3;v[2]=0;next.stable=0.0;message="导流器转至 %d 档。出口联锁已复位。"%v[index]
			elif v[0]==2 and v[1]==1: v[2]=1-int(v[2]);next.stable=0.0;message="出口闸已"+("打开，等待水位平稳。" if v[2] else "关闭。")
			else: message="出口压力反向。先比对两段刻线与流向，闸门未动。"
		3:
			var order: Array = [0,2,1,3]
			if index==4:
				next.solved=next.sequence==order;message="四拍回声吻合。" if next.solved else "回声尚未重现完整；四拍之后再验收。"
			elif next.sequence.size()<4 and index==order[next.sequence.size()]: next.sequence.append(index);v[index]=1;message="回声记住了第 %d 拍。"%next.sequence.size()
			else: next.sequence=[];next.values=[0,0,0,0,0];message="回声散去。顺序已清空，可从阶厅重新开始。"
		4:
			if index==0: v[0]=1-int(v[0]);v[1]=0;v[2]=0;next.stable=0.0;message="噪声闸已"+("隔离。可以打开百叶。" if v[0] else "解除隔离；排风已安全停止。")
			elif index==1 and v[0]==1: v[1]=1-int(v[1]);v[2]=0;next.stable=0.0;message="百叶已"+("打开。可以启动电机。" if v[1] else "关闭，电机已停。")
			elif index==2 and v[0]==1 and v[1]==1: v[2]=1-int(v[2]);next.stable=0.0;message="电机已"+("启动，正在排出滞气…" if v[2] else "停止。")
			else: message="安全联锁拒绝：必须先隔离噪声，再打开百叶。"
		5:
			if index in [1,3]: v[index]=(int(v[index])+1)%3;v[0]=0;next.stable=0.0;message="反射镜转至 %d 档；总闸已关闭以保护眼睛。"%v[index]
			elif index==2: v[2]=1-int(v[2]);message="消波排水"+("开启，水面更稳定。" if v[2] else "关闭。")
			elif index==0 and v[1]==1 and v[3]==2: v[0]=1-int(v[0]);message="采光总闸已"+("打开，正在蓄光。" if v[0] else "关闭。")
			elif index==4 and next.stable>=12.0: next.solved=true;v[4]=1;message="穹顶机械锁释放。日光出口已开启。"
			else: message="光线尚未汇聚或蓄光不足。检查两面镜子和主池总闸。"
	return {"accepted":true,"snapshot":next,"message":message}

static func tick(chapter: int, snapshot: Dictionary, delta: float) -> Dictionary:
	var next: Dictionary = snapshot.duplicate(true)
	if next.solved or not is_finite(delta) or delta<=0: return next
	var v: Array = next.values
	var stable: bool = (chapter==0 and _powered(v)) or (chapter==2 and v[0]==2 and v[1]==1 and v[2]==1) or (chapter==4 and v[0]==1 and v[1]==1 and v[2]==1) or (chapter==5 and v[0]==1 and v[1]==1 and v[3]==2)
	if stable:
		next.stable=minf(12.0,float(next.stable)+delta*(1.5 if chapter==5 and v[2]==1 else 1.0))
		if chapter!=5: next.solved=next.stable>=[8.0,0.0,6.0,0.0,10.0,12.0][chapter]
	else: next.stable=0.0
	return next

static func feedback(chapter: int, snapshot: Dictionary) -> String:
	if snapshot.solved: return "系统稳定 · 出口已解锁"
	var v: Array = snapshot.values
	match chapter:
		0: return "主馈电 %s · 故障支路 %s · 稳定 %.1f / 8 秒"%["开" if v[0] else "关","接通" if v[4] else "隔离",snapshot.stable]
		1: return "三路压力 %d / %d / %d（目标 3 / 4 / 5）"%[v[0]+v[1],v[1]+v[2],v[0]+v[2]]
		2: return "流向 %d → %d · 闸 %s · 平稳 %.1f / 6 秒"%[v[0],v[1],"开" if v[2] else "关",snapshot.stable]
		3: return "回声 %d / 4 拍 · 错序可从阶厅重演"%snapshot.sequence.size()
		4: return "隔离 %s / 百叶 %s / 电机 %s · 排风 %.1f / 10 秒"%[v[0],v[1],v[2],snapshot.stable]
		5: return "反射 %d / %d · 蓄光 %.1f / 12 秒"%[v[1],v[3],snapshot.stable]
	return ""

static func view(chapter: int, snapshot: Dictionary, index: int) -> Dictionary:
	return {"value":int(snapshot.values[index]),"active":snapshot.values[index]!=0,"solved":bool(snapshot.solved),"feedback":feedback(chapter,snapshot),"stable":float(snapshot.stable),"readings":[snapshot.values[0]+snapshot.values[1],snapshot.values[1]+snapshot.values[2],snapshot.values[0]+snapshot.values[2]] if chapter==1 else []}

static func status(chapter:int,snapshot:Dictionary)->String:
	if snapshot.solved:return "系统已稳定 · 出口联锁解除"
	if chapter==3:return "回声已记住 %d / 4 拍"%snapshot.sequence.size()
	if snapshot.stable>0.0:return "设备正在运行，等待稳定；可继续观察附近环境。"
	return "系统尚未稳定。附近设备的刻线和痕迹留下了线索。"
