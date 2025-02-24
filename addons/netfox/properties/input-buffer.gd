extends _PropertyHistoryBuffer
class_name _InputBuffer

var record_property_entries: Array[PropertyEntry] = []
var auth_property_entries: Array[PropertyEntry] = []

var _property_cache: PropertyCache

var earliest_input_tick: int 

static var _logger: _NetfoxLogger = _NetfoxLogger.for_netfox("InputBuffer")

func process_settings(root: Node, properties: Array[String]):
	_property_cache = PropertyCache.new(root)
	record_property_entries.clear()
	_buffer.clear()
	earliest_input_tick = NetworkTime.tick

	process_authority(properties)

func process_authority(properties: Array[String]):
	record_property_entries.clear()
	auth_property_entries.clear()

	# Gather input properties that we own
	# Only record input that is our own
	for property in properties:
		var property_entry = _property_cache.get_entry(property)
		if property_entry.node.is_multiplayer_authority():
			record_property_entries.push_back(property_entry)
			auth_property_entries.push_back(property_entry)

func apply_cache(tick: int):
	get_history(tick).apply(_property_cache)

func submit_serialized_inputs(serialized_inputs: Array, tick: int, sender: int):
	var inputs : Array[_PropertySnapshot] = []

	for input in serialized_inputs:
		inputs.push_back(_PropertySnapshot.from_dictionary(input))

	for offset in range(inputs.size()):
		var input_tick := tick - offset

		if input_tick < NetworkRollback.history_start:
			# Input too old
			_logger.warning("Received input for %s, rejecting because older than %s frames", [input_tick, NetworkRollback.history_limit])
			continue

		var input := inputs[offset]
		if input == null:
			# We've somehow received a null input - shouldn't happen
			_logger.error("Null input received for %d, full batch is %s", [input_tick, serialized_inputs])
			continue

		input.sanitize(sender, _property_cache)

		if input.is_empty():
			_logger.warning("Received invalid input from %s for tick %s for %s" % [sender, tick, _property_cache.root.name])
			continue

		var known_input := get_snapshot(input_tick)
		if not known_input.equals(input):
			# Received a new input, save to history
			set_snapshot(input_tick, input)
			earliest_input_tick = mini(earliest_input_tick, input_tick)