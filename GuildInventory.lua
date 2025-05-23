---@class GuildInventory
GuildInventory = GuildInventory or {}

---@class GuildInventory
local m = GuildInventory

---@diagnostic disable-next-line: undefined-global
local lib_stub = LibStub

GuildInventory.name = "GuildInventory"
GuildInventory.prefix = "GINV8"
GuildInventory.tagcolor = "FF8B3EE2"
GuildInventory.events = {}
GuildInventory.debug_enabled = false

BINDING_HEADER_GUILDINVENTORY = "GuildInventory"

---@class ItemData
---@field count integer
---@field price integer?

---@class Item
---@field id integer
---@field name string
---@field icon string
---@field link string?
---@field quality integer
---@field deleted integer?
---@field last_update integer?
---@field data table<string, ItemData>

---@class DBItem: Item
---@field slot integer
---@field last_update integer

---@class RequestItem: Item
---@field request_count integer

---@alias NotAceTimer any
---@alias TimerId number

---@class AceTimer
---@field ScheduleTimer fun( self: NotAceTimer, callback: function, delay: number, ... ): TimerId
---@field ScheduleRepeatingTimer fun( self: NotAceTimer, callback: function, delay: number, arg: any ): TimerId
---@field CancelTimer fun( self: NotAceTimer, timer_id: number )
---@field TimeLeft fun( self: NotAceTimer, timer_id: number )

---@class AceSerializer
---@field Serialize fun( self: any, ... ): string
---@field Deserialize fun( self: any, str: string ): any

---@class AceComm
---@field RegisterComm fun( self: any, prefix: string, method: function? )
---@field SendCommMessage fun( self: any, prefix: string, text: string, distribution: string, target: string?, prio: "BULK"|"NORMAL"|"ALERT"?, callbackFn: function?, callbackArg: any? )

function GuildInventory:init()
	self.frame = CreateFrame( "Frame" )
	self.frame:SetScript( "OnEvent", function()
		if m.events[ event ] then
			m.events[ event ]()
		end
	end )

	for k, _ in pairs( m.events ) do
		m.frame:RegisterEvent( k )
	end
end

function GuildInventory.events.ADDON_LOADED()
	if arg1 == m.name then
		---@type AceTimer
		m.ace_timer = lib_stub( "AceTimer-3.0" )

		---@type AceSerializer
		m.ace_serializer = lib_stub( "AceSerializer-3.0" )

		---@type AceComm
		m.ace_comm = lib_stub( "AceComm-3.0" )

		---@type MessageHandler
		m.msg = m.MessageHandler.new( m.ace_timer, m.ace_serializer, m.ace_comm )

		---@type Notifications
		m.notify = m.Notifications.new( m.ace_timer )

		---@type InventoryGui
		m.gui = m.Gui.new( m.FrameBuilder, m.ace_serializer, m.notify )

		---@type TradeskillGui
		m.tsgui = m.Tradeskills.new()

		---@type SlashCommand
		m.slash_command = m.SlashCommand.new( m.name, { "gi", "guildinventory" } )

		m.version = GetAddOnMetadata( m.name, "Version" )
		m.info( string.format( "(v%s) Loaded", m.version ) )
	end
end

function GuildInventory.events.PLAYER_LOGIN()
	-- Initialize DB
	GuildInventoryDB = GuildInventoryDB or {}
	m.db = GuildInventoryDB
	m.db.inventory = m.db.inventory or {}
	m.db.requests = m.db.requests or {}
	m.db.tradeskills = m.db.tradeskills or {}
	m.db.frame_inventory = m.db.frame_inventory or {}
	m.db.frame_tradeskills = m.db.frame_tradeskills or {}


	--if not m.db.version or tonumber( m.db.version ) < 0.6 then
---		m.debug( "Clearing all data." )
		--m.db.inventory = {}
		--m.db.inventory_last_update = nil
		--m.db.tradeskills = {}
		--m.db.tradeskills_last_update = nil
		--m.db.requests = {}
	--end
	m.db.version = m.version

	m.player = UnitName( "player" )
	m.player_class = UnitClass( "player" )
	m.slash_command.init()

	m.check_requests()
	m.msg.request_itemrequests()

	m.tooltip = CreateFrame( "GameTooltip", "GuildInventoryTooltip", nil, "GameTooltipTemplate" )
	m.tooltip:SetOwner( WorldFrame, "ANCHOR_NONE" )

	m.update_data()
end

function GuildInventory.events.BANKFRAME_OPENED()
	m.bank_open = true
	if m.gui.is_visible() then
		m.gui.enable_bank( true )
	end
end

function GuildInventory.events.BANKFRAME_CLOSED()
	m.bank_open = false
	if m.gui.is_visible() then
		m.gui.enable_bank( false )
	end
end

function GuildInventory.events.TRADE_SKILL_SHOW()
	local reverse = m.build_reverse_trade_map( GetLocale() )
	local tradeskill = reverse[ GetTradeSkillLine() ]
	local skills = {
		Alchemy = true,
		Blacksmithing = true,
		Engineering = true,
		Leatherworking = true,
		Tailoring = true,
		Jewelcrafting = true,
	}

	if skills[ tradeskill ] then
		local num = GetNumTradeSkills()

		for i = 1, GetNumTradeSkills() do
			local _, type = GetTradeSkillInfo( i )
			if type == "header" then
				num = num - 1
			end
		end

		m.db.tradeskills[ tradeskill ] = m.db.tradeskills[ tradeskill ] or {}

		if m.count_recipes( m.db.tradeskills[ tradeskill ], m.player ) ~= num then
			for i = 1, GetNumTradeSkills() do
				local _, type = GetTradeSkillInfo( i )
				if type ~= "header" then
					local item_link = GetTradeSkillItemLink( i )
					m.update_tradeskill_item( tradeskill, item_link, { m.player } )
				end
			end

			m.db.tradeskills_last_update = m.get_server_timestamp()
			m.msg.send_tradeskill( tradeskill )
		end
	end
end

function GuildInventory.events.CRAFT_SHOW()
	local reverse = m.build_reverse_trade_map( GetLocale() )
	local tradeskill = reverse[ GetCraftName() ]

	if tradeskill == "Enchanting" then
		local num = GetNumCrafts()

		m.db.tradeskills[ tradeskill ] = m.db.tradeskills[ tradeskill ] or {}

		if m.count_recipes( m.db.tradeskills[ tradeskill ], m.player ) ~= num then
			for i = 1, GetNumCrafts() do
				local item_link = GetCraftItemLink( i )
				m.update_tradeskill_item( tradeskill, item_link, { m.player } )
			end

			m.db.tradeskills_last_update = m.get_server_timestamp()
			m.msg.send_tradeskill( tradeskill )
		end
	end
end

function GuildInventory.events.UNIT_INVENTORY_CHANGED()
	if m.tsgui.is_visible() then
		m.tsgui.update()
	end
end

---@param tradeskill string
---@param item_link ItemLink
---@param players string[]
function GuildInventory.update_tradeskill_item( tradeskill, item_link, players )
	local id, name = m.parse_item_link( item_link )
	--local id = m.get_item_id( item_link )
	--local name = m.get_item_name( item_link )

	if id then
		if m.db.tradeskills[ tradeskill ][ id ] then
			if not players then
				m.debug( "ERROR, no players for: " .. tostring( item_link ) )
				return
			end
			for _, p in pairs( players ) do
				if not m.find( p, m.db.tradeskills[ tradeskill ][ id ].players ) then
					table.insert( m.db.tradeskills[ tradeskill ][ id ].players, p )
				end
			end
		else
			m.db.tradeskills[ tradeskill ][ id ] = {
				id = id,
				link = item_link,
				name = name,
				players = players
			}
		end
	end
end

function GuildInventory.get_cursor_item()
	local function scan_bags( bag_start, bag_end )
		for bag = bag_start, bag_end do
			local slots = GetContainerNumSlots( bag )
			for slot = 1, slots do
				local texture, item_count, locked = GetContainerItemInfo( bag, slot )

				if locked then
					if item_count < 0 then item_count = 1 end
					local item_link = GetContainerItemLink( bag, slot )
					local item_id, name, quality = m.parse_item_link( item_link )

					if item_id and name and quality then
						---@type Item
						return {
							id = item_id,
							name = name,
							quality = quality,
							icon = texture,
							data = {
								[ m.player ] = {
									count = item_count
								}
							}
						}
					end
				end
			end
		end
	end

	local link = scan_bags( 0, 4 )
	if link then return link end

	if BankFrame and BankFrame:IsVisible() then
		link = scan_bags( -1, -1 )
		if link then return link end

		link = scan_bags( 5, 10 )
		if link then return link end
	end

	return nil
end

function GuildInventory.update_data()
	local now = m.get_server_timestamp()

	-- Clear inventory if older then 1 week
	if m.db.inventory_last_update and m.db.inventory_last_update < now - 604800 then
		m.db.inventory_last_update = nil
		m.db.inventory = {}
	end

	-- Remove deleted items older then 2 days
	for index, item in m.db.inventory do
		if item.deleted and now >= item.deleted + 172800 then
			table.remove( m.db.inventory, index )
		end
	end

	-- Remove deleted item requests older then 2 days
	for index, request in m.db.requests do
		if request.deleted and now >= request.deleted + 172800 then
			table.remove( m.db.requests, index )
		end
	end

	-- Request inventory updated if empty or older then 12 hours
	if not m.db.inventory_last_update or now >= m.db.inventory_last_update + 43200 then
		m.db.inventory_last_update = now
		m.msg.request_inventory()
	end

	-- Request tradeskills if older then 2 days
	if not m.db.tradeskills_last_update or now >= m.db.tradeskills_last_update + 172800 then
		m.db.tradeskills_last_update = now
		m.msg.request_tradeskills()
	end
end

---@param item Item
---@param slot integer?
---@param broadcast boolean?
---@param add_count boolean?
function GuildInventory.add_item( item, slot, broadcast, add_count )
	---@type DBItem|nil
	local db_item = m.find( item.name, m.db.inventory, "name" )

	if db_item then
		if item.last_update and db_item.last_update and item.last_update < db_item.last_update then
			m.debug( string.format( "No update for %s", item.name ) )
			return
		end
		m.debug( string.format( "Updatating %s", item.name ) )
		if add_count then
			if db_item.data[ m.player ] and db_item.data[ m.player ].count then
				item.data[ m.player ].count = item.data[ m.player ].count + db_item.data[ m.player ].count
			end
		end
		for player, data in pairs( item.data ) do
			if not db_item.data[ player ] then
				db_item.data[ player ] = { count = 0 }
			end
			db_item.data[ player ].count = data.count

			if data.price then
				db_item.data[ player ].price = data.price
			end
		end

		if db_item.deleted and not item.deleted then
			db_item.deleted = nil
			db_item.slot = (slot and db_item.id == item.id) and slot or m.find_empty_slot()
		end

		if m.count_count( item.data ) <= 0 or item.deleted then
			db_item.slot = 0
			db_item.deleted = item.deleted or m.get_server_timestamp()
		end
		db_item.last_update = item.last_update

		if broadcast then m.msg.send_item( db_item ) end
	else
		if m.count_count( item.data ) == 0 then return end
		if item.deleted then return end
		if slot then
			db_item = m.find( slot, m.db.inventory, "slot" )
			if db_item and db_item.id ~= item.id then
				slot = m.find_empty_slot()
			end
		else
			slot = m.find_empty_slot()
		end

		---@type DBItem
		local data = {
			id = item.id,
			name = item.name,
			icon = item.icon,
			quality = item.quality,
			data = item.data,
			slot = slot,
			last_update = m.get_server_timestamp(),
		}
		table.insert( m.db.inventory, data )

		if broadcast then m.msg.send_item( data ) end
	end
end

---@param from integer
---@param to integer
function GuildInventory.move_item( from, to )
	local item_from = m.find( from, m.db.inventory, "slot" )
	local item_to = m.find( to, m.db.inventory, "slot" )

	if item_from then
		item_from.slot = to
	end

	if item_to then
		item_to.slot = from
	end
end

---@param slot_index integer
---@param count integer
---@param price number
---@param broadcast boolean
function GuildInventory.update_item_data( slot_index, count, price, broadcast )
	---@type DBItem|nil
	local db_item = m.find( slot_index, m.db.inventory, "slot" )

	if not db_item then
		m.error( string.format( "Unable to find item at slot %d in DB.", slot_index ) )
		return
	end

	if not db_item.data[ m.player ] then
		db_item.data[ m.player ] = {}
	end

	if db_item.data[ m.player ].count ~= count or db_item.data[ m.player ].price ~= price then
		db_item.data[ m.player ].count = count
		db_item.data[ m.player ].price = price

		if m.count_count( db_item.data ) == 0 then
			db_item.slot = 0
			db_item.deleted = m.get_server_timestamp()
		end
		db_item.last_update = m.get_server_timestamp()

		if broadcast then
			m.msg.send_item( db_item )
		end
	end
end

---@param bag_start integer
---@param bag_end integer
---@param name string
---@return integer
function GuildInventory.find_item_count_bag( bag_start, bag_end, name )
	local count = 0
	for bag = bag_start, bag_end do
		local slots = GetContainerNumSlots( bag )
		for slot = 1, slots do
			local _, item_count = GetContainerItemInfo( bag, slot )
			if item_count and item_count > 0 then
				local _, item_name = m.parse_item_link( GetContainerItemLink( bag, slot ) )
				if item_name == name then
					count = count + item_count
				end
			end
		end
	end
	return count
end

---@param loc "Inventory"|"Bank"
---@return boolean
function GuildInventory.sync_count( loc )
	local updated = {}

	for _, item in pairs( m.db.inventory ) do
		if item.data[ m.player ] and item.data[ m.player ].count then
			local count = 0
			if loc == "Inventory" then
				count = m.find_item_count_bag( 0, 4, item.name )
			elseif loc == "Bank" then
				count = m.find_item_count_bag( -1, -1, item.name )
				count = count + m.find_item_count_bag( 5, 10, item.name )
			end

			if count > 0 and count ~= item.data[ m.player ].count then
				item.data[ m.player ].count = count
				table.insert( updated, item )
			end
		end
	end

	if getn( updated ) > 0 then
		m.msg.send_items( updated )
		return true
	else
		return false
	end
end

---@return integer
function GuildInventory.get_num_slots()
	local last_slot = 0
	for _, item in pairs( m.db.inventory ) do
		if item.slot > last_slot then
			last_slot = item.slot
		end
	end

	local slots = math.ceil( last_slot / 10 ) * 10
	if last_slot == slots then
		slots = slots + 10
	end

	return slots
end

---@return integer
function GuildInventory.find_empty_slot()
	for i = 1, m.get_num_slots() do
		local item = m.find( i, m.db.inventory, "slot" )
		if not item then
			return i
		end
	end

	return m.get_num_slots() + 1
end

---@param data RequestData
function GuildInventory.add_request( data )
	if m.find( data.id, m.db.requests, "id" ) then
		return
	end

	table.insert( m.db.requests, data )
end

function GuildInventory.check_requests()
	for _, request in (m.db.requests) do
		if request.to == m.player and not request.read then
			m.notify.new_request( request )
		end
	end
end

function GuildInventory.convert()
	for _, item in m.db.inventory do
		item.data = {}
		for p, c in item.count do
			item.data[ p ] = {}
			item.data[ p ][ 'count' ] = c
		end
		item.count = nil
	end
end

GuildInventory:init()
