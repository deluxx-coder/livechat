-- Live Chat client (polling) untuk executor
local BASE = "https://deluxx-coder-livechat.vercel.app/api/chat"
local KEY  = ""       -- isi sama dengan env CHAT_KEY kalau kamu pakai
local POLL = 3        -- detik antar cek pesan

-- ========== Role system ==========
-- Pakai @username (bukan display name)
local ROLES = {
    ["wooda_stackerzzz"] = { label = "Owner", color = Color3.fromRGB(255, 215, 0) },   -- gold
}
local ROLE_DEFAULT = { label = "Member", color = Color3.fromRGB(160, 160, 170) }

local function getRole(username)
    return ROLES[username:lower()] or ROLE_DEFAULT
end

-- ========== Services ==========
local Players = game:GetService("Players")
local Http    = game:GetService("HttpService")
local UIS     = game:GetService("UserInputService")
local me      = Players.LocalPlayer
local req     = (syn and syn.request) or (http and http.request) or http_request or request
assert(req, "executor tidak mendukung request()")

-- ========== Network ==========
local function call(method, query, body)
    local headers = { ["Content-Type"] = "application/json" }
    if KEY ~= "" then headers["x-chat-key"] = KEY end
    local ok, res = pcall(req, {
        Url    = BASE .. (query or ""),
        Method = method,
        Headers = headers,
        Body   = body and Http:JSONEncode(body) or nil,
    })
    if not ok or not res or res.StatusCode ~= 200 then return nil, res and res.StatusCode end
    local ok2, data = pcall(Http.JSONDecode, Http, res.Body)
    return ok2 and data or nil
end

-- ========== UI ==========
local parent = (gethui and gethui()) or game:GetService("CoreGui")
local old = parent:FindFirstChild("LiveChatGui")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "LiveChatGui"
gui.ResetOnSpawn = false
gui.Parent = parent

-- Header bar
local main = Instance.new("Frame")
main.Size = UDim2.fromOffset(320, 320)
main.Position = UDim2.new(0, 20, 0.5, -160)
main.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
main.Active = true
main.Draggable = true
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)

-- Stroke border
local stroke = Instance.new("UIStroke", main)
stroke.Color = Color3.fromRGB(50, 50, 65)
stroke.Thickness = 1

-- Title bar
local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 30)
titleBar.BackgroundColor3 = Color3.fromRGB(28, 28, 38)
titleBar.BorderSizePixel = 0
titleBar.Parent = main
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 10)

-- fix bottom corners of titleBar
local titleFix = Instance.new("Frame")
titleFix.Size = UDim2.new(1, 0, 0, 10)
titleFix.Position = UDim2.new(0, 0, 1, -10)
titleFix.BackgroundColor3 = Color3.fromRGB(28, 28, 38)
titleFix.BorderSizePixel = 0
titleFix.Parent = titleBar

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1, -10, 1, 0)
titleLbl.Position = UDim2.fromOffset(10, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text = "💬  Live Chat"
titleLbl.TextColor3 = Color3.fromRGB(220, 220, 230)
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextSize = 13
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.Parent = titleBar

-- Message list
local list = Instance.new("ScrollingFrame")
list.Size = UDim2.new(1, -16, 1, -74)
list.Position = UDim2.fromOffset(8, 36)
list.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
list.BorderSizePixel = 0
list.ScrollBarThickness = 3
list.CanvasSize = UDim2.new()
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.Parent = main
Instance.new("UICorner", list).CornerRadius = UDim.new(0, 6)
local ll = Instance.new("UIListLayout", list)
ll.Padding = UDim.new(0, 3)
local lp = Instance.new("UIPadding", list)
lp.PaddingLeft   = UDim.new(0, 7)
lp.PaddingRight  = UDim.new(0, 7)
lp.PaddingTop    = UDim.new(0, 5)
lp.PaddingBottom = UDim.new(0, 5)

-- Input box
local box = Instance.new("TextBox")
box.Size = UDim2.new(1, -78, 0, 28)
box.Position = UDim2.new(0, 8, 1, -36)
box.BackgroundColor3 = Color3.fromRGB(30, 30, 42)
box.TextColor3 = Color3.new(1, 1, 1)
box.PlaceholderText = "Tulis pesan..."
box.PlaceholderColor3 = Color3.fromRGB(100, 100, 115)
box.ClearTextOnFocus = false
box.TextXAlignment = Enum.TextXAlignment.Left
box.Font = Enum.Font.Gotham
box.TextSize = 13
box.Parent = main
local boxCorner = Instance.new("UICorner", box)
boxCorner.CornerRadius = UDim.new(0, 6)
local boxPad = Instance.new("UIPadding", box)
boxPad.PaddingLeft = UDim.new(0, 8)

-- Send button
local sendBtn = Instance.new("TextButton")
sendBtn.Size = UDim2.fromOffset(60, 28)
sendBtn.Position = UDim2.new(1, -68, 1, -36)
sendBtn.BackgroundColor3 = Color3.fromRGB(88, 101, 242)
sendBtn.Text = "Kirim"
sendBtn.TextColor3 = Color3.new(1, 1, 1)
sendBtn.Font = Enum.Font.GothamBold
sendBtn.TextSize = 13
sendBtn.Parent = main
Instance.new("UICorner", sendBtn).CornerRadius = UDim.new(0, 6)

-- ========== Add message ==========
local function addLine(username, displayName, text)
    local role = getRole(username)

    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 0)
    row.AutomaticSize = Enum.AutomaticSize.Y
    row.BackgroundTransparency = 1
    row.Parent = list

    -- Badge [Owner] / [Member]
    local badge = Instance.new("TextLabel")
    badge.Size = UDim2.fromOffset(0, 16)
    badge.AutomaticSize = Enum.AutomaticSize.X
    badge.BackgroundTransparency = 1
    badge.Text = "[" .. role.label .. "] "
    badge.TextColor3 = role.color
    badge.Font = Enum.Font.GothamBold
    badge.TextSize = 12
    badge.TextXAlignment = Enum.TextXAlignment.Left
    badge.Parent = row

    -- Display name + @username
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(1, 0, 0, 16)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = displayName .. " (@" .. username .. "): " .. text
    nameLabel.TextColor3 = Color3.fromRGB(210, 210, 220)
    nameLabel.Font = Enum.Font.Gotham
    nameLabel.TextSize = 12
    nameLabel.TextWrapped = true
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.AutomaticSize = Enum.AutomaticSize.Y
    nameLabel.Size = UDim2.new(1, 0, 0, 0)
    nameLabel.Parent = row

    -- Layout dalam row
    local rl = Instance.new("UIListLayout", row)
    rl.FillDirection = Enum.FillDirection.Vertical
    rl.Padding = UDim.new(0, 1)

    -- Hapus pesan lama kalau terlalu banyak
    local kids = {}
    for _, c in ipairs(list:GetChildren()) do
        if c:IsA("Frame") then kids[#kids + 1] = c end
    end
    if #kids > 100 then kids[1]:Destroy() end

    task.defer(function()
        list.CanvasPosition = Vector2.new(0, list.AbsoluteCanvasSize.Y)
    end)
end

local function addSystem(text)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, 0, 0, 0)
    l.AutomaticSize = Enum.AutomaticSize.Y
    l.BackgroundTransparency = 1
    l.Text = "— " .. text
    l.TextColor3 = Color3.fromRGB(100, 100, 115)
    l.Font = Enum.Font.GothamItalic
    l.TextSize = 11
    l.TextWrapped = true
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = list
end

-- ========== State ==========
local room   = "global"
local lastId = {}
local generation = 0

local function pollOnce()
    local gen, r = generation, room
    local data = call("GET", ("?room=%s&since=%d"):format(r, lastId[r] or 0))
    if not data or gen ~= generation then return end
    for _, m in ipairs(data.messages or {}) do
        lastId[r] = math.max(lastId[r] or 0, m.id)
        -- format: "displayName|username" atau hanya username
        local disp, uname = m.user:match("^(.+)|(.+)$")
        if not disp then disp = m.user; uname = m.user end
        addLine(uname, disp, m.text)
    end
end

-- ========== Send ==========
local sending = false
local function send()
    local text = box.Text
    if sending or text:gsub("%s", "") == "" then return end
    sending = true
    box.Text = ""
    local myName = me.Name                          -- @username (tidak berubah)
    local myDisp = me.DisplayName ~= "" and me.DisplayName or me.Name
    local data, code = call("POST", "", {
        room = room,
        user = myDisp .. "|" .. myName,             -- kirim "DisplayName|@username"
        uid  = tostring(me.UserId),
        text = text,
    })
    if not data then
        addSystem(code == 429 and "Terlalu cepat, tunggu sebentar." or "Gagal kirim.")
    else
        pollOnce()
    end
    sending = false
end

sendBtn.MouseButton1Click:Connect(send)
box.FocusLost:Connect(function(enter) if enter then send() end end)

-- ========== Loop ==========
task.spawn(pollOnce)
task.spawn(function()
    while gui.Parent do
        task.wait(POLL)
        pollOnce()
    end
end)
