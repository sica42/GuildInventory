---@class GuildInventory
GuildInventory = GuildInventory or {}

---@class GuildInventory
local m = GuildInventory

if m.Gui then return end

---@class InventoryGui
---@field show fun()
---@field hide fun()
---@field toggle fun()
---@field is_visible fun(): boolean
---@field refresh fun()
---@field comm fun( send: boolean )
---@field enable_bank fun( enabled: boolean )
local M = {}

_G = getfenv()

function M.new()
  local popup
  local slots = {}
  local is_dragging = false
  local offset = 0
  local refresh
  local search_str

  ---@type FakeCursor
  local fake_cursor

  ---@type GISlot|nil
  local selected_item

  ---@type InfoFrame
  local info_frame

  local ROWS = 5

  local function clear_cursor()
    if is_dragging then
      is_dragging = false
      fake_cursor.slot_index = nil
      fake_cursor:SetScript( "OnUpdate", nil )
      fake_cursor:Hide()
    end
  end

  local function pickup_item( icon, slot_index )
    is_dragging = true
    fake_cursor.icon:SetTexture( icon )
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

  ---@param parent Frame
  ---@param title string
  ---@return Frame
  local function create_titlebar( parent, title )
    local frame = CreateFrame( "Frame", nil, parent )
    frame:SetPoint( "TopLeft", parent, "TopLeft", 5, -5 )
    frame:SetPoint( "BottomRight", parent, "TopRight", -5, -24 )
    frame:SetBackdrop( { bgFile = "Interface/Buttons/WHITE8x8" } )
    frame:SetBackdropColor( 0, 0, 0, 1 )

    local bottom_border = frame:CreateTexture( nil, "ARTWORK" )
    bottom_border:SetTexture( .6, .6, .6, 1 )
    bottom_border:SetPoint( "TopLeft", frame, "BottomLeft", -1, 1 )
    bottom_border:SetPoint( "BottomRight", frame, "BottomRight", 1, 0 )

    local btn_close = CreateFrame( "Button", nil, parent, "UIPanelCloseButton" )
    btn_close:SetPoint( "TopRight", parent, "TopRight", 2, 2 )
    btn_close:SetScript( "OnClick", function() parent:Hide() end )

    local title_label = frame:CreateFontString( nil, "ARTWORK", "GameFontNormal" )
    title_label:SetPoint( "TopLeft", frame, "TopLeft", 6, -3 )
    title_label:SetTextColor( 1, 1, 1 )
    title_label:SetJustifyH( "Left" )
    title_label:SetText( title )

    return frame
  end

  ---@param parent Frame
  ---@param title string
  ---@param width integer?
  ---@param onclick function
  ---@return MyButton
  local function create_button( parent, title, width, onclick )
    ---@class MyButton: Button
    local btn = CreateFrame( "Button", nil, parent, title == "Cancel" and nil or "UIPanelButtonTemplate" )
    btn:SetScript( "OnClick", onclick )

    if title == "Cancel" then
      btn:SetNormalTexture( "Interface\\Buttons\\CancelButton-Up" )
      btn:GetNormalTexture():SetTexCoord( 0, 1, 0, 1 )
      btn:SetPushedTexture( "Interface\\Buttons\\CancelButton-Down" )
      btn:GetPushedTexture():SetTexCoord( 0, 1, 0, 1 )
      btn:SetHighlightTexture( "Interface\\Buttons\\CancelButton-Highlight" )
      btn:GetHighlightTexture():SetTexCoord( 0, 1, 0, 1 )
      btn:GetHighlightTexture():SetBlendMode( "ADD" )
      btn:SetHitRectInsets( 9, 7, 7, 10 )
      btn:SetWidth( 34 )
      btn:SetHeight( 34 )
    else
      btn:SetWidth( width and width or 100 )
      btn:SetHeight( 24 )
      btn:SetText( title )
    end

    btn.Disable = function()
      btn:EnableMouse( false )
      btn:GetFontString():SetTextColor( 0.5, 0.41, 0 )
      btn:GetNormalTexture():SetVertexColor( 0.5, 0.5, 0.5 )
    end

    btn.Enable = function()
      btn:EnableMouse( true )
      btn:GetFontString():SetTextColor( 1, 0.82, 0 )
      btn:GetNormalTexture():SetVertexColor( 1, 1, 1 )
    end

    return btn
  end

  ---@param parent InventoryFrame
  local function create_info_frame( parent )
    ---@class InfoFrame: Frame
    local info = CreateFrame( "Frame", nil, parent )
    info:SetPoint( "TopLeft", parent.inv_frame, "BottomLeft", 0, -10 )
    info:SetPoint( "Right", parent.inv_frame, "Right", 0, 0 )
    info:SetHeight( 100 )
    info:SetBackdrop( {
      bgFile = "Interface/Buttons/WHITE8x8",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 }
    } )
    info:SetBackdropColor( 0, 0, 0, 0.7 )

    local btn_sync_inv = create_button( info, "Sync inventory items count", 150, function()
      if m.sync_count( "Inventory" ) then
        refresh()
      end
    end )
    btn_sync_inv:SetPoint( "Center", info, "Center", 0, 15 )

    local btn_sync_bank = create_button( info, "Sync bank items count", 150, function()
      if m.sync_count( "Bank" ) then
        refresh()
      end
    end )
    btn_sync_bank:SetPoint( "Center", info, "Center", 0, -15 )
    btn_sync_bank:Disable()
    info.btn_sync_bank = btn_sync_bank

    local text_item = info:CreateFontString( nil, "ARTWORK", "GameFontNormal" )
    text_item:SetPoint( "TopLeft", info, "TopLeft", 8, -8 )
    text_item:SetTextColor( 1, 1, 1 )
    text_item:SetJustifyH( "Left" )

    local function update_count()
      if info.input_count:GetText() == "" then info.input_count:SetText( "0" ) end
      local count = tonumber( info.input_count:GetText() )

      if count then
        m.update_item_count( info.slot_index + offset, count )
        info.input_count:SetTextColor( 1, 1, 1 )
        info.input_count:ClearFocus()
        refresh()
        if count == 0 then
          slots[ info.slot_index ].pressed( false )
          info.clear()
        end
      else
        info.input_count:SetTextColor( 1, 0, 0 )
      end
    end

    local btn_update = create_button( info, "Update Count", nil, update_count )
    btn_update:SetPoint( "BottomRight", info, "BottomRight", -8, 10 )
    btn_update:Hide()

    local input_count = CreateFrame( "EditBox", "GuildInventoryInputCount", info, "InputBoxTemplate" )
    input_count:SetPoint( "BottomLeft", btn_update, "TopLeft", 8, 5 )
    input_count:SetWidth( 90 )
    input_count:SetHeight( 22 )
    input_count:SetAutoFocus( false )
    input_count:Hide()
    input_count:SetScript( "OnEnterPressed", update_count )
    info.input_count = input_count

    local label_count = info:CreateFontString( nil, "ARTWORK", "GameFontNormalSmall" )
    label_count:SetPoint( "BottomLeft", input_count, "TopLeft", -5, 1 )
    label_count:SetTextColor( 1, 1, 1 )
    label_count:SetJustifyH( "Left" )
    label_count:SetText( "Your amount" )
    label_count:Hide()

    local label_gcount = info:CreateFontString( nil, "ARTWORK", "GameFontNormalSmall" )
    label_gcount:SetPoint( "TopRight", label_count, "TopLeft", -10, 0 )
    label_gcount:SetPoint( "Left", info, "Left", 8, 0 )
    label_gcount:SetTextColor( 1, 1, 1 )
    label_gcount:SetJustifyH( "Left" )
    label_gcount:SetText( "Guild members amount" )
    label_gcount:Hide()

    local text_gcount = info:CreateFontString( nil, "ARTWORK", "GameFontNormalSmall" )
    text_gcount:SetPoint( "TopLeft", label_gcount, "BottomLeft", 0, -5 )
    text_gcount:SetPoint( "Right", label_count, "Left", -5, 0 )
    text_gcount:SetTextColor( 1, 1, 1 )
    text_gcount:SetJustifyH( "Left" )
    text_gcount:Hide()

    ---@param item Item
    ---@param slot_index integer
    info.set = function( item, slot_index )
      text_item:SetText( m.get_item_name_colorized( item ) )
      input_count:SetText( item.count[ m.player ] or "0" )
      input_count:Show()
      label_count:Show()
      label_gcount:Show()
      text_gcount:Show()
      btn_update:Show()
      btn_sync_bank:Hide()
      btn_sync_inv:Hide()

      local str = ""
      for player, count in pairs( item.count ) do
        if player ~= m.player then
          str = str .. string.format( "%s: %d, ", player, count )
        end
      end
      text_gcount:SetText( string.match( str, "(.-), $" ) )

      info.slot_index = slot_index
    end

    info.clear = function()
      text_item:SetText( "" )
      text_gcount:SetText( "" )
      input_count:SetText( "" )
      input_count:Hide()
      label_count:Hide()
      label_gcount:Hide()
      text_gcount:Hide()
      btn_update:Hide()
      btn_sync_bank:Show()
      btn_sync_inv:Show()
    end

    info_frame = info
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
        pickup_item( this.item.icon, this.slot_index + offset )
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

      for _, c in pairs( item.count ) do
        count = count + c
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

  local function create_frame()
    ---@class InventoryFrame: Frame
    local frame = CreateFrame( "Frame", "GuildInventoryFrame", UIParent )
    frame:SetPoint( "Center", UIParent, "Center", 0, 0 )
    frame:SetWidth( 427 )
    frame:SetHeight( 376 )
    frame:SetMovable( true )
    frame:EnableMouse( true )
    frame:SetFrameStrata( "DIALOG" )
    frame:RegisterForDrag( "LeftButton" )
    frame:SetScript( "OnDragStart", function() this:StartMoving() end )
    frame:SetScript( "OnDragStop", function() this:StopMovingOrSizing() end )
    frame:SetBackdrop( {
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 }
    } )
    frame:SetBackdropColor( 0, 0, 0, 1 )
    frame:Hide()
    frame:SetScript( "OnEnter", clear_cursor )

    table.insert( UISpecialFrames, frame:GetName() )

    local title_bar = create_titlebar( frame, string.format( "GuildInventory v%s", m.version ) )

    local indicator = CreateFrame( "Frame", nil, title_bar )
    indicator:SetPoint( "Center", title_bar, "Right", -30, 1 )
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
    input_search:SetWidth( 150 )
    input_search:SetHeight( 22 )
    input_search:SetAutoFocus( false )

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

    local btn_cancel = create_button( frame, "Cancel", 24, function()
      input_search:SetText( "" )
      search_str = nil
      refresh()
    end )
    btn_cancel:SetPoint( "TopRight", input_search, "TopRight", 6, 4 )
    btn_cancel:SetFrameLevel( 10 )
    btn_cancel:Hide()
    frame.btn_cancel = btn_cancel

    local btn_search = create_button( frame, "Search", 60, function()
      search_str = input_search:GetText()
      refresh()
    end )
    btn_search:SetPoint( "TopLeft", input_search, "TopRight", 5, 1 )

    local btn_sort = create_button( frame, "Sort", 60, sort_inventory )
    btn_sort:SetPoint( "TopRight", frame, "TopRight", -11, -28 )

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

    inv_frame:SetScript( "OnLeave", function()
      if MouseIsOver( frame.inventory ) then return end
      clear_cursor()
    end )

    inv_frame:SetScript( "OnMouseWheel", function()
      local value = frame.scroll_bar:GetValue() - arg1
      frame.scroll_bar:SetValue( value )
    end )

    local inv = CreateFrame( "Frame", nil, inv_frame )
    frame.inventory = inv
    inv:SetPoint( "TopLeft", inv_frame, "TopLeft", 6, -5 )
    inv:SetWidth( 380 )
    inv:SetHeight( 190 )

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

    frame.info = create_info_frame( frame )

    for i = 1, ROWS * 10 do
      local x = ((mod( i, 10 ) == 0 and 10 or mod( i, 10 )) - 1) * 38
      local y = math.floor( (i - 1) / 10 ) * -38
      slots[ i ] = create_slot( inv, i )
      slots[ i ]:SetPoint( "TopLeft", inv, "TopLeft", x, y )
    end

    ---@class FakeCursor: Frame
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

  local function show()
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
    popup:Show()
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
