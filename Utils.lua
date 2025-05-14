GuildInventory = GuildInventory or {}

---@class GuildInventory
local M = GuildInventory

local QUALITY_COLORS = {
	[ "ff9d9d9d" ] = 0, -- poor (gray)
	[ "ffffffff" ] = 1, -- common (white)
	[ "ff1eff00" ] = 2, -- uncommon (green)
	[ "ff0070dd" ] = 3, -- rare (blue)
	[ "ffa335ee" ] = 4, -- epic (purple)
	[ "ffff8000" ] = 5, -- legendary (orange)
}

M.TRADE_SKILL_LOCALIZATION = {
	Alchemy = {
		enUS = "Alchemy",
		deDE = "Alchimie",
		frFR = "Alchimie",
		esES = "Alquimia",
		koKR = "연금술",
		zhCN = "炼金术",
		zhTW = "鍊金術",
	},
	Blacksmithing = {
		enUS = "Blacksmithing",
		deDE = "Schmiedekunst",
		frFR = "Forge",
		esES = "Herrería",
		koKR = "대장기술",
		zhCN = "锻造",
		zhTW = "鍛造",
	},
	Engineering = {
		enUS = "Engineering",
		deDE = "Ingenieurskunst",
		frFR = "Ingénierie",
		esES = "Ingeniería",
		koKR = "기계공학",
		zhCN = "工程学",
		zhTW = "工程學",
	},
	Leatherworking = {
		enUS = "Leatherworking",
		deDE = "Lederverarbeitung",
		frFR = "Travail du cuir",
		esES = "Peletería",
		koKR = "가죽세공",
		zhCN = "制皮",
		zhTW = "製皮",
	},
	Tailoring = {
		enUS = "Tailoring",
		deDE = "Schneiderei",
		frFR = "Couture",
		esES = "Sastrería",
		koKR = "재봉술",
		zhCN = "裁缝",
		zhTW = "裁縫",
	},
	Enchanting = {
		enUS = "Enchanting",
		deDE = "Verzauberkunst",
		frFR = "Enchantement",
		esES = "Encantamiento",
		koKR = "마법부여",
		zhCN = "附魔",
		zhTW = "附魔",
	},
	Jewelcrafting = {
		enUS = "Jewelcrafting",
	},
}

function M.build_reverse_trade_map( locale )
	local map = {}
	for internal, locs in pairs( M.TRADE_SKILL_LOCALIZATION ) do
		local localized = locs[ locale ]
		if localized then
			map[ localized ] = internal
		end
	end
	return map
end

function M.get_perfect_pixel()
	if M.pixel then return M.pixel end

	local scale = GetCVar( "uiScale" ) or 1
	local resolution = GetCVar( "gxResolution" ) or ""
	local _, _, _, screenheight = string.find( resolution, "(.+)x(.+)" )

	M.pixel = 768 / screenheight / scale
	M.pixel = M.pixel > 1 and 1 or M.pixel

	return M.pixel
end

---@param item_link ItemLink
---@return number|nil
function M.get_item_id( item_link )
	for item_id in string.gmatch( item_link, "|c%x%x%x%x%x%x%x%x|Hitem:(%d+):.+|r" ) do
		return tonumber( item_id )
	end
	for item_id in string.gmatch( item_link, "|c%x%x%x%x%x%x%x%x|Henchant:(%d+).+|r" ) do
		return tonumber( item_id )
	end
end

---@param item_id integer?
---@return ItemQuality
function M.get_item_quality( item_id )
	if not item_id then return 0 end
	local _, _, quality = GetItemInfo( item_id )
	return quality
end

---@param item_link string
---@return number|nil quality
function M.get_item_quality_from_link( item_link )
	local hex = string.match( item_link, "^|c(%x%x%x%x%x%x%x%x)" )
	local quality
	if hex then
		quality = QUALITY_COLORS[ string.lower( hex ) ]
	end

	if not quality then
		_, _, quality = GetItemInfo( item_link )
	end

	return tonumber( quality )
end

---@param item Item|integer
---@return string
function M.get_item_string( item )
	if type( item ) == "table" then
		return string.format( "item:%d:0:0:0:0:0:0:0", item.id )
	elseif type( item ) == "number" then
		return string.format( "item:%d:0:0:0:0:0:0:0", item )
	end

	return ""
end

function M.get_enchant_string( item )
	return string.format( "enchant:%d", item.id )
end

---@param item_link string
---@return string
function M.get_item_name( item_link )
	return string.match( item_link or "", "%[(.-)%]" )
end

---@param item Item
---@return string
function M.get_item_name_colorized( item )
	local color = ITEM_QUALITY_COLORS[ item.quality or 1 ]
	local hex = string.format( "%02x%02x%02x", color.r * 255, color.g * 255, color.b * 255 )

	return string.format( "|cFF%s%s|r", hex, item.name )
end

---@param item Item
---@return string
function M.get_item_link( item )
	local color = ITEM_QUALITY_COLORS[ item.quality or 1 ]
	local hex = string.format( "%02x%02x%02x", color.r * 255, color.g * 255, color.b * 255 )

	return string.format( "|cFF%s|Hitem:%d:0:0:0|h[%s]|h|r", hex, item.id, item.name )
end

function M.make_item_link( id, name, quality )
	local color = ITEM_QUALITY_COLORS[ quality or 1 ]
	local hex = string.format( "%02x%02x%02x", color.r * 255, color.g * 255, color.b * 255 )

	return string.format( "|cFF%s|Hitem:%d:0:0:0|h[%s]|h|r", hex, id, name )
end

function M.make_enchant_link( id, name )
	return string.format( "|cFF%s|Henchant:%d|h[%s]|h|r", "71d5ff", id, name )
end

function M.colorize_player_by_class( name, class )
	if not class then return name end
	local color = RAID_CLASS_COLORS[ string.upper( class ) ]
	if not color.colorStr then
		color.colorStr = string.format( "ff%02x%02x%02x", color.r * 255, color.g * 255, color.b * 255 )
	end
	return "|c" .. color.colorStr .. name .. "|r"
end

function M.clean_string( input )
	input = string.gsub( input, "^%s+", "" )
	input = string.gsub( input, "%s+$", "" )
	input = string.gsub( input, "|c%x%x%x%x%x%x%x%x", "" )
	input = string.gsub( input, "|r", "" )

	return input
end

---@param player_name string
---@return boolean
---@nodiscard
function M.guild_member_online( player_name )
	for i = 1, GetNumGuildMembers() do
		local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo( i )
		if player_name == name and online == 1 then
			return true
		end
	end

	return false
end

---@param timestamp integer
---@return string
function M.time_ago( timestamp )
	local now = time()
	local diff = now - timestamp

	if diff < 0 then
		return "From the future!"
	end

	if diff < 300 then
		return "Just now"
	elseif diff < 3600 then
		local minutes = math.floor( diff / 60 )
		return string.format( "%d minute%s ago", minutes, minutes ~= 1 and "s" or "" )
	end

	local today = date( "*t", now )
	today.hour, today.min, today.sec = 0, 0, 0
	local midnight = time( today )

	if timestamp < midnight then
		local days = math.floor( (midnight - timestamp) / 86400 ) + 1
		return string.format( "%d day%s ago", days, days ~= 1 and "s" or "" )
	end

	local hours = math.floor( diff / 3600 )
	return string.format( "%d hour%s ago", hours, hours ~= 1 and "s" or "" )
end

---@param copper number
---@param no_color boolean?
---@return string
---@nodiscard
function M.format_money( copper, no_color )
	if type( copper ) ~= "number" then return "-" end

	local gold = math.floor( copper / 10000 )
	local silver = math.floor( (copper - gold * 10000) / 100 )
	local copper_remain = copper - (gold * 10000) - (silver * 100)

	local result = ""
	if gold > 0 then
		result = result .. (no_color and string.format( "%dg", gold ) or string.format( "|cffffffff%d|cffffd700g|r", gold ))
	end
	if silver > 0 then
		result = result .. (no_color and string.format( "%ds", silver ) or string.format( "|cffffffff%d|cffc7c7cfs|r", silver ))
	end
	if copper_remain > 0 or result == "" then
		result = result .. (no_color and string.format( "%dc", copper_remain ) or string.format( "|cffffffff%d|cffeda55fc|r", copper_remain ))
	end

	return result
end

---@param str string
---@return number|nil
---@nodiscard
function M.parse_money( str )
	if not str then return nil end

	str = string.lower( string.match( str, "^%s*(.-)%s*$" ) )
	if str == "" then return nil end

	if string.find( str, "^%d+$" ) then
		return tonumber( str ) or nil
	end

	local copper = 0

	for amt, unit in string.gmatch( str, "(%d+)%s*([gsc])" ) do
		local amount = tonumber( amt )
		if unit == "g" then
			copper = copper + amount * 10000
		elseif unit == "s" then
			copper = copper + amount * 100
		elseif unit == "c" then
			copper = copper + amount
		end
	end

	local remain = string.gsub( str, "%d+%s*[gsc]", "" )
	remain = string.gsub( remain, "%s+", "" )
	if remain ~= "" then
		return nil
	end

	return copper
end

---@param message string
---@param short boolean?
function M.info( message, short )
	local tag = string.format( "|c%s%s|r", M.tagcolor, short and "GI" or "GuildInventory" )
	DEFAULT_CHAT_FRAME:AddMessage( string.format( "%s: %s", tag, message ) )
end

---@param message string
function M.error( message )
	local tag = string.format( "|c%s%s|r|cffff0000%s|r", M.tagcolor, "GI", "ERROR" )
	DEFAULT_CHAT_FRAME:AddMessage( string.format( "%s: %s", tag, message ) )
end

function M.debug( message )
	if M.debug_enabled then
		M.info( message, true )
	end
end

---@param value string|number
---@param t table
---@param extract_field string?
function M.find( value, t, extract_field )
	if type( t ) ~= "table" or M.count( t ) == 0 then return nil end

	for i, v in pairs( t ) do
		local val = extract_field and v[ extract_field ] or v
		if val == value then return v, i end
	end

	return nil
end

---@param t table
---@param field string?
---@return number
function M.count( t, field )
	local count = 0
	for _, e in pairs( t ) do
		if field and e[ field ] and e[ field ] > 0 or not field then
			--if e.count and e.count > 0 then
			count = count + 1
		end
	end

	return count
end

---@param recipes table
---@param player string
---@return number
function M.count_recipes( recipes, player )
	local count = 0

	for _, recipe in pairs( recipes ) do
		if M.find( player, recipe.players ) then
			count = count + 1
		end
	end

	return count
end

---@param t table
---@return number
function M.count_count( t )
	local count = 0
	for _, e in pairs( t ) do
		if e.count and e.count > 0 then
			count = count + 1
		end
	end

	return count
end

---@param s string|string[]
---@return string[]
function M.to_string_list( s )
	---@type string[]
	local r

	if type( s ) == "string" then r = { s } else r = s end
	return r
end

---@param str string
---@return integer
function M.hash_string( str )
	local hash = 5381
	for i = 1, string.len( str ) do
		local c = string.byte( str, i )
		hash = mod( hash * 33 + c, 4294967296 )
	end

	return hash
end

--- @param hex string
--- @return number r
--- @return number g
--- @return number b
--- @return number a
function M.hex_to_rgba( hex )
	local r, g, b, a = string.match( hex, "^#?(%x%x)(%x%x)(%x%x)(%x?%x?)$" )

	r, g, b = tonumber( r, 16 ) / 255, tonumber( g, 16 ) / 255, tonumber( b, 16 ) / 255
	a = a ~= "" and tonumber( a, 16 ) / 255 or 1
	return r, g, b, a
end

---@param o any
---@return string
function M.dump( o )
	if not o then return "nil" end
	if type( o ) ~= 'table' then return tostring( o ) end

	local entries = 0
	local s = "{"

	for k, v in pairs( o ) do
		if (entries == 0) then s = s .. " " end

		local key = type( k ) ~= "number" and '"' .. k .. '"' or k

		if (entries > 0) then s = s .. ", " end

		s = s .. "[" .. key .. "] = " .. M.dump( v )
		entries = entries + 1
	end

	if (entries > 0) then s = s .. " " end
	return s .. "}"
end

---@diagnostic disable-next-line: undefined-field
if not string.gmatch then string.gmatch = string.gfind end

return M
