GuildInventory = GuildInventory or {}

---@class GuildInventory
local m = GuildInventory

local MessageCommand = {
	Item = "ITEM",
	Items = "ITEMS",
	RequestInventory = "RINV",
	Ping = "PING",
	Pong = "PONG"
}

---@alias MessageCommand
---| "ITEM"
---| "ITEMS"
---| "RINV"
---| "PING"
---| "PONG"

if m.MessageHandler then return end

---@class MessageHandler
---@field send_item fun( item: Item )
---@field send_items fun( items: table<integer, Item> )
---@field send_inventory fun()
---@field request_inventory fun( force: boolean )
---@field on_message fun( data_str: string, sender: string )
local M = {}

function M.new()
	local pinging = false
	local chunked_messages = {}
	local var_names = {
		i = "id",
		n = "name",
		q = "quality",
		t = "icon",
		c = "count",
		d = "deleted"
	}
	setmetatable( var_names, { __index = function( _, key ) return key end } );

	local function parse_table( str )
		local function parse_inner( pos )
			local tbl = {}
			local key
			local i = 1

			while pos <= string.len( str ) do
				local char = string.sub( str, pos, pos )

				if char == "{" then
					local newTable, newPos = parse_inner( pos + 1 )
					if key then
						tbl[ var_names[ key ] ] = newTable
						key = nil
					else
						tbl[ i ] = newTable
						i = i + 1
					end
					pos = newPos
				elseif char == "}" then
					return tbl, pos
				elseif char == "[" then
					local _, newPos, extracted_key = string.find( str, '%["*(.-)"*%]', pos )
					key = tonumber( extracted_key ) and tonumber( extracted_key ) or extracted_key
					pos = newPos
				elseif char == "=" then
				elseif char == "," then
					key = nil
				else
					local _, newPos, raw_value = string.find( str, '([^,%]}]+)', pos )
					if raw_value then
						local value = tonumber( raw_value ) and tonumber( raw_value ) or raw_value
						if key then
							tbl[ var_names[ key ] ] = value
							key = nil
						else
							tbl[ i ] = value
							i = i + 1
						end
						pos = newPos
					end
				end
				pos = pos + 1
			end
			return tbl, pos
		end

		local final_table = parse_inner( 1 )
		return final_table[ 1 ]
	end


	---@param command MessageCommand
	---@param data table?
	local function broadcast( command, data )
		local channel = "GUILD"
		local data_str = data and string.gsub( m.dump( data ), "%s+", "" ) or ""
		local chunk_size = 220

		local function split_message( message )
			local chunks = {}
			local message_length = string.len( message )

			for i = 1, message_length, chunk_size do
				local chunk = string.sub( message, i, i + chunk_size - 1 )
				table.insert( chunks, chunk )
			end

			return chunks
		end

		if string.len( data_str ) > chunk_size then
			data_str = command .. "::" .. data_str
			local chunks = split_message( data_str )
			for i, chunk in ipairs( chunks ) do
				m.debug( string.format( "Broadcasting %s, chunk %d of %d", command, i, getn( chunks ) ) )
				SendAddonMessage( m.prefix, string.format( "CHUNK::%d::%d::%s", i, getn( chunks ), chunk ), channel )
			end
		else
			m.debug( string.format( "Broadcasting %s", command ) )
			SendAddonMessage( m.prefix, string.format( "%s::%s", command, data_str ), channel )
		end
		m.gui.comm( true )
	end

	local function send_item( item )
		broadcast( MessageCommand.Item, {
			i = item.id,
			n = string.gsub( item.name, "%s", "_" ),
			t = string.gsub( item.icon, "Interface\\Icons\\", "" ),
			q = item.quality,
			c = item.count,
			d = item.deleted
		} )
	end

	local function send_items( items )
		local data = {}
		for _, item in ipairs( items ) do
			table.insert( data, {
				i = item.id,
				n = string.gsub( item.name, "%s", "_" ),
				t = string.gsub( item.icon, "Interface\\Icons\\", "" ),
				q = item.quality,
				c = item.count,
				d = item.deleted
			} )
		end

		broadcast( MessageCommand.Items, data )
	end

	local function send_inventory()
		send_items( m.db.inventory )
	end

	local function request_inventory( force )
		local now = time()
		if force or not m.db.last_update or now >= m.db.last_update + 3600 then
			m.db.last_update = now
			pinging = true
			broadcast( MessageCommand.Ping )
		end
	end

	---@param command string
	---@param data table
	---@param sender string
	local function on_command( command, data, sender )
		if command == MessageCommand.Item then
			data.icon = "Interface\\Icons\\" .. data.icon
			data.name = string.gsub( data.name, "_", " " )

			m.add_item( data )
			if m.gui.is_visible() then m.gui.refresh() end
		elseif command == MessageCommand.Items then
			for _, item in ipairs( data ) do
				item.icon = "Interface\\Icons\\" .. item.icon
				item.name = string.gsub( item.name, "_", " " )

				m.add_item( item )
			end

			if m.gui.is_visible() then m.gui.refresh() end
		elseif command == MessageCommand.RequestInventory and data.player == m.player then
			send_inventory()
		elseif command == MessageCommand.Ping then
			broadcast( MessageCommand.Pong )
		elseif command == MessageCommand.Pong and pinging then
			pinging = false
			broadcast( MessageCommand.RequestInventory, { player = sender } )
		end
	end

	local function on_message( data_str, sender )
		local command = string.match( data_str, "^(.-)::" )
		data_str = string.gsub( data_str, "^.-::", "" )

		if command == "CHUNK" then
			local chunk_num, total_chunks, chunk_content = string.match( data_str, "^(%d+)::(%d+)::(.+)$" )
			chunked_messages[ sender ] = chunked_messages[ sender ] or {}

			local sender_chunks = chunked_messages[ sender ]
			sender_chunks[ tonumber( chunk_num ) ] = chunk_content

			if getn( sender_chunks ) == tonumber( total_chunks ) then
				data_str = table.concat( sender_chunks )
				command = string.match( data_str, "^(.-)::" )
				data_str = string.gsub( data_str, "^.-::", "" )

				chunked_messages[ sender ] = nil
			else
				return
			end
		end

		local data = data_str ~= "" and parse_table( data_str ) or {}
		on_command( command, data, sender )
		m.gui.comm( false )
	end

	return {
		broadcast = broadcast,
		send_item = send_item,
		send_items = send_items,
		send_inventory = send_inventory,
		request_inventory = request_inventory,
		on_message = on_message,
	}
end

m.MessageHandler = M
return M
