from pathlib import Path
import json
from datetime import datetime, timezone
base=Path(r"D:/Projects/AI/dst_mod/assets_src/spell_card_subjects/v3_full_catalog/music_targets")
reviews=json.loads((base/"reviews.json").read_text(encoding="utf-8-sig"))
validation=json.loads((base/"validation.json").read_text(encoding="utf-8"))
metrics={r["id"]:r for r in validation["assets"]}
assets=[]
for path in sorted(base.glob("*.result.json")):
    record=json.loads(path.read_text(encoding="utf-8-sig"))
    rid=record["id"]; rev=reviews[rid]
    record["review_status"]=rev["status"]
    record["notes"]=rev["notes"]
    record["issues"]=[rev["notes"]] if rev["status"]=="needs_retry" else []
    record["review"]={"status":rev["status"],"notes":rev["notes"],"issues":record["issues"],"checked_visual":True,"checked_alpha":True}
    record["validation"]=metrics.get(rid,{})
    record["reviewed_at"]=datetime.now(timezone.utc).isoformat()
    if rev.get("retry"):
        retry_path=base/(rid+".retry.prompt.txt")
        original=(base/(rid+".prompt.txt")).read_text(encoding="utf-8-sig")
        retry_path.write_text(original+"\n\n【下次由用户安排的修正重点；本轮未再次生成】\n"+rev["retry"]+"\n",encoding="utf-8")
        record["retry_prompt"]=str(retry_path).replace("\\","/")
        record["retry_prompt_mode"]="optional_not_required" if rev.get("optional_retry") else "recommended"
    path.write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding="utf-8")
    attempt_path=base/(rid+".attempt.json")
    attempt=json.loads(attempt_path.read_text(encoding="utf-8-sig"))
    attempt["status"]="completed" if record["status"]=="generated" else "failed"
    attempt["completed_at"]=record.get("completed_at")
    attempt["result_file"]=path.name
    attempt_path.write_text(json.dumps(attempt,ensure_ascii=False,indent=2),encoding="utf-8")
    assets.append({"id":rid,"name":record["name"],"status":record["status"],"review_status":record["review_status"],"attempt_count":record["attempt_count"],"output":record["output"],"prompt":str(base/(rid+".prompt.txt")).replace("\\","/"),"notes":record["notes"],"issues":record["issues"],"retry_prompt":record.get("retry_prompt"),"retry_prompt_mode":record.get("retry_prompt_mode")})
summary={
 "group":"music_targets","generated_at":datetime.now(timezone.utc).isoformat(),
 "total":26,"attempted":len(assets),"generated":sum(a["status"]=="generated" for a in assets),
 "candidate":sum(a["review_status"]=="candidate" for a in assets),
 "needs_retry":sum(a["review_status"]=="needs_retry" for a in assets),
 "failed":sum(a["status"]!="generated" for a in assets),
 "policy":"Exactly one built-in image_gen call per assigned image. Original PNG copied without edits. No regeneration, cleanup, compositing, or runtime changes.",
 "validation":{"pngs_checked":len(metrics),"all_rgba":all(m["mode"]=="RGBA" for m in metrics.values()),"all_originals_preserved_byte_identical":all(m["matches_original"] for m in metrics.values()),"all_transparent":all(m["transparent_pixels"]>0 and m["nearly_opaque_pixels"]>0 for m in metrics.values()),"none_clipped_alpha8":all(m["border_pixels_alpha_gte8"]==0 for m in metrics.values()),"report":str(base/"validation.json").replace("\\","/")},
 "retry_recommendations":[a for a in assets if a["review_status"]=="needs_retry"],
 "optional_retry_prompts":[a for a in assets if a["retry_prompt_mode"]=="optional_not_required"],
 "assets":assets}
(base.parent/"music_targets_summary.json").write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding="utf-8")
print(json.dumps({k:summary[k] for k in ["total","attempted","generated","candidate","needs_retry","failed"]},ensure_ascii=False))

