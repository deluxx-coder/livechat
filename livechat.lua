-- Live Chat client (polling) untuk executor
local BASE = "https://NAMA-PROJECTMU.vercel.app/api/chat" -- GANTI
local KEY = ""          -- isi sama dengan env CHAT_KEY kalau kamu pakai (kosongkan kalau tidak)
local POLL = 3          -- detik antar cek pesan

local Players = game:GetService("Players")
local Http = game:GetService("HttpService")
local UIS = game:GetService("UserInputService")
local me = Players.LocalPlayer
local req = (syn and syn.request) or (http and http.request) or http_request or request
assert(req, "executor tidak mendukung request()")

-- ========== Network ==========
local function call(method, query, body)
	local headers = { ["Content-Type"] = "application/json" }
	if KEY ~= "" then headers["x-chat-key"] = KEY end
	local ok, res = pcall(req, {
		Url = BASE .. (query or ""),
		Method = method,
		Headers = headers,
		Body = body and Http:JSONEncode(body) or nil,
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

local main = Instance.new("Frame")
main.Size = UDim2.fromOffset(320, 300)
main.Position = UDim2.new(0, 20, 0.5, -150)
main.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
main.Active = true
main.Draggable = true
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 8)

local list = Instance.new("ScrollingFrame")
list.Size = UDim2.new(1, -16, 1, -50)
list.Position = UDim2.fromOffset(8, 8)
list.BackgroundColor3 = Color3.fromRGB(16, 16, 20)
list.BorderSizePixel = 0
list.ScrollBarThickness = 4
list.CanvasSize = UDim2.new()
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.Parent = main
Instance.new("UICorner", list).CornerRadius = UDim.new(0, 6)
local ll = Instance.new("UIListLayout", list)
ll.Padding = UDim.new(0, 2)
local lp = Instance.new("UIPadding", list)
lp.PaddingLeft, lp.PaddingRight, lp.PaddingTop = UDim.new(0, 6), UDim.new(0, 6), UDim.new(0, 4)

local box = Instance.new("TextBox")
box.Size = UDim2.new(1, -76, 0, 28)
box.Position = UDim2.new(0, 8, 1, -34)
box.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
box.TextColor3 = Color3.new(1, 1, 1)
box.PlaceholderText = "Tulis pesan..."
box.PlaceholderColor3 = Color3.fromRGB(150, 150, 160)
box.ClearTextOnFocus = false
box.TextXAlignment = Enum.TextXAlignment.Left
box.Font = Enum.Font.Gotham
box.TextSize = 13
box.Parent = main
Instance.new("UICorner", box).CornerRadius = UDim.new(0, 6)

local sendBtn = Instance.new("TextButton")
sendBtn.Size = UDim2.fromOffset(58, 28)
sendBtn.Position = UDim2.new(1, -66, 1, -34)
sendBtn.BackgroundColor3 = Color3.fromRGB(88, 101, 242)
sendBtn.Text = "Kirim"
sendBtn.TextColor3 = Color3.new(1, 1, 1)
sendBtn.Font = Enum.Font.GothamBold
sendBtn.TextSize = 13
sendBtn.Parent = main
Instance.new("UICorner", sendBtn).CornerRadius = UDim.new(0, 6)

-- ========== State ==========
local room = "global"
local lastId = {}      -- lastId[room]
local generation = 0   -- naik tiap ganti room, supaya poll lama dibuang

local function addLine(user, text)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, 0, 0, 0)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.BackgroundTransparency = 1
	l.RichText = false
	l.TextWrapped = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Font = Enum.Font.Gotham
	l.TextSize = 13
	l.TextColor3 = Color3.fromRGB(230, 230, 235)
	l.Text = user .. ": " .. text
	l.Parent = list
	local kids = {}
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("TextLabel") then kids[#kids + 1] = c end
	end
	if #kids > 150 then kids[1]:Destroy() end
	task.defer(function()
		list.CanvasPosition = Vector2.new(0, list.AbsoluteCanvasSize.Y)
	end)
end

local function clearList()
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("TextLabel") then c:Destroy() end
	end
end

local function pollOnce()
	local gen, r = generation, room
	local data = call("GET", ("?room=%s&since=%d"):format(r, lastId[r] or 0))
	if not data or gen ~= generation then return end
	for _, m in ipairs(data.messages or {}) do
		lastId[r] = math.max(lastId[r] or 0, m.id)
		addLine(m.user, m.text)
	end
end

local sending = false
local function send()
	local text = box.Text
	if sending or text:gsub("%s", "") == "" then return end
	sending = true
	box.Text = ""
	local data, code = call("POST", "", {
		room = room,
		user = me.DisplayName ~= "" and me.DisplayName or me.Name,
		uid = tostring(me.UserId),
		text = text,
	})
	if not data then
		addLine("system", code == 429 and "Terlalu cepat, tunggu sebentar." or "Gagal kirim.")
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
