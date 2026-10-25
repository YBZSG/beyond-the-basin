extends RefCounted
static func digest(value: Variant) -> String: return var_to_str(value).sha256_text()
