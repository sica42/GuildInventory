GuildInventory = GuildInventory or {}

---@class GuildInventory
local m = GuildInventory

if m.SlashCommand then return end

---@class SlashCommand
---@field register fun( command: string|string[], func: fun( args: string[] ) )
---@field init fun()
local M = {}

---@param name string
---@param slash_commands string|string[]
function M.new( name, slash_commands )
	local _G = getfenv()
	local commands = {}

	---@param command string
	---@return boolean
	local function has_command( command )
		for k, _ in pairs( commands ) do
			if k == command then return true end
		end
		return false
	end

	---@param command string
	---@return fun(args: string[])
	local function get_command( command )
		local cmd = commands[ command ]
		if cmd then return cmd else return commands[ "__DEFAULT__" ] end
	end

	---@param command string
	---@param args string[]
	local function handle_command( command, args )
		local cmd = get_command( command )
		if cmd then
			cmd( args )
		else
			m.info( string.format( "%q is not a valid command.", command ) )
		end
	end

	if type( slash_commands ) == "string" then
		slash_commands = { slash_commands }
	end

	for i, v in ipairs( slash_commands ) do
		_G[ "SLASH_" .. string.upper( name ) .. i ] = "/" .. v
	end

	SlashCmdList[ string.upper( name ) ] = function( msg )
		local args = {}
		local t = {}

		msg = string.gsub( msg, "^%s*(.-)%s*$", "%1" )
		for part in string.gmatch( msg, "%S+" ) do
			table.insert( args, part )
		end

		local command = args[ 1 ]
		if getn( args ) > 1 then
			for i = 2, getn( args ) do
				table.insert( t, args[ i ] )
			end
		end

		handle_command( command, t )
	end

	---@param command string|string[]
	---@param func fun(args: string[])
	local function register( command, func )
		if type( command ) == "string" then
			command = { command }
		end
		for _, v in pairs( command ) do
			if not has_command( v ) then
				if v ~= "__DEFAULT__" then v = string.lower( v ) end
				commands[ v ] = func
			end
		end
	end

	local function init()
		register( "__DEFAULT__", function()
			DEFAULT_CHAT_FRAME:AddMessage( string.format( "|c%s%s Help|r", m.tagcolor, m.name ) )
			DEFAULT_CHAT_FRAME:AddMessage( "|c" .. m.tagcolor .. "/gi toggle|r|||c".. m.tagcolor .. "show|r|||c" .. m.tagcolor .. "hide|r Toggle/show/hide guild inventory" )
			DEFAULT_CHAT_FRAME:AddMessage( "|c" .. m.tagcolor .. "/gi clear|r Clear guild inventory" )
			DEFAULT_CHAT_FRAME:AddMessage( "|c" .. m.tagcolor .. "/gi refresh|r Refresh guild inventory" )
			DEFAULT_CHAT_FRAME:AddMessage( "|c" .. m.tagcolor .. "/gi broadcast|r Sends your version of the guild inventory to other members" )
		end )

		register( { "toggle", "t" }, function()
			m.gui.toggle()
		end )

		register( { "show", "s" }, function()
			m.gui.show()
		end )

		register( { "hide", "s" }, function()
			m.gui.hide()
		end )

		register( { "refresh", "r" }, function()
			m.msg.request_inventory( true )
		end )

		register( { "clear", "c" }, function()
			m.db.inventory = {}
		end )

		register( { "broadcast", "b" }, function()
			m.msg.send_inventory()
		end )

		register( { "versioncheck", "vc" }, function()
			m.msg.version_check()
		end )
	end

	return {
		register = register,
		init = init
	}
end

m.SlashCommand = M
return M
