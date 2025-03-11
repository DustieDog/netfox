extends RefCounted
class_name _DiffHistoryEncoder

var _history: _PropertyHistoryBuffer
var _property_cache: PropertyCache

var _property_indexes := _BiMap.new()

static var _logger := _NetfoxLogger.for_netfox("DiffHistoryEncoder")

func _init(p_history: _PropertyHistoryBuffer, p_property_cache: PropertyCache):
	_history = p_history
	_property_cache = p_property_cache

func add_properties(properties: Array[PropertyEntry]) -> void:
	for property_entry in properties:
		_ensure_property_idx(property_entry.to_string())

func encode(tick: int, reference_tick: int, properties: Array[PropertyEntry]) -> PackedByteArray:
	assert(properties.size() <= 255, "Property indices may not fit into bytes!")

	var snapshot := _history.get_snapshot(tick)
	var property_strings := properties.map(func(it): return it.to_string())

	var reference_snapshot := _history.get_history(reference_tick)
	var diff_snapshot := reference_snapshot.make_patch(snapshot)

	if diff_snapshot.is_empty():
		return PackedByteArray()

	var buffer := StreamPeerBuffer.new()

	for property in diff_snapshot.properties():
		var property_idx := _property_indexes.get_by_value(property) as int
		var property_value = diff_snapshot.get_value(property)

		buffer.put_u8(property_idx)
		buffer.put_var(property_value)

	return buffer.data_array

func decode(data: PackedByteArray, properties: Array[PropertyEntry]) -> _PropertySnapshot:
	var result := _PropertySnapshot.new()

	if data.is_empty():
		return result

	var buffer := StreamPeerBuffer.new()
	buffer.data_array = data
	
	while buffer.get_available_bytes() > 0:
		var property_idx := buffer.get_u8()
		var property_value := buffer.get_var()
		if not _property_indexes.has_key(property_idx):
			_logger.warning("Received unknown property index %d, ignoring!", [property_idx])
			continue

		var property_entry := _property_indexes.get_by_key(property_idx)
		result.set_value(property_entry, property_value)

	return result

func apply(tick: int, snapshot: _PropertySnapshot, reference_tick: int, sender: int = -1) -> bool:
	if tick < NetworkRollback.history_start:
		# State too old!
		_logger.error(
			"Received diff snapshot for @%d, rejecting because older than %s frames",
			[tick, NetworkRollback.history_limit]
		)
		return false

	if snapshot.is_empty():
		return true

	if sender > 0:
		snapshot.sanitize(sender, _property_cache)
		if snapshot.is_empty():
			_logger.warning("Received invalid diff from #%s for @%s", [sender, tick])
			return false

	if not _history.has(reference_tick):
		# Reference tick missing, hope for the best
		_logger.warning("Reference tick %d missing for applying %d", [reference_tick, tick])

	var reference_snapshot := _history.get_snapshot(reference_tick)
	_history.set_snapshot(tick, reference_snapshot.merge(snapshot))
	return true

func _ensure_property_idx(property: String):
	if _property_indexes.has_value(property):
		return

	assert(_property_indexes.size() < 256, "Property index map is full, can't add new property!")
	var idx := hash(property) % 256
	while _property_indexes.has_key(idx):
		idx = hash(idx + 1) % 256
	_property_indexes.put(idx, property)
