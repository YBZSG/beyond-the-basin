extends RefCounted
## Closed data-only schema. This is not a command, expression or script channel.
const EXPOSURES := [1.12, 2.2, 3.2]
const KEYS := ["schema", "run_id", "decision", "lighting", "exposure", "selected_image_sha256"]
static func validate(value: Variant, run_id: String, lighting: String, images: Dictionary) -> Dictionary:
    if not value is Dictionary: return {"valid": false, "reason": "Expected a JSON object"}
    for key: Variant in value:
        if not key is String or key not in KEYS: return {"valid": false, "reason": "Unknown decision field"}
    if typeof(value.get("schema")) not in [TYPE_INT, TYPE_FLOAT]: return {"valid": false, "reason": "Schema must be numeric version 1"}
    if value.get("schema") != 1 or value.get("run_id") != run_id: return {"valid": false, "reason": "Stale or wrong decision identity"}
    if value.get("decision") == "cancel": return {"valid": true, "decision": "cancel"}
    if value.get("decision") != "record" or value.get("lighting") != lighting: return {"valid": false, "reason": "Expected explicit recording decision for this lighting mode"}
    var number: Variant = value.get("exposure")
    if not (number is float or number is int) or not is_finite(float(number)): return {"valid": false, "reason": "Exposure must be a finite number"}
    var chosen := -1.0
    for allowed: float in EXPOSURES:
        if absf(float(number) - allowed) < 0.0000001: chosen = allowed
    if chosen < 0: return {"valid": false, "reason": "Exposure is outside the three reviewed values"}
    var label := "exposure-" + str(chosen).replace(".", "p")
    if not images.has(label) or value.get("selected_image_sha256") != images[label]: return {"valid": false, "reason": "Decision does not name this run's reviewed image"}
    return {"valid": true, "decision": "record", "exposure": chosen, "selected_image_sha256": images[label]}
