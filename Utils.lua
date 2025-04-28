GuildInventory = GuildInventory or {}

---@class GuildInventory
local M = GuildInventory

---@param item_link ItemLink
---@return number|nil
function M.get_item_id( item_link )
	for item_id in string.gmatch( item_link, "|c%x%x%x%x%x%x%x%x|Hitem:(%d+):.+|r" ) do
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

---@param item Item
---@return string
function M.get_item_string( item )
	return string.format( "item:%d:0:0:0:0:0:0:0", item.id )
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

function M.colorize_player_by_class( name, class )
	if not class then return name end
	local color = RAID_CLASS_COLORS[ string.upper( class ) ]
	if not color.colorStr then
		color.colorStr = string.format( "ff%02x%02x%02x", color.r * 255, color.g * 255, color.b * 255 )
	end
	return "|c" .. color.colorStr .. name .. "|r"
end

---@param message string
---@param short boolean?
function M.info( message, short )
	local tag = string.format( "|c%s%s|r", M.tagcolor, short and "GI" or "GuildInventory" )
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
	if type( t ) ~= "table" or getn( t ) == 0 then return nil end

	for i, v in pairs( t ) do
		local val = extract_field and v[ extract_field ] or v
		if val == value then return v, i end
	end

	return nil
end

---@param t table
---@return number
function M.count( t )
	local count = 0
	for _ in pairs( t ) do
		count = count + 1
	end

	return count
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
