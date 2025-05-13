GuildInventory = GuildInventory or {}

---@class GuildInventory
local m = GuildInventory

if m.Notifications then return end

---@alias NotificationType
---| "NewRequest"
---| "Error"
---| "Info"

---@type NotificationType
local NotificationType = {
  NewRequest = "NewRequest",
  Error = "Error",
  Info = "Info",
}

m.NotificationType = NotificationType

---@class NotifyData
---@field message string
---@field type NotificationType
---@field timestamp integer?
---@field duration integer?

---@class Notifications
---@field add fun( message: string, type: NotificationType, timestamp: integer?, duration: integer? )
---@field new_request fun( data: table )
local M = {}

---@param ace_timer AceTimer
function M.new( ace_timer )
  local notifications = {}
  local notify_frames = {}

  local running
  local tmp = 0

  local function notify_update()
    if this.fade == "out" then
      tmp = tmp + 1
      this.alpha = this.alpha - 0.01
      this:SetAlpha( this.alpha )
      local _, _, _, _, y = this:GetPoint()

      for _, f in notify_frames do
        if f.is_used then
          local point, relativeTo, relativePoint, xOfs, yOfs = f:GetPoint()

          if yOfs <= y then
            yOfs = yOfs + 0.81
            f:SetPoint( point, relativeTo, relativePoint, xOfs, yOfs )
          end
        end
      end

      if this.alpha <= 0 then
        this.fade = nil
        this.is_used = false
        this:SetPoint( "TopRight", UIParent, "TopRight", -2, 80 )
        this:Hide()
        this:SetScript( "OnUpdate", nil )
      end
    elseif this.fade == "in" then
      this.alpha = this.alpha + 0.01
      this:SetAlpha( this.alpha )

      if this.alpha >= 1 then
        this.fade = nil
        this:SetScript( "OnUpdate", nil )
      end
    end
  end

  local function create_notify_frame()
    ---@class NotifyFrame: Frame
    local frame = CreateFrame( "Frame", nil, UIParent )
    frame:SetFrameStrata( "TOOLTIP" )
    frame:EnableMouse( true )
    frame:SetWidth( 250 )
    frame:SetHeight( 80 )
    frame:SetBackdrop( { bgFile = "Interface/Buttons/WHITE8x8" } )
    frame:SetBackdropColor( 0, 0, 0, 0.9 )
    frame:Hide()

    frame:SetScript( "OnMouseDown", function()
      m.gui.show( "Inbox" )
    end )

    local type_line = CreateFrame( "Frame", nil, frame )
    type_line:SetPoint( "TopLeft", frame, "TopLeft", 0, 0 )
    type_line:SetPoint( "BottomRight", frame, "BottomLeft", 3, 0 )
    type_line:SetBackdrop( { bgFile = "Interface/Buttons/WHITE8x8" } )

    local text_message = frame:CreateFontString( nil, "ARTWORK", "GameFontNormal" )
    text_message:SetPoint( "TopLeft", frame, "TopLeft", 8, -5 )
    text_message:SetPoint( "BottomRight", frame, "BottomRight", -5, 5 )
    text_message:SetJustifyH( "Left" )
    text_message:SetJustifyV( "Top" )

    local text_timestamp = frame:CreateFontString( nil, "ARTWORK", "GameFontNormalSmall" )
    text_timestamp:SetPoint( "BottomRight", frame, "BottomRight", -3, 3 )
    text_timestamp:SetJustifyH( "Right" )

    frame.is_used = true
    frame.fade = nil
    frame.aplha = 0

    ---@param data NotifyData
    frame.show = function( data )
      local ty = 80

      for i = getn( notify_frames ), 1, -1 do
        if notify_frames[ i ].is_used then
          local _, _, _, _, y = notify_frames[ i ]:GetPoint()
          if y and y < 0 and y < ty then ty = y end
        end
      end

      --if ty > -1 then ty = 0 - (ty or 81) end
      ty = ty - 81

      frame:SetPoint( "TopRight", UIParent, "TopRight", -2, ty )

      if data.type == m.NotificationType.NewRequest then
        type_line:SetBackdropColor( 0, 0.7, 0, 1 )
      elseif data.type == m.NotificationType.Error then
        type_line:SetBackdropColor( 0.7, 0, 0, 1 )
      elseif data.type == m.NotificationType.Info then
        type_line:SetBackdropColor( 0.7, 0.7, 0, 1 )
      end
      text_message:SetText( data.message )
      text_timestamp:SetText( tostring( m.time_ago( data.timestamp ) ) )

      frame.fadein()
      ace_timer.ScheduleTimer( m, frame.fadeout, data.duration or 10 )
    end

    frame.fadein = function()
      frame:SetAlpha( 0 )
      frame:Show()
      frame.fade = "in"
      frame.alpha = 0
      frame:SetScript( "OnUpdate", notify_update )
    end

    frame.fadeout = function()
      frame.fade = "out"
      frame.alpha = 1
      frame:SetScript( "OnUpdate", notify_update )
    end

    return frame
  end

  local function get_notify_frame()
    for i = getn( notify_frames ), 1, -1 do
      if not notify_frames[ i ].is_used then
        notify_frames[ i ].is_used = true
        return notify_frames[ i ]
      end
    end

    local notify_frame = create_notify_frame()
    table.insert( notify_frames, notify_frame )

    return notify_frame
  end

  local function show_notification()
    if notifications[ 1 ] then
      local notify_frame = get_notify_frame()

      notify_frame.show( notifications[ 1 ] )
      table.remove( notifications, 1 )
    end
  end

  local function show_notifications()
    if getn( notifications ) == 0 then
      return
    end
    show_notification()
    running = ace_timer.ScheduleTimer( M, show_notifications, 2 )
  end

  local function add( message, type, timestamp, duration )
    table.insert( notifications, {
      message = message,
      type = type,
      timestamp = timestamp,
      duration = duration
    } )

    if ace_timer:TimeLeft( running ) == 0 then
      show_notifications()
    end
  end

  ---@param data RequestData
  local function new_request( data )
    local count = 0
    for _, item in data.items do
      count = count + item.count
    end

    local message = string.format( "You have received a new request for %d item%s from %s", count, count > 1 and "s" or "", data.from )
    message = message .. "\n\nClick to view request."

    add( message, NotificationType.NewRequest, data.timestamp )
  end

  return {
    add = add,
    new_request = new_request
  }
end

m.Notifications = M
return M
