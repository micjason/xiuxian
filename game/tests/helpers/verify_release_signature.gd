extends SceneTree


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		push_error("Usage: -- PUBLIC_KEY MANIFEST SIGNATURE")
		quit(2)
		return

	var public_key := CryptoKey.new()
	if public_key.load(args[0], true) != OK:
		push_error("Unable to load public key.")
		quit(1)
		return

	var manifest := FileAccess.get_file_as_bytes(args[1])
	var signature := FileAccess.get_file_as_bytes(args[2])
	var hash := _sha256(manifest)
	var verified := Crypto.new().verify(
		HashingContext.HASH_SHA256,
		hash,
		signature,
		public_key
	)
	if not verified:
		push_error("Manifest signature verification failed.")
		quit(1)
		return

	print("Godot manifest signature verification passed.")
	quit(0)


func _sha256(data: PackedByteArray) -> PackedByteArray:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return PackedByteArray()
	context.update(data)
	return context.finish()
