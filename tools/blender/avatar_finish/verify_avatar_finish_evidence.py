"""CPU-only hash binding: does the latest native evidence test current files?"""
from pathlib import Path
import hashlib,json
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2]
latest=HERE/'audit/latest_native_result.txt'
r=dict(current_files_match_native=False,native_technical_pass=False,visual_verdict='pending',production_approval_provided=False)
if latest.exists():
 out=Path(latest.read_text().strip());manifest=json.loads((out/'stage_manifest.json').read_text());changed=[]
 for name,digest in manifest['copied_files'].items():
  p=ROOT/name
  if not p.exists() or hashlib.sha256(p.read_bytes()).hexdigest()!=digest:changed.append(name)
 receipt=json.loads((out/'completed_exit_receipt.json').read_text())
 report=json.loads((out/'captures/avatar_finish_candidate_native_report.json').read_text())
 review=out/'avatar_finish_candidate_visual_review.json'
 r.update(native_evidence=str(out.relative_to(ROOT)),changed_since_native=changed,
          current_files_match_native=not changed,
          native_technical_pass=receipt['passed'] and report['passed'] and len(report['captures'])==12,
          native_completed_utc=receipt['completed_utc'])
 if review.exists():r['visual_verdict']=json.loads(review.read_text())['verdict']
(HERE/'audit/avatar_finish_candidate_current_evidence.json').write_text(json.dumps(r,indent=2)+'\n')
print(json.dumps(r,indent=2))
