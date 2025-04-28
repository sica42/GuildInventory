---@class GuildInventory
GuildInventory = GuildInventory or {}
GuildInventory.name = "GuildInventory"
GuildInventory.prefix = "GUILDINV"
GuildInventory.tagcolor = "FF8B3EE2"
GuildInventory.events = {}
GuildInventory.debug_enabled = false

BINDING_HEADER_GUILDINVENTORY = "GuildInventory"

---@class Item
---@field id integer
---@field name string
---@field icon string
---@field quality integer
---@field count table<string, integer>

---@class DBItem: Item
---@field slot integer
---@field deleted integer?

---@class GuildInventory
local m = GuildInventory

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
    m.msg = m.MessageHandler.new()
    m.version = GetAddOnMetadata( m.name, "Version" )
    m.info( string.format( "(v%s) Loaded", m.version ) )
  end
end

function GuildInventory.events.PLAYER_LOGIN()
  GuildInventoryDB = GuildInventoryDB or {}
  m.db = GuildInventoryDB
  m.db.inventory = m.db.inventory or {}
  m.player = UnitName( "player" )
  m.player_class = UnitClass( "player" )

  ---@type InventoryGui
  m.gui = m.Gui.new()

  ---@type SlashCommand
  m.slash_command = m.SlashCommand.new( m.name, { "gi", "guildinventory" } )
  m.slash_command.init()

  ---@type MessageHandler
  m.msg.request_inventory()
end

function GuildInventory.events.CHAT_MSG_ADDON()
  if arg1 == m.prefix and arg4 ~= m.player then
    m.msg.on_message( arg2, arg4 )
  end
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

function GuildInventory.get_cursors_item()
  local function scan_bags( bag_start, bag_end )
    for bag = bag_start, bag_end do
      local slots = GetContainerNumSlots( bag )
      for slot = 1, slots do
        local texture, item_count, locked = GetContainerItemInfo( bag, slot )
        if locked then
          local item_link = GetContainerItemLink( bag, slot )
          local item_id = m.get_item_id( item_link )

          if item_id then
            ---@type Item
            return {
              id = item_id,
              name = m.get_item_name( item_link ),
              quality = m.get_item_quality( item_id ),
              icon = texture,
              count = {
                [ m.player ] = item_count
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

---@param item Item
---@param slot integer?
---@param broadcast boolean?
---@param add_count boolean?
function GuildInventory.add_item( item, slot, broadcast, add_count )
  ---@type DBItem|nil
  local db_item = m.find( item.name, m.db.inventory, "name" )

  if db_item then
    if add_count then
      db_item.count[ m.player ] = db_item.count[ m.player ] and db_item.count[ m.player ] + item.count[ m.player ] or item.count[ m.player ]
    end
    for player, count in pairs( item.count ) do
      if not db_item.count[ player ] then
        db_item.count[ player ] = count
      else
        if db_item.count[ player ] and db_item.count[ player ] ~= count then
          db_item.count[ player ] = count
        end
      end
    end

    if db_item.deleted then
      db_item.deleted = nil
      db_item.slot = (slot and db_item.id == item.id) and slot or m.find_empty_slot()
    end

    if m.count( item.count ) == 0 then
      db_item.slot = 0
      db_item.deleted = time()
    end

    if broadcast then m.msg.send_item( db_item ) end
    return
  else
    if m.count( item.count ) == 0 then return end
    if slot then
      db_item = m.find( slot, m.db.inventory, "slot" )
      if db_item and db_item.id ~= item.id then
        print("find new slot")
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
      count = item.count,
      slot = slot,
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
function GuildInventory.update_item_count( slot_index, count )
  ---@type DBItem|nil
  local db_item, index = m.find( slot_index, m.db.inventory, "slot" )

  if db_item and db_item.count[ m.player ] ~= count then
    db_item.count[ m.player ] = count > 0 and count or nil

    if m.count( db_item.count ) == 0 then
      --table.remove( m.db.inventory, index )
      db_item.slot = 0
      db_item.deleted = time()
    end

    m.msg.send_item( db_item )
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
        local item_name = m.get_item_name( GetContainerItemLink( bag, slot ) )
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
    if item.count[ m.player ] then
      local count = 0
      if loc == "Inventory" then
        count = m.find_item_count_bag( 0, 4, item.name )
      elseif loc == "Bank" then
        count = m.find_item_count_bag( -1, -1, item.name )
        count = count + m.find_item_count_bag( 5, 10, item.name )
      end
      if count > 0 and count ~= item.count[ m.player ] then
        item.count[ m.player ] = count
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

GuildInventory:init()
