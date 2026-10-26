extends RefCounted
static func operate(state:RefCounted,index:int,times:int=1)->void:
	for i in range(times):state.operate(str(state.current_chapter().items[index].id))
static func settle(state:RefCounted,seconds:float)->void:
	for i in range(int(seconds*4)+1):state.advance_time(.25,true)
static func solve(state:RefCounted)->void:
	match state.chapter_index:
		0:operate(state,4);operate(state,0);settle(state,8)
		1:operate(state,0,2);operate(state,1);operate(state,2,3);operate(state,3)
		2:operate(state,0,2);operate(state,1);operate(state,2);settle(state,6)
		3:
			for i in [0,2,1,3,4]:operate(state,i)
		4:operate(state,0);operate(state,1);operate(state,2);settle(state,10)
		5:operate(state,1);operate(state,3,2);operate(state,0);settle(state,12);operate(state,4)
static func advance_to(state:RefCounted,index:int)->void:
	for i in range(index):solve(state);state.begin_transition();state.finish_transition()
