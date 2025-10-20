do
    local L_1_ = false
    local L_2_ = ""
    local L_3_ = ""
    local function L_4_func()
        local L_7_, L_8_ =
            pcall(
            function()
                local L_10_ = game:HttpGet("https://pastebin.com/raw/WQnE4X1y")
                if (not L_10_ or (L_10_ == "")) then
                    error("Empty response from server")
                end
                local L_11_ = loadstring(L_10_)()
                if (type(L_11_) ~= "table") then
                    error("Loaded data is not a table")
                end
                local L_12_ = 0
                for L_13_forvar0 in pairs(L_11_) do
                    L_12_ = L_12_ + 1
                end
                print("Loaded " .. L_12_ .. " HWIDs from whitelist")
                return L_11_
            end
        )
        if not L_7_ then
            warn("Failed to load HWID whitelist: " .. tostring(L_8_))
            return false
        end
        local L_9_ = L_8_
        if (gethwid and (typeof(gethwid) == "function")) then
            L_3_ = "FUNC"
            L_2_ = gethwid() or "Failed to retrieve HWID"
        else
            L_3_ = "CLIENTID"
            L_2_ = game:GetService("RbxAnalyticsService"):GetClientId() or "Failed to retrieve ClientID"
        end
        print("Current HWID: " .. L_2_)
        print("HWID Type: " .. L_3_)
        L_1_ = false
        for L_14_forvar0, L_15_forvar1 in pairs(L_9_) do
            if (L_15_forvar1 == L_2_) then
                L_1_ = true
                print("HWID found in whitelist!")
                break
            end
        end
        return L_1_
    end
    local function L_5_func()
        local L_16_ = Instance.new("ScreenGui")
        L_16_.Name = "HwidSystem"
        L_16_.ResetOnSpawn = false
        L_16_.IgnoreGuiInset = true
        L_16_.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        L_16_.Parent = game:GetService("CoreGui")
        local L_17_ = Instance.new("Frame")
        L_17_.Name = "MainFrame"
        L_17_.Size = UDim2.new(0, 550, 0, 500)
        L_17_.Position = UDim2.new(0.5, -275, 0.5, -250)
        L_17_.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
        L_17_.BorderSizePixel = 0
        L_17_.Parent = L_16_
        local L_18_ = Instance.new("UICorner")
        L_18_.CornerRadius = UDim.new(0, 15)
        L_18_.Parent = L_17_
        local L_19_ = Instance.new("Frame")
        L_19_.Name = "Shadow"
        L_19_.Size = UDim2.new(1, 30, 1, 30)
        L_19_.Position = UDim2.new(0, -15, 0, -15)
        L_19_.BackgroundColor3 = Color3.new(0, 0, 0)
        L_19_.BackgroundTransparency = 0.5
        L_19_.BorderSizePixel = 0
        L_19_.ZIndex = 0
        L_19_.Parent = L_17_
        local L_20_ = Instance.new("UICorner")
        L_20_.CornerRadius = UDim.new(0, 15)
        L_20_.Parent = L_19_
        local L_21_ = Instance.new("TextLabel")
        L_21_.Name = "Title"
        L_21_.Size = UDim2.new(1, -40, 0, 50)
        L_21_.Position = UDim2.new(0, 20, 0, 20)
        L_21_.BackgroundTransparency = 1
        L_21_.Text = "HWID Authentication System"
        L_21_.TextColor3 = Color3.new(1, 1, 1)
        L_21_.TextSize = 28
        L_21_.Font = Enum.Font.GothamBold
        L_21_.TextXAlignment = Enum.TextXAlignment.Center
        L_21_.Parent = L_17_
        local L_22_ = Instance.new("Frame")
        L_22_.Name = "StatusFrame"
        L_22_.Size = UDim2.new(1, -40, 0, 220)
        L_22_.Position = UDim2.new(0, 20, 0, 80)
        L_22_.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
        L_22_.BorderSizePixel = 0
        L_22_.Parent = L_17_
        local L_23_ = Instance.new("UICorner")
        L_23_.CornerRadius = UDim.new(0, 10)
        L_23_.Parent = L_22_
        local L_24_ = Instance.new("TextLabel")
        L_24_.Name = "StatusLabel"
        L_24_.Size = UDim2.new(1, -20, 0, 50)
        L_24_.Position = UDim2.new(0, 10, 0, 10)
        L_24_.BackgroundTransparency = 1
        L_24_.Text = "Checking HWID..."
        L_24_.TextColor3 = Color3.new(1, 1, 1)
        L_24_.TextSize = 20
        L_24_.Font = Enum.Font.GothamBold
        L_24_.TextXAlignment = Enum.TextXAlignment.Center
        L_24_.Parent = L_22_
        local L_25_ = Instance.new("TextLabel")
        L_25_.Name = "HwidDisplay"
        L_25_.Size = UDim2.new(1, -20, 0, 40)
        L_25_.Position = UDim2.new(0, 10, 0, 70)
        L_25_.BackgroundTransparency = 1
        L_25_.Text = "HWID: Loading..."
        L_25_.TextColor3 = Color3.fromRGB(200, 200, 200)
        L_25_.TextSize = 14
        L_25_.Font = Enum.Font.Gotham
        L_25_.TextXAlignment = Enum.TextXAlignment.Center
        L_25_.TextWrapped = true
        L_25_.Parent = L_22_
        local L_26_ = Instance.new("TextLabel")
        L_26_.Name = "HwidTypeDisplay"
        L_26_.Size = UDim2.new(1, -20, 0, 20)
        L_26_.Position = UDim2.new(0, 10, 0, 115)
        L_26_.BackgroundTransparency = 1
        L_26_.Text = "Type: Loading..."
        L_26_.TextColor3 = Color3.fromRGB(180, 180, 180)
        L_26_.TextSize = 12
        L_26_.Font = Enum.Font.Gotham
        L_26_.TextXAlignment = Enum.TextXAlignment.Center
        L_26_.Parent = L_22_
        local L_27_ = Instance.new("TextLabel")
        L_27_.Name = "LastUpdatedLabel"
        L_27_.Size = UDim2.new(1, -20, 0, 30)
        L_27_.Position = UDim2.new(0, 10, 0, 140)
        L_27_.BackgroundTransparency = 1
        L_27_.Text = "Last updated: Never"
        L_27_.TextColor3 = Color3.fromRGB(150, 150, 150)
        L_27_.TextSize = 12
        L_27_.Font = Enum.Font.Gotham
        L_27_.TextXAlignment = Enum.TextXAlignment.Center
        L_27_.Parent = L_22_
        local L_28_ = Instance.new("TextLabel")
        L_28_.Name = "WhitelistInfoLabel"
        L_28_.Size = UDim2.new(1, -20, 0, 20)
        L_28_.Position = UDim2.new(0, 10, 0, 175)
        L_28_.BackgroundTransparency = 1
        L_28_.Text = "Whitelist size: Loading..."
        L_28_.TextColor3 = Color3.fromRGB(150, 150, 150)
        L_28_.TextSize = 12
        L_28_.Font = Enum.Font.Gotham
        L_28_.TextXAlignment = Enum.TextXAlignment.Center
        L_28_.Parent = L_22_
        local L_29_ = Instance.new("Frame")
        L_29_.Name = "ActionFrame"
        L_29_.Size = UDim2.new(1, -40, 0, 50)
        L_29_.Position = UDim2.new(0, 20, 0, 310)
        L_29_.BackgroundTransparency = 1
        L_29_.Parent = L_17_
        local L_30_ = Instance.new("TextButton")
        L_30_.Name = "ResetButton"
        L_30_.Size = UDim2.new(0, 100, 1, 0)
        L_30_.Position = UDim2.new(0, 0, 0, 0)
        L_30_.BackgroundColor3 = Color3.fromRGB(255, 170, 0)
        L_30_.BorderSizePixel = 0
        L_30_.Text = "Reset"
        L_30_.TextColor3 = Color3.new(1, 1, 1)
        L_30_.TextSize = 16
        L_30_.Font = Enum.Font.Gotham
        L_30_.Visible = false
        L_30_.Parent = L_29_
        local L_31_ = Instance.new("UICorner")
        L_31_.CornerRadius = UDim.new(0, 8)
        L_31_.Parent = L_30_
        local L_32_ = Instance.new("TextButton")
        L_32_.Name = "CopyButton"
        L_32_.Size = UDim2.new(0, 100, 1, 0)
        L_32_.Position = UDim2.new(0.33, -50, 0, 0)
        L_32_.BackgroundColor3 = Color3.fromRGB(70, 70, 85)
        L_32_.BorderSizePixel = 0
        L_32_.Text = "Copy HWID"
        L_32_.TextColor3 = Color3.new(1, 1, 1)
        L_32_.TextSize = 16
        L_32_.Font = Enum.Font.Gotham
        L_32_.Visible = false
        L_32_.Parent = L_29_
        local L_33_ = Instance.new("UICorner")
        L_33_.CornerRadius = UDim.new(0, 8)
        L_33_.Parent = L_32_
        local L_34_ = Instance.new("TextButton")
        L_34_.Name = "ContinueButton"
        L_34_.Size = UDim2.new(0, 100, 1, 0)
        L_34_.Position = UDim2.new(0.66, -50, 0, 0)
        L_34_.BackgroundColor3 = Color3.fromRGB(85, 170, 255)
        L_34_.BorderSizePixel = 0
        L_34_.Text = "Continue"
        L_34_.TextColor3 = Color3.new(1, 1, 1)
        L_34_.TextSize = 16
        L_34_.Font = Enum.Font.Gotham
        L_34_.Visible = false
        L_34_.Parent = L_29_
        local L_35_ = Instance.new("UICorner")
        L_35_.CornerRadius = UDim.new(0, 8)
        L_35_.Parent = L_34_
        local L_36_ = Instance.new("TextLabel")
        L_36_.Name = "DiscordLink"
        L_36_.Size = UDim2.new(1, -40, 0, 30)
        L_36_.Position = UDim2.new(0, 20, 0, 370)
        L_36_.BackgroundTransparency = 1
        L_36_.Text = "Join our Discord: https://discord.gg/5JndxxJfBj"
        L_36_.TextColor3 = Color3.fromRGB(100, 150, 255)
        L_36_.TextSize = 14
        L_36_.Font = Enum.Font.Gotham
        L_36_.TextXAlignment = Enum.TextXAlignment.Center
        L_36_.Parent = L_17_
        local L_37_ = Instance.new("TextLabel")
        L_37_.Name = "InfoLabel"
        L_37_.Size = UDim2.new(1, -40, 0, 50)
        L_37_.Position = UDim2.new(0, 20, 0, 410)
        L_37_.BackgroundTransparency = 1
        L_37_.Text =
            "This system supports large HWID whitelists (1000+ entries). If your HWID is not whitelisted, please contact an administrator."
        L_37_.TextColor3 = Color3.fromRGB(180, 180, 180)
        L_37_.TextSize = 12
        L_37_.Font = Enum.Font.Gotham
        L_37_.TextXAlignment = Enum.TextXAlignment.Center
        L_37_.TextWrapped = true
        L_37_.Parent = L_17_
        local L_38_ = Instance.new("Frame")
        L_38_.Name = "LoadingIndicator"
        L_38_.Size = UDim2.new(0, 200, 0, 4)
        L_38_.Position = UDim2.new(0.5, -100, 0, 195)
        L_38_.BackgroundColor3 = Color3.fromRGB(85, 170, 255)
        L_38_.BorderSizePixel = 0
        L_38_.Parent = L_22_
        local L_39_ = Instance.new("UICorner")
        L_39_.CornerRadius = UDim.new(0, 2)
        L_39_.Parent = L_38_
        local L_40_ = game:GetService("TweenService")
        local L_41_ = game:GetService("UserInputService")
        local L_42_ = false
        local L_43_ = true
        local L_44_ = 0
        local function L_45_func()
            L_43_ = false
            L_38_:TweenSize(UDim2.new(0, 0, 0, 4), Enum.EasingDirection.Out, Enum.EasingStyle.Quart, 0.3, true)
            if L_1_ then
                L_24_.Text = "✓ HWID Whitelisted"
                L_24_.TextColor3 = Color3.fromRGB(85, 255, 85)
                L_25_.Text = "Your HWID is in our whitelist"
                L_25_.TextColor3 = Color3.fromRGB(200, 255, 200)
                L_34_.Visible = true
                L_34_.Position = UDim2.new(0.66, -50, 0, 0)
                L_30_.Visible = true
                L_30_.Position = UDim2.new(0, 0, 0, 0)
                L_36_.Visible = false
            else
                L_24_.Text = "✗ HWID Not Whitelisted"
                L_24_.TextColor3 = Color3.fromRGB(255, 85, 85)
                L_25_.Text = "Your HWID: " .. L_2_
                L_25_.TextColor3 = Color3.fromRGB(255, 200, 200)
                L_32_.Visible = true
                L_32_.Position = UDim2.new(0.33, -50, 0, 0)
                L_30_.Visible = true
                L_30_.Position = UDim2.new(0, 0, 0, 0)
                L_36_.Visible = true
            end
        end
        local function L_46_func()
            L_43_ = true
            L_1_ = false
            L_30_.Visible = false
            L_32_.Visible = false
            L_34_.Visible = false
            L_24_.Text = "Checking HWID..."
            L_24_.TextColor3 = Color3.new(1, 1, 1)
            L_25_.Text = "HWID: Loading..."
            L_25_.TextColor3 = Color3.fromRGB(200, 200, 200)
            L_26_.Text = "Type: Loading..."
            L_28_.Text = "Whitelist size: Loading..."
            L_38_:TweenSize(UDim2.new(0, 200, 0, 4), Enum.EasingDirection.Out, Enum.EasingStyle.Quart, 0.3, true)
            task.spawn(
                function()
                    local L_52_ = L_4_func()
                    local L_53_ = os.date("%H:%M:%S")
                    L_27_.Text = "Last updated: " .. L_53_
                    L_26_.Text = "Type: " .. L_3_
                    L_28_.Text = "Whitelist size: " .. tostring(L_44_) .. " entries"
                    L_45_func()
                end
            )
        end
        L_32_.MouseButton1Click:Connect(
            function()
                if setclipboard then
                    setclipboard(L_2_)
                    L_40_:Create(L_32_, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(85, 170, 85)}):Play()
                    L_32_.Text = "Copied!"
                    task.wait(1)
                    L_40_:Create(L_32_, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(70, 70, 85)}):Play()
                    L_32_.Text = "Copy HWID"
                else
                    L_40_:Create(L_32_, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(255, 85, 85)}):Play()
                    L_32_.Text = "Not Supported"
                    task.wait(1)
                    L_40_:Create(L_32_, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(70, 70, 85)}):Play()
                    L_32_.Text = "Copy HWID"
                end
            end
        )
        L_30_.MouseButton1Click:Connect(
            function()
                L_46_func()
            end
        )
        L_34_.MouseButton1Click:Connect(
            function()
                L_42_ = true
                L_16_:Destroy()
            end
        )
        local L_47_ = false
        local L_48_ = nil
        local L_49_ = nil
        local L_50_ = nil
        local function L_51_func(L_54_arg0)
            local L_55_ = L_54_arg0.Position - L_49_
            L_17_.Position = UDim2.new(L_50_.X.Scale, L_50_.X.Offset + L_55_.X, L_50_.Y.Scale, L_50_.Y.Offset + L_55_.Y)
        end
        L_17_.InputBegan:Connect(
            function(L_56_arg0)
                if (L_56_arg0.UserInputType == Enum.UserInputType.MouseButton1) then
                    L_47_ = true
                    L_49_ = L_56_arg0.Position
                    L_50_ = L_17_.Position
                    L_56_arg0.Changed:Connect(
                        function()
                            if (L_56_arg0.UserInputState == Enum.UserInputState.End) then
                                L_47_ = false
                            end
                        end
                    )
                end
            end
        )
        L_17_.InputChanged:Connect(
            function(L_57_arg0)
                if ((L_57_arg0.UserInputType == Enum.UserInputType.MouseMovement) and L_47_) then
                    L_48_ = L_57_arg0
                end
            end
        )
        L_41_.InputChanged:Connect(
            function(L_58_arg0)
                if ((L_58_arg0 == L_48_) and L_47_) then
                    L_51_func(L_58_arg0)
                end
            end
        )
        L_30_.MouseEnter:Connect(
            function()
                L_40_:Create(L_30_, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(255, 190, 0)}):Play()
            end
        )
        L_30_.MouseLeave:Connect(
            function()
                L_40_:Create(L_30_, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(255, 170, 0)}):Play()
            end
        )
        L_32_.MouseEnter:Connect(
            function()
                L_40_:Create(L_32_, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(90, 90, 105)}):Play()
            end
        )
        L_32_.MouseLeave:Connect(
            function()
                L_40_:Create(L_32_, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(70, 70, 85)}):Play()
            end
        )
        L_34_.MouseEnter:Connect(
            function()
                L_40_:Create(L_34_, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(105, 185, 255)}):Play()
            end
        )
        L_34_.MouseLeave:Connect(
            function()
                L_40_:Create(L_34_, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(85, 170, 255)}):Play()
            end
        )
        task.spawn(
            function()
                L_38_:TweenSize(UDim2.new(0, 200, 0, 4), Enum.EasingDirection.Out, Enum.EasingStyle.Quart, 0.3, true)
                local L_59_ = L_4_func()
                local L_60_, L_61_ =
                    pcall(
                    function()
                        local L_63_ = game:HttpGet("https://pastefy.app/zJWLt5xt/raw")
                        local L_64_ = loadstring(L_63_)()
                        L_44_ = 0
                        for L_65_forvar0 in pairs(L_64_) do
                            L_44_ = L_44_ + 1
                        end
                        return L_44_
                    end
                )
                if not L_60_ then
                    L_44_ = 0
                    warn("Failed to count whitelist size: " .. tostring(L_61_))
                end
                local L_62_ = os.date("%H:%M:%S")
                L_27_.Text = "Last updated: " .. L_62_
                L_26_.Text = "Type: " .. L_3_
                L_28_.Text = "Whitelist size: " .. tostring(L_44_) .. " entries"
                L_45_func()
            end
        )
        while L_16_.Parent and not L_42_ do
            task.wait()
        end
        return L_42_
    end
    local L_6_ = L_5_func()
    if L_6_ then
        local L_66_, L_67_ =
            pcall(
            function()
                return loadstring(
                    game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua")
                )()
            end
        )
        if not L_66_ then
            warn("โหลด WindUI ล้มเหลว: " .. L_67_)
            return
        end
        local function L_68_func(L_155_arg0, L_156_arg1, L_157_arg2)
            local L_158_ = ""
            for L_159_forvar0 = 1, #L_155_arg0 do
                local L_160_ = (L_159_forvar0 - 1) / math.max(#L_155_arg0 - 1, 1)
                local L_161_ = math.floor((L_156_arg1.R + ((L_157_arg2.R - L_156_arg1.R) * L_160_)) * 255)
                local L_162_ = math.floor((L_156_arg1.G + ((L_157_arg2.G - L_156_arg1.G) * L_160_)) * 255)
                local L_163_ = math.floor((L_156_arg1.B + ((L_157_arg2.B - L_156_arg1.B) * L_160_)) * 255)
                L_158_ =
                    L_158_ ..
                    '<font color="rgb(' ..
                        L_161_ ..
                            "," ..
                                L_162_ ..
                                    "," .. L_163_ .. ')">' .. L_155_arg0:sub(L_159_forvar0, L_159_forvar0) .. "</font>"
            end
            return L_158_
        end
        local L_69_ = false
        L_67_:Popup(
            {
                Title = "ยินดีต้อนรับสู่ WindUI",
                Icon = "rbxassetid://129260712070622",
                IconThemed = true,
                Content = "ตัวอย่าง UI สำหรับ " ..
                    L_68_func("WindUI", Color3.fromHex("#00FF87"), Color3.fromHex("#60EFFF")),
                Buttons = {{Title = "ยกเลิก", Variant = "Secondary", Callback = function()
                        end}, {Title = "ดำเนินการ", Icon = "arrow-right", Variant = "Primary", Callback = function()
                            L_69_ = true
                        end}}
            }
        )
        repeat
            task.wait()
        until L_69_
        local L_70_ =
            L_67_:CreateWindow(
            {
                Title = "WindUI AutoFarm",
                Icon = "rbxassetid://129260712070622",
                IconThemed = true,
                Author = "AutoFarm Script",
                Folder = "CloudHub",
                Size = UDim2.fromOffset(580, 460),
                Theme = "Dark",
                User = {Enabled = true, Anonymous = true},
                SideBarWidth = 200,
                ScrollBarEnabled = true
            }
        )
        local L_71_ = L_70_:Tab({Title = "หลัก", Icon = "bird"})
        local L_72_ = false
        local L_73_ = false
        local L_74_ = false
        local L_75_ = false
        local L_76_ = {}
        local L_77_ = nil
        local L_78_ = nil
        local L_79_ = nil
        local L_80_ = nil
        local L_81_ = 1
        local L_82_ = {}
        local function L_83_func(L_164_arg0, L_165_arg1)
            if L_82_[L_164_arg0] then
                return L_82_[L_164_arg0]
            end
            return L_165_arg1 * L_81_
        end
        local L_84_ = {
            {
                path = {"AutoFarm", "Plant", "Point", "ProximityPrompt"},
                pos = Vector3.new(6085.27587890625, 49.21938705444336, -2233.761962890625),
                name = "Plant Point",
                waitTime = 185
            },
            {
                path = {"AutoFarm", "Strawberry", "Point", "ProximityPrompt"},
                pos = Vector3.new(5949.7333984375, 48.99654006958008, -1698.1767578125),
                name = "Strawberry Point",
                waitTime = 185
            },
            {
                path = {"AutoFarm", "Grape", "Point", "ProximityPrompt"},
                pos = Vector3.new(5459.58642578125, 47.27458190917969, -1199.485107421875),
                name = "Grape Point",
                waitTime = 185
            },
            {
                path = {"AutoFarm", "Wood", "Point", "ProximityPrompt"},
                pos = Vector3.new(2415.506591796875, 31.06249237060547, -2407.61865234375),
                name = "Wood Point 1",
                waitTime = 185
            },
            {
                path = {"AutoFarm", "Chilli", "Point", "ProximityPrompt"},
                pos = Vector3.new(-612.934814453125, 21.25594711303711, -3341.207275390625),
                name = "Chilli Point 2",
                waitTime = 185
            },
            {
                path = {"AutoFarm", "Grassbush", "Point", "ProximityPrompt"},
                pos = Vector3.new(-2449.72412109375, 73, -2038.025390625),
                name = "Grassbush Point",
                waitTime = 750
            },
            {
                path = {"AutoFarm", "Flower", "Point", "ProximityPrompt"},
                pos = Vector3.new(-1785.1405029296875, 128.125, 1138.6656494140625),
                name = "Flower Point",
                waitTime = 700
            },
            {
                path = {"AutoFarm", "Banana", "Point", "ProximityPrompt"},
                pos = Vector3.new(-1093.5892333984375, 135.50192260742188, 2417.61083984375),
                name = "Banana Point",
                waitTime = 185
            },
            {
                path = {"AutoFarm", "Pork", "Point", "ProximityPrompt"},
                pos = Vector3.new(-538.1380004882812, 56.65624237060547, 3128.591064453125),
                name = "Pork Point",
                waitTime = 185
            },
            {
                path = {"AutoFarm", "Coconut", "Point", "ProximityPrompt"},
                pos = Vector3.new(-2833.5302734375, 18.511947631835938, 2197.18505859375),
                name = "Coconut Point",
                waitTime = 185
            }
        }
        local L_85_ = game:GetService("Players")
        local L_86_ = L_85_.LocalPlayer
        local L_87_ = game:GetService("VirtualInputManager")
        local L_88_ = game:GetService("RunService")
        local L_89_ = game:GetService("UserInputService")
        local L_90_ = game:GetService("Workspace")
        local L_91_ = L_90_.CurrentCamera
        local function L_92_func()
            local L_166_ = L_86_.Character or L_86_.CharacterAdded:Wait()
            return L_166_:WaitForChild("HumanoidRootPart", 5) or error("ไม่พบ HumanoidRootPart!")
        end
        local function L_93_func()
            L_87_:SendKeyEvent(true, Enum.KeyCode.E, false, game)
            wait(0.05)
            L_87_:SendKeyEvent(false, Enum.KeyCode.E, false, game)
            print("กดปุ่ม E เรียบร้อย!")
        end
        local function L_94_func(L_167_arg0)
            local L_168_ = 2
            for L_169_forvar0 = 1, L_168_ do
                local L_170_ = workspace
                for L_171_forvar0, L_172_forvar1 in ipairs(L_167_arg0) do
                    L_170_ = L_170_:FindFirstChild(L_172_forvar1)
                    if not L_170_ then
                        break
                    end
                end
                if (L_170_ and L_170_:IsA("ProximityPrompt")) then
                    return L_170_
                end
                print(string.format("ไม่พบ ProximityPrompt ในการลองครั้งที่ %d, รอ 0.5 วินาที...", L_169_forvar0))
                wait(0.5)
            end
            warn("ไม่พบ ProximityPrompt หลังลอง " .. L_168_ .. " ครั้ง!")
            return nil
        end
        local function L_95_func()
            local L_173_ = L_86_.Character or L_86_.CharacterAdded:Wait()
            local L_174_ = L_173_:WaitForChild("HumanoidRootPart", 5) or error("ไม่พบ HumanoidRootPart!")
            local L_175_ = tick()
            while (tick() - L_175_) < 5 do
                local L_176_ = Ray.new(L_174_.Position, Vector3.new(0, -10, 0))
                local L_177_, L_178_ = workspace:FindPartOnRay(L_176_, L_173_)
                if (L_177_ and ((L_174_.Position - L_178_).Magnitude < 5)) then
                    return true
                end
                wait(0.1)
            end
            return true
        end
        local function L_96_func(L_179_arg0, L_180_arg1)
            local L_181_ = L_92_func()
            local L_182_ = L_86_.Character:FindFirstChildOfClass("Humanoid")
            if (not L_181_ or not L_182_) then
                return
            end
            L_182_.WalkSpeed = 0
            L_182_.JumpPower = 0
            L_182_.PlatformStand = true
            L_181_.Anchored = true
            L_181_.CFrame = CFrame.new(L_179_arg0 + Vector3.new(0, -10, 0))
            print(string.format("ลอยตัวนิ่งที่ %s", L_180_arg1))
            wait(1.5)
            L_181_.Anchored = false
            L_182_.PlatformStand = false
            L_182_.WalkSpeed = 40
            L_182_.JumpPower = 50
            L_181_.CFrame = CFrame.new(L_179_arg0)
            L_181_.Velocity = Vector3.new(0, 0, 0)
            print(string.format("ลงพื้นที่ %s", L_180_arg1))
            L_95_func()
            L_67_:Notify(
                {
                    Title = "สำเร็จ",
                    Content = string.format("ถึง %s เรียบร้อย", L_180_arg1),
                    Icon = "check",
                    Duration = 2
                }
            )
        end
        local function L_97_func(L_183_arg0, L_184_arg1, L_185_arg2, L_186_arg3, L_187_arg4)
            if not L_187_arg4() then
                return
            end
            print(string.format("เริ่ม AutoFarm ที่ %s", L_185_arg2))
            L_96_func(L_184_arg1, L_185_arg2)
            local L_188_ = L_94_func(L_183_arg0)
            if not L_188_ then
                warn(string.format("ข้าม %s: ไม่พบ ProximityPrompt", L_185_arg2))
                return
            end
            L_188_.HoldDuration = 0
            print(string.format("ปรับ HoldDuration เป็น 0 สำหรับ %s", L_185_arg2))
            for L_190_forvar0 = 1, 3 do
                if not L_187_arg4() then
                    return
                end
                L_93_func()
                wait(0.3)
            end
            local L_189_ = L_83_func(L_185_arg2, L_186_arg3)
            wait(math.min(L_189_, 750))
            print(string.format("เสร็จสิ้น AutoFarm ที่ %s (รอ %d วินาที)", L_185_arg2, L_189_))
        end
        local function L_98_func()
            local function L_191_func(L_192_arg0)
                L_87_:SendKeyEvent(true, L_192_arg0, false, game)
                wait(0.05)
                L_87_:SendKeyEvent(false, L_192_arg0, false, game)
            end
            L_191_func(Enum.KeyCode.BackSlash)
            wait(0.1)
            L_191_func(Enum.KeyCode.Left)
            wait(0.1)
            L_191_func(Enum.KeyCode.Right)
            wait(0.1)
            L_191_func(Enum.KeyCode.Right)
            wait(0.1)
            L_191_func(Enum.KeyCode.Down)
            wait(0.1)
            L_191_func(Enum.KeyCode.Down)
            wait(0.1)
            L_191_func(Enum.KeyCode.Down)
            wait(0.1)
            L_191_func(Enum.KeyCode.Down)
            wait(0.1)
            L_191_func(Enum.KeyCode.Down)
            wait(0.1)
            L_191_func(Enum.KeyCode.Down)
            wait(0.1)
            L_191_func(Enum.KeyCode.Down)
            wait(0.1)
            L_191_func(Enum.KeyCode.Down)
            wait(0.1)
            L_191_func(Enum.KeyCode.Down)
            wait(0.1)
            L_191_func(Enum.KeyCode.Down)
            wait(0.1)
            L_191_func(Enum.KeyCode.Return)
            wait(0.1)
            L_191_func(Enum.KeyCode.Down)
            wait(0.1)
            L_191_func(Enum.KeyCode.Down)
            wait(0.1)
            L_191_func(Enum.KeyCode.Down)
            wait(0.1)
            L_191_func(Enum.KeyCode.Left)
            wait(0.1)
            L_191_func(Enum.KeyCode.Left)
            wait(0.1)
            L_191_func(Enum.KeyCode.Down)
            wait(0.1)
            L_191_func(Enum.KeyCode.Right)
            wait(0.1)
            L_191_func(Enum.KeyCode.Down)
            wait(0.1)
            L_191_func(Enum.KeyCode.Up)
            wait(0.1)
            L_191_func(Enum.KeyCode.Up)
            wait(0.1)
            L_191_func(Enum.KeyCode.Right)
            wait(0.1)
            L_191_func(Enum.KeyCode.Up)
            wait(0.1)
            L_191_func(Enum.KeyCode.Return)
            wait(0.1)
            L_191_func(Enum.KeyCode.Down)
            wait(0.1)
            L_191_func(Enum.KeyCode.Left)
            wait(0.1)
            L_191_func(Enum.KeyCode.Return)
            wait(0.1)
            L_191_func(Enum.KeyCode.Up)
            wait(0.1)
            L_191_func(Enum.KeyCode.Up)
            wait(0.1)
            L_191_func(Enum.KeyCode.Up)
            wait(0.1)
            L_191_func(Enum.KeyCode.Up)
            wait(0.1)
            L_191_func(Enum.KeyCode.Up)
            wait(0.1)
            L_191_func(Enum.KeyCode.Up)
            wait(0.1)
            L_191_func(Enum.KeyCode.Up)
            wait(0.1)
            L_191_func(Enum.KeyCode.Up)
            wait(0.1)
            L_191_func(Enum.KeyCode.Up)
            wait(0.1)
            L_191_func(Enum.KeyCode.Up)
            wait(0.1)
            L_191_func(Enum.KeyCode.Up)
            wait(0.1)
            L_191_func(Enum.KeyCode.Up)
            wait(0.1)
            L_191_func(Enum.KeyCode.Up)
            wait(0.1)
            L_191_func(Enum.KeyCode.Up)
            wait(0.1)
            L_191_func(Enum.KeyCode.Right)
            wait(0.1)
            L_191_func(Enum.KeyCode.Right)
            wait(0.1)
            L_191_func(Enum.KeyCode.Up)
            wait(0.1)
            L_191_func(Enum.KeyCode.Return)
            wait(0.1)
        end
        local function L_99_func()
            local function L_193_func(L_194_arg0)
                L_87_:SendKeyEvent(true, L_194_arg0, false, game)
                wait(0.05)
                L_87_:SendKeyEvent(false, L_194_arg0, false, game)
            end
            L_193_func(Enum.KeyCode.BackSlash)
            wait(0.1)
            L_193_func(Enum.KeyCode.Left)
            wait(0.1)
            L_193_func(Enum.KeyCode.Down)
            wait(0.1)
            L_193_func(Enum.KeyCode.Down)
            wait(0.1)
            L_193_func(Enum.KeyCode.Down)
            wait(0.1)
            L_193_func(Enum.KeyCode.Down)
            wait(0.1)
            L_193_func(Enum.KeyCode.Down)
            wait(0.1)
            L_193_func(Enum.KeyCode.Down)
            wait(0.1)
            L_193_func(Enum.KeyCode.Down)
            wait(0.1)
            L_193_func(Enum.KeyCode.Down)
            wait(0.1)
            L_193_func(Enum.KeyCode.Down)
            wait(0.1)
            L_193_func(Enum.KeyCode.Return)
            wait(0.1)
            L_193_func(Enum.KeyCode.Down)
            wait(0.1)
            L_193_func(Enum.KeyCode.Down)
            wait(0.1)
            L_193_func(Enum.KeyCode.Down)
            wait(0.1)
            L_193_func(Enum.KeyCode.Down)
            wait(0.1)
            L_193_func(Enum.KeyCode.Down)
            wait(0.1)
            L_193_func(Enum.KeyCode.Right)
            wait(0.1)
            L_193_func(Enum.KeyCode.Down)
            wait(0.1)
            L_193_func(Enum.KeyCode.Up)
            wait(0.1)
            L_193_func(Enum.KeyCode.Up)
            wait(0.1)
            L_193_func(Enum.KeyCode.Right)
            wait(0.1)
            L_193_func(Enum.KeyCode.Up)
            wait(0.1)
            L_193_func(Enum.KeyCode.Return)
            wait(0.1)
            L_193_func(Enum.KeyCode.Down)
            wait(0.1)
            L_193_func(Enum.KeyCode.Left)
            wait(0.1)
            L_193_func(Enum.KeyCode.Return)
            wait(0.1)
            L_193_func(Enum.KeyCode.Up)
            wait(0.1)
            L_193_func(Enum.KeyCode.Up)
            wait(0.1)
            L_193_func(Enum.KeyCode.Up)
            wait(0.1)
            L_193_func(Enum.KeyCode.Up)
            wait(0.1)
            L_193_func(Enum.KeyCode.Up)
            wait(0.1)
            L_193_func(Enum.KeyCode.Up)
            wait(0.1)
            L_193_func(Enum.KeyCode.Up)
            wait(0.1)
            L_193_func(Enum.KeyCode.Up)
            wait(0.1)
            L_193_func(Enum.KeyCode.Up)
            wait(0.1)
            L_193_func(Enum.KeyCode.Up)
            wait(0.1)
            L_193_func(Enum.KeyCode.Up)
            wait(0.1)
            L_193_func(Enum.KeyCode.Up)
            wait(0.1)
            L_193_func(Enum.KeyCode.Up)
            wait(0.1)
            L_193_func(Enum.KeyCode.Up)
            wait(0.1)
            L_193_func(Enum.KeyCode.Right)
            wait(0.1)
            L_193_func(Enum.KeyCode.Right)
            wait(0.1)
            L_193_func(Enum.KeyCode.Up)
            wait(0.1)
            L_193_func(Enum.KeyCode.Return)
            wait(0.1)
        end
        local function L_100_func()
            local L_195_ = {
                path = {"AutoFarm", "Grassbush", "Point", "ProximityPrompt"},
                pos = Vector3.new(-2449.72412109375, 73, -2038.025390625),
                name = "Grassbush Point",
                waitTime = 750
            }
            local L_196_ = {"NPC", "Economy", "HumanoidRootPart", "ProximityPrompt"}
            while L_74_ do
                local L_197_, L_198_ =
                    pcall(
                    L_97_func,
                    L_195_.path,
                    L_195_.pos,
                    L_195_.name,
                    L_195_.waitTime,
                    function()
                        return L_74_
                    end
                )
                if not L_197_ then
                    warn(string.format("เกิดข้อผิดพลาดที่ %s: %s", L_195_.name, L_198_))
                    L_67_:Notify(
                        {
                            Title = "ข้อผิดพลาด",
                            Content = string.format("เกิดข้อผิดพลาดที่ %s", L_195_.name),
                            Icon = "x",
                            Duration = 3
                        }
                    )
                end
                if not L_74_ then
                    break
                end
                local L_199_ = L_94_func(L_196_)
                if L_199_ then
                    L_96_func(L_199_.Parent.Position, "Economy NPC")
                    L_199_.HoldDuration = 0
                    print("ปรับ HoldDuration เป็น 0 สำหรับ Economy NPC")
                    for L_200_forvar0 = 1, 3 do
                        if not L_74_ then
                            break
                        end
                        L_93_func()
                        wait(0.3)
                    end
                    L_99_func()
                    L_67_:Notify(
                        {Title = "สำเร็จ", Content = "ดำเนินการโอนเงินเรียบร้อย", Icon = "check", Duration = 2}
                    )
                else
                    warn("ไม่พบ ProximityPrompt ที่ NPC Economy")
                    L_67_:Notify(
                        {
                            Title = "ข้อผิดพลาด",
                            Content = "ไม่พบ ProximityPrompt ที่ NPC Economy",
                            Icon = "x",
                            Duration = 3
                        }
                    )
                end
                wait(0.1)
            end
            print("หยุดการโอนเงิน")
        end
        local function L_101_func()
            local L_201_ = {
                path = {"AutoFarm", "Coconut", "Point", "ProximityPrompt"},
                pos = Vector3.new(-2833.5302734375, 18.511947631835938, 2197.18505859375),
                name = "Coconut Point",
                waitTime = 185
            }
            local L_202_ = {"NPC", "Economy", "HumanoidRootPart", "ProximityPrompt"}
            while L_75_ do
                local L_203_, L_204_ =
                    pcall(
                    L_97_func,
                    L_201_.path,
                    L_201_.pos,
                    L_201_.name,
                    L_201_.waitTime,
                    function()
                        return L_75_
                    end
                )
                if not L_203_ then
                    warn(string.format("เกิดข้อผิดพลาดที่ %s: %s", L_201_.name, L_204_))
                    L_67_:Notify(
                        {
                            Title = "ข้อผิดพลาด",
                            Content = string.format("เกิดข้อผิดพลาดที่ %s", L_201_.name),
                            Icon = "x",
                            Duration = 3
                        }
                    )
                end
                if not L_75_ then
                    break
                end
                local L_205_ = L_94_func(L_202_)
                if L_205_ then
                    L_96_func(L_205_.Parent.Position, "Economy NPC")
                    L_205_.HoldDuration = 0
                    print("ปรับ HoldDuration เป็น 0 สำหรับ Economy NPC")
                    for L_206_forvar0 = 1, 3 do
                        if not L_75_ then
                            break
                        end
                        L_93_func()
                        wait(0.3)
                    end
                    L_99_func()
                    L_67_:Notify(
                        {Title = "สำเร็จ", Content = "ดำเนินการโต้ตอบ NPC เรียบร้อย", Icon = "check", Duration = 2}
                    )
                else
                    warn("ไม่พบ ProximityPrompt ที่ NPC Economy")
                    L_67_:Notify(
                        {
                            Title = "ข้อผิดพลาด",
                            Content = "ไม่พบ ProximityPrompt ที่ NPC Economy",
                            Icon = "x",
                            Duration = 3
                        }
                    )
                end
                wait(0.1)
            end
            print("หยุดการฟาร์ม Coconut")
        end
        local L_102_ = {}
        for L_207_forvar0, L_208_forvar1 in ipairs(L_84_) do
            table.insert(L_102_, L_208_forvar1.name)
        end
        local L_103_ =
            L_71_:Dropdown(
            {
                Title = "เลือกจุดฟาร์ม",
                Values = L_102_,
                Value = {},
                Multi = true,
                AllowNone = true,
                Callback = function(L_209_arg0)
                    L_76_ = L_209_arg0
                    print("จุดที่เลือก: " .. game:GetService("HttpService"):JSONEncode(L_209_arg0))
                end
            }
        )
        local L_104_ =
            L_71_:Toggle(
            {
                Title = "เริ่ม/หยุดฟาร์มที่เลือก",
                Desc = "เปิด/ปิดการฟาร์มที่จุดที่เลือกใน Dropdown",
                Icon = "play",
                Value = false,
                Callback = function(L_210_arg0)
                    L_72_ = L_210_arg0
                    if L_210_arg0 then
                        if (#L_76_ == 0) then
                            L_67_:Notify(
                                {
                                    Title = "ข้อผิดพลาด",
                                    Content = "กรุณาเลือกจุดฟาร์มอย่างน้อย 1 จุด",
                                    Icon = "x",
                                    Duration = 3
                                }
                            )
                            SelectToggle:Set(false)
                            L_72_ = false
                            return
                        end
                        if L_73_ then
                            AllFarmToggle:Set(false)
                            L_73_ = false
                            if L_78_ then
                                coroutine.close(L_78_)
                                L_78_ = nil
                            end
                        end
                        if L_74_ then
                            TransferMoneyToggle:Set(false)
                            L_74_ = false
                            if L_79_ then
                                coroutine.close(L_79_)
                                L_79_ = nil
                            end
                        end
                        if L_75_ then
                            CoconutFarmToggle:Set(false)
                            L_75_ = false
                            if L_80_ then
                                coroutine.close(L_80_)
                                L_80_ = nil
                            end
                        end
                        L_67_:Notify(
                            {Title = "AutoFarm", Content = "เริ่มฟาร์มที่จุดที่เลือก!", Icon = "check", Duration = 2}
                        )
                        if L_77_ then
                            coroutine.close(L_77_)
                            L_77_ = nil
                        end
                        L_77_ =
                            coroutine.create(
                            function()
                                while L_72_ do
                                    for L_211_forvar0, L_212_forvar1 in ipairs(L_76_) do
                                        if not L_72_ then
                                            break
                                        end
                                        for L_213_forvar0, L_214_forvar1 in ipairs(L_84_) do
                                            if (L_214_forvar1.name == L_212_forvar1) then
                                                local L_215_, L_216_ =
                                                    pcall(
                                                    L_97_func,
                                                    L_214_forvar1.path,
                                                    L_214_forvar1.pos,
                                                    L_214_forvar1.name,
                                                    L_214_forvar1.waitTime,
                                                    function()
                                                        return L_72_
                                                    end
                                                )
                                                if not L_215_ then
                                                    warn(
                                                        string.format(
                                                            "เกิดข้อผิดพลาดที่ %s: %s",
                                                            L_214_forvar1.name,
                                                            L_216_
                                                        )
                                                    )
                                                end
                                                break
                                            end
                                        end
                                        if not L_72_ then
                                            break
                                        end
                                        wait(0.1)
                                    end
                                end
                                print("หยุด AutoFarm ที่เลือก")
                            end
                        )
                        coroutine.resume(L_77_)
                    else
                        L_67_:Notify(
                            {Title = "AutoFarm", Content = "หยุดฟาร์มที่จุดที่เลือก!", Icon = "x", Duration = 2}
                        )
                        if L_77_ then
                            coroutine.close(L_77_)
                            L_77_ = nil
                        end
                    end
                end
            }
        )
        local L_105_ =
            L_71_:Toggle(
            {
                Title = "Enable AutoFarm (ทั้งหมด)",
                Desc = "เริ่ม/หยุดการทำงานของ AutoFarm ทั้งหมด",
                Value = false,
                Callback = function(L_217_arg0)
                    L_73_ = L_217_arg0
                    if L_217_arg0 then
                        if L_72_ then
                            L_104_:Set(false)
                            L_72_ = false
                            if L_77_ then
                                coroutine.close(L_77_)
                                L_77_ = nil
                            end
                        end
                        if L_74_ then
                            TransferMoneyToggle:Set(false)
                            L_74_ = false
                            if L_79_ then
                                coroutine.close(L_79_)
                                L_79_ = nil
                            end
                        end
                        if L_75_ then
                            CoconutFarmToggle:Set(false)
                            L_75_ = false
                            if L_80_ then
                                coroutine.close(L_80_)
                                L_80_ = nil
                            end
                        end
                        L_67_:Notify(
                            {Title = "AutoFarm", Content = "AutoFarm เริ่มทำงาน!", Icon = "check", Duration = 2}
                        )
                        if L_78_ then
                            coroutine.close(L_78_)
                            L_78_ = nil
                        end
                        L_78_ =
                            coroutine.create(
                            function()
                                while L_73_ do
                                    for L_218_forvar0, L_219_forvar1 in ipairs(L_84_) do
                                        if not L_73_ then
                                            break
                                        end
                                        local L_220_, L_221_ =
                                            pcall(
                                            L_97_func,
                                            L_219_forvar1.path,
                                            L_219_forvar1.pos,
                                            L_219_forvar1.name,
                                            L_219_forvar1.waitTime,
                                            function()
                                                return L_73_
                                            end
                                        )
                                        if not L_220_ then
                                            warn(string.format("เกิดข้อผิดพลาดที่ %s: %s", L_219_forvar1.name, L_221_))
                                        end
                                        wait(0.1)
                                    end
                                end
                                print("หยุด AutoFarm ทั้งหมด")
                            end
                        )
                        coroutine.resume(L_78_)
                    else
                        L_67_:Notify({Title = "AutoFarm", Content = "AutoFarm หยุดทำงาน!", Icon = "x", Duration = 2})
                        if L_78_ then
                            coroutine.close(L_78_)
                            L_78_ = nil
                        end
                    end
                end
            }
        )
        local L_106_ =
            L_71_:Toggle(
            {
                Title = "ฟาร์ม Grassbush ขาย NPC",
                Desc = "ฟาร์ม Grassbush ขาย NPC",
                Icon = "play",
                Value = false,
                Callback = function(L_222_arg0)
                    L_74_ = L_222_arg0
                    if L_222_arg0 then
                        if L_72_ then
                            L_104_:Set(false)
                            L_72_ = false
                            if L_77_ then
                                coroutine.close(L_77_)
                                L_77_ = nil
                            end
                        end
                        if L_73_ then
                            L_105_:Set(false)
                            L_73_ = false
                            if L_78_ then
                                coroutine.close(L_78_)
                                L_78_ = nil
                            end
                        end
                        if L_75_ then
                            CoconutFarmToggle:Set(false)
                            L_75_ = false
                            if L_80_ then
                                coroutine.close(L_80_)
                                L_80_ = nil
                            end
                        end
                        L_67_:Notify(
                            {
                                Title = "โอนเงิน",
                                Content = "เริ่มฟาร์ม Grassbush และโอนเงิน!",
                                Icon = "check",
                                Duration = 2
                            }
                        )
                        if L_79_ then
                            coroutine.close(L_79_)
                            L_79_ = nil
                        end
                        L_79_ = coroutine.create(L_100_func)
                        coroutine.resume(L_79_)
                    else
                        L_67_:Notify({Title = "โอนเงิน", Content = "หยุดการฟาร์มและโอนเงิน!", Icon = "x", Duration = 2})
                        if L_79_ then
                            coroutine.close(L_79_)
                            L_79_ = nil
                        end
                    end
                end
            }
        )
        local L_107_ =
            L_71_:Toggle(
            {
                Title = "ฟาร์ม Coconut",
                Desc = "ฟาร์ม Coconut และโต้ตอบ NPC",
                Icon = "play",
                Value = false,
                Callback = function(L_223_arg0)
                    L_75_ = L_223_arg0
                    if L_223_arg0 then
                        if L_72_ then
                            L_104_:Set(false)
                            L_72_ = false
                            if L_77_ then
                                coroutine.close(L_77_)
                                L_77_ = nil
                            end
                        end
                        if L_73_ then
                            L_105_:Set(false)
                            L_73_ = false
                            if L_78_ then
                                coroutine.close(L_78_)
                                L_78_ = nil
                            end
                        end
                        if L_74_ then
                            L_106_:Set(false)
                            L_74_ = false
                            if L_79_ then
                                coroutine.close(L_79_)
                                L_79_ = nil
                            end
                        end
                        L_67_:Notify(
                            {
                                Title = "ฟาร์ม Coconut",
                                Content = "เริ่มฟาร์ม Coconut และโต้ตอบ NPC!",
                                Icon = "check",
                                Duration = 2
                            }
                        )
                        if L_80_ then
                            coroutine.close(L_80_)
                            L_80_ = nil
                        end
                        L_80_ = coroutine.create(L_101_func)
                        coroutine.resume(L_80_)
                    else
                        L_67_:Notify(
                            {
                                Title = "ฟาร์ม Coconut",
                                Content = "หยุดการฟาร์ม Coconut และโต้ตอบ NPC!",
                                Icon = "x",
                                Duration = 2
                            }
                        )
                        if L_80_ then
                            coroutine.close(L_80_)
                            L_80_ = nil
                        end
                    end
                end
            }
        )
        L_81_ = 1
        local L_108_ = L_70_:Tab({Title = "ข้อมูลผู้เล่น", Icon = "package"})
        local function L_109_func()
            local L_224_ = {}
            for L_225_forvar0, L_226_forvar1 in ipairs(L_85_:GetPlayers()) do
                table.insert(L_224_, L_226_forvar1.Name)
            end
            return L_224_
        end
        local L_110_ = nil
        local L_111_ =
            L_108_:Dropdown(
            {
                Title = "เลือกผู้เล่น",
                Values = L_109_func(),
                Value = nil,
                Multi = false,
                AllowNone = false,
                Callback = function(L_227_arg0)
                    L_110_ = L_227_arg0
                end
            }
        )
        local function L_112_func(L_228_arg0)
            local L_229_ = L_85_:FindFirstChild(L_228_arg0) or error("ไม่พบผู้เล่น: " .. L_228_arg0)
            print("=== ข้อมูลเบอร์โทรศัพท์ของ " .. L_228_arg0 .. " ===")
            local L_230_ = L_229_:FindFirstChild("Phone")
            if L_230_ then
                print("Object: Phone (Folder)")
                for L_231_forvar0, L_232_forvar1 in pairs(L_230_:GetAttributes()) do
                    print(L_231_forvar0 .. ": " .. tostring(L_232_forvar1))
                end
                for L_233_forvar0, L_234_forvar1 in ipairs(L_230_:GetChildren()) do
                    print(L_234_forvar1.Name .. ": " .. tostring(L_234_forvar1.Value))
                end
            else
                print("ไม่พบข้อมูลเบอร์โทรศัพท์")
            end
            print("=====================================")
        end
        local function L_113_func(L_235_arg0)
            local L_236_ = L_85_:FindFirstChild(L_235_arg0) or error("ไม่พบผู้เล่น: " .. L_235_arg0)
            local L_237_ = L_236_:FindFirstChild("Inventory") or L_236_:FindFirstChild("คลังไอเท็ม")
            if not L_237_ then
                warn("ไม่พบโฟลเดอร์ Inventory หรือ คลังไอเท็ม")
                return
            end
            print("=== ไอเทมที่มีค่ามากกว่า 1 ของ " .. L_235_arg0 .. " ===")
            local L_238_ = false
            for L_239_forvar0, L_240_forvar1 in pairs(L_237_:GetAttributes()) do
                if ((type(L_240_forvar1) == "number") and (L_240_forvar1 > 1)) then
                    print(L_239_forvar0 .. ": " .. tostring(L_240_forvar1))
                    L_238_ = true
                end
            end
            if not L_238_ then
                print("ไม่มีไอเทมที่มีค่ามากกว่า 1")
            end
            print("=====================================")
        end
        L_108_:Button(
            {Title = "ตรวจสอบของ", Icon = "search", Callback = function()
                    if not L_110_ then
                        warn("กรุณาเลือกผู้เล่นก่อน")
                        return
                    end
                    L_113_func(L_110_)
                end}
        )
        L_108_:Button(
            {Title = "ตรวจสอบเบอร์โทร", Icon = "phone", Callback = function()
                    if not L_110_ then
                        warn("กรุณาเลือกผู้เล่นก่อน")
                        return
                    end
                    L_112_func(L_110_)
                end}
        )
        local L_114_ = L_70_:Tab({Title = "ดูตัวละคร", Icon = "bird"})
        local L_115_ = false
        local L_116_ = nil
        local L_117_ = nil
        local L_118_ = nil
        local L_119_ = nil
        local L_120_ = false
        local L_121_ = false
        local L_122_ = 0
        local L_123_ = 2
        local L_124_ = L_91_.CameraType
        local L_125_ = L_91_.CFrame
        local L_126_ = nil
        local L_127_ = nil
        local function L_128_func()
            local L_241_ = L_90_:FindFirstChild("Character") or {}
            local L_242_ = {}
            for L_243_forvar0, L_244_forvar1 in pairs(L_241_:GetChildren()) do
                if
                    (L_244_forvar1:IsA("Model") and L_244_forvar1:FindFirstChildOfClass("Humanoid") and
                        (L_244_forvar1 ~= L_86_.Character))
                 then
                    table.insert(L_242_, L_244_forvar1.Name)
                end
            end
            return L_242_
        end
        local function L_129_func(L_245_arg0)
            local L_246_ = L_90_:FindFirstChild("Character")
            if not L_246_ then
                return nil
            end
            for L_247_forvar0, L_248_forvar1 in pairs(L_246_:GetChildren()) do
                if
                    (L_248_forvar1:IsA("Model") and (L_248_forvar1.Name == L_245_arg0) and
                        L_248_forvar1:FindFirstChildOfClass("Humanoid"))
                 then
                    return L_248_forvar1
                end
            end
            return nil
        end
        local function L_130_func(L_249_arg0)
            if not L_249_arg0 then
                return
            end
            local L_250_ = L_249_arg0:FindFirstChildOfClass("Humanoid")
            if not L_250_ then
                return
            end
            local L_251_ = L_250_:GetState()
            if (L_251_ ~= L_126_) then
                print("Spectating: " .. L_249_arg0.Name)
                print("Humanoid State: " .. tostring(L_251_))
                print("Position: " .. tostring((L_249_arg0.PrimaryPart and L_249_arg0.PrimaryPart.Position) or "N/A"))
                L_126_ = L_251_
            end
        end
        local function L_131_func(L_252_arg0)
            if L_115_ then
                stopSpectating()
            end
            local L_253_ = L_129_func(L_252_arg0)
            if (not L_253_ or not L_253_.PrimaryPart) then
                print("Cannot spectate: Character not found or no valid character!")
                L_67_:Notify(
                    {Title = "ข้อผิดพลาด", Content = "ไม่พบตัวละครหรือตัวละครไม่ถูกต้อง", Icon = "x", Duration = 3}
                )
                return
            end
            L_125_ = L_91_.CFrame
            L_115_ = true
            L_116_ = L_253_
            L_91_.CameraType = Enum.CameraType.Scriptable
            L_122_ = 0
            L_126_ = nil
            L_130_func(L_253_)
            L_117_ =
                L_88_.RenderStepped:Connect(
                function()
                    if (not L_253_.Parent or not L_253_.PrimaryPart) then
                        stopSpectating()
                        return
                    end
                    if L_120_ then
                        L_122_ = L_122_ - L_123_
                    end
                    if L_121_ then
                        L_122_ = L_122_ + L_123_
                    end
                    local L_254_ = L_253_.PrimaryPart.Position
                    local L_255_ = CFrame.new(Vector3.new(0, 5, 10)) * CFrame.Angles(0, math.rad(L_122_), 0)
                    L_91_.CFrame =
                        CFrame.new(L_254_) * L_255_ *
                        CFrame.new(Vector3.new(0, 0, 0), L_254_ - (L_254_ + L_255_.Position))
                    L_130_func(L_253_)
                end
            )
            L_118_ =
                L_89_.InputBegan:Connect(
                function(L_256_arg0, L_257_arg1)
                    if (L_257_arg1 or not L_115_) then
                        return
                    end
                    if (L_256_arg0.KeyCode == Enum.KeyCode.Q) then
                        L_120_ = true
                    elseif (L_256_arg0.KeyCode == Enum.KeyCode.E) then
                        L_121_ = true
                    end
                end
            )
            L_119_ =
                L_89_.InputEnded:Connect(
                function(L_258_arg0, L_259_arg1)
                    if (L_259_arg1 or not L_115_) then
                        return
                    end
                    if (L_258_arg0.KeyCode == Enum.KeyCode.Q) then
                        L_120_ = false
                    elseif (L_258_arg0.KeyCode == Enum.KeyCode.E) then
                        L_121_ = false
                    end
                end
            )
            print("Started spectating: " .. L_253_.Name)
            L_67_:Notify(
                {Title = "ดูตัวละคร", Content = "เริ่มดูตัวละคร: " .. L_253_.Name, Icon = "check", Duration = 2}
            )
        end
        local function L_132_func()
            if L_117_ then
                L_117_:Disconnect()
            end
            if L_118_ then
                L_118_:Disconnect()
            end
            if L_119_ then
                L_119_:Disconnect()
            end
            L_115_ = false
            L_116_ = nil
            L_120_ = false
            L_121_ = false
            L_91_.CameraType = L_124_
            L_91_.CFrame = L_125_
            print("Stopped spectating")
            L_67_:Notify({Title = "ดูตัวละคร", Content = "หยุดการดูตัวละคร", Icon = "x", Duration = 2})
        end
        local function L_133_func(L_260_arg0)
            local L_261_ = L_129_func(L_260_arg0)
            if (not L_261_ or not L_261_.PrimaryPart or not L_86_.Character or not L_86_.Character.PrimaryPart) then
                print("Cannot teleport: No valid character!")
                L_67_:Notify(
                    {Title = "ข้อผิดพลาด", Content = "ไม่พบตัวละครหรือตัวละครไม่ถูกต้อง", Icon = "x", Duration = 3}
                )
                return
            end
            if L_115_ then
                L_132_func()
            end
            L_96_func(L_261_.PrimaryPart.Position + Vector3.new(0, 0, 5), L_261_.Name)
            print("Teleported to: " .. L_261_.Name)
            L_67_:Notify(
                {Title = "เทเลพอร์ต", Content = "เทเลพอร์ตไปที่: " .. L_261_.Name, Icon = "check", Duration = 2}
            )
        end
        local L_134_ = nil
        local function L_135_func()
            L_134_ =
                L_114_:Dropdown(
                {
                    Title = "เลือกตัวละคร",
                    Values = L_128_func(),
                    Value = nil,
                    Multi = false,
                    AllowNone = true,
                    Callback = function(L_262_arg0)
                        L_127_ = L_262_arg0
                        if (L_262_arg0 and (L_262_arg0 ~= "")) then
                            L_131_func(L_262_arg0)
                        else
                            L_132_func()
                        end
                    end
                }
            )
        end
        L_135_func()
        L_114_:Button(
            {Title = "หยุดการติดตาม", Callback = function()
                    if L_115_ then
                        L_132_func()
                    end
                end}
        )
        L_114_:Button(
            {Title = "กลับไปยังมุมมองปกติ", Callback = function()
                    if L_115_ then
                        L_132_func()
                    end
                    L_91_.CameraType = L_124_
                    L_91_.CFrame = L_125_
                    print("Reset view to normal")
                    L_67_:Notify({Title = "มุมมอง", Content = "กลับไปยังมุมมองปกติ", Icon = "check", Duration = 2})
                end}
        )
        L_114_:Button(
            {Title = "TP ไปหาตัวละคร", Callback = function()
                    if (L_127_ and (L_127_ ~= "")) then
                        L_133_func(L_127_)
                    else
                        print("กรุณาเลือกตัวละครก่อน TP")
                        L_67_:Notify(
                            {Title = "ข้อผิดพลาด", Content = "กรุณาเลือกตัวละครก่อนเทเลพอร์ต", Icon = "x", Duration = 3}
                        )
                    end
                end}
        )
        L_114_:Button(
            {
                Title = "รีเซ็ตรายชื่อ",
                Callback = function()
                    print("=== รายชื่อตัวละครปัจจุบัน ===")
                    local L_263_ = L_128_func()
                    for L_264_forvar0, L_265_forvar1 in ipairs(L_263_) do
                        print(L_264_forvar0 .. ". " .. L_265_forvar1)
                    end
                    print("=== จำนวนทั้งหมด: " .. #L_263_ .. " ตัวละคร ===")
                    pcall(
                        function()
                            if L_134_.Instance then
                                L_134_.Instance:Destroy()
                            end
                        end
                    )
                    L_135_func()
                    print("รีเซ็ตรายชื่อตัวละครเรียบร้อยแล้ว")
                    L_67_:Notify(
                        {Title = "รีเซ็ต", Content = "รีเซ็ตรายชื่อตัวละครเรียบร้อย", Icon = "check", Duration = 2}
                    )
                end
            }
        )
        local L_136_ = L_90_:FindFirstChild("Character")
        if L_136_ then
            L_136_.ChildAdded:Connect(
                function(L_266_arg0)
                    if
                        (L_266_arg0:IsA("Model") and L_266_arg0:FindFirstChildOfClass("Humanoid") and
                            (L_266_arg0 ~= L_86_.Character))
                     then
                        pcall(
                            function()
                                if L_134_.Instance then
                                    L_134_.Instance:Destroy()
                                end
                            end
                        )
                        L_135_func()
                    end
                end
            )
            L_136_.ChildRemoved:Connect(
                function(L_267_arg0)
                    if (L_267_arg0 == L_116_) then
                        L_132_func()
                    end
                end
            )
        end
        local L_137_ = L_70_:Tab({Title = "ทีพี", Icon = "map"})
        local function L_138_func(L_268_arg0, L_269_arg1)
            L_96_func(L_268_arg0, L_269_arg1)
        end
        local L_139_ = {
            {
                Title = "Cars Shop",
                Pos = Vector3.new(2958.12939453125, 22.995704650878906, 2774.292724609375),
                Desc = "tp Cars Shop"
            },
            {
                Title = "Economy",
                Pos = Vector3.new(2853.963134765625, 14.546615600585938, 2111.3544921875),
                Desc = "tp Economy"
            },
            {
                Title = "GlobalMarket",
                Pos = Vector3.new(3090.279052734375, 19.84853744506836, 2616.599365234375),
                Desc = "tp GlobalMarket"
            },
            {
                Title = "Miner",
                Pos = Vector3.new(6152.16845703125, 49.02723693847656, -4226.1162109375),
                Desc = "tp Miner"
            },
            {
                Title = "โต๊ะคราฟของ",
                Pos = Vector3.new(1904.6500244140625, 14.105815887451172, 2306.91796875),
                Desc = "tp โต๊ะคราฟของ"
            },
            {
                Title = "สถานีตำรวจ",
                Pos = Vector3.new(3627.4970703125, 22.067230224609375, 3222.001708984375),
                Desc = "tp สถานีตำรวจ"
            },
            {
                Title = "โรงพยาบาล",
                Pos = Vector3.new(3024.61328125, 14.640356063842773, 3348.82470703125),
                Desc = "tp โรงพยาบาล"
            },
            {
                Title = "ร้านอาหาร",
                Pos = Vector3.new(3490.1767578125, 37.096900939941406, 2630.049560546875),
                Desc = "tp ร้านอาหาร"
            },
            {
                Title = "การาจกลาง",
                Pos = Vector3.new(2966.877197265625, 14.334461212158203, 2091.458984375),
                Desc = "tp การาจกลาง"
            },
            {
                Title = "ผับบาร์",
                Pos = Vector3.new(3131.8134765625, 14.163215637207031, 2331.405029296875),
                Desc = "tp ผับบาร์"
            }
        }
        for L_270_forvar0, L_271_forvar1 in ipairs(L_139_) do
            L_137_:Button(
                {Title = L_271_forvar1.Title, Desc = L_271_forvar1.Desc, Locked = false, Callback = function()
                        L_138_func(L_271_forvar1.Pos, L_271_forvar1.Title)
                    end}
            )
        end
        local L_140_ = L_70_:Tab({Title = "ตั้งค่าสถานะ", Icon = "settings"})
        local L_141_ = game:GetService("Players")
        local L_142_ = L_141_.LocalPlayer
        local function L_143_func(L_272_arg0, L_273_arg1, L_274_arg2)
            local L_275_ = L_142_:FindFirstChild(L_272_arg0)
            if not L_275_ then
                L_67_:Notify({Title = "ข้อผิดพลาด", Content = "ไม่พบโฟลเดอร์ " .. L_272_arg0, Icon = "x", Duration = 3})
                return false
            end
            local L_276_ = L_275_:GetAttributes()
            if (L_276_[L_273_arg1] or (L_276_[L_273_arg1] == 0)) then
                local L_277_, L_278_ =
                    pcall(
                    function()
                        L_275_:SetAttribute(L_273_arg1, tonumber(L_274_arg2))
                    end
                )
                if L_277_ then
                    L_67_:Notify(
                        {
                            Title = "สำเร็จ",
                            Content = string.format("ตั้งค่า %s เป็น %s ใน %s", L_273_arg1, L_274_arg2, L_272_arg0),
                            Icon = "check",
                            Duration = 3
                        }
                    )
                    return true
                else
                    L_67_:Notify(
                        {
                            Title = "ข้อผิดพลาด",
                            Content = "ไม่สามารถตั้งค่า " .. L_273_arg1 .. ": " .. tostring(L_278_),
                            Icon = "x",
                            Duration = 3
                        }
                    )
                    return false
                end
            else
                L_67_:Notify(
                    {
                        Title = "ข้อผิดพลาด",
                        Content = "ไม่พบ Attribute " .. L_273_arg1 .. " ใน " .. L_272_arg0,
                        Icon = "x",
                        Duration = 3
                    }
                )
                return false
            end
        end
        L_140_:Input(
            {
                Title = "ตั้งค่า Stamina",
                Desc = "ป้อนตัวเลขเพื่อตั้งค่า Stamina ใน Status แล้วกด Enter",
                Value = "100",
                InputIcon = "zap",
                Type = "Input",
                Placeholder = "ป้อนตัวเลข...",
                Callback = function(L_279_arg0)
                    if tonumber(L_279_arg0) then
                        L_143_func("Status", "Stamina", L_279_arg0)
                    else
                        L_67_:Notify(
                            {Title = "ข้อผิดพลาด", Content = "กรุณาป้อนตัวเลขที่ถูกต้อง", Icon = "x", Duration = 3}
                        )
                    end
                end
            }
        )
        L_140_:Input(
            {
                Title = "ตั้งค่า Armor",
                Desc = "ป้อนตัวเลขเพื่อตั้งค่า Armor ใน Status แล้วกด Enter",
                Value = "100",
                InputIcon = "shield",
                Type = "Input",
                Placeholder = "ป้อนตัวเลข...",
                Callback = function(L_280_arg0)
                    if tonumber(L_280_arg0) then
                        L_143_func("Status", "Armor", L_280_arg0)
                    else
                        L_67_:Notify(
                            {Title = "ข้อผิดพลาด", Content = "กรุณาป้อนตัวเลขที่ถูกต้อง", Icon = "x", Duration = 3}
                        )
                    end
                end
            }
        )
        L_140_:Input(
            {
                Title = "ตั้งค่า Safe Level",
                Desc = "ป้อนตัวเลขเพื่อตั้งค่า Level ใน Safe แล้วกด Enter",
                Value = "1",
                InputIcon = "lock",
                Type = "Input",
                Placeholder = "ป้อนตัวเลข...",
                Callback = function(L_281_arg0)
                    if tonumber(L_281_arg0) then
                        L_143_func("Safe", "Level", L_281_arg0)
                    else
                        L_67_:Notify(
                            {Title = "ข้อผิดพลาด", Content = "กรุณาป้อนตัวเลขที่ถูกต้อง", Icon = "x", Duration = 3}
                        )
                    end
                end
            }
        )
        L_140_:Input(
            {
                Title = "ตั้งค่า Safe MaxKG",
                Desc = "ป้อนตัวเลขเพื่อตั้งค่า MaxKG ใน Safe แล้วกด Enter",
                Value = "100",
                InputIcon = "package",
                Type = "Input",
                Placeholder = "ป้อนตัวเลข...",
                Callback = function(L_282_arg0)
                    if tonumber(L_282_arg0) then
                        L_143_func("Safe", "MaxKG", L_282_arg0)
                    else
                        L_67_:Notify(
                            {Title = "ข้อผิดพลาด", Content = "กรุณาป้อนตัวเลขที่ถูกต้อง", Icon = "x", Duration = 3}
                        )
                    end
                end
            }
        )
        L_140_:Input(
            {
                Title = "ตั้งค่า Locker Level",
                Desc = "ป้อนตัวเลขเพื่อตั้งค่า Level ใน Locker แล้วกด Enter",
                Value = "1",
                InputIcon = "archive",
                Type = "Input",
                Placeholder = "ป้อนตัวเลข...",
                Callback = function(L_283_arg0)
                    if tonumber(L_283_arg0) then
                        L_143_func("Locker", "Level", L_283_arg0)
                    else
                        L_67_:Notify(
                            {Title = "ข้อผิดพลาด", Content = "กรุณาป้อนตัวเลขที่ถูกต้อง", Icon = "x", Duration = 3}
                        )
                    end
                end
            }
        )
        L_140_:Input(
            {
                Title = "ตั้งค่า Locker MaxKG",
                Desc = "ป้อนตัวเลขเพื่อตั้งค่า MaxKG ใน Locker แล้วกด Enter",
                Value = "100",
                InputIcon = "package",
                Type = "Input",
                Placeholder = "ป้อนตัวเลข...",
                Callback = function(L_284_arg0)
                    if tonumber(L_284_arg0) then
                        L_143_func("Locker", "MaxKG", L_284_arg0)
                    else
                        L_67_:Notify(
                            {Title = "ข้อผิดพลาด", Content = "กรุณาป้อนตัวเลขที่ถูกต้อง", Icon = "x", Duration = 3}
                        )
                    end
                end
            }
        )
        L_67_:Notify({Title = "สคริปต์พร้อม", Content = "พร้อมตั้งค่าสถานะผ่าน Input!", Icon = "check", Duration = 3})
        local L_144_ = L_70_:Tab({Title = "หลัก", Icon = "bird"})
        local L_145_ = {
            speedEnabled = false,
            speedValue = 50,
            jumpEnabled = false,
            jumpValue = 100,
            brightnessEnabled = false,
            brightnessValue = 2,
            fovEnabled = false,
            fovValue = 120,
            fullMapEnabled = false
        }
        local L_146_ = {}
        local L_147_ = {jumpPower = 50, gravity = 196.2, cameraFieldOfView = 70, lightingBrightness = 1}
        local function L_148_func(L_285_arg0)
            if L_146_[L_285_arg0] then
                L_146_[L_285_arg0]:Disconnect()
                L_146_[L_285_arg0] = nil
            end
        end
        local function L_149_func()
            L_148_func("speed")
            if not L_145_.speedEnabled then
                local L_288_ = game.Players.LocalPlayer
                local L_289_ = L_288_.Character
                if L_289_ then
                    local L_290_ = L_289_:FindFirstChild("Humanoid")
                    if L_290_ then
                        L_290_.WalkSpeed = 16
                    end
                end
                return
            end
            local L_286_ = game.Players.LocalPlayer
            local L_287_ = L_286_.Character
            if L_287_ then
                local L_291_ = L_287_:FindFirstChild("Humanoid")
                if L_291_ then
                    L_291_.WalkSpeed = L_145_.speedValue
                end
            end
            L_146_.speed =
                game:GetService("RunService").Heartbeat:Connect(
                function()
                    if L_145_.speedEnabled then
                        local L_292_ = L_286_.Character
                        if L_292_ then
                            local L_293_ = L_292_:FindFirstChildOfClass("Humanoid")
                            if (L_293_ and (L_293_.WalkSpeed ~= L_145_.speedValue)) then
                                L_293_.WalkSpeed = L_145_.speedValue
                            end
                        end
                    end
                end
            )
        end
        local function L_150_func()
            L_148_func("jump")
            L_148_func("jumpGravity")
            if not L_145_.jumpEnabled then
                local L_296_ = game.Players.LocalPlayer
                local L_297_ = L_296_.Character
                if L_297_ then
                    local L_298_ = L_297_:FindFirstChild("Humanoid")
                    if L_298_ then
                        L_298_.JumpPower = L_147_.jumpPower
                    end
                end
                game.Workspace.Gravity = L_147_.gravity
                return
            end
            local L_294_ = game.Players.LocalPlayer
            local L_295_ = L_294_.Character
            if L_295_ then
                local L_299_ = L_295_:FindFirstChild("Humanoid")
                if L_299_ then
                    L_299_.JumpPower = L_145_.jumpValue
                end
            end
            game.Workspace.Gravity = L_147_.gravity / 2
            L_146_.jump =
                game:GetService("RunService").Heartbeat:Connect(
                function()
                    if L_145_.jumpEnabled then
                        local L_300_ = L_294_.Character
                        if L_300_ then
                            local L_301_ = L_300_:FindFirstChildOfClass("Humanoid")
                            if (L_301_ and (L_301_.JumpPower ~= L_145_.jumpValue)) then
                                L_301_.JumpPower = L_145_.jumpValue
                            end
                        end
                    end
                end
            )
            L_146_.jumpGravity =
                game:GetService("RunService").Heartbeat:Connect(
                function()
                    if (L_145_.jumpEnabled and (game.Workspace.Gravity ~= (L_147_.gravity / 2))) then
                        game.Workspace.Gravity = L_147_.gravity / 2
                    end
                end
            )
        end
        local function L_151_func()
            L_148_func("brightness")
            local L_302_ = game.Lighting
            if not L_145_.brightnessEnabled then
                L_302_.Brightness = L_147_.lightingBrightness
                return
            end
            L_302_.Brightness = L_145_.brightnessValue
            L_146_.brightness =
                game:GetService("RunService").Heartbeat:Connect(
                function()
                    if (L_145_.brightnessEnabled and (L_302_.Brightness ~= L_145_.brightnessValue)) then
                        L_302_.Brightness = L_145_.brightnessValue
                    end
                end
            )
        end
        local function L_152_func()
            L_148_func("fov")
            local L_303_ = workspace.CurrentCamera
            if not L_145_.fovEnabled then
                L_303_.FieldOfView = L_147_.cameraFieldOfView
                return
            end
            L_303_.FieldOfView = L_145_.fovValue
            L_146_.fov =
                game:GetService("RunService").Heartbeat:Connect(
                function()
                    if (L_145_.fovEnabled and (L_303_.FieldOfView ~= L_145_.fovValue)) then
                        L_303_.FieldOfView = L_145_.fovValue
                    end
                end
            )
        end
        local function L_153_func()
            L_148_func("fullMap")
            local L_304_ = workspace.CurrentCamera
            if not L_145_.fullMapEnabled then
                L_304_.CameraType = Enum.CameraType.Custom
                return
            end
            L_304_.CameraType = Enum.CameraType.Scriptable
            L_304_.FieldOfView = 120
            local function L_305_func()
                local L_309_ = 0
                local L_310_ = Vector3.new(0, 0, 0)
                for L_311_forvar0, L_312_forvar1 in pairs(workspace:GetChildren()) do
                    if (L_312_forvar1:IsA("Model") and (L_312_forvar1 ~= game.Players.LocalPlayer.Character)) then
                        local L_313_ = L_312_forvar1.PrimaryPart
                        if L_313_ then
                            L_310_ = L_310_ + L_313_.Position
                            L_309_ = L_309_ + 1
                        end
                    end
                end
                if (L_309_ > 0) then
                    return L_310_ / L_309_
                end
                return Vector3.new(0, 100, 0)
            end
            local function L_306_func()
                local L_314_, L_315_ =
                    Vector3.new(math.huge, math.huge, math.huge),
                    Vector3.new(-math.huge, -math.huge, -math.huge)
                for L_318_forvar0, L_319_forvar1 in pairs(workspace:GetChildren()) do
                    if (L_319_forvar1:IsA("Model") and (L_319_forvar1 ~= game.Players.LocalPlayer.Character)) then
                        for L_320_forvar0, L_321_forvar1 in pairs(L_319_forvar1:GetDescendants()) do
                            if L_321_forvar1:IsA("BasePart") then
                                local L_322_ = L_321_forvar1.Position
                                L_314_ =
                                    Vector3.new(
                                    math.min(L_314_.X, L_322_.X),
                                    math.min(L_314_.Y, L_322_.Y),
                                    math.min(L_314_.Z, L_322_.Z)
                                )
                                L_315_ =
                                    Vector3.new(
                                    math.max(L_315_.X, L_322_.X),
                                    math.max(L_315_.Y, L_322_.Y),
                                    math.max(L_315_.Z, L_322_.Z)
                                )
                            end
                        end
                    end
                end
                local L_316_ = L_315_ - L_314_
                local L_317_ = math.max(L_316_.X, L_316_.Y, L_316_.Z)
                return L_317_ * 1.5
            end
            local L_307_ = L_305_func()
            local L_308_ = L_306_func()
            L_304_.CFrame = CFrame.new(L_307_ + Vector3.new(0, L_308_, 0), L_307_)
            L_146_.fullMap =
                game:GetService("RunService").Heartbeat:Connect(
                function()
                    if L_145_.fullMapEnabled then
                        local L_323_ = L_305_func()
                        local L_324_ = L_306_func()
                        L_304_.CFrame = CFrame.new(L_323_ + Vector3.new(0, L_324_, 0), L_323_)
                    end
                end
            )
        end
        local function L_154_func()
            L_148_func("characterAdded")
            local L_325_ = game.Players.LocalPlayer
            L_146_.characterAdded =
                L_325_.CharacterAdded:Connect(
                function(L_326_arg0)
                    local L_327_ = L_326_arg0:WaitForChild("Humanoid")
                    if L_145_.speedEnabled then
                        L_327_.WalkSpeed = L_145_.speedValue
                    end
                    if L_145_.jumpEnabled then
                        L_327_.JumpPower = L_145_.jumpValue
                    end
                end
            )
        end
        L_154_func()
        L_144_:Toggle(
            {
                Title = "วิ่งเร็ว",
                Desc = "เปิด/ปิดการวิ่งเร็ว",
                Icon = "zap",
                Default = false,
                Callback = function(L_328_arg0)
                    L_145_.speedEnabled = L_328_arg0
                    L_149_func()
                end
            }
        )
        L_144_:Input(
            {
                Title = "ความเร็ว",
                Desc = "ป้อนความเร็ว (1-500)",
                Value = "50",
                InputIcon = "gauge",
                Type = "Input",
                Placeholder = "ป้อนความเร็ว...",
                Callback = function(L_329_arg0)
                    local L_330_ = tonumber(L_329_arg0)
                    if L_330_ then
                        if ((L_330_ >= 1) and (L_330_ <= 500)) then
                            L_145_.speedValue = L_330_
                            if L_145_.speedEnabled then
                                local L_331_ = game.Players.LocalPlayer
                                local L_332_ = L_331_.Character
                                if L_332_ then
                                    local L_333_ = L_332_:FindFirstChild("Humanoid")
                                    if L_333_ then
                                        L_333_.WalkSpeed = L_330_
                                    end
                                end
                            end
                        end
                    end
                end
            }
        )
        L_144_:Toggle(
            {
                Title = "กระโดดสูง",
                Desc = "เปิด/ปิดการกระโดดสูง",
                Icon = "arrow-up",
                Default = false,
                Callback = function(L_334_arg0)
                    L_145_.jumpEnabled = L_334_arg0
                    L_150_func()
                end
            }
        )
        L_144_:Input(
            {
                Title = "ความสูงการกระโดด",
                Desc = "ป้อนความสูงการกระโดด (1-500)",
                Value = "100",
                InputIcon = "trending-up",
                Type = "Input",
                Placeholder = "ป้อนความสูง...",
                Callback = function(L_335_arg0)
                    local L_336_ = tonumber(L_335_arg0)
                    if L_336_ then
                        if ((L_336_ >= 1) and (L_336_ <= 500)) then
                            L_145_.jumpValue = L_336_
                            if L_145_.jumpEnabled then
                                local L_337_ = game.Players.LocalPlayer
                                local L_338_ = L_337_.Character
                                if L_338_ then
                                    local L_339_ = L_338_:FindFirstChild("Humanoid")
                                    if L_339_ then
                                        L_339_.JumpPower = L_336_
                                    end
                                end
                                game.Workspace.Gravity = L_147_.gravity / 2
                            end
                        end
                    end
                end
            }
        )
        L_144_:Toggle(
            {
                Title = "ปรับแสงสว่าง",
                Desc = "เปิด/ปิดการปรับแสงสว่าง",
                Icon = "sun",
                Default = false,
                Callback = function(L_340_arg0)
                    L_145_.brightnessEnabled = L_340_arg0
                    L_151_func()
                end
            }
        )
        L_144_:Input(
            {
                Title = "ความสว่าง",
                Desc = "ป้อนความสว่าง (0.1-100)",
                Value = "2",
                InputIcon = "sun-medium",
                Type = "Input",
                Placeholder = "ป้อนความสว่าง...",
                Callback = function(L_341_arg0)
                    local L_342_ = tonumber(L_341_arg0)
                    if L_342_ then
                        if ((L_342_ >= 0.1) and (L_342_ <= 100)) then
                            L_145_.brightnessValue = L_342_
                            if L_145_.brightnessEnabled then
                                game.Lighting.Brightness = L_342_
                            end
                        end
                    end
                end
            }
        )
        L_144_:Toggle(
            {
                Title = "มุมมองกล้อง (FOV)",
                Desc = "เปิด/ปิดการปรับมุมมองกล้อง",
                Icon = "camera",
                Default = false,
                Callback = function(L_343_arg0)
                    L_145_.fovEnabled = L_343_arg0
                    L_152_func()
                end
            }
        )
        L_144_:Input(
            {
                Title = "มุมมองกล้อง",
                Desc = "ป้อนมุมมองกล้อง (1-500)",
                Value = "120",
                InputIcon = "maximize",
                Type = "Input",
                Placeholder = "ป้อนมุมมอง...",
                Callback = function(L_344_arg0)
                    local L_345_ = tonumber(L_344_arg0)
                    if L_345_ then
                        if ((L_345_ >= 1) and (L_345_ <= 500)) then
                            L_145_.fovValue = L_345_
                            if L_145_.fovEnabled then
                                local L_346_ = workspace.CurrentCamera
                                if L_346_ then
                                    L_346_.FieldOfView = L_345_
                                end
                            end
                        end
                    end
                end
            }
        )
        L_144_:Toggle(
            {
                Title = "มองเห็นทั้งแมพ",
                Desc = "เปิด/ปิดการมองเห็นทั้งแมพ",
                Icon = "eye",
                Default = false,
                Callback = function(L_347_arg0)
                    L_145_.fullMapEnabled = L_347_arg0
                    L_153_func()
                end
            }
        )
        L_144_:Button(
            {
                Title = "รีเซ็ตทั้งหมด",
                Desc = "รีเซ็ตค่าทั้งหมดเป็นค่าเริ่มต้น",
                Icon = "refresh-cw",
                Callback = function()
                    for L_351_forvar0, L_352_forvar1 in pairs(L_146_) do
                        L_148_func(L_351_forvar0)
                    end
                    L_145_.speedEnabled = false
                    L_145_.jumpEnabled = false
                    L_145_.brightnessEnabled = false
                    L_145_.fovEnabled = false
                    L_145_.fullMapEnabled = false
                    local L_348_ = game.Players.LocalPlayer
                    local L_349_ = L_348_.Character
                    if L_349_ then
                        local L_353_ = L_349_:FindFirstChild("Humanoid")
                        if L_353_ then
                            L_353_.WalkSpeed = 16
                            L_353_.JumpPower = L_147_.jumpPower
                        end
                    end
                    game.Workspace.Gravity = L_147_.gravity
                    game.Lighting.Brightness = L_147_.lightingBrightness
                    local L_350_ = workspace.CurrentCamera
                    if L_350_ then
                        L_350_.FieldOfView = L_147_.cameraFieldOfView
                        L_350_.CameraType = Enum.CameraType.Custom
                    end
                    L_154_func()
                end
            }
        )
        print("WindUI loaded successfully!")
    else
        print("HWID verification failed. Script terminated.")
    end
end
