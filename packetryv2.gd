##A better version of IcyEngine's packet handling in their low-level networking tutorial. [br]
##[color=light_blue]Thank you IcyEngine for fueling my fire of scripting.[/color] [br]
##_______________________[br]
##Automatically handles allocation for floats, strings , integers , dictionaries and arrays, as well as providing tools to allow for more flexible networking.
## @tutorial: https://www.youtube.com/watch?v=8GfJw0E5MFE
#v 1.1.2
class_name packetryv2
##The amount of time a fragmented [packetryv2.packet] should stay cached before being deleted & triggering a lockout for that specific [packetryv2.packet].[br]
##This prevents memory leaks that occur when a fragment isnt completed.
static var defrag_timeout = 500 #in ms
##A flag for debug mode, used for tracking errors that happen inside of this module.
static var debug:bool = false
##The maximum amount of elements that can be contained inside of an [Array].
static var max_array_size = 255
##The maximum amount of elements that can be contained inside of a [Dictionary].
static var max_dict_size = 255
##Sizes for integers, both signed and unsigned, used in encoding and decoding functions, as well as being included in the header for [method packetryv2.packet.autoencode] and [method packetryv2.autodecode].
enum INT_SIZE {
	s8 = 1,
	s16 = 2,
	s32 = 3,
	s64 = 4,
	u8 = 1,
	u16 = 2,
	u32 = 3,
	u64 = 4
}
##Sizes for strings, used in encoding and decoding functions, as well as being included in the header for [method packetryv2.packet.autoencode] and [method packetryv2.autodecode].
enum STRING_SIZE {
	utf8 = 1,
	utf16 = 2,
	utf32 = 3
}

static var i_s8_max:int = 127
static var i_s16_max:int = 32767
static var i_s32_max:int = 2147483647
static var i_s64_max:int = 4611686018427387902
static var i_u8_max:int = 255
static var i_u16_max:int = 65535
static var i_u32_max:int = 4294967295
static var i_u64_max:int = 9223372036854775806
##A dictionary that stores fragments assigned to keys with peer id, packet id, packet code and channel.[br]
##Example: [code][{"order":0 , "data":[...bytes]} , {"order":1 , "data":[...bytes]}][/code]
static var awaiting_defragmentation:Dictionary[String , Array] = {}
##A class that stores packet types with custom decode/encode functions & packet flag setting, along with a base integersize and stringsize, which is associated with a [packetryv2.packet] with a matching [member packetryv2.packet.packet_id].
class packet_type:
	##Stores all defined [packetryv2.packet_type]s, as they are not meant to be modified or contained in variables.
	static var packet_types:Dictionary[int , packet_type] = {}
	##A dictionary where keys are names of packets, and the members are the ids attached to said names.
	static var packet_ids:Dictionary[String , int] = {}
	##The id associated with this [packetryv2.packet_type].
	var packet_id:int
	##The name associated with this [packetryv2.packet_type].
	var packet_name:String
	##The [enum INT_SIZE] associated with this [packetryv2.packet_type].
	var integersize:INT_SIZE = INT_SIZE.s64
	##The [enum STRING_SIZE] associated with this [packetryv2.packet_type].
	var stringsize:STRING_SIZE = STRING_SIZE.utf8
	##The custom decode function associated with this [packetryv2.packet_type].[br]
	##Example: [br][code]func(pack:packetryv2.packet):
	## 	var data:PackedByteArray
	## 	packetryv2.encode_int(data , pack.variables["int_test])
	## 	return data
	##[/code]
	var custom_decode:Callable
	##The custom encode function associated with this [packetryv2.packet_type].[br]
	##Example: [br][code]func(data:PackedByteArray):
	##				print(data.decode_u8(0))[/code]
	var custom_encode:Callable
	##The flag used on a packet with a matching packet_id when calling [method send].[br]
	##Uses [ENetPacketPeer]'s flags , those being [enum ENetPacketPeer.FLAG_RELIABLE] , [enum ENetPacketPeer.FLAG_UNRELIABLE_FRAGMENT] , and [enum ENetPacketPeer.FLAG_UNSEQUENCED].
	var flag:int 
	func _init(pid:int , pname:String):
		packet_id = pid
		integersize = INT_SIZE.s64
		stringsize = STRING_SIZE.utf8
		flag  = ENetPacketPeer.FLAG_RELIABLE
		packet_name = pname
		packet_type.packet_types[packet_id] = self
		packet_type.packet_ids[packet_name] = packet_id
#Instantiated by a sender, either the host or client. Stored variables are automatically encoded using [method packetryv2.autoencode]. [br]
##Contains overrides, along with individual packet flags/asiignments such as [member has_incoming] , [member packet_code], [member channel], and [member order].
class packet:
	##The maximum byte size per packet. Do with this what you will, as it is not handled in [method autoencode].
	static var max_byte_size:int = 2000
	##The variables to be encoded when calling [method autoencode].
	var variables:Dictionary[String , Variant]
	##The id associated with this packet, used in functions like [method send], [method autoencode], and [method packetryv2.autodecode].
	var packet_id:int
	##The peer id associated with this packet. Although it means nothing due to server/host validation, it can be overriden, given that the server-side handles it correctly.
	var peer_id:int
	##The integer size override. Used in case there is no packet type assigned to the [member packet.packet_id].
	var int_size_override:Variant
	##The string size override. Used in case there is no packet type assigned to the [member packet.packet_id].
	var string_size_override:Variant
	##flag override
	var flag_override:int
	##Determines if another [packetryv2.packet] is coming after this one.
	var has_incoming:bool
	##The packet code, which is used in specific connections.
	var packet_code:int
	##The channel, used in [ENetConnection]s and [ENetPacketPeer]s.
	var channel:int
	##The order, which is only used when [packetryv2.packet.has_incoming] is true when decoding happens in [method packetryv2.autodecode]'s header.
	var order:int
	func _init(pid:int , int_override:Variant = null , str_override:Variant = null):
		variables = {}
		packet_id = pid
		int_size_override = int_override
		string_size_override = str_override
		has_incoming = false
	##Automatically handles encoding, iterating through all elements and encoding based on their respective types.[br]
	##If this packet's [member packet.packet_id] matches [member packet_type.packet_id], it will offload work to a custom encode function, using its return value as the final [PackedByteArray].
	func autoencode() -> PackedByteArray:
		if packet_type.packet_types.get(packet_id) and packet_type.packet_types.get(packet_id).custom_encode:
			return packet_type.packet_types.get(packet_id).custom_encode.call(self)
		var data:PackedByteArray
		data.resize(13)
		data.encode_u16(0 , packet_id) #Packet id
		data.encode_u8(2 , peer_id) #Peer id
		var i_size = int_size_override if int_size_override != null else packet_type.packet_types.get(packet_id).integersize
		var s_size = string_size_override if string_size_override != null else packet_type.packet_types.get(packet_id).stringsize
		data.encode_u8(3 , i_size) #Integer size
		data.encode_u8(4 , s_size) #String size
		data.encode_u8(5 , int(has_incoming)) #has incoming
		data.encode_u8(6 , packet_code) #packet code
		data.encode_u8(7 , channel) #channel
		data.encode_u8(8 , order) #order
		data.encode_float(9 , Time.get_unix_time_from_system()) #unix time
		for k in variables:
			var vartype = typeof(variables[k])
			data.resize(data.size()+3)
			#type
			data.encode_u8(data.size()-3 , vartype)
			#2 bytes to measure string length
			var stringthing:PackedByteArray = k.to_utf8_buffer()
			data.encode_u16(data.size()-2 , stringthing.size())
			data.append_array(stringthing)
			match vartype:
				TYPE_FLOAT:
					packetryv2.encode_float(data , variables[k])
				TYPE_INT:
					packetryv2.encode_int(data , variables[k] , i_size)
				TYPE_STRING:
					packetryv2.encode_string(data , variables[k] , s_size)
				TYPE_BOOL:
					packetryv2.encode_bool(data , variables[k])
				#region vectors
				TYPE_VECTOR2:
					packetryv2.encode_vector(data , variables[k])
				TYPE_VECTOR2I:
					packetryv2.encode_vector(data , variables[k])
				TYPE_VECTOR3:
					packetryv2.encode_vector(data , variables[k])
				TYPE_VECTOR3I:
					packetryv2.encode_vector(data , variables[k])
				TYPE_VECTOR4:
					packetryv2.encode_vector(data , variables[k])
				TYPE_VECTOR4I:
					packetryv2.encode_vector(data , variables[k])
				#endregion
				TYPE_COLOR:
					packetryv2.encode_color(data , variables[k])
				TYPE_NIL:
					pass
				#region array types (0/11)
				TYPE_ARRAY:
					packetryv2.encode_array(data , variables[k])
					pass
				#endregion
				TYPE_DICTIONARY:
					packetryv2.encode_dictionary(data , variables[k])
					pass
		return data
	##Adds a header to the beginning of a [PackedByteArray]. Note that this should only be used on [i]EMPTY[/i] [PackedByteArray]s.
	func add_header(data:PackedByteArray) -> PackedByteArray:
		data.resize(data.size()+14)
		data.encode_u16(0 , packet_id) #Packet id
		data.encode_u8(2 , peer_id) #Peer id
		var i_size = int_size_override if int_size_override != null else packet_type.packet_types.get(packet_id).integersize
		var s_size = string_size_override if string_size_override != null else packet_type.packet_types.get(packet_id).stringsize
		data.encode_u8(3 , i_size) #Integer size
		data.encode_u8(4 , s_size) #String size
		data.encode_u8(5 , int(has_incoming)) #has incoming
		data.encode_u8(6 , packet_code) #packet code
		data.encode_u8(7 , channel) #channel
		data.encode_u8(8 , order) #order
		data.encode_float(9 , Time.get_unix_time_from_system()) #unix time
		return data
	pass
##A packet recieved over the network and decoded by packetryv2.autodecode. [br]
##Other than variables, this class stores information such as timestamps, channel, packet and peer ids.
class recievedpacket:
	var variables:Dictionary ##Stores the variables that came from [method packetryv2.autodecode].
	var peer_id:int ##The peer that sent this [packetryv2.packet].
	var packet_id:int ##The id for this [packetryv2.packet].
	func _init(pack_id:int , p_id:int):
		peer_id = p_id
		packet_id = pack_id
		variables = {}
		pass
	##Casts all values in [member variables] to an [Object]'s keys if possible.
	func cast_to_obj(obj:Object) -> Object:
		return obj
##@experimental
##Streams data over the network. (coming in v1.4)
class streamsender:
	func _init():
		
		pass
	
	pass
##experimental
##Recieves stream data from a source. (coming in v1.4)
class streamreciever:
	
	
	pass
#helper functions
##Gets the number of bytes required for this [enum INT_SIZE].
static func int_bytes(int_size:INT_SIZE = INT_SIZE.s64)->int:
	match int_size:
		INT_SIZE.s64:
			return 8
		INT_SIZE.u64:
			return 8
		INT_SIZE.s32:
			return 4
		INT_SIZE.u32:
			return 4
		INT_SIZE.s16:
			return 2
		INT_SIZE.u16:
			return 2
		INT_SIZE.s8:
			return 1
		INT_SIZE.u8:
			return 1
	return 0
##Gets the enum name from the given [enum INT_SIZE].
static func int_name(int_size:INT_SIZE = INT_SIZE.s64)->String:
	match int_size:
		INT_SIZE.s64:
			return "s64"
		INT_SIZE.u64:
			return "u64"
		INT_SIZE.s32:
			return "s32"
		INT_SIZE.u32:
			return "u32"
		INT_SIZE.s16:
			return "s16"
		INT_SIZE.u16:
			return "u16"
		INT_SIZE.s8:
			return "s8"
		INT_SIZE.u8:
			return "u8"
	return ""
##Sorts, then combines all [PackedByteArray]s inside of the given [Array] into a singular [PackedByteArray].[br]
##While already handled by [method packetryv2.autodecode], This is generally used for handling defragmentation inside of [member packet_type.custom_decode].[br]
static func combine_byte_arrays(array:Array):
	var arr:Array
	var casted:PackedByteArray
	arr.sort_custom(func(a,b):return a["order"] < b["order"])
	for dict in array:
		arr.append_array(dict["data"])
	casted.append_array(arr)
	return casted
##(not to be confused with a Dynamic Linked Library)[br]
##dll stands for Dynamic Latency Lockout, and calculates [member defrag_timeout] based on [param latency] and [param ping].
static func dll(latency:int , ping:int):
	defrag_timeout = ping+(4*latency)+0.2
	pass
##Chops a [PackedByteArray] into multiple pieces based on [param bytes].[br]
##This should be used for fragmentation inside of [member packet_type.custom_encode].
static func snip(data:PackedByteArray , bytes:int)->Array:
	var arrays = []
	var i = data.size()-1
	while i > 0:
		var snipped = data.slice(i-bytes,i)
		arrays.push_back(snipped)
		i -= bytes
		data = data.slice(0 , i)
		pass
	return arrays
##@experimental
##Attempts to sanitize a string for security, removing any potentially dangerous code that may be able to be arbitrarily executed through another client/server upon recieving a packet with this string.
static func sanitize_string(_string:String):pass
##Encodes a [Array] into a [PackedByteArray]. Limited by [member max_array_size] for security.
static func encode_array(data:PackedByteArray , v:Array):
	var arr:Array = v
	if arr.size() > max_array_size:return
	data.resize(data.size()+2)
	#Array size
	data.encode_u16(data.size()-2 , arr.size())
	for element in arr:
		#variable type
		data.resize(data.size()+1)
		var vtype = typeof(element)
		data.encode_u8(data.size()-1 , vtype)
		match vtype:
			TYPE_FLOAT:
				packetryv2.encode_float(data , element)
			pass
			TYPE_INT:
				packetryv2.encode_int(data , element)
			pass
			TYPE_STRING:
				packetryv2.encode_string(data , element)
			pass
			TYPE_BOOL:
				packetryv2.encode_bool(data , element)
			pass
		#region vectors
			TYPE_VECTOR2:
				packetryv2.encode_vector(data , element)
			TYPE_VECTOR2I:
				packetryv2.encode_vector(data , element)
			pass
			TYPE_VECTOR3:
				packetryv2.encode_vector(data , element)
			pass
			TYPE_VECTOR3I:
				packetryv2.encode_vector(data , element)
			pass
			TYPE_VECTOR4:
				packetryv2.encode_vector(data , element)
			TYPE_VECTOR4I:
				packetryv2.encode_vector(data , element)
		#endregion
			TYPE_COLOR:
				packetryv2.encode_color(data , element)
			TYPE_NIL:
				pass
			TYPE_ARRAY:
				packetryv2.encode_array(data , element)
			TYPE_DICTIONARY:
				packetryv2.encode_dictionary(data , element)
			pass
	return
##Encodes a [Dictionary] of other variables into a [PackedByteArray]. Limited by [member max_dict_size] for security.
static func encode_dictionary(data:PackedByteArray , v:Dictionary)->PackedByteArray:
	#dictionary size
	data.resize(data.size()+1)
	data.encode_u8(data.size()-1 , v.size())
	for k:String in v:
		var element:Variant = v[k]
		var vtype:int = typeof(element)
		var stringbuff:PackedByteArray = k.to_utf8_buffer()
		#name byte size
		data.resize(data.size() + 2)
		data.encode_u16(data.size()-2 , stringbuff.size())
		#entry name
		data.append_array(stringbuff)
		#type
		data.resize(data.size()+1)
		data.encode_u8(data.size()-1 , vtype)
		match vtype:
			TYPE_FLOAT:
				packetryv2.encode_float(data , element)
			pass
			TYPE_INT:
				packetryv2.encode_int(data , element)
			pass
			TYPE_STRING:
				packetryv2.encode_string(data , element)
			pass
			TYPE_BOOL:
				packetryv2.encode_bool(data , element)
			pass
		#region vectors
			TYPE_VECTOR2:
				packetryv2.encode_vector(data , element)
			TYPE_VECTOR2I:
				packetryv2.encode_vector(data , element)
			pass
			TYPE_VECTOR3:
				packetryv2.encode_vector(data , element)
			pass
			TYPE_VECTOR3I:
				packetryv2.encode_vector(data , element)
			pass
			TYPE_VECTOR4:
				packetryv2.encode_vector(data , element)
			TYPE_VECTOR4I:
				packetryv2.encode_vector(data , element)
		#endregion
			TYPE_COLOR:
				packetryv2.encode_color(data , element)
			TYPE_NIL:
				pass
			TYPE_ARRAY:
				packetryv2.encode_array(data , element)
			TYPE_DICTIONARY:
				packetryv2.encode_dictionary(data , element)
			pass
	return data
##Encodes a [float] into a [PackedByteArray].
static func encode_float(data:PackedByteArray , v:float):
	data.resize(data.size()+4)
	data.encode_float(data.size() - 4 , v)
	pass
##Encodes an [int] into a [PackedByteArray]. The size of the integer being encoded is determined by a [packetryv2.packet_type]'s [member packet_type.integersize].
static func encode_int(data:PackedByteArray , v:int , int_size:INT_SIZE = INT_SIZE.s64):
	data.resize(data.size()+int_bytes(int_size))
	match int_size:
		INT_SIZE.s64:
			data.encode_s64(data.size()-int_bytes(int_size) , v)
		INT_SIZE.u64:
			data.encode_u64(data.size()-int_bytes(int_size) , v)
		INT_SIZE.s32:
			data.encode_s32(data.size()-int_bytes(int_size) , v)
		INT_SIZE.u32:
			data.encode_u32(data.size()-int_bytes(int_size) , v)
		INT_SIZE.s16:
			data.encode_s16(data.size()-int_bytes(int_size) , v)
		INT_SIZE.u16:
			data.encode_u16(data.size()-int_bytes(int_size) , v)
		INT_SIZE.s8:
			data.encode_s8(data.size()-int_bytes(int_size) , v)
		INT_SIZE.u8:
			data.encode_u8(data.size()-int_bytes(int_size) , v)
	pass
##Encodes an [String] into a [PackedByteArray]. The size of the string being encoded is determined by a [packetryv2.packet_type]'s [member packet_type.stringsize].
static func encode_string(data:PackedByteArray , v:String , string_size:STRING_SIZE = STRING_SIZE.utf8):
	data.resize(data.size()+2)
	var sbuff:PackedByteArray 
	match string_size:
		STRING_SIZE.utf8:
			sbuff = v.to_utf8_buffer()
		STRING_SIZE.utf16:
			sbuff = v.to_utf16_buffer()
		STRING_SIZE.utf32:
			sbuff = v.to_utf32_buffer()
	data.encode_u16(data.size()-2 , sbuff.size())
	data.append_array(sbuff)
	pass
##Encodes a [bool] into a [PackedByteArray].[br]
##[color=orange][b][u]HEADS UP![/u][/b][/color][br]
##Booleans use a single byte instead of one bit due to computer architecture. [br]
##Use another module to pack booleans into a single bit instead of a byte.
static func encode_bool(data:PackedByteArray , v:bool):
	data.resize(data.size()+1)
	data.encode_u8(data.size() - 1 , int(v))
	pass
##Encodes a [Color] into a [PackedByteArray].
static func encode_color(data:PackedByteArray , v:Color):
	data.resize(data.size() + 16)
	#R
	data.encode_float(data.size() - 16 , v.r)
	#G
	data.encode_float(data.size() - 12 , v.g)
	#B
	data.encode_float(data.size()- 8 , v.b)
	#A
	data.encode_float(data.size() - 4 , v.a)
	pass
##Encodes a [Vector2]/[Vector3]/[Vector4], and their integer counterparts into a [PackedByteArray].
static func encode_vector(data:PackedByteArray , v:Variant):
	var vectype = typeof(v)
	match vectype:
		TYPE_VECTOR2:
			data.resize(data.size()+8)
			#X
			data.encode_float(data.size()-8 , v.x)
			#Y
			data.encode_float(data.size()-4 , v.y)
			pass
		TYPE_VECTOR2I:
			data.resize(data.size()+16)
			#X
			data.encode_s64(data.size()-16 , v.x)
			#Y
			data.encode_s64(data.size()-8 , v.y)
			pass
		TYPE_VECTOR3:
			data.resize(data.size()+12)
			#X
			data.encode_float(data.size()-12 , v.x)
			#Y
			data.encode_float(data.size()-8 , v.y)
			#Z
			data.encode_float(data.size()-4 , v.z)
			pass
		TYPE_VECTOR3I:
			data.resize(data.size()+24)
			#X
			data.encode_s64(data.size()-24 , v.x)
			#Y
			data.encode_s64(data.size()-16 , v.y)
			#Z
			data.encode_s64(data.size()-8 , v.z)
			pass
		TYPE_VECTOR4:
			data.resize(data.size()+16)
			#X
			data.encode_float(data.size()-16 , v.x)
			#Y
			data.encode_float(data.size()-12 , v.y)
			#Z
			data.encode_float(data.size()-8 , v.z)
			#W
			data.encode_float(data.size()-4 , v.w)
		TYPE_VECTOR4I:
			data.resize(data.size()+32)
			#X
			data.encode_s64(data.size()-32 , v.x)
			#Y
			data.encode_s64(data.size()-24 , v.y)
			#Z
			data.encode_s64(data.size()-16 , v.z)
			#W
			data.encode_s64(data.size()-8 , v.w)
		pass
	pass
##Decodes an [Array] based off of the pointer value, [param i], returning [code][Array,int][/code]. Limited by [member max_array_size] for security.[br]
##Returns [code]"terminate"[/code] when going over the set limit.
static func decode_array(data:PackedByteArray , i:int)->Array:
	var array = []
	#Array size
	var arr_size:int = data.decode_u16(i);i+=2
	#"no u"
	if arr_size > max_array_size:return ["terminate"]
	for _i in arr_size:
		#Type
		var var_type:int = data.decode_u8(i);i+=1
		#Value
		var _yield
		match var_type:
			TYPE_FLOAT:
				_yield = decode_float(data , i)
			TYPE_INT:
				_yield = decode_int(data , i)
			TYPE_STRING:
				_yield = decode_string(data , i)
			TYPE_BOOL:
				_yield = decode_bool(data , i)
			#region vectors
			TYPE_VECTOR2:
				_yield = decode_vector(data , i , var_type)
			TYPE_VECTOR2I:
				_yield = decode_vector(data , i , var_type)
			TYPE_VECTOR3:
				_yield = decode_vector(data , i , var_type)
			TYPE_VECTOR3I:
				_yield = decode_vector(data , i , var_type)
			TYPE_VECTOR4:
				_yield = decode_vector(data , i , var_type)
			TYPE_VECTOR4I:
				_yield = decode_vector(data , i , var_type)
			TYPE_ARRAY:
				_yield = decode_array(data , i)
			#endregion
			TYPE_COLOR:
				_yield = decode_color(data , i)
			TYPE_NIL:
				array.push(null)
				continue
		array.push_back(_yield[0])
		i = _yield[1]
		pass
	return [array , i]
##Decodes an [Dictionary] based off of the pointer value, [param i], returning [code][Dictionary,int][/code]. Limited by [member max_dict_size] for security.[br]
##Returns [code]"terminate"[/code] when going over the set limit.
static func decode_dictionary(data:PackedByteArray , i:int)->Array:
	var dict:Dictionary
	#dictionary size
	var dsize:int = data.decode_u8(i);i+=1
	if dsize > max_dict_size:return ["terminate"]
	for _i in dsize:
		var name_byte_size:int = data.decode_u16(i);i+=2
		var entry_name:String = data.slice(i , i + name_byte_size).get_string_from_utf8();i+=name_byte_size
		var var_type:int = data.decode_u8(i);i+=1
		var _yield:Array
		match var_type:
			TYPE_FLOAT:
				_yield = decode_float(data , i)
			TYPE_INT:
				_yield = decode_int(data , i)
			TYPE_STRING:
				_yield = decode_string(data , i)
			TYPE_BOOL:
				_yield = decode_bool(data , i)
			#region vectors
			TYPE_VECTOR2:
				_yield = decode_vector(data , i , var_type)
			TYPE_VECTOR2I:
				_yield = decode_vector(data , i , var_type)
			TYPE_VECTOR3:
				_yield = decode_vector(data , i , var_type)
			TYPE_VECTOR3I:
				_yield = decode_vector(data , i , var_type)
			TYPE_VECTOR4:
				_yield = decode_vector(data , i , var_type)
			TYPE_VECTOR4I:
				_yield = decode_vector(data , i , var_type)
			TYPE_ARRAY:
				_yield = decode_array(data , i)
			TYPE_DICTIONARY:
				_yield = decode_dictionary(data , i)
			#endregion
			TYPE_COLOR:
				_yield = decode_color(data , i)
			TYPE_NIL:
				dict.set(entry_name , null)
				continue
		dict.set(entry_name , _yield[0])
		i = _yield[1]
		pass
	return [dict , i]
##Decodes an [float] based off of the pointer value, [param i], returning [code][float,int][/code].
static func decode_float(data:PackedByteArray , i:int)->Array:
	return [data.decode_float(i) , i + 4]
##Decodes an [int] based off of the pointer value, [param i], and [enum INT_SIZE], returning [code][int,int][/code].
static func decode_int(data:PackedByteArray , i:int , int_size:INT_SIZE = INT_SIZE.s64)->Array:
	var integer
	match int_size:
		INT_SIZE.s64:
			integer=data.decode_s64(i)
		INT_SIZE.u64:
			integer=data.decode_u64(i)
		INT_SIZE.s32:
			integer=data.decode_s32(i)
		INT_SIZE.u32:
			integer=data.decode_u32(i)
		INT_SIZE.s16:
			integer=data.decode_s16(i)
		INT_SIZE.u16:
			integer=data.decode_u16(i)
		INT_SIZE.s8:
			integer=data.decode_s8(i)
		INT_SIZE.u8:
			integer=data.decode_u8(i)
	return [integer,i + int_bytes(int_size)]
##Decodes an [String] based off of the pointer value, [param i], and [enum STRING_SIZE], returning [code][String,int][/code].
static func decode_string(data:PackedByteArray , i:int , string_size:STRING_SIZE = STRING_SIZE.utf8)->Array:
	var innerstringsize = data.decode_u16(i);i+=2
	var strin:String = "placeholder"
	match string_size:
		STRING_SIZE.utf8:
			strin = data.slice(i , i + innerstringsize).get_string_from_utf8();i+=innerstringsize
		STRING_SIZE.utf16:
			strin = data.slice(i , i + innerstringsize).get_string_from_utf16();i+=innerstringsize
		STRING_SIZE.utf32:
			strin = data.slice(i , i + innerstringsize).get_string_from_utf32();i+=innerstringsize
	return [strin , i]
##Decodes an [bool] based off of the pointer value, [param i], returning [code][bool,int][/code].
static func decode_bool(data:PackedByteArray , i:int)->Array:
	return [bool(data.decode_u8(i)) , i + 1]
##Decodes an [Vector2]/[Vector3]/[Vector4] and their integer counterparts based off of the pointer value, [param i], and type [param type], returning [code][Vector<#>,int][/code].
static func decode_vector(data:PackedByteArray , i:int , type:int)->Array:
	var value
	match type:
		#region vectors
		TYPE_VECTOR2:
			value = Vector2()
			var x = data.decode_float(i);i+=4
			var y = data.decode_float(i);i+=4
			value.x = x
			value.y = y
		TYPE_VECTOR2I:
			value = Vector2i()
			var x = data.decode_s64(i);i+=8
			var y = data.decode_s64(i);i+=8
			value.x = x
			value.y = y
		TYPE_VECTOR3:
			value = Vector3()
			var x = data.decode_float(i);i+=4
			var y = data.decode_float(i);i+=4
			var z = data.decode_float(i);i+=4
			value.x = x
			value.y = y
			value.z = z
		TYPE_VECTOR3I:
			value = Vector3i()
			var x = data.decode_s64(i);i+=8
			var y = data.decode_s64(i);i+=8
			var z = data.decode_s64(i);i+=8
			value.x = x
			value.y = y
			value.z = z
		TYPE_VECTOR4:
			value = Vector4()
			var x = data.decode_float(i);i+=4
			var y = data.decode_float(i);i+=4
			var z = data.decode_float(i);i+=4
			var w = data.decode_float(i);i+=4
			value.x = x
			value.y = y
			value.z = z
			value.w = w
		TYPE_VECTOR4I:
			value = Vector4i()
			var x = data.decode_s64(i);i+=8
			var y = data.decode_s64(i);i+=8
			var z = data.decode_s64(i);i+=8
			var w = data.decode_s64(i);i+=8
			value.x = x
			value.y = y
			value.z = z
			value.w = w
	return [value , i]
##Decodes an [Color] based off of the pointer value, [param i], returning [code][Color,int][/code].
static func decode_color(data:PackedByteArray , i:int)->Array:
	var value = Color()
	var r = data.decode_float(i);i+=4
	var g = data.decode_float(i);i+=4
	var b = data.decode_float(i);i+=4
	var a = data.decode_float(i);i+=4
	value.r = r
	value.g = g
	value.b = b
	value.a = a
	return [value , i]
##Automatically decodes incoming packets, handling headers, security, defragmentation and gracefully handling corruption errors (dropping the packet)[br]
##[param data]: The data recieved over the network via a [ENetPacketPeer] or [ENetConnection].[br]
##[param obj]: The object to cast the constructed [packetryv2.recievedpacket] to immediately after the packet is decoded.[br]
##[param is_constructing]: Determines whether this call of [method packetryv2.autodecode] meant to construct a fragmented packet.
static func autodecode(data:PackedByteArray , obj:Object = null , is_constructing:bool = false) -> Object:
	var i = 0
	const byte_amt = 13
	var packet_id = data.decode_u16(0)
	if packet_type.packet_types.get(packet_id) and packet_type.packet_types.get(packet_id).custom_decode:
			return packet_type.packet_types.get(packet_id).custom_decode.call(data)
	var peer_id = data.decode_u8(2)
	var int_size = data.decode_u8(3)
	var str_size = data.decode_u8(4)
	var has_incoming:bool = bool(data.decode_u8(5))
	var packet_code:int = data.decode_u8(6)
	var channel:int = data.decode_u8(7)
	var order:int = data.decode_u8(8)
	var time:float = data.decode_float(9) #unix time
	print(time)
	if is_constructing:
		has_incoming = false
		if debug:
			print(
				"p_id: ",packet_id,
				" peer_id: ",peer_id,
				" int_size: ",int_size,
				" str_size: ",str_size,
				" packet_code: ",packet_code,
				" channel: ",channel,
				" order: ",order,
				" time: ",time
			)
		pass
	var defrag_location = str(channel)+"_"+str(packet_id)+"_"+str(packet_code)+str(peer_id)
	var defrag = awaiting_defragmentation.get(defrag_location)
	if debug:print("has incoming: " , has_incoming , " , " , data.decode_u8(5))
	if has_incoming == true and !is_constructing:
		#Remove the first 13 bytes if order isnt 0
		if order != 0:
			data = data.slice(byte_amt)
		#if there is no entry in awaiting_defrag
		if not defrag:
			awaiting_defragmentation.set(defrag_location , [])
		awaiting_defragmentation.get(defrag_location).push_back({"order":order,"data":data})
		return null
	#Could have security issues.
	elif defrag != null and !is_constructing:
		if debug:print("Last packet")
		#Remove the first 13 bytes
		data = data.slice(byte_amt)
		awaiting_defragmentation.get(defrag_location).push_back({"order":order,"data":data})
		var df = combine_byte_arrays(defrag)
		var decoded = autodecode(df , obj , true)
		awaiting_defragmentation.erase(defrag_location)
		return decoded
	var newdata = recievedpacket.new(packet_id , peer_id)
	i = byte_amt
	#skip over the header
	while i < data.size():
		#variable type
		var var_type:int = data.decode_u8(i);i+=1
		#String size
		var stringsize:int = data.decode_u16(i);i+=2
		#String
		var string:String = data.slice(i , i+stringsize).get_string_from_utf8();i+=stringsize
		var value:Variant
		var _yield:Array
		match var_type:
			TYPE_FLOAT:
				_yield = decode_float(data , i)
			TYPE_INT:
				_yield = decode_int(data , i , int_size)
			TYPE_STRING:
				_yield = decode_string(data , i , str_size)
			TYPE_BOOL:
				_yield = decode_bool(data , i)
			#region vectors
			TYPE_VECTOR2:
				_yield = decode_vector(data , i , var_type)
			TYPE_VECTOR2I:
				_yield = decode_vector(data , i , var_type)
			TYPE_VECTOR3:
				_yield = decode_vector(data , i , var_type)
			TYPE_VECTOR3I:
				_yield = decode_vector(data , i , var_type)
			TYPE_VECTOR4:
				_yield = decode_vector(data , i , var_type)
			TYPE_VECTOR4I:
				_yield = decode_vector(data , i , var_type)
			#endregion
			TYPE_COLOR:
				_yield = decode_color(data , i)
			TYPE_ARRAY:
				_yield = decode_array(data , i)
			TYPE_DICTIONARY:
				_yield = decode_dictionary(data , i)
			TYPE_NIL:
				value = null
				continue
		value = _yield[0]
		if typeof(value) == TYPE_STRING and value == "terminate":push_error("A security error occurred in an Array or Dictionary.");return null
		i = _yield[1]
		newdata.variables[string] = value
	if obj:return newdata.cast_to_obj(obj)
	return newdata
##Handles encoding of a [packetryv2.packet] and sends it over the network to an [ENetPacketPeer].
static func send(pack:packet , target:ENetPacketPeer):
	var flag
	if pack.flag_override:
		flag = pack.flag_override
	else: 
		flag = packet_type.packet_types[pack.packet_id].flag
	target.send(0 , pack.autoencode() , flag)
##Handles encoding of a [packetryv2.packet] and sends it over the network to an [ENetConnection].
static func broadcast(pack:packet , target:ENetConnection):
	var flag
	if pack.flag_override:
		flag = pack.flag_override
	else: 
		flag = packet_type.packet_types[pack.packet_id].flag
	target.broadcast(0 ,pack.autoencode() , flag)
