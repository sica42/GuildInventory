---@class GuildInventory
GuildInventory = GuildInventory or {}

---@class GuildInventory
local m = GuildInventory

if m.Gui then return end

---@class FakeCursor: Frame
---@field icon Texture
---@field item Item
---@field slot_index integer

---@class InventoryGui
---@field show fun( tab: string? )
---@field hide fun()
---@field toggle fun()
---@field is_visible fun(): boolean
---@field refresh fun()
---@field comm fun( send: boolean )
---@field enable_bank fun( enabled: boolean )

local M = {}

local _G = getfenv()

---@param frame_builder FrameBuilderFactory
---@param ace_serializer AceSerializer
---@param notify Notifications
---@return InventoryGui
function M.new( frame_builder, ace_serializer, notify )
  local popup
  local slots = {}
  local is_dragging = false
  local offset = 0
  local refresh
  local search_str
  local inbox_frames = {}

  ---@type FakeCursor
  local fake_cursor

  ---@type GISlot|nil
  local selected_item

  ---@type InfoFrame
  local info_frame

  ---@type RequestFrame
  local request_frame

  ---@type InboxFrame
  local inbox_frame

  local ROWS = 5

  local function clear_cursor()
    if is_dragging then
      is_dragging = false
      fake_cursor.slot_index = nil
      fake_cursor:SetScript( "OnUpdate", nil )
      fake_cursor:Hide()
    end
  end

  ---@param item Item
  ---@param slot_index integer
  local function pickup_item( item, slot_index )
    is_dragging = true
    fake_cursor.icon:SetTexture( item.icon )
    fake_cursor.item = item
    fake_cursor.slot_index = slot_index

    fake_cursor:Show()
    fake_cursor:SetScript( "OnUpdate", function()
      local x, y = GetCursorPosition()
      local scale = UIParent:GetEffectiveScale()
      fake_cursor:SetPoint( "Center", UIParent, "BottomLeft", x / scale, y / scale )
    end )
  end

  local function sort_inventory()
    for _, item in ipairs( m.db.inventory ) do
      if not item.type then
        local _, _, _, _, _, type, sub_type = GetItemInfo( item.id )
        item.type = type
        item.sub_type = sub_type
      end
    end

    table.sort( m.db.inventory, function( a, b )
      if a.deleted and not b.deleted then
        return false
      elseif not a.deleted and b.deleted then
        return true
      elseif a.deleted and b.deleted then
        return false
      end

      if a.type ~= b.type then
        return a.type < b.type
      end

      if a.sub_type ~= b.sub_type then
        return a.sub_type < b.sub_type
      end

      return a.name < b.name
    end )

    for i, item in ipairs( m.db.inventory ) do
      if not item.deleted then
        item.slot = i
      end
    end

    refresh()
  end

  local function submit_request()
    local requests = {}

    for _, item in request_frame.items do
      local total = 0
      for _, data in item.data do
        total = total + data.count
      end

      if total < item.request_count then
        m.error( string.format( "You have requested %d %s, but only %d is available.", item.request_count, item.name, total ) )
        notify.add( string.format( "You have requested %d %s, but only %d is available.", item.request_count, item.name, total ), "Error", time(), 2 )
        return
      end

      if item.request_count == 0 then
        m.error( string.format( "You have requested 0 %s", item.name ) )
        notify.add( string.format( "You have requested 0 %s", item.name ), "Error", time(), 2 )
        return
      end

      local request_count = item.request_count

      local function add_request( player, count )
        requests[ player ] = requests[ player ] or {
          from = m.player,
          to = player,
          timestamp = time(),
          message = request_frame.input_message:GetText(),
          items = {}
        }
        table.insert( requests[ player ].items, {
          id = item.id,
          name = item.name,
          count = count
        } )
      end

      local done = false
      for player, data in item.data do
        if data.count >= item.request_count then
          add_request( player, request_count )
          request_count = 0
          done = true
          break
        end
      end

      if not done then
        local keys = {}
        for k in pairs( item.count ) do
          table.insert( keys, k )
        end
        table.sort( keys, function( a, b )
          return item.count[ a ] > item.count[ b ]
        end )

        for _, p in ipairs( keys ) do
          local count = item.data[ p ].count
          request_count = request_count - count
          add_request( p, request_count < 0 and count + request_count or count )
          if request_count <= 0 then
            break
          end
        end
      end
    end

    for _, request in requests do
      request.id = m.hash_string( ace_serializer.Serialize( M, request ) )

      table.insert( m.db.requests, request )
      m.msg.send_itemrequest( request )
      m.notify.add( string.format( "Request sent to %s", request.to ), m.NotificationType.Info, time(), 2 )
    end
    request_frame.clear()
  end


  ---@param parent Frame
  ---@param title string
  ---@param width integer?
  ---@param onclick function
  ---@return Tab
  local function create_tab( parent, title, width, onclick )
    ---@class Tab: Button
    local tab = CreateFrame( "Button", "GuildInventoryTab" .. title, parent )
    tab:SetScript( "OnClick", onclick )
    tab:SetScript( "OnReceiveDrag", clear_cursor )
    tab:SetWidth( width and width or 80 )
    tab:SetHeight( 26 )
    tab:SetBackdrop( {
      bgFile = "Interface/Buttons/WHITE8x8",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 }
    } )
    tab:SetBackdropColor( 0, 0, 0, 0.7 )

    local text = tab:CreateFontString( nil, "ARTWORK", "GameFontNormal" )
    text:SetPoint( "Center", tab, "Center", 0, 1 )
    text:SetText( title )

    local bottom = CreateFrame( "Frame", nil, tab )
    bottom:SetPoint( "TopLeft", tab, "BottomLeft", 4, 7 )
    bottom:SetPoint( "BottomRight", tab, "BottomRight", -4, 0 )
    bottom:SetBackdrop( { bgFile = "Interface/Buttons/WHITE8x8" } )
    bottom:SetBackdropColor( 0, 0, 0, 1 )

    tab.active = function( active )
      tab:Show()
      if active then
        text:SetTextColor( 1, 1, 1, 1 )
        bottom:SetPoint( "TopLeft", tab, "BottomLeft", 4, 7 )
        if tab == popup.tab_request then
          popup.tab_inbox.active( false )
        elseif tab == popup.tab_inbox then
          popup.tab_request.active( false )
        end
      else
        text:SetTextColor( 1, 0.82, 0, 1 )
        bottom:SetPoint( "TopLeft", tab, "BottomLeft", 4, 5 )
      end
    end

    return tab
  end

  

  ---@param parent Frame
  ---@param slot_index integer
  ---@return GISlot
  local function create_slot( parent, slot_index )
    ---@class GISlot: Button
    local slot_frame = CreateFrame( "Button", "GuildInventorySlot" .. slot_index, parent, "ItemButtonTemplate" )
    slot_frame:RegisterForDrag( "LeftButton" )
    slot_frame.slot_index = slot_index

    slot_frame:SetScript( "OnEnter", function()
      if this.item then
        GameTooltip:SetOwner( this, "ANCHOR_RIGHT" )
        GameTooltip:SetHyperlink( m.get_item_string( this.item ) )
      end
    end )

    slot_frame:SetScript( "OnLeave", function()
      GameTooltip:Hide()
    end )

    slot_frame:SetScript( "OnDragStart", function()
      if this.item then
        pickup_item( this.item, this.slot_index + offset )
      end
    end )

    slot_frame:SetScript( "OnReceiveDrag", function()
      if not slot_frame.check_cursor_item_add() and is_dragging then
        m.move_item( fake_cursor.slot_index, slot_frame.slot_index + offset )
        clear_cursor()
        refresh()
      end
    end )

    slot_frame:SetScript( "OnClick", function()
      if IsShiftKeyDown() and slot_frame.item then
        if ChatFrameEditBox:IsVisible() then
          ChatFrameEditBox:Insert( m.get_item_link( slot_frame.item ) )
          return
        end
      end

      if not slot_frame.check_cursor_item_add() then
        if slot_frame.item then
          slot_frame.pressed( not slot_frame.is_pressed )
          if slot_frame.is_pressed then
            info_frame.set( slot_frame.item, slot_frame.slot_index )
          else
            info_frame.clear()
          end
        elseif selected_item then
          selected_item.pressed( false )
          info_frame.clear()
        end
      end
    end )

    ---@return boolean
    slot_frame.check_cursor_item_add = function()
      if CursorHasItem() then
        ---@class DBItem
        local item = m.get_cursors_item()
        if item then
          m.add_item( item, slot_frame.slot_index + offset, true, true )
          refresh()
          if info_frame.slot_index == slot_frame.slot_index then
            info_frame.set( slot_frame.item, slot_frame.slot_index )
          end
          ClearCursor()
        end
        return true
      end

      return false
    end

    ---@param item DBItem
    slot_frame.set_item = function( item )
      local color = ITEM_QUALITY_COLORS[ item.quality ]
      local count = 0

      for _, c in pairs( item.data ) do
        count = count + c.count
      end

      SetItemButtonTexture( slot_frame, item.icon )
      SetItemButtonCount( slot_frame, count )
      SetItemButtonNormalTextureVertexColor( slot_frame, color.r, color.g, color.b )
      slot_frame.item = item
    end

    slot_frame.clear_item = function()
      SetItemButtonTexture( slot_frame, nil )
      SetItemButtonCount( slot_frame, 0 )
      SetItemButtonNormalTextureVertexColor( slot_frame, 1, 1, 1 )
      slot_frame.item = nil
      slot_frame.pressed( false )
    end

    ---@param state boolean
    slot_frame.pressed = function( state )
      if state then
        if selected_item then
          selected_item.pressed( false )
        end
        slot_frame.pressed_tex:Show()
        slot_frame.pressed_highlight:Show()
        slot_frame.is_pressed = true
        selected_item = slot_frame
      else
        slot_frame.pressed_tex:Hide()
        slot_frame.pressed_highlight:Hide()
        slot_frame.is_pressed = false
        selected_item = nil
      end
    end

    slot_frame.pressed_tex = slot_frame:CreateTexture( nil, "ARTWORK" )
    slot_frame.pressed_tex:SetTexture( "Interface\\Buttons\\UI-Quickslot-Depress" )
    slot_frame.pressed_tex:SetAllPoints()
    slot_frame.pressed_tex:Hide()

    slot_frame.pressed_highlight = slot_frame:CreateTexture( nil, "ARTWORK" )
    slot_frame.pressed_highlight:SetTexture( "Interface\\Buttons\\ButtonHilight-Square" )
    slot_frame.pressed_highlight:SetAllPoints()
    slot_frame.pressed_highlight:SetBlendMode( "ADD" )
    slot_frame.pressed_highlight:Hide()

    table.insert( slots, slot_frame )
    return slot_frame
  end

  ---@param parent InventoryFrame
  local function create_info_frame( parent )
    ---@class InfoFrame: Frame
    local info = frame_builder.new()
        :parent( parent )
        :point( "TopLeft", parent.inv_frame, "BottomLeft", 0, -10 )
        :point( "Right", parent.inv_frame, "Right", 0, 0 )
        :height( 120 )
        :frame_style( "TOOLTIP" )
        :backdrop( { bgFile = "Interface/Buttons/WHITE8x8" } )
        :backdrop_color( 0, 0, 0, 0.7 )
        :build()

    local btn_sync_inv = m.GuiElements.create_button( info, "Sync inventory items count", 150, function()
      if m.sync_count( "Inventory" ) then
        refresh()
      end
    end, clear_cursor )
    btn_sync_inv:SetPoint( "Center", info, "Center", 0, 15 )

    local btn_sync_bank = m.GuiElements.create_button( info, "Sync bank items count", 150, function()
      if m.sync_count( "Bank" ) then
        refresh()
      end
    end, clear_cursor )
    btn_sync_bank:SetPoint( "Center", info, "Center", 0, -15 )
    btn_sync_bank:Disable()
    info.btn_sync_bank = btn_sync_bank

    local text_item = info:CreateFontString( nil, "ARTWORK", "GameFontNormal" )
    text_item:SetPoint( "TopLeft", info, "TopLeft", 8, -8 )
    text_item:SetTextColor( 1, 1, 1 )
    text_item:SetJustifyH( "Left" )

    local function update_data()
      if info.input_count:GetText() == "" then info.input_count:SetText( "0" ) end
      if info.input_price:GetText() == "" then info.input_price:SetText( "0" ) end

      local count = tonumber( info.input_count:GetText() )
      if not count then
        info.input_count:SetTextColor( 1, 0, 0 )
        return
      end

      local price = m.parse_money( info.input_price:GetText() )
      if not price then
        info.input_price:SetTextColor( 1, 0, 0 )
        return
      end

      m.update_item_data( info.slot_index + offset, count, price, true )
      info.input_count:SetTextColor( 1, 1, 1 )
      info.input_count:ClearFocus()
      info.input_price:SetTextColor( 1, 1, 1 )
      info.input_price:ClearFocus()
      refresh()
      if count == 0 then
        slots[ info.slot_index ].pressed( false )
        info.clear()
      end
    end

    local btn_update = m.GuiElements.create_button( info, "Update", nil, update_data, clear_cursor )
    btn_update:SetPoint( "BottomRight", info, "BottomRight", -8, 10 )
    btn_update:Hide()

    local input_count = CreateFrame( "EditBox", "GuildInventoryInputCount", info, "InputBoxTemplate" )
    input_count:SetPoint( "BottomLeft", btn_update, "TopLeft", 8, 5 )
    input_count:SetWidth( 90 )
    input_count:SetHeight( 22 )
    input_count:SetAutoFocus( false )
    input_count:Hide()
    input_count:SetScript( "OnEnterPressed", update_data )
    input_count:SetScript( "OnReceiveDrag", clear_cursor )
    info.input_count = input_count

    local label_count = info:CreateFontString( nil, "ARTWORK", "GameFontNormalSmall" )
    label_count:SetPoint( "BottomLeft", input_count, "TopLeft", -5, 1 )
    label_count:SetTextColor( 1, 1, 1 )
    label_count:SetJustifyH( "Left" )
    label_count:SetText( "Your amount" )
    label_count:Hide()

    local input_price = CreateFrame( "EditBox", "GuildInventoryInputPrice", info, "InputBoxTemplate" )
    input_price:SetPoint( "BottomLeft", input_count, "TopLeft", 0, 15 )
    input_price:SetWidth( 90 )
    input_price:SetHeight( 22 )
    input_price:SetAutoFocus( false )
    input_price:Hide()
    input_price:SetScript( "OnEnterPressed", update_data )
    input_price:SetScript( "OnReceiveDrag", clear_cursor )
    info.input_price = input_price

    local label_price = info:CreateFontString( nil, "ARTWORK", "GameFontNormalSmall" )
    label_price:SetPoint( "BottomLeft", input_price, "TopLeft", -5, 1 )
    label_price:SetTextColor( 1, 1, 1 )
    label_price:SetJustifyH( "Left" )
    label_price:SetText( "Your price per item" )
    label_price:Hide()

    local label_gcount = info:CreateFontString( nil, "ARTWORK", "GameFontNormalSmall" )
    label_gcount:SetPoint( "TopLeft", text_item, "BottomLeft", 0, -5 )
    label_gcount:SetPoint( "Right", label_count, "TopLeft", -10, 0 )
    label_gcount:SetTextColor( 1, 1, 1 )
    label_gcount:SetJustifyH( "Left" )
    label_gcount:SetText( "Guild members amount" )
    label_gcount:Hide()

    local text_gcount = info:CreateFontString( nil, "ARTWORK", "GameFontNormalSmall" )
    text_gcount:SetPoint( "TopLeft", label_gcount, "BottomLeft", 0, -5 )
    text_gcount:SetPoint( "Right", label_count, "Left", -5, 0 )
    text_gcount:SetPoint( "Bottom", info, "Bottom", 0, 8 )
    text_gcount:SetTextColor( 1, 1, 1 )
    text_gcount:SetNonSpaceWrap( false )
    text_gcount:SetJustifyH( "Left" )
    text_gcount:SetJustifyV( "Top" )

    ---@param item Item
    ---@param slot_index integer
    info.set = function( item, slot_index )
      info.slot_index = slot_index
      info.item = item

      for _, e in { input_count, label_count, input_price, label_price, label_gcount, btn_update } do
        e:Show()
      end

      text_item:SetText( m.get_item_name_colorized( item ) )
      input_count:SetText( item.data[ m.player ] and item.data[ m.player ].count or "0" )
      input_price:SetText( item.data[ m.player ] and m.format_money( item.data[ m.player ].price, true ) or "0" )
      btn_sync_bank:Hide()
      btn_sync_inv:Hide()

      local str = ""
      for player, data in pairs( item.data ) do
        if player ~= m.player then
          if data.price and data.price > 0 then
            str = str .. string.format( "%s|c00000000n|r|cff00ff00%d|r|c00000000i|r@|c00000000i|r%s, ", player, data.count, m.format_money( data.price ) )
          else
            str = str .. string.format( "%s|c00000000n|r%d, ", player, data.count )
          end
        end
      end
      text_gcount:SetText( string.match( str, "(.-), $" ) )
    end

    info.clear = function()
      for _, e in { input_count, label_count, input_price, label_price, label_gcount, btn_update } do
        e:Hide()
      end

      text_item:SetText( "" )
      text_gcount:SetText( "" )
      input_count:SetText( "" )
      input_price:SetText( "" )
      btn_sync_bank:Show()
      btn_sync_inv:Show()
    end

    info_frame = info
  end

  ---@param parent Frame
  ---@param index integer
  local function create_request_item( parent, index )
    ---@class RequestItemFrame: Button
    local frame = CreateFrame( "Button", nil, parent )
    frame:SetWidth( 162 )
    frame:SetHeight( 32 )
    frame:Hide()
    frame.slot_index = index

    frame:SetScript( "OnReceiveDrag", function() frame.on_receive_drag() end )

    local icon_frame = CreateFrame( "Frame", nil, frame )
    icon_frame:SetPoint( "TopLeft", frame, "TopLeft", 0, 0 )
    icon_frame:SetWidth( 32 )
    icon_frame:SetHeight( 32 )

    local icon = icon_frame:CreateTexture( nil, "ARTWORK" )
    icon:SetAllPoints( icon_frame )

    local text_item = frame:CreateFontString( nil, "ARTWORK", "GameFontNormalSmall" )
    text_item:SetPoint( "TopLeft", icon_frame, "TopRight", 5, 0 )
    text_item:SetWidth( 100 )
    text_item:SetHeight( 16 )
    text_item:SetTextColor( 1, 1, 1 )
    text_item:SetJustifyH( "Left" )

    local btn_remove = CreateFrame( "Button", nil, frame, "UIPanelCloseButton" )
    btn_remove:SetPoint( "TopRight", frame, "TopRight", 1, 3 )
    btn_remove:SetScale( 0.6 )
    btn_remove:SetHitRectInsets( 4, 4, 4, 4 )
    btn_remove:SetScript( "OnClick", function()
      table.remove( request_frame.items, frame.slot_index + request_frame.offset )
      request_frame.refresh_items()
    end )
    btn_remove:SetScript( "OnReceiveDrag", function() frame.on_receive_drag() end )

    local input_count = CreateFrame( "EditBox", "GuildInventoryRequestItemCount" .. index, frame, "InputBoxTemplate" )
    frame.input_count = input_count
    input_count:SetPoint( "BottomRight", frame, "BottomRight", -5, 1 )
    input_count:SetWidth( 30 )
    input_count:SetHeight( 22 )
    input_count:SetAutoFocus( false )
    input_count:SetScale( 0.8 )
    input_count:SetScript( "OnReceiveDrag", function() frame.on_receive_drag() end )
    input_count:SetScript( "OnTextChanged", function()
      request_frame.items[ frame.slot_index + request_frame.offset ].request_count = tonumber( input_count:GetText() ) or 0
    end )
    input_count:SetScript( "OnEnterPressed", function()
      input_count:ClearFocus()
    end )

    local label_amount = frame:CreateFontString( nil, "ARTWORK", "GameFontNormalSmall" )
    label_amount:SetPoint( "TopRight", input_count, "TopLeft", -8, -3 )
    label_amount:SetTextColor( 1, 1, 1 )
    label_amount:SetJustifyH( "Right" )
    label_amount:SetText( "Amount" )

    frame.on_receive_drag = function()
      if is_dragging then
        request_frame.add_item( fake_cursor.item )
        clear_cursor()
      end
    end

    ---@param item RequestItem
    frame.set_item = function( item )
      icon:SetTexture( item.icon )
      text_item:SetText( m.get_item_name_colorized( item ) )
      input_count:SetText( tostring( item.request_count ) )
      input_count:ClearFocus()
      frame:Show()
    end

    return frame
  end

  ---@param parent InventoryFrame
  local function create_request_frame( parent )
    ---@class RequestFrame: Frame
    local frame = frame_builder.new()
        :parent( parent )
        :point( "TopLeft", parent, "TopLeft", 427, -55 )
        :width( 200 )
        :height( 330 )
        :frame_style( "TOOLTIP" )
        :backdrop( { bgFile = "Interface/Buttons/WHITE8x8" } )
        :backdrop_color( 0, 0, 0, 0.7 )
        :hidden()
        :build()

    local border_items = CreateFrame( "Frame", nil, frame )
    border_items:SetPoint( "TopLeft", frame, "TopLeft", 10, -25 )
    border_items:SetPoint( "BottomRight", frame, "TopRight", -10, -187 )
    border_items:EnableMouse( true )
    border_items:EnableMouseWheel( true )
    border_items:SetBackdrop( {
      bgFile = "Interface/Buttons/WHITE8x8",
      edgeFile = "Interface/Buttons/WHITE8x8",
      edgeSize = m.get_perfect_pixel(),
      insets = { left = 1, right = 1, top = 1, bottom = 1 }
    } )
    border_items:SetBackdropColor( 0, 0, 0, 1 )
    border_items:SetBackdropBorderColor( 0.7, 0.7, 0.7, 1 )
    border_items:SetScript( "OnReceiveDrag", function()
      if is_dragging then
        frame.add_item( fake_cursor.item )
        clear_cursor()
      end
    end )
    border_items:SetScript( "OnMouseWheel", function()
      local value = frame.scroll_bar_items:GetValue() - arg1
      frame.scroll_bar_items:SetValue( value )
    end )

    local label_info = border_items:CreateFontString( nil, "ARTWORK", "GameFontNormal" )
    frame.label_info = label_info
    label_info:SetPoint( "Center", border_items, "Center", 0, 0 )
    label_info:SetText( "Drag items here to add" )

    local label_items = frame:CreateFontString( nil, "ARTWORK", "GameFontNormalSmall" )
    label_items:SetPoint( "BottomLeft", border_items, "TopLeft", 0, 2 )
    label_items:SetTextColor( 1, 1, 1 )
    label_items:SetJustifyH( "Left" )
    label_items:SetText( "Items" )

    local scroll_bar_items = CreateFrame( "Slider", "GuildInventoryRequestItemsScrollBar", border_items, "UIPanelScrollBarTemplate" )
    frame.scroll_bar_items = scroll_bar_items
    scroll_bar_items:SetPoint( "TopRight", border_items, "TopRight", -1, -17 )
    scroll_bar_items:SetPoint( "Bottom", border_items, "Bottom", 0, 16.5 )
    scroll_bar_items:SetMinMaxValues( 0, 0 )
    scroll_bar_items:SetValueStep( 1 )
    scroll_bar_items:SetScript( "OnValueChanged", function()
      frame.offset = arg1
      frame.refresh_items()
    end )

    frame.offset = 0

    ---@type table<integer, RequestItem>
    frame.items = {}

    frame.frame_items = {}
    for i = 1, 5 do
      local item = create_request_item( border_items, i )
      item:SetPoint( "TopLeft", border_items, "TopLeft", 1, ((i - 1) * -32) - 1 )
      table.insert( frame.frame_items, item )
    end

    local border_message = CreateFrame( "Frame", nil, frame )
    border_message:SetPoint( "TopLeft", frame, "TopLeft", 10, -215 )
    border_message:SetPoint( "BottomRight", frame, "TopRight", -10, -263 )
    border_message:SetBackdrop( {
      bgFile = "Interface/Buttons/WHITE8x8",
      edgeFile = "Interface/Buttons/WHITE8x8",
      edgeSize = m.get_perfect_pixel(),
      insets = { left = 1, right = 1, top = 1, bottom = 1 }
    } )
    border_message:SetBackdropColor( 0, 0, 0, 1 )
    border_message:SetBackdropBorderColor( 0.7, 0.7, 0.7, 1 )

    local frame_message = CreateFrame( "ScrollFrame", "GuildInventoryMessageScrollFrame", border_message, "UIPanelScrollFrameTemplate" )
    frame_message:SetPoint( "TopLeft", border_message, "TopLeft", 1, -1 )
    frame_message:SetPoint( "BottomRight", border_message, "BottomRight", -23, 1 )
    frame_message:EnableMouse( true )
    frame_message:SetScript( "OnReceiveDrag", clear_cursor )
    frame_message:SetScript( "OnMouseDown", function()
      frame.input_message:SetFocus()
    end )

    local input_message = CreateFrame( "EditBox", "MyMultiLineEditBox", frame_message )
    frame.input_message = input_message
    input_message:SetPoint( "TopLeft", border_message, "TopLeft", 1, -1 )
    input_message:SetMultiLine( true )
    input_message:SetFontObject( GameFontHighlightSmall )
    input_message:SetWidth( 155 )
    input_message:SetAutoFocus( false )

    input_message:SetScript( "OnEscapePressed", function()
      this:ClearFocus()
    end )
    input_message:SetScript( "OnCursorChanged", function()
      ScrollingEdit_OnCursorChanged( arg1, arg2, arg3, arg4 )
    end )
    input_message:SetScript( "OnTextChanged", function()
      ScrollingEdit_OnTextChanged()
    end )
    input_message:SetScript( "OnUpdate", function()
      ScrollingEdit_OnUpdate()
    end )

    frame_message:SetScrollChild( input_message )

    local label_message = frame:CreateFontString( nil, "ARTWORK", "GameFontNormalSmall" )
    label_message:SetPoint( "BottomLeft", border_message, "TopLeft", 0, 2 )
    label_message:SetTextColor( 1, 1, 1 )
    label_message:SetJustifyH( "Left" )
    label_message:SetText( "Message" )

    local btn_send = m.GuiElements.create_button( frame, "Send Request", nil, submit_request, clear_cursor )
    btn_send:SetPoint( "Bottom", frame, "Bottom", 0, 10 )

    ---@param item Item
    frame.add_item = function( item )
      ---@type RequestItem
      local ritem = {
        id = item.id,
        name = item.name,
        icon = item.icon,
        quality = item.quality,
        data = item.data,
        request_count = 0
      }

      table.insert( frame.items, ritem )
      frame.refresh_items()

      local _, max = frame.scroll_bar_items:GetMinMaxValues()
      frame.scroll_bar_items:SetValue( max )

      frame.frame_items[ math.min( 5, getn( frame.items ) ) ].input_count:SetFocus()
      frame.label_info:Hide()
    end

    frame.refresh_items = function()
      local max = math.max( 0, getn( frame.items ) - 5 )
      local value = math.min( max, frame.scroll_bar_items:GetValue() )
      frame.scroll_bar_items:SetMinMaxValues( 0, max )

      for slot = 1, 5 do
        local item = frame.items[ slot + frame.offset ]
        if item then
          frame.frame_items[ slot ].set_item( item )
        else
          frame.frame_items[ slot ]:Hide()
        end
      end

      local name = frame.scroll_bar_items:GetName()
      if value == 0 then
        _G[ name .. "ScrollUpButton" ]:Disable()
      else
        _G[ name .. "ScrollUpButton" ]:Enable()
      end

      if value == max then
        _G[ name .. "ScrollDownButton" ]:Disable()
      else
        _G[ name .. "ScrollDownButton" ]:Enable()
      end
    end

    frame.clear = function()
      input_message:SetText( "" )
      frame.items = {}
      frame.refresh_items()
    end

    frame.refresh_items()

    request_frame = frame
  end

  ---@param parent Frame
  local function create_inbox_item( parent )
    for i = getn( inbox_frames ), 1, -1 do
      if not inbox_frames[ i ].is_used then
        inbox_frames[ i ].is_used = true
        return inbox_frames[ i ]
      end
    end

    ---@class InboxItem: Frame
    local frame = CreateFrame( "Frame", nil, parent )
    frame:SetWidth( 180 )
    frame:SetHeight( 90 )
    frame:SetBackdrop( { bgFile = "Interface/Buttons/WHITE8x8" } )
    frame:SetBackdropColor( 0.2, 0.2, 0.2, 0.5 )
    frame.is_used = true

    local btn_remove = CreateFrame( "Button", nil, frame, "UIPanelCloseButton" )
    btn_remove:SetPoint( "TopRight", frame, "TopRight", -3, 3 )
    btn_remove:SetScale( 0.6 )
    btn_remove:SetHitRectInsets( 4, 4, 4, 4 )
    btn_remove:SetScript( "OnClick", function()
      table.remove( m.db.requests, frame.index )
      inbox_frame.refresh()
    end )
    btn_remove:SetScript( "OnReceiveDrag", clear_cursor )

    local text_from = frame:CreateFontString( nil, "ARTWORK", "GameFontNormal" )
    text_from:SetPoint( "TopLeft", frame, "TopLeft", 4, -4 )

    local text_items = frame:CreateFontString( nil, "ARTWORK", "GameFontHighlightSmall" )
    text_items:SetPoint( "TopLeft", frame, "TopLeft", 4, -20 )
    text_items:SetWidth( 170 )
    text_items:SetJustifyV( "Top" )
    text_items:SetJustifyH( "Left" )
    text_items:SetNonSpaceWrap( true )

    local text_message = frame:CreateFontString( nil, "ARTWORK", "GameFontHighlightSmall" )
    text_message:SetPoint( "TopLeft", text_items, "BottomLeft", 0, -10 )
    text_message:SetWidth( 170 )
    text_message:SetJustifyV( "Top" )
    text_message:SetJustifyH( "Left" )

    local btn_done = m.GuiElements.create_button( frame, "Completed", nil, function()
      local updated_items = {}

      for _, ritem in frame.request.items do
        local item = m.find( ritem.id, m.db.inventory, "id" )
        if item and item.data[ m.player ].count then
          item.data[ m.player ].count = item.data[ m.player ].count - ritem.count
          m.add_item( item )
          table.insert( updated_items, item )
        end
      end

      m.msg.send_items( updated_items )
      m.notify.add( string.format( "Request to %s fulfilled.", frame.request.to ), m.NotificationType.Info, time() )
      table.remove( m.db.requests, frame.index )
      inbox_frame.refresh()
      refresh()
    end, clear_cursor )

    btn_done:SetScale( 0.8 )
    btn_done:SetPoint( "Center", frame, "Bottom", 0, 16 )


    ---@param request RequestData
    ---@param index integer
    frame.set = function( request, index )
      frame.index = index
      frame.request = request

      text_from:SetText( "Request from " .. request.from )

      local items = ""
      for _, item in request.items do
        items = items .. string.format( "%dx %s, ", item.count, item.name )
      end

      if request.timestamp == 1745965309 then
        items = items .. "2x Falaffel, 5x Boots, "
      end
      text_items:SetText( string.match( items, "(.-), $" ) )
      text_message:SetText( request.message )

      frame:SetHeight( 55 + text_items:GetHeight() + text_message:GetHeight() )
      frame:Show()
    end


    table.insert( inbox_frames, frame )
    return frame
  end

  ---@param parent InventoryFrame
  local function create_inbox_frame( parent )
    ---@class InboxFrame: Frame
    local frame = frame_builder.new()
        :parent( parent )
        :point( "TopLeft", parent, "TopLeft", 427, -55 )
        :width( 200 )
        :height( 330 )
        :frame_style( "TOOLTIP" )
        :backdrop( { bgFile = "Interface/Buttons/WHITE8x8" } )
        :backdrop_color( 0, 0, 0, 0.7 )
        :hidden()
        :build()

    local inbox = CreateFrame( "Frame", nil, frame )
    inbox:SetWidth( 100 )
    inbox:SetHeight( 1 )

    local scroll_frame = CreateFrame( "ScrollFrame", "GuildInventoryInboxScrollFrame", frame, "UIPanelScrollFrameTemplate" )
    scroll_frame:SetPoint( "TopLeft", frame, "TopLeft", 5, -15 )
    scroll_frame:SetPoint( "BottomRight", frame, "BottomRight", -20, 5 )

    _G[ "GuildInventoryInboxScrollFrameScrollBar" ]:ClearAllPoints()
    _G[ "GuildInventoryInboxScrollFrameScrollBar" ]:SetPoint( "TopLeft", scroll_frame, "TopRight", 0, -16 )
    _G[ "GuildInventoryInboxScrollFrameScrollBar" ]:SetPoint( "Bottom", scroll_frame, "Bottom", 0, 15 )

    scroll_frame:SetScrollChild( inbox )

    frame.refresh = function()
      local top = 0
      for _, f in inbox_frames do
        f.is_used = false
        f:Hide()
      end

      for index, request in m.db.requests do
        ---@type RequestData
        request = request
        if request.to == m.player then
          request.read = true
          local r = create_inbox_item( inbox )
          r:SetPoint( "TopLeft", inbox, "TopLeft", 0, -top )
          r.set( request, index )

          top = top + r:GetHeight() + 1
        end
      end

      inbox:SetHeight( top - 2 )
    end

    frame.show = function()
      frame:Show()
      frame.refresh()
    end

    inbox_frame = frame
  end


  local function create_frame()
    ---@class InventoryFrame: Frame
    local frame = frame_builder.new()
        :name( "GuildInventoryFrame" )
        :title( string.format( "GuildInventory v%s", m.version ) )
        :frame_style( "TOOLTIP" )
        :backdrop_color( 0, 0, 0, 1 )
        :close_button()
        :width( 427 )
        :height( 396 )
        :movable()
        :esc()
        :hidden()
        :build()

    frame:SetScript( "OnLeave", function()
      if MouseIsOver( frame ) then return end
      clear_cursor()
    end )
    frame:SetScript( "OnReceiveDrag", clear_cursor )

    local btn_tradeskills = m.GuiElements.tiny_button( frame, "T", "Toggle Guild Tradeskills" )
    btn_tradeskills:SetPoint( "TopRight", frame, "TopRight", -20, -4 )
    btn_tradeskills:SetScript( "OnClick", function()
      m.tsgui.toggle()
    end )

    local indicator = CreateFrame( "Frame", nil, frame )
    indicator:SetPoint( "Center", frame, "TopRight", -45, -13 )
    indicator:SetWidth( 15 )
    indicator:SetHeight( 15 )

    local indicator_tex = indicator:CreateTexture( nil, "ARTWORK" )
    indicator_tex:SetAllPoints( indicator )
    indicator_tex:SetTexture( "Interface\\TargetingFrame\\UI-TargetingFrame-AttackBackground" )
    indicator_tex:SetVertexColor( 0, 1, 0, 0 )

    frame.comm = function( send )
      if send then
        indicator_tex:SetVertexColor( 0, 1, 0, .9 )
      else
        indicator_tex:SetVertexColor( 0, 1, 1, .9 )
      end
      local timer = 0
      indicator:SetScript( "OnUpdate", function()
        timer = timer + 1
        if timer >= 20 then
          indicator:SetScript( "OnUpdate", nil )
          indicator_tex:SetVertexColor( 0, 0, 0, 0 )
        end
      end )
    end

    local label_search = frame:CreateFontString( nil, "ARTWORK", "GameFontNormal" )
    label_search:SetPoint( "TopLeft", frame, "TopLeft", 12, -35 )
    label_search:SetTextColor( 1, 1, 1 )
    label_search:SetJustifyH( "Left" )
    label_search:SetText( "Search" )

    local input_search = CreateFrame( "EditBox", "GuildInventoryInputSearch", frame, "InputBoxTemplate" )
    frame.search = input_search
    input_search:SetPoint( "TopLeft", frame, "TopLeft", 50, -29 )
    input_search:SetWidth( 130 )
    input_search:SetHeight( 22 )
    input_search:SetAutoFocus( false )

    input_search:SetScript( "OnReceiveDrag", clear_cursor )
    input_search:SetScript( "OnTextChanged", function()
      if input_search:GetText() ~= "" then
        frame.btn_cancel:Show()
      else
        frame.btn_cancel:Hide()
      end
    end )

    input_search:SetScript( "OnEnterPressed", function()
      search_str = input_search:GetText()
      refresh()
    end )

    local btn_cancel = m.GuiElements.create_button( frame, "Cancel", 24, function()
      input_search:SetText( "" )
      search_str = nil
      refresh()
    end, clear_cursor )
    btn_cancel:SetPoint( "TopRight", input_search, "TopRight", 6, 4 )
    btn_cancel:SetFrameLevel( 10 )
    btn_cancel:Hide()
    frame.btn_cancel = btn_cancel

    local btn_search = m.GuiElements.create_button( frame, "Search", 60, function()
      search_str = input_search:GetText()
      refresh()
    end, clear_cursor )
    btn_search:SetPoint( "TopLeft", input_search, "TopRight", 5, 1 )

    local btn_sort = m.GuiElements.create_button( frame, "Sort", 60, sort_inventory, clear_cursor )
    btn_sort:SetPoint( "TopLeft", btn_search, "TopRight", 5, 0 )

    frame.btn_request = m.GuiElements.create_button( frame, "Request >>", 70, function()
      if request_frame:IsVisible() or inbox_frame:IsVisible() then
        this:SetText( "Request >>" )
        frame.tab_request:Hide()
        frame.tab_inbox:Hide()
        request_frame:Hide()
        inbox_frame:Hide()
        frame:SetWidth( 427 )
      else
        this:SetText( "Request <<" )
        frame.tab_request.active( true )
        frame:SetWidth( 638 )
        request_frame:Show()
      end
    end, clear_cursor )
    frame.btn_request:SetPoint( "TopRight", frame, "TopLeft", 417, -28 )

    local inv_frame = CreateFrame( "Frame", nil, frame )
    frame.inv_frame = inv_frame
    inv_frame:EnableMouse( true )
    inv_frame:EnableMouseWheel( true )
    inv_frame:SetPoint( "TopLeft", frame, "TopLeft", 10, -55 )
    inv_frame:SetWidth( 407 )
    inv_frame:SetHeight( 200 )
    inv_frame:SetBackdrop( {
      bgFile = "Interface/Buttons/WHITE8x8",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 }
    } )
    inv_frame:SetBackdropColor( 0, 0, 0, 1 )
    inv_frame:SetScript( "OnMouseWheel", function()
      local value = frame.scroll_bar:GetValue() - arg1
      frame.scroll_bar:SetValue( value )
    end )

    local inv = CreateFrame( "Frame", nil, inv_frame )
    frame.inventory = inv
    inv:SetPoint( "TopLeft", inv_frame, "TopLeft", 6, -5 )
    inv:SetWidth( 380 )
    inv:SetHeight( 190 )
    inv:SetScript( "OnReceiveDrag", clear_cursor )

    local scroll_bar = CreateFrame( "Slider", "GuildInventoryScrollBar", inv_frame, "UIPanelScrollBarTemplate" )
    frame.scroll_bar = scroll_bar
    scroll_bar:SetPoint( "TopRight", inv_frame, "TopRight", -5, -20 )
    scroll_bar:SetPoint( "Bottom", inv_frame, "Bottom", 0, 20 )
    scroll_bar:SetMinMaxValues( 0, math.max( 0, (m.get_num_slots() - 50) / 10 ) )
    scroll_bar:SetValueStep( 1 )
    scroll_bar:SetScript( "OnValueChanged", function()
      offset = arg1 * 10
      refresh()
    end )

    scroll_bar:SetScript( "OnReceiveDrag", clear_cursor )
    for _, child in ipairs( { scroll_bar:GetChildren() } ) do
      ---@type Frame
      child = child

      if child:IsMouseEnabled() then
        child:SetScript( "OnReceiveDrag", clear_cursor )
      end
    end

    create_info_frame( frame )

    frame.tab_request = create_tab( frame, "Request", 80, function()
      frame.tab_request.active( true )
      frame.tab_inbox.active( false )
      inbox_frame:Hide()
      request_frame:Show()
    end )
    frame.tab_request:SetPoint( "TopLeft", frame, "TopLeft", 435, -38 )
    frame.tab_request:Hide()
    frame.tab_inbox = create_tab( frame, "Inbox", 80, function()
      frame.tab_request.active( false )
      frame.tab_inbox.active( true )
      request_frame:Hide()
      inbox_frame.refresh()
      inbox_frame.show()
    end )
    frame.tab_inbox:SetPoint( "Left", frame.tab_request, "Right", 3, 0 )
    frame.tab_inbox:Hide()

    create_request_frame( frame )
    create_inbox_frame( frame )

    for i = 1, ROWS * 10 do
      local x = ((mod( i, 10 ) == 0 and 10 or mod( i, 10 )) - 1) * 38
      local y = math.floor( (i - 1) / 10 ) * -38
      slots[ i ] = create_slot( inv, i )
      slots[ i ]:SetPoint( "TopLeft", inv, "TopLeft", x, y )
    end

    ---@class FakeCursor
    fake_cursor = CreateFrame( "Frame", nil, UIParent )
    fake_cursor:SetFrameStrata( "TOOLTIP" )
    fake_cursor:SetWidth( 32 )
    fake_cursor:SetHeight( 32 )
    fake_cursor.icon = fake_cursor:CreateTexture( nil, "OVERLAY" )
    fake_cursor.icon:SetAllPoints()
    fake_cursor:Hide()
    return frame
  end

  function refresh()
    local selected_slot = selected_item and selected_item.item.slot - offset or nil
    local now = time()

    for i = 1, ROWS * 10 do
      local slot = i + offset
      local item, index = m.find( slot, m.db.inventory, "slot" )

      if item then
        slots[ i ].set_item( item )
        slots[ i ].pressed( false )

        if search_str then
          if string.find( string.upper( item.name ), string.upper( search_str ), nil, true ) then
            SetItemButtonDesaturated( slots[ i ] )
          else
            SetItemButtonDesaturated( slots[ i ], true )
          end
        else
          SetItemButtonDesaturated( slots[ i ] )
        end
        if item.deleted and now >= item.deleted + 172800 then
          table.remove( m.db.inventory, index )
        end
      else
        slots[ i ].clear_item()
      end
    end

    if selected_slot then
      if selected_slot > 0 and selected_slot <= ROWS * 10 then
        slots[ selected_slot ].pressed( true )
      else
        info_frame.clear()
      end
    end

    local max = math.max( 0, (m.get_num_slots() - 50) / 10 )
    local value = math.min( max, popup.scroll_bar:GetValue() )
    popup.scroll_bar:SetMinMaxValues( 0, max )

    if value == 0 then
      _G[ "GuildInventoryScrollBarScrollUpButton" ]:Disable()
    else
      _G[ "GuildInventoryScrollBarScrollUpButton" ]:Enable()
    end

    if value == max then
      _G[ "GuildInventoryScrollBarScrollDownButton" ]:Disable()
    else
      _G[ "GuildInventoryScrollBarScrollDownButton" ]:Enable()
    end
  end

  local function enable_bank( enabled )
    if enabled then
      info_frame.btn_sync_bank:Enable()
    else
      info_frame.btn_sync_bank:Disable()
    end
  end

  local function show( tab )
    if not popup then
      popup = create_frame()
    end

    enable_bank( m.bank_open )
    if selected_item then
      selected_item.pressed( false )
      selected_item = nil
    end
    info_frame.clear()
    popup.scroll_bar:SetValue( offset )

    if tab == "Inbox" then
      popup.btn_request:SetText( "Request <<" )
      popup.tab_inbox.active( true )
      popup:SetWidth( 638 )
      request_frame:Hide()
      inbox_frame.show()
    else
      popup.btn_request:SetText( "Request >>" )
      popup.tab_request:Hide()
      popup.tab_inbox:Hide()
      popup:SetWidth( 427 )
      request_frame:Hide()
      inbox_frame:Hide()
    end

    popup:Show()
    refresh()
  end

  local function hide()
    if popup then
      popup:Hide()
    end
  end

  local function toggle()
    if popup and popup:IsVisible() then
      popup:Hide()
    else
      show()
    end
  end

  local function is_visible()
    return popup and popup:IsVisible() or false
  end

  local function comm( send )
    if popup and popup:IsVisible() then
      popup.comm( send )
    end
  end

  ---@type InventoryGui
  return {
    show = show,
    hide = hide,
    toggle = toggle,
    is_visible = is_visible,
    refresh = refresh,
    comm = comm,
    enable_bank = enable_bank
  }
end

m.Gui = M
return M
