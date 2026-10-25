extends SceneTree

func _init() -> void:
	print("--- Validating all GDScript files in project ---")
	var error_count := 0
	var scripts_to_check := []
	
	var dir := DirAccess.open("res://")
	_scan_dir("res://", scripts_to_check)
	
	print("Found %d scripts to validate." % scripts_to_check.size())
	for path in scripts_to_check:
		var script = load(path)
		if script == null:
			printerr("ERROR loading script: " + path)
			error_count += 1
		else:
			print("OK: " + path)

	print("--- Validation finished with %d errors ---" % error_count)
	quit(error_count)

func _scan_dir(dir_path: String, out_scripts: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if file_name == "." or file_name == ".." or file_name == ".git" or file_name == ".godot":
			file_name = dir.get_next()
			continue
		var full_path := dir_path.path_join(file_name)
		if dir.current_is_dir():
			_scan_dir(full_path, out_scripts)
		elif file_name.ends_with(".gd"):
			out_scripts.append(full_path)
		file_name = dir.get_next()
	dir.list_dir_end()
