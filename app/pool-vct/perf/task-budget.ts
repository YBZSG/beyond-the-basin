/** Cooperative budget: never start another work unit after the deadline.
 * A native allocation/upload cannot be preempted; callers keep units small. */
export function backgroundBudget(frameCpuMs:number){return Math.max(0,Math.min(3,14-frameCpuMs));}
export function advanceTask<T>(task:Generator<void,T>,budgetMs:number,now=()=>performance.now()):IteratorResult<void,T>|null{
  if(budgetMs<=0)return null;
  const deadline=now()+Math.min(3,budgetMs);let result:IteratorResult<void,T>;
  do{result=task.next();if(result.done)return result;}while(now()<deadline);
  return result;
}
