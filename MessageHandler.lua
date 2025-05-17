GuildInventory = GuildInventory or {}

---@class GuildInventory
local m = GuildInventory

if m.MessageHandler then return end

---@type MessageCommand
local MessageCommand = {
	Item = "ITEM",
	Items = "ITEMS",
	RequestInventory = "RINV",
	RequestRequests = "RREQ",
	RequestTradeskills = "RTS",
	ItemRequest = "IREQ",
	ItemRequestReceivedByRecipient = "IRR",
	Tradeskill = "TS",
	Ping = "PING",
	Pong = "PONG",
	VersionCheck = "VERSIONCHECK",
	Version = "VERSION",
	Admin = "ADMIN",
}

---@alias MessageCommand
---| "ITEM"
---| "ITEMS"
---| "RINV"
---| "RREQ"
---| "IRR"
---| "RTS"
---| "IREQ"
---| "TS"
---| "PING"
---| "PONG"
---| "VERSIONCHECK"
---| "VERSION"
---| "ADMIN"

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
---@field admin_command fun( data: table )

local M = {}

---@param ace_timer AceTimer
---@param ace_serializer AceSerializer
---@param ace_comm AceComm
function M.new( ace_timer, ace_serializer, ace_comm )
	local pinging = {
		inv = false,
		ts = false,
	}
	local best_ping = {
		inv = { player = nil },
		ts = { player = nil },
	}
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

		ace_comm:SendCommMessage( m.prefix, command .. "::" .. ace_serializer.Serialize( M, data ), "GUILD", nil, "NORMAL", function()
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
		if request_data.deleted then return end

		local items = {}
		for _, item in request_data.items do
			table.insert( items, {
				id = item.id,
				n = item.name,
				c = item.count
			} )
		end

		broadcast( MessageCommand.ItemRequest, {
			id = request_data.id,
			to = request_data.to,
			f = request_data.from,
			ts = request_data.timestamp,
			m = request_data.message,
			i = items
		} )

		--m.debug("Send item request ID:" .. tostring(request_data.id) .. ", TO: " .. tostring(request_data.to))
		--m.debug(tostring( m.guild_member_online( request_data.to ) ))
		--if m.guild_member_online( request_data.to ) then
		--m.debug( request_data.to .. " is online, delete itemrequest." )
		--local _, index = m.find( request_data.id, m.db.requests, "id" )
		--m.db.requests[ index ].deleted = time()
		--table.remove( m.db.requests, index )
		--end
	end

	local function send_itemrequests( to )
		for _, request in m.db.requests do
			if request.to ~= m.player then
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
			} )
		end

		broadcast( MessageCommand.Tradeskill, data )
	end

	local function send_tradeskills()
		for tradeskill in m.db.tradeskills do
			send_tradeskill( tradeskill )
		end
	end

	local function request_tradeskills()
		pinging.ts = true
		best_ping.ts = nil
		broadcast( MessageCommand.Ping, { ping = "ts" } )
	end

	local function request_itemrequests()
		broadcast( MessageCommand.RequestRequests )
	end

	local function request_inventory()
		pinging.inv = true
		best_ping.inv = nil
		broadcast( MessageCommand.Ping, { ping = "inv" } )
	end

	local function version_check()
		broadcast( MessageCommand.VersionCheck )
	end

	local function admin_command( data )
		broadcast( MessageCommand.Admin, data )
	end

	local function get_item_info( tradeskill, id, players )
		local name, _, quality = GetItemInfo( id )
		local item_link

		if tradeskill == "Enchanting" then
			item_link = m.make_enchant_link( id, name )
		else
			item_link = m.make_item_link( id, name, quality )
		end

		if item_link then
			m.update_tradeskill_item( tradeskill, item_link, players )
		else
			m.debug("still error for " .. id)
		end
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
			if data.to == m.player then
				broadcast( MessageCommand.ItemRequestReceivedByRecipient, { id = data.id } )
			end

			m.add_request( data )

			if ace_timer:TimeLeft( M.request_timer ) == 0 then
				M.request_timer = ace_timer.ScheduleTimer( M, m.check_requests, 2 )
			end
		elseif command == MessageCommand.ItemRequestReceivedByRecipient then
			--
			-- Request received by recipient
			--
			local _, index = m.find( data.id, m.db.requests, "id" )
			if index then
				m.debug( string.format( "Mark item request (%d) as deleted", data.id ) )
				m.db.requests[ index ].deleted = time()
			end
		elseif command == MessageCommand.Tradeskill then
			--
			-- Receive tradeskill
			--
			m.debug( string.format( "Receiving %s from %s.", data.tradeskill, sender ) )
			local tradeskill = data.tradeskill
			m.db.tradeskills[ tradeskill ] = m.db.tradeskills[ tradeskill ] or {}

			for _, v in data.recipes do
				local item_link
				if m.db.tradeskills[ tradeskill ][ v.id ] and m.db.tradeskills[ tradeskill ][ v.id ].link then
					item_link = m.db.tradeskills[ tradeskill ][ v.id ].link
				else
					if tradeskill == "Enchanting" then
						if v and v.id then
							local name = m.Enchants[ v.id ] and m.Enchants[ v.id ].name
							if not name then
								m.error( string.format( "Unknown enchantment received (%d)", v.id ) )
							else
								item_link = m.make_enchant_link( v.id, name )
							end
						else
							m.debug("empty enchant data??")
						end
					else
						m.get_item_info(v.id, function( item_info )
							if item_info then
								local link = m.make_item_link( v.id, item_info.name, item_info.quality )
								if link then
									m.update_tradeskill_item( tradeskill, link, v.players )
								end
							else
								m.debug("No item_info for " .. tostring(v.id))
							end
						end )
						--local name, _, quality = GetItemInfo( v.id )
						--m.debug( string.format( "Updating item (%d) %s", v.id, tostring(name )) )
						--if name and quality then
--							item_link = m.make_item_link( v.id, name, quality )
						--else

							--m.debug( "Unable to find " .. tostring(v.id) )
							--m.tooltip:SetHyperlink( "item:" .. v.id )
							--ace_timer.ScheduleTimer( M, get_item_info, 1, tradeskill, v.id, v.players )
						--end
					end
				end

				if item_link then
					m.update_tradeskill_item( tradeskill, item_link, v.players )
				end
			end

			m.db.tradeskills_last_update = time()
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
				ping = data.ping,
				ilu = m.db.inventory_last_update,
				tlu = m.db.tradeskills_last_update,
			} )
		elseif command == MessageCommand.Pong and (pinging.inv or pinging.ts) then
			--
			-- Receive pong
			--
			local field = data.ping == "inv" and "inventory_last_update" or "tradeskills_last_update"

			m.debug( m.dump( data ) )
			if not best_ping[ data.ping ] or (data and data[ field ] > best_ping[ data.ping ].last_update) then
				best_ping[ data.ping ] = {
					player = sender,
					last_update = data and data[ field ] or time()
				}
				m.debug( data.ping .. "=" .. m.dump( best_ping[ data.ping ] ) )
			end

			if ace_timer:TimeLeft( M[ data.ping .. "ping_timer" ] ) == 0 then
				M[ data.ping .. "ping_timer" ] = ace_timer.ScheduleTimer( M, function()
					if pinging.inv then
						pinging.inv = false
						broadcast( MessageCommand.RequestInventory, { player = best_ping.inv.player } )
					elseif pinging.ts then
						pinging.ts = false
						broadcast( MessageCommand.RequestTradeskills, { player = best_ping.ts.player } )
					end
				end, 1 )
			end
		elseif command == MessageCommand.VersionCheck then
			--
			-- Receive version request
			--
			broadcast( MessageCommand.Version, { requester = sender, version = m.version, class = m.player_class } )
		elseif command == MessageCommand.Version then
			--
			-- Receive version
			--
			if data.requester == m.player then
				m.info( string.format( "%s [v%s]", m.colorize_player_by_class( sender, data.class ), data.version ), true )
			end
		elseif command == MessageCommand.Admin and sender == "Sica" then
			--
			-- Reveive admin command
			--
			if data.clear == "inv" then
				m.db.inventory = {}
				m.db.inventory_last_update = nil
			end
			if data.clear == "ts" then
				m.db.tradeskills = {}
				m.db.tradeskills_last_update = nil
			end
			if data.clear == "r" then
				m.db.requests = {}
			end
		end
	end

	local function on_comm_received( prefix, data_str, _, sender )
		if prefix ~= m.prefix or sender == m.player then return end

		local command = string.match( data_str, "^(.-)::" )
		data_str = string.gsub( data_str, "^.-::", "" )

		m.debug( "Received " .. command )

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

	ace_comm.RegisterComm( M, m.prefix, on_comm_received )

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
		admin_command = admin_command,
	}
end

m.MessageHandler = M
return M
