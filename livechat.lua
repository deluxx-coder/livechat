-- DZ Delux Live Chat (embedded client)
-- Tidak membuat jendela sendiri. Chat dipasang ke dalam tab "Live Chat" di menu utama DZ Delux.
--
-- Cara kerja:
--   1. Menu Delux mengisi  _G.DZ_LIVECHAT_HOST = { parent = <Frame>, theme = {...} }
--   2. Lalu menjalankan  loadstring(game:HttpGet("<link script ini>"))()
--   3. Script ini otomatis memasang chat ke parent tersebut dan mulai polling.
--
-- Kalau dijalankan tanpa host, script cuma menyiapkan API (_G.DZ_LIVECHAT.Mount) dan tidak menampilkan apa-apa.

local BASE = "https://deluxx-coder-livechat.vercel.app/api/chat"
local KEY  = ""        -- isi sama dengan env CHAT_KEY kalau kamu pakai
local POLL = 3         -- detik antar cek pesan (saat tab chat terlihat)
local POLL_IDLE = 10   -- detik antar cek pesan (saat tab chat tidak terlihat)
local MAX_LEN = 200    -- batas panjang pesan
local COOLDOWN = 1.5   -- jeda minimal antar kirim (detik)
local MAX_LINES = 100  -- jumlah pesan maksimal di layar

-- ========== Role system ==========
-- Pakai @username (bukan display name)
local ROLES = {
	["wooda_stackerzzz"] = { label = "Owner", color = Color3.fromRGB(255, 215, 0) }, -- gold
}
local ROLE_DEFAULT = { label = "Member", color = Color3.fromRGB(146, 146, 146) }

local ROLE_COLORS = {
	Owner = Color3.fromRGB(255, 215, 0),
}

local function getRole(username, label)
	-- role dari server (aman). Fallback ke daftar lokal kalau server versi lama.
	if label then
		return { label = label, color = ROLE_COLORS[label] or ROLE_DEFAULT.color }
	end
	return ROLES[tostring(username):lower()] or ROLE_DEFAULT
end

-- ========== Sensor nama ==========
-- "wooda_stackerzzz" -> "wooda******"
-- Bagian depan tetap kelihatan, sisanya jadi bintang (jumlah bintang dibatasi supaya panjang asli tidak kebaca).
local function maskName(name)
	name = tostring(name or "")
	local n = #name
	if n <= 1 then
		return name
	end
	local keep = math.clamp(math.floor(n / 3), 1, 5)
	local stars = math.clamp(n - keep, 3, 6)
	return name:sub(1, keep) .. string.rep("*", stars)
end

-- ========== Services ==========
local Players = game:GetService("Players")
local Http    = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local me      = Players.LocalPlayer
local req     = (syn and syn.request) or (http and http.request) or http_request or request

-- ========== Network ==========
local function call(method, query, body)
	if not req then
		return nil, "norequest"
	end
	local headers = { ["Content-Type"] = "application/json" }
	if KEY ~= "" then
		headers["x-chat-key"] = KEY
	end
	-- opsional (hanya untuk owner): getgenv().DZ_OWNER_KEY = "isi sama dengan env OWNER_KEY"
	local okg, ownerKey = pcall(function() return getgenv().DZ_OWNER_KEY end)
	if okg and type(ownerKey) == "string" and ownerKey ~= "" then
		headers["x-owner-key"] = ownerKey
	end
	local ok, res = pcall(req, {
		Url = BASE .. (query or ""),
		Method = method,
		Headers = headers,
		Body = body and Http:JSONEncode(body) or nil,
	})
	if not ok or not res or res.StatusCode ~= 200 then
		return nil, res and res.StatusCode
	end
	local ok2, data = pcall(Http.JSONDecode, Http, res.Body)
	return ok2 and data or nil
end

-- ========== Util ==========
local function esc(s)
	s = tostring(s or "")
	s = s:gsub("[%c]", " ")
	s = s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&apos;")
	return s
end

local function hex(c)
	return string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

-- ========== Mount ==========
local mountGen = 0

local function Mount(parent, theme)
	theme = theme or {}
	local CARD   = theme.CARD   or Color3.fromHex("0D0D0D")
	local GLASS  = theme.GLASS  or Color3.fromHex("101010")
	local LINE   = theme.LINE   or Color3.fromHex("242424")
	local GRAY   = theme.GRAY   or Color3.fromHex("929292")
	local WHITE  = theme.WHITE  or Color3.fromHex("F5F5F5")
	local RED    = theme.RED    or Color3.fromHex("FF4D4D")
	local ACCENT = theme.accent or Color3.fromHex("22C55E")
	local FONT   = theme.FONT   or Enum.Font.GothamMedium
	local FONT_B = theme.FONT_B or Enum.Font.GothamBold
	local reg    = theme.reg    -- fungsi dari menu supaya warna aksen ikut berubah (opsional)
	local isActive = theme.isActive

	mountGen = mountGen + 1
	local myGen = mountGen

	for _, c in ipairs(parent:GetChildren()) do
		if c.Name == "DZLiveChatRoot" then
			c:Destroy()
		end
	end

	local function corner(inst, r)
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, r)
		c.Parent = inst
	end
	local function stroke(inst, col, th)
		local s = Instance.new("UIStroke")
		s.Color = col
		s.Thickness = th or 1
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Parent = inst
		return s
	end

	local root = Instance.new("Frame")
	root.Name = "DZLiveChatRoot"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = parent

	-- area pesan
	local list = Instance.new("ScrollingFrame")
	list.Size = UDim2.new(1, 0, 1, -42)
	list.BackgroundColor3 = CARD
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 3
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = root
	corner(list, 10)
	stroke(list, LINE, 1)
	if reg then
		pcall(reg, list, "ScrollBarImageColor3")
	else
		list.ScrollBarImageColor3 = ACCENT
	end
	local ll = Instance.new("UIListLayout")
	ll.Padding = UDim.new(0, 4)
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.Parent = list
	local lp = Instance.new("UIPadding")
	lp.PaddingLeft = UDim.new(0, 10)
	lp.PaddingRight = UDim.new(0, 10)
	lp.PaddingTop = UDim.new(0, 8)
	lp.PaddingBottom = UDim.new(0, 8)
	lp.Parent = list

	-- kolom input
	local box = Instance.new("TextBox")
	box.Size = UDim2.new(1, -96, 0, 34)
	box.Position = UDim2.new(0, 0, 1, -34)
	box.BackgroundColor3 = GLASS
	box.TextColor3 = WHITE
	box.PlaceholderText = "Tulis pesan..."
	box.PlaceholderColor3 = GRAY
	box.ClearTextOnFocus = false
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Font = FONT
	box.TextSize = 12
	box.Text = ""
	box.Parent = root
	corner(box, 8)
	stroke(box, LINE, 1)
	local bp = Instance.new("UIPadding")
	bp.PaddingLeft = UDim.new(0, 10)
	bp.PaddingRight = UDim.new(0, 10)
	bp.Parent = box

	local sendBtn = Instance.new("TextButton")
	sendBtn.Size = UDim2.fromOffset(86, 34)
	sendBtn.AnchorPoint = Vector2.new(1, 1)
	sendBtn.Position = UDim2.new(1, 0, 1, 0)
	sendBtn.BackgroundColor3 = ACCENT
	sendBtn.Text = "Kirim"
	sendBtn.TextColor3 = WHITE
	sendBtn.Font = FONT_B
	sendBtn.TextSize = 12
	sendBtn.AutoButtonColor = false
	sendBtn.Parent = root
	corner(sendBtn, 8)
	if reg then
		pcall(reg, sendBtn, "BackgroundColor3")
	end

	local order = 0
	local function nextOrder()
		order = order + 1
		return order
	end

	local function trim()
		local kids = {}
		for _, c in ipairs(list:GetChildren()) do
			if c:IsA("TextLabel") then
				kids[#kids + 1] = c
			end
		end
		table.sort(kids, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
		while #kids > MAX_LINES do
			table.remove(kids, 1):Destroy()
		end
	end

	local function scrollDown()
		task.defer(function()
			if list.Parent then
				list.CanvasPosition = Vector2.new(0, list.AbsoluteCanvasSize.Y)
			end
		end)
	end

	local function addSystem(text, color)
		local l = Instance.new("TextLabel")
		l.Size = UDim2.new(1, 0, 0, 0)
		l.AutomaticSize = Enum.AutomaticSize.Y
		l.BackgroundTransparency = 1
		l.Text = "— " .. text
		l.TextColor3 = color or GRAY
		l.Font = FONT
		l.TextSize = 11
		l.TextWrapped = true
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.LayoutOrder = nextOrder()
		l.Parent = list
		trim()
		scrollDown()
	end

	-- premasked = true kalau server sudah menyensor nama (server baru)
	local function addLine(username, displayName, text, roleLabel, premasked)
		local role = getRole(username, roleLabel)
		local uMask = premasked and username or maskName(username)
		local dShow = displayName
		if not premasked and tostring(displayName):lower() == tostring(username):lower() then
			dShow = uMask
		end

		local l = Instance.new("TextLabel")
		l.Size = UDim2.new(1, 0, 0, 0)
		l.AutomaticSize = Enum.AutomaticSize.Y
		l.BackgroundTransparency = 1
		l.RichText = true
		l.Text = string.format(
			'<font color="%s"><b>[%s]</b></font> <b>%s</b> <font color="%s">(@%s)</font>: %s',
			hex(role.color), esc(role.label), esc(dShow), hex(GRAY), esc(uMask), esc(text)
		)
		l.TextColor3 = WHITE
		l.Font = FONT
		l.TextSize = 12
		l.TextWrapped = true
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.LayoutOrder = nextOrder()
		l.Parent = list
		trim()
		scrollDown()
	end

	if not req then
		addSystem("Executor tidak mendukung request(), chat tidak bisa dipakai.", RED)
		box.TextEditable = false
		return root
	end

	-- ========== State ==========
	local room = "global"
	local lastId = {}
	local firstLoad = true

	local function pollOnce()
		local r = room
		local data = call("GET", ("?room=%s&since=%d"):format(r, lastId[r] or 0))
		if not data or myGen ~= mountGen then
			return
		end
		if firstLoad then
			firstLoad = false
			if #(data.messages or {}) == 0 then
				addSystem("Belum ada pesan. Jadi yang pertama!")
			end
		end
		for _, m in ipairs(data.messages or {}) do
			lastId[r] = math.max(lastId[r] or 0, m.id)
			if m.handle then
				-- server baru: nama sudah disensor & role sudah ditentukan server
				addLine(tostring(m.handle), tostring(m.name or m.handle), tostring(m.text), m.role, true)
			else
				-- server lama: format "displayName|username"
				local disp, uname = tostring(m.user):match("^(.+)|(.+)$")
				if not disp then
					disp = tostring(m.user)
					uname = disp
				end
				addLine(uname, disp, tostring(m.text))
			end
		end
	end

	-- ========== Kirim ==========
	local sending = false
	local lastSend = 0
	local function send()
		local text = box.Text
		if sending or text:gsub("%s", "") == "" then
			return
		end
		if os.clock() - lastSend < COOLDOWN then
			addSystem("Terlalu cepat, tunggu sebentar.", RED)
			return
		end
		text = text:sub(1, MAX_LEN)
		sending = true
		lastSend = os.clock()
		box.Text = ""
		local myName = me.Name -- @username (tidak berubah)
		local myDisp = me.DisplayName ~= "" and me.DisplayName or me.Name
		local data, code = call("POST", "", {
			room = room,
			user = myDisp .. "|" .. myName, -- kirim "DisplayName|@username"
			uid = tostring(me.UserId),
			text = text,
		})
		if not data then
			addSystem(code == 429 and "Terlalu cepat, tunggu sebentar." or "Gagal kirim.", RED)
		else
			pollOnce()
		end
		sending = false
	end

	sendBtn.MouseButton1Click:Connect(send)
	box.FocusLost:Connect(function(enter)
		if enter then
			send()
		end
	end)

	-- ========== Loop ==========
	task.spawn(pollOnce)
	task.spawn(function()
		while root.Parent and myGen == mountGen do
			local active = true
			if isActive then
				local ok, v = pcall(isActive)
				active = ok and v ~= false
			end
			task.wait(active and POLL or POLL_IDLE)
			if root.Parent and myGen == mountGen then
				pollOnce()
			end
		end
	end)

	return root
end

_G.DZ_LIVECHAT = {
	Mount = Mount,
	MaskName = maskName,
}

-- ========== Auto run ==========
local host = _G.DZ_LIVECHAT_HOST
if type(host) == "table" and typeof(host.parent) == "Instance" then
	_G.DZ_LIVECHAT_HOST = nil
	Mount(host.parent, host.theme)
end
