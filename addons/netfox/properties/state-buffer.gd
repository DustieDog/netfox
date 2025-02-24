extends _PropertyHistoryBuffer
class_name _StateBuffer

var record_property_entries: Array[PropertyEntry] = []
var auth_property_entries: Array[PropertyEntry] = []

var _property_cache: PropertyCache

var latest_state_tick: int 

static var _logger: _NetfoxLogger = _NetfoxLogger.for_netfox("StateBuffer")

func process_settings(root: Node, properties: Array[String]):
	_property_cache = PropertyCache.new(root)
	record_property_entries.clear()
	_buffer.clear()
	latest_state_tick = NetworkTime.tick - 1

	# Gather state properties - all state properties are recorded
	for property in properties:
		var property_entry = _property_cache.get_entry(property)
		record_property_entries.push_back(property_entry)
	
	process_authority(properties)

func process_authority(properties: Array[String]):
	auth_property_entries.clear()

	# Gather state properties that we own
	# i.e. it's the state of a node that belongs to the local peer
	for property in properties:
		var property_entry = _property_cache.get_entry(property)
		if property_entry.node.is_multiplayer_authority():
			auth_property_entries.push_back(property_entry)

func apply_cache(tick: int):
	get_history(tick).apply(_property_cache)

func extract_snapshot(filter: Callable) -> _PropertySnapshot:
	var filtered_state := _PropertySnapshot.new()

	for property in auth_property_entries:
		if filter.call(property):
			filtered_state.set_value(property.to_string(), property.get_value())

	return filtered_state

func submit_serialized_state(serialized_state: Dictionary, tick: int, sender: int) -> bool:
	if tick < NetworkRollback.history_start:
		# State too old!
		_logger.error("Received full state for %s, rejecting because older than %s frames", [tick, NetworkRollback.history_limit])
		return false

	var state := _PropertySnapshot.from_dictionary(serialized_state)
	
	state.sanitize(sender, _property_cache)

	if state.is_empty():
		# State is completely invalid
		_logger.warning("Received invalid state from %s for tick %s", [sender, tick])
		return false
	
	merge(state, tick)

	return true

func submit_serialized_diff_state(serialized_diff_state: Dictionary, tick: int, reference_tick: int, sender: int) -> bool:
	if tick < NetworkTime.tick - NetworkRollback.history_limit:
		# State too old!
		_logger.error("Received diff state for %s, rejecting because older than %s frames", [tick, NetworkRollback.history_limit])
		return false
	
	if not _buffer.has(reference_tick):
		# Reference tick missing, hope for the best
		_logger.warning("Reference tick %d missing for %d", [reference_tick, tick])

	var diff_state := _PropertySnapshot.from_dictionary(serialized_diff_state)
	var reference_state = get_snapshot(reference_tick)
	var is_valid_state := true

	if serialized_diff_state.is_empty():
		merge(reference_state, tick)
		return true
	else:
		diff_state.sanitize(sender, _property_cache)

		if diff_state.is_empty():
			# State is completely invalid
			_logger.warning("Received invalid state from %s for tick %s", [sender, tick])
			return false
		else:
			var result_state := reference_state.merge(diff_state)
			set_snapshot(tick, result_state)
			return true