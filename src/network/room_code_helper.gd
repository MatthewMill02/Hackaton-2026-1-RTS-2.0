# Helper for generating, validating, and normalizing 6-letter room codes
class_name RoomCodeHelper
extends RefCounted

const CODE_LENGTH: int = 6
const CHARACTERS: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

static func generate_code() -> String:
	var code = ""
	for i in range(CODE_LENGTH):
		var idx = randi() % CHARACTERS.length()
		code += CHARACTERS[idx]
	return code

static func normalize(raw_code: String) -> String:
	var clean = ""
	for c in raw_code.to_upper():
		if CHARACTERS.contains(c):
			clean += c
	return clean.substr(0, CODE_LENGTH)

static func is_valid(code: String) -> bool:
	var norm = normalize(code)
	return norm.length() == CODE_LENGTH

# Fallback direct IP <-> Alphanumeric Base36 mapping (for zero-config direct LAN/VPN connect)
static func encode_ip_to_code(ip_str: String) -> String:
	var parts = ip_str.split(".")
	if parts.size() != 4:
		return generate_code()
		
	var ip_int: int = (parts[0].to_int() << 24) | (parts[1].to_int() << 16) | (parts[2].to_int() << 8) | parts[3].to_int()
	# Convert 32-bit uint to 6-char base26 letters
	var chars = ""
	var temp = abs(ip_int)
	for i in range(CODE_LENGTH):
		var rem = temp % 26
		chars += CHARACTERS[rem]
		temp = int(temp / 26)
	return chars
