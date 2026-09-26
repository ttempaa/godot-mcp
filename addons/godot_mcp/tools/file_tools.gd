@tool
extends Node
class_name FileTools
## File operation tools for MCP.
## Handles: list_dir, read_file, search_project, create_script

const DEFAULT_MAX_BYTES := 200_000
const DEFAULT_MAX_RESULTS := 200
const MAX_TRAVERSAL_DEPTH := 20
const DEFAULT_PREVIEW_HEAD := 40
const DEFAULT_PREVIEW_TAIL := 10
const REDACTED_TEXT := "[REDACTED]"
const _SKIP_EXTENSIONS: Dictionary = {
	".import": true, ".png": true, ".jpg": true, ".jpeg": true,
	".webp": true, ".svg": true, ".ogg": true, ".wav": true,
	".mp3": true, ".escn": true, ".glb": true, ".gltf": true,
	".uid": true,
}

var _editor_plugin: EditorPlugin = null

func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin

# =============================================================================
# list_dir - List files and folders in a directory
# =============================================================================
func list_dir(args: Dictionary) -> Dictionary:
	var root: String = str(args.get(&"root", "res://"))
	var include_hidden: bool = bool(args.get(&"include_hidden", false))

	if not root.begins_with("res://"):
		root = "res://" + root

	var dir := DirAccess.open(root)
	if dir == null:
		return {&"ok": false, &"error": "Cannot open directory: " + root}

	var files: PackedStringArray = []
	var folders: PackedStringArray = []

	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		# Skip hidden files unless requested
		if not include_hidden and name.begins_with("."):
			name = dir.get_next()
			continue

		# Skip .uid files
		if name.ends_with(".uid"):
			name = dir.get_next()
			continue

		if dir.current_is_dir():
			folders.append(name)
		else:
			files.append(name)

		name = dir.get_next()
	dir.list_dir_end()

	# Sort alphabetically
	files.sort()
	folders.sort()

	return {
		&"ok": true,
		&"path": root,
		&"files": files,
		&"folders": folders,
		&"total": files.size() + folders.size()
	}

# =============================================================================
# read_file - Read contents of a file
# =============================================================================
func read_file(args: Dictionary) -> Dictionary:
	var path: String = str(args.get(&"path", ""))
	var start_line: int = int(args.get(&"start_line", 1))
	var end_line: int = int(args.get(&"end_line", 0))
	var max_bytes: int = int(args.get(&"max_bytes", DEFAULT_MAX_BYTES))

	if path.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'path' parameter"}

	if not path.begins_with("res://"):
		path = "res://" + path

	if not FileAccess.file_exists(path):
		return {&"ok": false, &"error": "File not found: " + path}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {&"ok": false, &"error": "Cannot open file: " + path}

	var redact_secrets: bool = bool(args.get(&"redact_secrets", true))
	var preview: bool = bool(args.get(&"preview", false))

	# Preview mode: numbered head + tail only, independent of byte budget —
	# for orienting in large files without pulling the whole thing.
	if preview:
		var all_lines: PackedStringArray = []
		while not file.eof_reached():
			all_lines.append(file.get_line())
		file.close()
		var total_lines := all_lines.size()
		var head_n := int(args.get(&"preview_head", DEFAULT_PREVIEW_HEAD))
		var tail_n := int(args.get(&"preview_tail", DEFAULT_PREVIEW_TAIL))
		var preview_text: String
		var head_range: Array = []
		var tail_range: Array = []
		if total_lines <= head_n + tail_n:
			var numbered: Array = []
			for i in range(total_lines):
				numbered.append("%5d| %s" % [i + 1, all_lines[i]])
			preview_text = "
".join(numbered)
			if total_lines > 0:
				head_range = [1, total_lines]
		else:
			var head_lines: Array = []
			for i in range(head_n):
				head_lines.append("%5d| %s" % [i + 1, all_lines[i]])
			var tail_start := total_lines - tail_n
			var tail_lines: Array = []
			for i in range(tail_start, total_lines):
				tail_lines.append("%5d| %s" % [i + 1, all_lines[i]])
			preview_text = "
".join(head_lines) 				+ "
... [%d lines omitted: %d-%d] ...
" % [total_lines - head_n - tail_n, head_n + 1, tail_start] 				+ "
".join(tail_lines)
			head_range = [1, head_n]
			tail_range = [tail_start + 1, total_lines]
		if redact_secrets:
			preview_text = _redact_sensitive_content(preview_text)
		return {
			&"ok": true,
			&"path": path,
			&"preview": true,
			&"content": preview_text,
			&"total_lines": total_lines,
			&"head_range": head_range,
			&"tail_range": tail_range,
		}

	var content: String
	var line_count: int = 0

	# If no line range specified, read up to max_bytes
	if end_line <= 0 and start_line <= 1:
		var size := mini(max_bytes, file.get_length())
		content = file.get_buffer(size).get_string_from_utf8()
		# Count lines
		line_count = content.count("\n") + 1
	else:
		# Read specific line range
		var lines: Array = []
		var current_line := 0
		var total_bytes := 0

		while not file.eof_reached():
			var line := file.get_line()
			current_line += 1

			if current_line < start_line:
				continue
			if end_line > 0 and current_line > end_line:
				break

			lines.append(line)
			total_bytes += line.length() + 1  # +1 for newline

			if total_bytes > max_bytes:
				break

		content = "\n".join(lines)
		line_count = lines.size()

	file.close()

	if redact_secrets:
		content = _redact_sensitive_content(content)

	return {
		&"ok": true,
		&"path": path,
		&"content": content,
		&"line_count": line_count,
		&"range": [start_line, end_line] if end_line > 0 else null
	}

# =============================================================================
# find_files_by_name - Find files by exact filename or substring
# =============================================================================
func find_files_by_name(args: Dictionary) -> Dictionary:
	var name: String = str(args.get(&"name", "")).strip_edges()
	if name.is_empty():
		return {&"ok": false, &"error": "Missing 'name'"}

	var root: String = str(args.get(&"root", "res://"))
	if not root.begins_with("res://"):
		root = "res://" + root
	var exact: bool = bool(args.get(&"exact", false))
	var max_results: int = int(args.get(&"max_results", 50))
	var target := name.to_lower()

	var out: Array = []
	_find_files_recursive(root, target, exact, out, max_results, 0)
	return {
		&"ok": true,
		&"name": name,
		&"root": root,
		&"matches": out,
		&"count": out.size(),
		&"truncated": out.size() >= max_results,
	}


func _find_files_recursive(path: String, target_lower: String, exact: bool, out: Array, max_results: int, depth: int) -> void:
	if out.size() >= max_results or depth > MAX_TRAVERSAL_DEPTH:
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full := path.path_join(name)
		if dir.current_is_dir():
			_find_files_recursive(full, target_lower, exact, out, max_results, depth + 1)
		else:
			var lname := name.to_lower()
			var matched := lname == target_lower if exact else lname.find(target_lower) != -1
			if matched:
				out.append(full)
				if out.size() >= max_results:
					dir.list_dir_end()
					return
		name = dir.get_next()
	dir.list_dir_end()


# =============================================================================
# get_file_outline - Top-level declarations of a .gd file with line spans
# =============================================================================
func get_file_outline(args: Dictionary) -> Dictionary:
	var path: String = str(args.get(&"path", "")).strip_edges()
	if path.is_empty():
		return {&"ok": false, &"error": "Missing 'path'"}
	if not path.begins_with("res://"):
		path = "res://" + path
	if not FileAccess.file_exists(path):
		return {&"ok": false, &"error": "File not found: " + path}

	# Top-level declarations only by default: indented declarations (locals
	# inside function bodies) dominate outline noise, so callers must opt in.
	var include_locals: bool = bool(args.get(&"include_locals", false))

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {&"ok": false, &"error": "Cannot open file: " + path}
	var lines: PackedStringArray = []
	while not file.eof_reached():
		lines.append(file.get_line())
	file.close()

	var ext := path.get_extension().to_lower()
	if ext != "gd":
		return {&"ok": false, &"error": "Outline only supported for .gd files (got ." + ext + ")"}

	var entries: Array = []
	var re := RegEx.new()
	re.compile("^(\s*)(class_name|extends|class|func|signal|const|var|@export|enum)\b")
	for i in range(lines.size()):
		var line: String = lines[i]
		var stripped := line.strip_edges(true, false)
		if stripped.is_empty() or stripped.begins_with("#"):
			continue
		var m := re.search(line)
		if m == null:
			continue
		var indent_depth := m.get_string(1).length()
		if not include_locals and indent_depth > 0:
			continue
		var kw := m.get_string(2)
		var sig: String = stripped
		if sig.length() > 120:
			sig = sig.substr(0, 120) + "…"
		entries.append({
			&"line": i + 1,
			&"kind": kw,
			&"depth": indent_depth,
			&"signature": sig,
		})

	_compute_outline_spans(entries, lines)

	return {
		&"ok": true,
		&"path": path,
		&"total_lines": lines.size(),
		&"entries": entries,
		&"count": entries.size(),
		&"include_locals": include_locals,
		&"hint": "Top-level only by default. Pass include_locals=true to surface declarations inside function bodies. Use start_line/end_line from each entry with read_file to fetch its body.",
	}


func _compute_outline_spans(entries: Array, lines: PackedStringArray) -> void:
	# End of a func/class span = the line before the next non-blank line at
	# the same or shallower indent. Indentation-based heuristic.
	for i in range(entries.size()):
		var entry: Dictionary = entries[i]
		var kind := str(entry.get(&"kind", ""))
		if kind != "func" and kind != "class":
			continue
		var start_line := int(entry.get(&"line", 0))
		var depth := int(entry.get(&"depth", 0))
		var end_line := lines.size()
		for j in range(start_line, lines.size()):
			var l: String = lines[j]
			var stripped := l.strip_edges()
			if stripped.is_empty() or stripped.begins_with("#"):
				continue
			var leading := 0
			while leading < l.length() and (l.substr(leading, 1) == "	" or l.substr(leading, 1) == " "):
				leading += 1
			if leading <= depth:
				end_line = j
				break
		entry[&"end_line"] = end_line
		entry[&"line_count"] = end_line - start_line + 1


# =============================================================================
# _redact_sensitive_content - best-effort secret scrubbing for file reads
# =============================================================================
func _redact_sensitive_content(content: String) -> String:
	var out := content
	var rules := [
		{"pattern": "(?im)^(\s*(?:provider/)?api_key\s*=\s*).*$", "replacement": "$1" + REDACTED_TEXT},
		{"pattern": "(?im)^(\s*(?:api[_-]?key|token|access[_-]?token|refresh[_-]?token|password|secret)\s*[:=]\s*).*$", "replacement": "$1" + REDACTED_TEXT},
		{"pattern": "(?im)^(\s*authorization\s*[:=]\s*bearer\s+).*$", "replacement": "$1" + REDACTED_TEXT},
		{"pattern": "(?im)^(\s*x-api-key\s*[:=]\s*).*$", "replacement": "$1" + REDACTED_TEXT},
	]
	for rule in rules:
		var regex := RegEx.new()
		var err := regex.compile(str(rule["pattern"]))
		if err != OK:
			continue
		out = regex.sub(out, str(rule["replacement"]), true)
	return out


# =============================================================================
# search_project - Search for text in project files
# =============================================================================
func search_project(args: Dictionary) -> Dictionary:
	var query: String = str(args.get(&"query", ""))
	var glob_filter: String = str(args.get(&"glob", ""))
	var max_results: int = int(args.get(&"max_results", DEFAULT_MAX_RESULTS))
	var case_sensitive: bool = bool(args.get(&"case_sensitive", false))

	if query.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'query' parameter"}

	var search_query := query if case_sensitive else query.to_lower()
	var files := _collect_files("res://", glob_filter)
	var matches: Array = []

	for file_path: String in files:
		if matches.size() >= max_results:
			break

		var file := FileAccess.open(file_path, FileAccess.READ)
		if file == null:
			continue

		var content := file.get_as_text()
		file.close()

		var search_content := content if case_sensitive else content.to_lower()
		if search_content.find(search_query) == -1:
			continue

		var lines := content.split("\n")
		for i: int in range(lines.size()):
			var line := lines[i]
			var search_line := line if case_sensitive else line.to_lower()
			if search_line.find(search_query) != -1:
				matches.append({
					&"file": file_path,
					&"line": i + 1,
					&"content": line.strip_edges()
				})
				if matches.size() >= max_results:
					break

	return {
		&"ok": true,
		&"query": query,
		&"matches": matches,
		&"total_matches": matches.size(),
		&"truncated": matches.size() >= max_results
	}

func _collect_files(path: String, glob_filter: String) -> PackedStringArray:
	"""Recursively collect all searchable files."""
	var result: PackedStringArray = []
	_collect_files_recursive(path, glob_filter, result)
	return result

func _collect_files_recursive(path: String, glob_filter: String, out: PackedStringArray, depth: int = 0) -> void:
	if depth >= MAX_TRAVERSAL_DEPTH:
		return

	var dir := DirAccess.open(path)
	if dir == null:
		return

	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		# Skip hidden
		if name.begins_with("."):
			name = dir.get_next()
			continue

		var full_path := path.path_join(name)

		if dir.current_is_dir():
			_collect_files_recursive(full_path, glob_filter, out, depth + 1)
		else:
			var ext := "." + name.get_extension().to_lower()
			if not _SKIP_EXTENSIONS.has(ext):
				if glob_filter.is_empty() or _matches_glob(full_path, glob_filter):
					out.append(full_path)

		name = dir.get_next()
	dir.list_dir_end()

func _matches_glob(path: String, pattern: String) -> bool:
	"""Simple glob matching: *.gd, **/*.tscn, etc."""
	# Handle **/*.ext pattern
	if pattern.begins_with("**/"):
		var ext := pattern.substr(3)  # Remove **/
		return path.ends_with(ext.replace("*", ""))

	# Handle *.ext pattern
	if pattern.begins_with("*."):
		return path.ends_with(pattern.substr(1))

	# Simple contains check
	return path.find(pattern) != -1

# =============================================================================
# create_script - Create a new GDScript file
# =============================================================================
func create_script(args: Dictionary) -> Dictionary:
	var path: String = str(args.get(&"path", ""))
	var content: String = str(args.get(&"content", ""))

	if path.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'path' parameter"}

	if not path.begins_with("res://"):
		path = "res://" + path

	# Enforce GDScript-only. An explicit non-.gd extension is rejected with a
	# pointer at write_file, which handles arbitrary text. A missing extension
	# is treated as a forgotten ".gd" and auto-completed (legacy convenience).
	var filename := path.get_file()
	if "." in filename:
		if not filename.to_lower().ends_with(".gd"):
			return {
				&"ok": false,
				&"error": "create_script only writes GDScript (.gd) files. For other text formats (.gdignore, .json, .md, configs, etc.), use write_file instead. Got: %s" % path,
				&"wrong_extension": true,
			}
	else:
		path += ".gd"

	# Check if file already exists
	if FileAccess.file_exists(path):
		return {&"ok": false, &"error": "File already exists: " + path}

	# Ensure parent directory exists
	var dir_path := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		var err := DirAccess.make_dir_recursive_absolute(dir_path)
		if err != OK:
			return {&"ok": false, &"error": "Could not create directory: " + dir_path}

	# Write file
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {&"ok": false, &"error": "Could not create file: " + path}

	file.store_string(content)
	file.close()

	# Refresh filesystem so Godot sees the new file
	_refresh_filesystem()

	return {
		&"ok": true,
		&"path": path,
		&"size_bytes": content.length(),
		&"message": "Script created successfully"
	}

func _refresh_filesystem() -> void:
	"""Tell Godot to rescan the filesystem."""
	if _editor_plugin != null:
		_editor_plugin.get_editor_interface().get_resource_filesystem().scan()
	elif Engine.is_editor_hint():
		# Fallback if no plugin reference
		var editor_interface = Engine.get_singleton("EditorInterface")
		if editor_interface:
			editor_interface.get_resource_filesystem().scan()
