GuildInventory = GuildInventory or {}

---@class GuildInventory
local m = GuildInventory

if m.MessageHandler then return end

local PREFIX = "GUINV"

---@type MessageCommand
local MessageCommand = {
	Item = "ITEM",
	Items = "ITEMS",
	RequestInventory = "RINV",
	RequestRequests = "RREQ",
	RequestTradeskills = "RTS",
	ItemRequest = "IREQ",
	Tradeskill = "TS",
	Ping = "PING",
	Pong = "PONG",
	VersionCheck = "VERSIONCHECK",
	Version = "VERSION",
}

---@alias MessageCommand
---| "ITEM"
---| "ITEMS"
---| "RINV"
---| "RREQ"
---| "RTS",
---| "IREQ"
---| "TS"
---| "PING"
---| "PONG"
---| "VERSIONCHECK"
---| "VERSION"

---@class RequestData
---@field id integer
---@field from string
---@field to string
---@field message string
---@field timestamp integer
---@field read boolean?
---@field items table<integer, RequestItem>

---@class MessageHandler
---@field send_item fun( item: Item )
---@field send_items fun( items: table<integer, Item> )
---@field send_inventory fun()
---@field send_itemrequest fun( request_data: RequestData )
---@field send_tradeskill fun( tradeskill: string )
---@field request_inventory fun()
---@field request_itemrequests fun()
---@field request_tradeskills fun()
---@field version_check fun()

local M = {}

---@param ace_timer AceTimer
---@param ace_serializer AceSerializer
---@param ace_comm AceComm
function M.new( ace_timer, ace_serializer, ace_comm )
	local pinging = nil
	local best_ping
	local var_names = {
		n = "name",
		q = "quality",
		t = "icon",
		c = "count",
		p = "price",
		pl = "players",
		d = "data",
		x = "deleted",
		f = "from",
		i = "items",
		m = "message",
		ts = "timestamp",
		ilu = "inventory_last_update",
		tlu = "tradeskills_last_update",
	}
	setmetatable( var_names, { __index = function( _, key ) return key end } );

	---@param t table
	local function decode( t )
		local l = {}
		for key, value in pairs( t ) do
			if type( value ) == "table" then
				value = decode( value )
			end
			if key == "t" then
				value = "Interface\\Icons\\" .. value
			end
			l[ var_names[ key ] ] = value
		end
		return l
	end

	---@param command MessageCommand
	---@param data table?
	local function broadcast( command, data )
		m.debug( string.format( "Broadcasting %s", command ) )

		ace_comm:SendCommMessage( PREFIX, command .. "::" .. ace_serializer.Serialize( M, data ), "GUILD", nil, "NORMAL", function()
			m.gui.comm( true )
		end )
		m.gui.comm( true )
	end

	local function send_item( item )
		local item_data = {}
		for k, v in pairs( item.data ) do
			item_data[ k ] = v
		end

		broadcast( MessageCommand.Item, {
			id = item.id,
			n = item.name,
			t = string.gsub( item.icon, "Interface\\Icons\\", "" ),
			q = item.quality,
			d = item_data,
			x = item.deleted
		} )
	end

	local function send_items( items )
		local data = {}
		for _, item in ipairs( items ) do
			local item_data = {}
			for k, v in pairs( item.data ) do
				item_data[ k ] = v
			end

			table.insert( data, {
				id = item.id,
				n = item.name,
				t = string.gsub( item.icon, "Interface\\Icons\\", "" ),
				q = item.quality,
				d = item_data,
				x = item.deleted
			} )
		end

		broadcast( MessageCommand.Items, data )
	end

	local function send_inventory()
		send_items( m.db.inventory )
	end

	local function send_itemrequest( request_data )
		local items = {}
		for _, item in request_data.items do
			table.insert( items, {
				id = item.id,
				n = item.name,
				c = item.count
			} )
		end

		broadcast( MessageCommand.ItemRequest, {
			to = request_data.to,
			f = request_data.from,
			ts = request_data.timestamp,
			m = request_data.message,
			i = items
		} )

		if m.guild_member_online( request_data.to ) then
			m.debug( request_data.to .. "is online. Delete itemrequest." )
			local _, index = m.find( request_data.id, m.db.requests, "id" )
			table.remove( m.db.requests, index )
		end
	end

	local function send_itemrequests( to )
		for _, request in m.db.requests do
			if request.to == to then
				send_itemrequest( request )
			end
		end
	end

	local function send_tradeskill( tradeskill )
		local data = {
			tradeskill = tradeskill,
			recipes = {}
		}

		for _, skill in m.db.tradeskills[ tradeskill ] do
			table.insert( data.recipes, {
				id = skill.id,
				pl = skill.players
			})
		end

		broadcast( MessageCommand.Tradeskill, data )
	end

	local function send_tradeskills()
		for tradeskill in m.db.tradeskills do
			send_tradeskill( tradeskill )
		end
	end

	local function request_tradeskills()
		pinging = "tradeskills"
		best_ping = nil
		broadcast( MessageCommand.Ping )
	end

	local function request_itemrequests()
		broadcast( MessageCommand.RequestRequests )
	end

	local function request_inventory()
		pinging = "inventory"
		best_ping = nil
		broadcast( MessageCommand.Ping )
	end

	local function version_check()
		broadcast( MessageCommand.VersionCheck )
	end

	---@param command string
	---@param data table
	---@param sender string
	local function on_command( command, data, sender )
		if command == MessageCommand.Item then
			--
			-- Receive single item
			--	
			m.add_item( data )
			if m.gui.is_visible() then m.gui.refresh() end
		elseif command == MessageCommand.Items then
			--
			-- Receive multiple items
			--
			for _, item in ipairs( data ) do
				m.add_item( item )
			end

			if m.gui.is_visible() then m.gui.refresh() end
		elseif command == MessageCommand.ItemRequest then
			--
			-- Receive item request
			--
			if m.guild_member_online( data.to ) and data.to ~= m.player then
				return
			end

			m.add_request( data )

			if ace_timer:TimeLeft( M.request_timer ) == 0 then
				M.request_timer = ace_timer.ScheduleTimer( M, m.check_requests, 2 )
			end
		elseif command == MessageCommand.Tradeskill then
			--
			-- Receive tradeskill
			--
			m.debug( "Receive tradeskill " .. data.tradeskill)
			local tradeskill = data.tradeskill
			m.db.tradeskills[ tradeskill ] = m.db.tradeskills[ tradeskill ] or {}
			for _, v in data.recipes do
				local item_link
				if m.db.tradeskills[ tradeskill ][ v.id ] and m.db.tradeskills[ tradeskill ][ v.id ].link then
					item_link = m.db.tradeskills[ tradeskill ][ v.id ].link
				else
					if tradeskill == "Enchanting" then
						local name = m.Enchants[ v.id ].name
						item_link = m.make_enchant_link( v.id, name )
					else
						local name, _, quality = GetItemInfo( v.id )
						item_link = m.make_item_link( v.id, name, quality )
					end
				end

				m.update_tradeskill_item( tradeskill, item_link, v.players )
			end
		elseif command == MessageCommand.RequestTradeskills and data.player == m.player then
			--
			-- Request for tradeskills
			--
			send_tradeskills()
		elseif command == MessageCommand.RequestInventory and data.player == m.player then
			--
			-- Request for inventory
			--
			send_inventory()
		elseif command == MessageCommand.RequestRequests then
			--
			-- Request for item requests
			--
			send_itemrequests( sender )
		elseif command == MessageCommand.Ping then
			--
			-- Recive ping
			--
			broadcast( MessageCommand.Pong, {
				ilu = m.db.inventory_last_update,
				tlu = m.db.tradeskills_last_update,
			} )
		elseif command == MessageCommand.Pong and pinging then
			--
			-- Receive pong
			--
			local field = pinging == "inventory" and "inventory_last_update" or "tradeskills_last_update"

			if not best_ping or data[field] > best_ping.last_update then
				best_ping = {
					player = sender,
					last_update = data[field]
				}
			end

			if ace_timer:TimeLeft( M.ping_timer ) == 0 then
				M.ping_timer = ace_timer.ScheduleTimer( M, function()
					if pinging == "inventory" then
						broadcast( MessageCommand.RequestInventory, { player = best_ping.player } )
					elseif pinging == "tradeskills" then
						broadcast( MessageCommand.RequestTradeskills, { player = best_ping.player } )
					end
					pinging = nil
				end, 1 )
			end
		elseif command == MessageCommand.VersionCheck then
			--
			-- Receive version request
			--
			broadcast( MessageCommand.Version, { requester = sender, version = m.version, class = m.player_class } )
		elseif command == MessageCommand.Version then
			--
			-- Reveive version
			--
			if data.requester == m.player then
				m.info( string.format( "%s [v%s]", m.colorize_player_by_class( sender, data.class ), data.version ), true )
			end
		end
	end

	local function on_comm_received( prefix, data_str, _, sender )
		if prefix ~= PREFIX or sender == m.player then return end

		local command = string.match( data_str, "^(.-)::" )
		data_str = string.gsub( data_str, "^.-::", "" )

		m.debug("Received " .. command)

		local success, data = ace_serializer.Deserialize( M, data_str )
		if success then
			if data then
				data = decode( data )
			end

			on_command( command, data, sender )
			m.gui.comm( false )
		else
			m.error( "Corrupt data in addon message!" )
		end
	end

	ace_comm.RegisterComm( M, PREFIX, on_comm_received )

	---@type MessageHandler
	return {
		broadcast = broadcast,
		send_item = send_item,
		send_items = send_items,
		send_inventory = send_inventory,
		send_itemrequest = send_itemrequest,
		send_tradeskill = send_tradeskill,
		request_inventory = request_inventory,
		request_itemrequests = request_itemrequests,
		request_tradeskills = request_tradeskills,
		version_check = version_check,
	}
end

m.MessageHandler = M
return M
