local WE_server = {}

local data_store_service = game:GetService("DataStoreService")
local pets_store = data_store_service:GetDataStore("RANGERSPETSA")

local badge_service = game:GetService('BadgeService')
local msg_service = game:GetService('MessagingService')
local debris = game:GetService('Debris')
local http_service = game:GetService('HttpService')
local teleport_service = game:GetService('TeleportService')
local physics_service = game:GetService("PhysicsService")
local server_storage = game:GetService('ServerStorage')
local players = game:GetService("Players")
local replicated_storage = game:GetService('ReplicatedStorage')
local mps = game:GetService("MarketplaceService")
local run_service = game:GetService("RunService")
local config_service = game:GetService("ConfigService")
local config = config_service:GetConfigAsync()

local modules = {
	PetSystem = require(script:WaitForChild('PetSystem'));
	ClientListener = require(script:WaitForChild('ClientListener'));
	ProfileService = require(script.Parent:WaitForChild("ProfileService"))
}

local badges = require(script.Parent.Parent:WaitForChild('Badges'))
local products = require(replicated_storage:WaitForChild('CommonModules'):WaitForChild('Products'))
local zonedata = require(replicated_storage:WaitForChild('CommonModules'):WaitForChild('ZoneData'))

--DBG
local dbgremote = replicated_storage:WaitForChild('DBGDEV')
local dbgassets = dbgremote:WaitForChild('Assets')

function WE_server.Init()
	--Initialize meta reference
	local self = setmetatable({}, {__index = WE_server})
	
	self.is_Restarting = false
	
	self.player_tags = server_storage:WaitForChild('PlayerTag')
	self.mod_menu = server_storage:WaitForChild('MODERATOR')
	
	self.banned_vis_parts = require(replicated_storage.CommonModules:WaitForChild('BannedVisibilityParts'))
	self.pet_data = require(replicated_storage.CommonModules:WaitForChild('PetData'))
	self.player_controller = replicated_storage.ClientRemotes:WaitForChild('PlayerControl')
	
	self.data_store_name = 'RANGERSNEW'
	self.profile_format = require(script:WaitForChild('DataTemplate'))
	self.xp_multi = tonumber(workspace:GetAttribute('xp_multi'))
	self.players_last_xp = {}
	
	self.shared_avatar = server_storage:WaitForChild('SharedAvatar')
	self.shared_avatars = {}
	
	self.profile_store = modules.ProfileService.GetProfileStore(self.data_store_name, self.profile_format)
	self.profiles = {}
	
	--self.char_infos = replicated_storage.CommonModules:WaitForChild('Informations')
	self.chars_data = require(replicated_storage.CommonModules:WaitForChild('CharactersData'))
	
	self.admins = require(replicated_storage.CommonModules:WaitForChild('Admins'))
	self.testers = require(replicated_storage.CommonModules:WaitForChild('Testers'))
	self.tester_passes = {
		OLD_game_access_pass = 867854679;
		game_access_pass = 1592323581
	}
	
	self.modules = {
		pet_system = modules.PetSystem.Init(self, pets_store);
		client_listener = modules.ClientListener.Init(self);
	}
	
	players.PlayerAdded:Connect(function(plr)
		self:PlayerAdded(plr)
	end)
	
	for i, plr in pairs(players:GetPlayers()) do 
		self:PlayerAdded(plr)
	end

	players.PlayerRemoving:Connect(function(plr)
		self:PlayerRemoving(plr)
	end)
	
	replicated_storage.ServerRemotes.SaveData.OnServerEvent:Connect(function(plr, data)
		if data == nil or type(data) ~= 'table' then return end
		self.profiles[plr].Data = data
		plr.leaderstats.Level.Value = data.Level
		plr.leaderstats.Rings.Value = data.Rings
		plr.leaderstats.RSRS.Value = data.RSRS

		plr.other.xp.Value = data.xp
		plr.other.xp_needed.Value = data.Level*self.xp_multi
		plr.other.maxpetsslots.Value = data.maxpetsslots
		plr.other.skills.Value = data.skills
	end)
	
	replicated_storage.ServerRemotes.GetDataValue.OnServerInvoke = function(plr, targetData)
		local profile = self.profiles[plr]
		return profile.Data[targetData]
	end

	replicated_storage.ServerRemotes.GetData.OnServerInvoke = function(plr)
		local profile
		
		for i = 1, 5 do
			profile = self.profiles[plr]
			if profile then break end
			task.wait(3)
		end
		
		if not profile or profile.Data == nil then
			plr:Kick('Wish Engine Server: Data didnt retrieved because data is currently in use. Please make sure you dont play currently on another device.')
			return
		end
		
		return profile.Data
	end
	
	replicated_storage.ServerRemotes.CharAdd.OnServerEvent:Connect(function(plr)
		self:CharacterAdded(plr, plr.Character or plr.CharacterAdded:Wait())
	end)
	
	replicated_storage.ServerRemotes.RequestZoneDownload.OnServerInvoke = function(plr, zone, part)
		local zones = server_storage:WaitForChild('Zones')
		local result
		
		if part == 'Collision' then
			result = zones.Collision:FindFirstChild(zone..' Collision'):Clone()
		elseif part == 'Decorations' then
			result = zones.Decorations:FindFirstChild(zone..' Decorations'):Clone()
		elseif part == 'Lighting' then
			result = zones.Lighting:FindFirstChild(zone..' Lighting'):Clone()
		elseif part == 'Clouds' then
			result = zones.Lighting.Clouds:FindFirstChild(zone..' Clouds'):Clone()
		elseif part == 'Object' then
			result = zones.Object:FindFirstChild(zone..' Objects'):Clone()
		elseif part == 'Rails' then
			result = zones.Object.Rails:FindFirstChild(zone..' Rails'):Clone()
		else
			warn("["..script.Name.."] "..'Unknown part of zone')
			result = nil
		end

		if result then
			result.Parent = plr.TEMP
			debris:AddItem(result, 40)
		end

		return result
	end
	
	replicated_storage.ServerRemotes.ZoneDownloadCompleted.OnServerInvoke = function(plr, zone)
		local temp = plr:WaitForChild('TEMP',30)
		if temp and #temp:GetChildren() > 0 then
			temp:ClearAllChildren()
		end
		if plr:WaitForChild('other'):WaitForChild('Zone') then
			plr.other.Zone.Value = tostring(zone)
		end
		return true
	end
	
	--Character visibility
	replicated_storage.ServerRemotes.SetVisibilityToCharacter.OnServerEvent:Connect(function(plr, char, vis)
		if char or plr.Character ~= nil then
			local skin = plr.other:WaitForChild('skin')
			
			if skin.Value == 'Sonic' or skin.Value == 'SuperSonic' then
				local superhead = char:WaitForChild('HeadSuper', 10)
				local head = char:WaitForChild('Head', 10)
				if not head or not superhead then return end
				if head or superhead then
					if head.Transparency == 0 and superhead.Transparency == 0 then
						if skin.Value == 'Sonic' then
							superhead.Transparency = 1
							head.Transparency = 0
						elseif skin.Value == 'SuperSonic' then
							superhead.Transparency = 0
							head.Transparency = 1
						end
					elseif head.Transparency == 1 and superhead.Transparency == 1 then
						if skin.Value == 'Sonic' then
							superhead.Transparency = 1
							head.Transparency = 0
						elseif skin.Value == 'SuperSonic' then
							superhead.Transparency = 0
							head.Transparency = 1
						end
					end
				end
			end

			for _,inst in pairs(char:GetDescendants()) do
				if inst:IsA("BasePart") or inst:IsA("TriangleMeshPart") or inst:IsA("MeshPart") or inst:IsA('Decal') then
					if not self.banned_vis_parts[inst.Name] then
						inst.Transparency = vis
					end
				end
			end
		end
	end)
	
	--[[Damage replication
	replicated_storage.ServerRemotes.PlayerDamaged.OnServerEvent:Connect(function(plr, who)
		players:FindFirstChild(tostring(who)):SetAttribute('IsDamagedPlayer', true)
	end)--]]

	--Set attribute server
	replicated_storage.ServerRemotes.SetAttributeToPlayer.OnServerEvent:Connect(function(player, name, value)
		player:SetAttribute(name, value)
	end)
	
	--Character skin switching
	replicated_storage.ServerRemotes.Skin.OnServerEvent:Connect(function(plr,model)
		--local char_name = require(self.char_infos:WaitForChild(model.Name)).character
		local char_name = self.chars_data[model:GetAttribute('CharId')].dse_info.character
		local skin_plr = plr:WaitForChild('other'):WaitForChild('skin')
		local char = model:Clone()
		local savename = plr.Name
		local pos = plr.Character.HumanoidRootPart.CFrame
		
		char.HumanoidRootPart.CFrame = pos
		char.HumanoidRootPart.Anchored = false
		char.Name = savename

		for _,inst in char:GetDescendants() do
			if inst:IsA("BasePart") or inst:IsA("TriangleMeshPart") or inst:IsA("MeshPart") or inst:IsA('Decal') then
				if not self.banned_vis_parts[inst.Name] then
					inst.Transparency = 1
				end
				if inst.Name == 'HeadSuper' then
					inst.Transparency = 1
				end
			end
		end

		plr.Character:Destroy()
		plr.Character = char

		char.Parent = workspace.Players
		char.HumanoidRootPart.CFrame = pos
		
		modules.ClientListener.InitMovementReplication(plr)
		
		skin_plr.Value = char_name
	end)
	
	replicated_storage.ServerRemotes.Avatar.OnServerEvent:Connect(function(plr)
		local char = replicated_storage.Assets.Skins:WaitForChild('Avatar'):Clone()

		local savename = plr.Name
		local pos = plr.Character.HumanoidRootPart.CFrame
		local skin_plr = plr:WaitForChild('other'):WaitForChild('skin')

		if char then
			char.Name = savename
			
			--[[local Emulator = replicated_storage.Assets.Avatar.References:WaitForChild('CharacterEmulation'):Clone()
			Emulator.Parent = char
			local Effects = replicated_storage.Assets.Avatar.References:WaitForChild('LocalEffects'):Clone()
			Effects.Parent = char--]]

			plr.Character:Destroy()
			plr.Character = char

			char.Parent = workspace.Players
			char.HumanoidRootPart.CFrame = pos
			
			modules.ClientListener.InitMovementReplication(plr)
			
			local succ, err = pcall(function()
				char.Humanoid:ApplyDescription(game.Players:GetHumanoidDescriptionFromUserId(plr.UserId))
				
				char.PrimaryPart = char.HumanoidRootPart
				skin_plr.Value = char:GetAttribute('CharId')
			end)
			
			if not succ then
				print("["..script.Name.."] "..err)
			--[[else
				local AvatarUnificationFolder = replicated_storage:WaitForChild("AvatarUnification")
				local MoveHitboxes = require(AvatarUnificationFolder:WaitForChild("MoveAdapterPartHitboxes"))
				local Scale = require(AvatarUnificationFolder:WaitForChild("UnificationScale"))
				local SetupAdapterParts = require(AvatarUnificationFolder:WaitForChild("SetupAdapterParts"))

				-- AdapterReference.rbxm is set up as { AdapterReference {Left Arm {...}, Right Arm {...},...}, CollisionHead {...} }
				-- i.e. CollisionHead and AdapterReference are at then same level
				local AdapterReference = script:WaitForChild("AdapterReference")
				local CollisionHead = script:WaitForChild("CollisionHead")
				AdapterReference.Parent = nil
				CollisionHead.Parent = nil

				-- Need to wait here due to avatar loading order. If we don't wait a frame,
				-- rig building/scaling will be done after this script runs
				task.wait()
				local tables = SetupAdapterParts.setupCharacter(char, AdapterReference, CollisionHead)
				Scale.ScaleCharacter(char, Scale.Target)

				MoveHitboxes.moveHitboxes(char)--]]
			end
		else
			warn("["..script.Name.."] "..'Character called from "Avatar" RemoteEvent is not found or failed to create, please recall event to try again.')
		end
	end)
	
	replicated_storage.ServerRemotes.ChangeSkinValueOnServer.OnServerEvent:Connect(function(plr, newskin)
		plr.other.skin.Value = tostring(newskin)
	end)

	replicated_storage.ServerRemotes.CreatePlayer.OnServerEvent:Connect(function(plr, hum)
		if run_service:IsStudio() then return end
		local char = plr.Character
		if char then
			if char:FindFirstChild('Humanoid'):FindFirstChild('HumanoidDescription') then
				local succ, err = pcall(function()
					hum:ApplyDescription(players:GetHumanoidDescriptionFromUserId(plr.UserId))
				end)
				if not succ then
					warn("["..script.Name.."] "..err)
				end
				return true
			end
		end
	end)
	
	replicated_storage.ServerRemotes.ChangeCharModel.OnServerInvoke = function(plr, skin, variation)
		if not plr.Character then return end
		if skin == 'Sonic' and variation == 'Super' then
			local ref = replicated_storage.Assets.SuperSonic:WaitForChild('TransformThings')
			local body_appearence = ref:WaitForChild('BodyFur'):WaitForChild('SurfaceAppearance')
			local eye_tex = ref:WaitForChild('Eye').Texture
			local head_bone = ref.HumanoidRootPart.Reference.Hips.Spine.Spine1.Neck:Clone()
			local og_head_bone = plr.Character.HumanoidRootPart.Reference.Hips.Spine.Spine1.Neck
			local eyel = plr.Character:WaitForChild('EyeL')
			local eyer = plr.Character:WaitForChild('EyeR')

			local body_fur_table = {
				'BodyFur',
				'LegL',
				'LegR',
				'Tail'
			}

			--Check for character parts
			for _,part in pairs(plr.Character:GetChildren()) do
				if table.find(body_fur_table, part.Name) then
					if part:FindFirstChildOfClass('SurfaceAppearance') then

						--Delete old texture
						part:FindFirstChildOfClass('SurfaceAppearance'):Destroy()

						--Create new texture
						body_appearence:Clone().Parent = part
					end
				end
			end

			--Edit eye texture
			for _,part in pairs(plr.Character:GetChildren()) do
				if part.Name == 'EyeR' or part.Name == 'EyeL' then
					part.Decal.Texture = eye_tex
				end
			end

			--Remesh sonic head
			local head_og = plr.Character:WaitForChild('Head')
			local head_super = plr.Character:WaitForChild('HeadSuper')
			head_og.Transparency = 1
			head_super.Transparency = 0

			--Insert Super Sonic common things
			--if not ref:WaitForChild('HumanoidRootPart'):FindFirstChild('aura') then
				ref.HumanoidRootPart.aura:Clone().Parent = plr.Character.HumanoidRootPart
			--end

			--Replace effects
			for _,v in pairs(plr.Character.HumanoidRootPart.Reference:GetChildren()) do
				if v:IsA('Attachment') then
					v:Destroy()
				end
			end

			for _,v in pairs(ref.HumanoidRootPart.Reference:GetChildren()) do
				if v:IsA('Attachment') then
					v:Clone().Parent = plr.Character.HumanoidRootPart.Reference
				end
			end

			--Reconfig bones
			og_head_bone:Destroy()
			head_bone.Parent = plr.Character.HumanoidRootPart.Reference.Hips.Spine.Spine1
			eyer.RigidConstraint.Attachment1 = plr.Character.HumanoidRootPart.Reference.Hips.Spine.Spine1.Neck.Head.EyeR
			eyel.RigidConstraint.Attachment1 = plr.Character.HumanoidRootPart.Reference.Hips.Spine.Spine1.Neck.Head.EyeL

			--plr.Character:SetAttribute('Transformed', 'Super')

			return true
		elseif skin == 'Sonic' and variation == 'Default' then
			local ref = replicated_storage.Assets.Sonic:WaitForChild('TransformThings')
			local body_appearence = ref:WaitForChild('BodyFur'):WaitForChild('SurfaceAppearance')
			local eye_tex = ref:WaitForChild('Eye').Texture
			local head_bone = ref.HumanoidRootPart.Reference.Hips.Spine.Spine1.Neck:Clone()
			local og_head_bone = plr.Character.HumanoidRootPart.Reference.Hips.Spine.Spine1.Neck
			local eyel = plr.Character:WaitForChild('EyeL')
			local eyer = plr.Character:WaitForChild('EyeR')

			local body_fur_table = {
				'BodyFur',
				'LegL',
				'LegR',
				'Tail'
			}

			--Check for character parts
			for _,part in pairs(plr.Character:GetChildren()) do
				if table.find(body_fur_table, part.Name) then
					if part:FindFirstChildOfClass('SurfaceAppearance') then

						--Delete old texture
						part:FindFirstChildOfClass('SurfaceAppearance'):Destroy()

						--Create new texture
						body_appearence:Clone().Parent = part
					end
				end
			end

			--Edit eye texture
			for _,part in pairs(plr.Character:GetChildren()) do
				if part.Name == 'EyeR' or part.Name == 'EyeL' then
					part.Decal.Texture = eye_tex
				end
			end

			--Remesh sonic head
			local head_og = plr.Character:WaitForChild('HeadSuper')
			local head_super = plr.Character:WaitForChild('Head')
			head_og.Transparency = 1
			head_super.Transparency = 0

			--Delete Super Sonic common things
			local aura = plr.Character:WaitForChild('HumanoidRootPart'):WaitForChild('aura') or nil
			if aura ~= nil then
				aura:Destroy()
			end

			--Replace effects
			for _,v in pairs(plr.Character.HumanoidRootPart.Reference:GetChildren()) do
				if v:IsA('Attachment') then
					v:Destroy()
				end
			end

			for _,v in pairs(ref.HumanoidRootPart.Reference:GetChildren()) do
				if v:IsA('Attachment') then
					v:Clone().Parent = plr.Character.HumanoidRootPart.Reference
				end
			end

			plr.Character.HumanoidRootPart.Reference.CFrame = ref.HumanoidRootPart.Reference.CFrame

			--Reconfig bones
			og_head_bone:Destroy()
			head_bone.Parent = plr.Character.HumanoidRootPart.Reference.Hips.Spine.Spine1
			eyer.RigidConstraint.Attachment1 = plr.Character.HumanoidRootPart.Reference.Hips.Spine.Spine1.Neck.Head.EyeR
			eyel.RigidConstraint.Attachment1 = plr.Character.HumanoidRootPart.Reference.Hips.Spine.Spine1.Neck.Head.EyeL

			--plr.Character:SetAttribute('Transformed', 'Default')

			return true
		end
	end
	
	local client_replicate_sound = replicated_storage.ClientRemotes:WaitForChild('ReplicateSound')
	local client_replicate_effect = replicated_storage.ClientRemotes:WaitForChild('ReplicateEffect')
	local client_replicate_tilt = replicated_storage.ClientRemotes:WaitForChild('ReplicateTilt')
	
	replicated_storage.ServerRemotes.ReplicateSound.OnServerEvent:Connect(function(plr, id: number, vol: number, speed: number, parent: Instance)
		local clients = {}
		for _,plr_res in pairs(players:GetPlayers()) do
			if plr_res ~= plr then
				table.insert(clients, plr_res)
			end
		end
		
		for _, plr in clients do
			client_replicate_sound:FireClient(plr, id, vol, speed, parent)
			
			if clients ~= nil then
				clients = nil
			end
			return true
		end
		return false
	end)
	
	self.effect_replication_active = true
	replicated_storage.ServerRemotes.ReplicateEffect.OnServerEvent:Connect(function(plr, effectInstance: Instance, state: boolean, parent: Instance)
		if self.effect_replication_active then
			--self.effect_replication_active = false
			local clients = {}
			for _,plr_res in pairs(players:GetPlayers()) do
				if plr_res ~= plr then
					table.insert(clients, plr_res)
				end
			end
			
			for _, plr in clients do
				client_replicate_effect:FireClient(plr, effectInstance, state, parent)
				if clients ~= nil then
					clients = nil
				end
				return true
			end
			--self.effect_replication_active = true
		end
		return false
	end)
	
	replicated_storage.ServerRemotes.ReplicateTilt.OnServerEvent:Connect(function(plr_runner, bone, cf, c0: boolean)
		if c0 then
			if bone.C0 == cf then return end
		else
			if bone.CFrame == cf then return end
		end
		
		local clients = {}
		for _,plr_res in pairs(players:GetPlayers()) do
			if plr_res ~= plr_runner then
				table.insert(clients, plr_res)
			end
		end

		for _, plr in clients do
			client_replicate_tilt:FireClient(plr, plr_runner, bone, cf, c0)
			if clients ~= nil then
				clients = nil
			end
			return true
		end
	end)

	--Update state
	replicated_storage.ServerRemotes.UpdatePlayerStateForServer.OnServerEvent:Connect(function(plr, state)
		if tonumber(state) then
			plr:SetAttribute('State', tonumber(state))
		end
	end)
	
	--Product handlers
	local productFunctions = {
		[products.r9] = function(plr, receiptInfo)
			self.player_controller:FireClient(plr, 'give',"total_donated",9)
			self.profiles[plr].Data.total_donated += 9
			return true
		end;
		[products.r19] = function(plr, receiptInfo)
			self.player_controller:FireClient(plr, 'give',"total_donated",19)
			self.profiles[plr].Data.total_donated += 19
			return true
		end;
		[products.r49] = function(plr, receiptInfo)
			self.player_controller:FireClient(plr, 'give',"total_donated",49)
			self.profiles[plr].Data.total_donated += 49
			return true
		end;
		[products.r99] = function(plr, receiptInfo)
			self.player_controller:FireClient(plr, 'give',"total_donated",99)
			self.profiles[plr].Data.total_donated += 99
			return true
		end;
		[products.r499] = function(plr, receiptInfo)
			self.player_controller:FireClient(plr, 'give',"total_donated",499)
			self.profiles[plr].Data.total_donated += 499
			return true
		end;
		[products.r999] = function(plr, receiptInfo)
			self.player_controller:FireClient(plr, 'give',"total_donated",999)
			self.profiles[plr].Data.total_donated += 999
			return true
		end;
	};

	mps.ProcessReceipt = function(receiptInfo)
		local plr = players:GetPlayerByUserId(receiptInfo.PlayerId)
		
		if not plr then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local productHandler = productFunctions[receiptInfo.ProductId]
		
		if productHandler then
			local success, result = pcall(productHandler, plr, receiptInfo)
			
			if success and result == true then
				return Enum.ProductPurchaseDecision.PurchaseGranted
			end
			
		end

		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	--Moderator tools
	self.server_admin_functions = {
		getTargets = function(targetName)
			local result = {}

			if targetName == "e" then
				for _, plr in ipairs(players:GetPlayers()) do
					if not self.admins[plr.UserId] then
						table.insert(result, plr)
					end
				end

			elseif targetName == "eA" then
				return players:GetPlayers()

			else
				local plr = players:FindFirstChild(targetName)
				if plr then
					table.insert(result, plr)
				end
			end

			return result
		end;
		parseCommand = function(input)
			local funcName, argsStr = string.match(input, "^WE:(%w+)%((.*)%)")
			if not funcName then return nil end

			local args = {}
			local current = ""
			local inQuotes = false

			for i = 1, #argsStr do
				local char = argsStr:sub(i, i)

				if char == '"' then
					inQuotes = not inQuotes

				elseif char == ',' and not inQuotes then
					table.insert(args, current:match("^%s*(.-)%s*$"))
					current = ""

				else
					current = current .. char
				end
			end

			if current ~= "" then
				table.insert(args, current:match("^%s*(.-)%s*$"))
			end

			for i, v in ipairs(args) do
				if v:sub(1,1) == '"' and v:sub(-1) == '"' then
					args[i] = v:sub(2, -2)
				else
					local num = tonumber(v)
					if num then
						args[i] = num
					else
						args[i] = v
					end
				end
			end

			local target = args[1]
			table.remove(args, 1)

			return funcName, target, args
		end
	};
	self.commands = {
		kick = function(victims, reason)
			for _, victim in ipairs(victims) do
				local result_plr = players:FindFirstChild(victim.Name)
				local result_reason = tostring(reason)

				if result_plr and result_reason then
					if not self.admins[result_plr.UserId] then
						result_plr:Kick('Wish Engine Administrator: '..result_reason)
					end
				end
			end
		end,
		ban = function(victims, reason, duration, alt_accounts)
			for _, victim in ipairs(victims) do
				local result_plr = players:FindFirstChild(victim.Name)
				local result_userId = result_plr.UserId
				local result_reason = tostring(reason)
				local result_duration = tonumber(duration)

				if result_plr and result_reason and result_duration then
					if not self.admins[result_userId] then
						--Generate config
						local final_config = {
							UserIds = {result_userId},
							Duration = result_duration,
							DisplayReason = result_reason,
							PrivateReason = '-',
							ExcludeAltAccounts = true,
							ApplyToUniverse = true
						}

						local succ, err = pcall(function()
							return players:BanAsync(final_config)
						end)

						if succ then
							print("["..script.Name.."] ".."Player "..result_plr.Name.." banned successfully.")
						else
							print("["..script.Name.."] ".."Error banning player "..result_plr.Name..": " .. err)
						end
					end
				end
			end
		end,
		requestdatachange = function(victims, method, var, val)
			for _, victim in ipairs(victims) do
				local result_plr = players:FindFirstChild(victim.Name)
				local result_method = tostring(method)
				local result_var = tostring(var)
				local result_val

				if tonumber(val) then
					result_val = tonumber(val)
				else
					result_val = tostring(val)
				end

				if result_plr and result_method and result_var and result_val then
					replicated_storage.ClientRemotes.PlayerControl:FireClient(result_plr, result_method, result_var, result_val)
				end
			end
		end,
		freeze = function(victims, freezemethod, duration)
			for _, victim in ipairs(victims) do
				local result_plr = players:FindFirstChild(victim.Name)
				local result_method = tostring(freezemethod):lower()
				local result_duration = tonumber(duration)
				
				if result_plr and result_method and result_duration then
					if result_method == 'freeze with timer' then
						if result_plr:GetAttribute('IsModFreezed') == false or not workspace.Objects.DBG:FindFirstChild(result_plr.Name.."'s Jail") then
							result_plr:SetAttribute('IsModFreezed', true)
							local jail = dbgassets:WaitForChild('FreezedJail'):Clone()
							jail.Name = result_plr.Name.."'s Jail"
							jail.Parent = workspace.Objects.DBG
							jail.PrimaryPart.CFrame = result_plr.Character.HumanoidRootPart.CFrame

							local j = Instance.new('Motor6D',result_plr.Character.HumanoidRootPart)
							j.Name = 'Jail'
							j.Part0 = result_plr.Character.HumanoidRootPart
							j.Part1 = jail.PrimaryPart

							task.wait(duration)

							result_plr:SetAttribute('IsModFreezed', false)
							j:Destroy()
							jail:Destroy()
						end
					elseif result_method == 'freeze' then
						if result_plr:GetAttribute('IsModFreezed') == false or not workspace.Objects.DBG:FindFirstChild(result_plr.Name.."'s Jail") then
							result_plr:SetAttribute('IsModFreezed', true)
							local jail = dbgassets:WaitForChild('FreezedJail'):Clone()
							jail.Name = result_plr.Name.."'s Jail"
							jail.Parent = workspace.Objects.DBG
							jail.PrimaryPart.CFrame = result_plr.Character.HumanoidRootPart.CFrame

							local j = Instance.new('Motor6D',result_plr.Character.HumanoidRootPart)
							j.Name = 'Jail'
							j.Part0 = result_plr.Character.HumanoidRootPart
							j.Part1 = jail.PrimaryPart
						end
					elseif result_method == 'unfreeze' then
						if result_plr:GetAttribute('IsModFreezed') ~= false or workspace.Objects.DBG:FindFirstChild(result_plr.Name.."'s Jail") then
							result_plr:SetAttribute('IsModFreezed', false)
							if result_plr.Character.HumanoidRootPart:FindFirstChild('Jail') then
								result_plr.Character.HumanoidRootPart:FindFirstChild('Jail'):Destroy()
							end
							if workspace.Objects.DBG:FindFirstChild(result_plr.Name.."'s Jail") then
								workspace.Objects.DBG:FindFirstChild(result_plr.Name.."'s Jail"):Destroy()
							end
						end
					else
						warn("["..script.Name.."] "..'Unknown Freeze method!')
					end
				else
					print("["..script.Name.."] "..'not admin')
				end
			end
		end,
		sendmessage = function(msg)
			local result_msg = tostring(msg)
			if result_msg then
				msg_service:PublishAsync("SendMessage", result_msg)
			end
		end,
		teleporttozone = function(victims, zone)
			for _, victim in ipairs(victims) do
				local result_plr = players:FindFirstChild(victim.Name)
				local result_zone = tostring(zonedata.Zones[zone].name)
				
				if result_plr and result_zone then
					replicated_storage.ClientRemotes.ZoneInstanceSignal:FireClient(result_plr, result_zone)
				end
			end
		end,
		changecharacter = function(victims, modelname)
			for _, victim in ipairs(victims) do
				local result_plr = players:FindFirstChild(victim.Name)
				local result_modelname = tostring(modelname)
				
				if result_plr and result_modelname then
					replicated_storage.ClientRemotes.CharacterChangeSignal:FireClient(result_plr, result_modelname)
				end
			end
		end,
		jumpscare = function(victims)
			for _, victim in ipairs(victims) do
				local result_plr = players:FindFirstChild(victim.Name)
				
				if result_plr then
					replicated_storage.ClientRemotes.JumpscareSignal:FireClient(result_plr)
				end
			end
		end,
		restartserver = function()
			self:DoRestart()
		end,
		givepet = function(victims, petname)
			for _, victim in ipairs(victims) do
				local result_plr = players:FindFirstChild(victim.Name)
				local result_pet = replicated_storage.Pets:FindFirstChild(petname, true).Name
				
				if result_plr and result_pet then
					modules.PetSystem.createPet(self, result_plr, result_pet)
				end
			end
		end,
		bring = function(victims, admin)
			print(admin)
			print(victims)
			for _, victim in ipairs(victims) do
				local result_admin = players:FindFirstChild(admin.Name)
				local result_victim = players:FindFirstChild(victim.Name)
				local result_admin_position = result_admin.Character:WaitForChild('HumanoidRootPart').CFrame.Position

				if result_victim and result_admin_position then
					replicated_storage.ClientRemotes.TeleportToSignal:FireClient(result_victim, result_admin_position)
				end
			end
		end,
		tpto = function(victims, admin)
			print(admin)
			print(victims)
			for _, victim in ipairs(victims) do
				local result_admin = players:FindFirstChild(admin.Name)
				local result_victim = players:FindFirstChild(victim.Name)
				local result_victim_position = result_victim.Character:WaitForChild('HumanoidRootPart').CFrame.Position

				if result_admin and result_victim_position then
					replicated_storage.ClientRemotes.TeleportToSignal:FireClient(result_admin, result_victim_position)
				end
			end
		end,
	}
	
	dbgremote.SendCommand.OnServerEvent:Connect(function(plr, cmd)
		if not self.admins[plr.UserId] then
			warn("["..script.Name.."] ".."Non-admin tried command:", plr.Name)
			return
		end

		local funcName, targetName, args = self.server_admin_functions.parseCommand(cmd)
		if not funcName then
			warn("["..script.Name.."] ".."Invalid command format")
			return
		end

		local commandFunc = self.commands[funcName]
		if not commandFunc then
			warn("["..script.Name.."] ".."Unknown command:", funcName)
			return
		end

		local targets = self.server_admin_functions.getTargets(targetName)

		if #targets == 0 then
			warn("["..script.Name.."] ".."No targets found")
			return
		end

		commandFunc(targets, unpack(args))
	end)
	
	local msg_connection = msg_service:SubscribeAsync(
		"SendMessage",
		function(receivedData)
			dbgremote.ClientMSG:FireAllClients(receivedData.Data)
		end
	)

	game:BindToClose(function()
		for _, profile in pairs(self.profiles) do
			profile:Release()
		end
		
		self:DoRestart()
	end)
	
	print("["..script.Name.."] "..'Server awake')
	return self
end

function WE_server:calculateXPIncrementOnLevelUp(level)
	return (self.xp_multi*level)
end

function WE_server:DoRestart()
	if not self.is_Restarting then
		self.is_Restarting = true
		
		for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
			local remoteEvent = Instance.new("RemoteEvent")
			remoteEvent.Name = "ServerRestartNotification"
			remoteEvent.Parent = player
		end

		replicated_storage.ClientRemotes.UpdateDataSignal:FireAllClients()
		for i, player in pairs(players:GetPlayers()) do 
			replicated_storage.ClientRemotes.UpdateDataSignal:FireClient(player)
		end

		print("["..script.Name.."] "..'Server is shutting down, sent updatedatasignal')

		task.wait(5)

		for _, plr in ipairs(players:GetPlayers()) do
			teleport_service:TeleportToPlaceInstance(
				game.PlaceId,
				game.JobId,
				plr
			)
		end
	end
end

function WE_server:RestartRequest(plr)
	if self.admins[plr.UserId] then
		self:DoRestart()
	else
		print("["..script.Name.."] "..'not admin')
	end
end

--[[function WE_server:CreateSound(id: number, vol: number, speed: number, looped: boolean, parent: Instance)
	local snd = Instance.new('Sound', parent)
	snd.SoundId = "rbxassetid://"..tostring(id)
	snd.Volume = vol
	snd.Speed = speed
	snd.Looped = looped
	
	self.created_sounds[snd] = snd
	return snd
end--]]

function WE_server:CheckLevelUp(plr)
	if self.profiles[plr] then
		local other = plr:WaitForChild("other", 10)
		local xp_needed = other:FindFirstChild("xp_needed")

		if xp_needed and self.profiles[plr].Data.xp ~= self.players_last_xp[plr] then
			self.players_last_xp[plr] = self.profiles[plr].Data.xp

			while self.profiles[plr].Data.xp >= xp_needed.Value do
				self.player_controller:FireClient(plr,'decrease',"xp",xp_needed.Value)
				self.player_controller:FireClient(plr,'give',"Level",1)
				
				self.profiles[plr].Data.xp -= xp_needed.Value
				self.profiles[plr].Data.Level += 1
				
				xp_needed.Value = self:calculateXPIncrementOnLevelUp(self.profiles[plr].Data.Level)
			end
		end
	end
end

function WE_server:updateLevelUp(plr)
	local other = plr:WaitForChild("other", 10)

	if other then
		task.spawn(function()
			while plr.Parent do
				self:CheckLevelUp(plr)
				task.wait(0.25)
			end
		end)
	end
end

function WE_server:CheckTester(plr)
	if run_service:IsStudio() then return true end
	if workspace:GetAttribute('Whitelist') == true then
		if self.testers[plr.UserId] or self.admins[plr.UserId] or mps:UserOwnsGamePassAsync(plr.UserId, self.tester_passes.OLD_game_access_pass) or mps:UserOwnsGamePassAsync(plr.UserId, self.tester_passes.game_access_pass) then
			print("["..script.Name.."] "..plr.Name..' has access to the game.')
			return true
		end
	else
		return true
	end
	
	return false
end

function WE_server:PlayerAdded(plr)
	if self:CheckTester(plr) then
		--Data initialization
		local profile = self.profile_store:LoadProfileAsync("savefile" .. plr.UserId, "ForceLoad")

		if profile then
			profile:AddUserId(plr.UserId)
			profile:Reconcile()

			self.profiles[plr] = profile

			if not plr:IsDescendantOf(players) then
				profile:Release()
				return
			end

			plr:SetAttribute('IsModFreezed',false)
			plr:SetAttribute('IsDamagedPlayer',false)
			plr:SetAttribute('State',-999)

			local leaderstats = Instance.new("StringValue", plr)
			leaderstats.Name = "leaderstats"

			local other = Instance.new('StringValue', plr)
			other.Name = 'other'

			local temp = Instance.new("ObjectValue", plr)
			temp.Name = "TEMP"

			local petsboost = Instance.new('StringValue', plr)
			petsboost.Name = 'PetsBoost'

			local control = Instance.new('BoolValue', other)
			control.Name = 'HaveControl'
			control.Value = true

			local Level = Instance.new("IntValue", leaderstats)
			Level.Name = "Level"
			Level.Value = profile.Data.Level

			local rings = Instance.new("IntValue", leaderstats)
			rings.Name = "Rings"
			rings.Value = profile.Data.Rings

			local RSRS = Instance.new("IntValue", leaderstats)
			RSRS.Name = "RSRS"
			RSRS.Value = profile.Data.RSRS

			local xp = Instance.new("IntValue", other)
			xp.Name = "xp"
			xp.Value = profile.Data.xp

			local xp_needed = Instance.new("IntValue", other)
			xp_needed.Name = "xp_needed"
			xp_needed.Value = Level.Value*self.xp_multi

			local maxpetsslots = Instance.new('IntValue', other)
			maxpetsslots.Name = 'maxpetsslots'
			maxpetsslots.Value = profile.Data.maxpetsslots

			local skills = Instance.new("IntValue", other)
			skills.Name = "skills"
			skills.Value = profile.Data.skills

			local skin = Instance.new('StringValue', other)
			skin.Name = 'skin'
			skin.Value = 'Avatar'

			local zone = Instance.new("StringValue", other)
			zone.Name = "Zone"
			zone.Value = 'nil'

			local Ringvalue = Instance.new('IntValue', petsboost)
			Ringvalue.Name = 'Ringvalue'
			Ringvalue.Value = 0

			local XPvalue = Instance.new('IntValue', petsboost)
			XPvalue.Name = 'XPvalue'
			XPvalue.Value = 0

			--Give data to client
			replicated_storage.ClientRemotes.FirstLoad:FireClient(plr, profile.Data)
		else
			plr:Kick("Wish Engine Server: Something went wrong while loading your data. If server has shut down - please wait a bit and rejoin. Check your internet connection or contact Wish's Games!")
		end

		self.shared_avatars[plr] = self.shared_avatar:Clone()
		self.shared_avatars[plr].Parent = plr
		self.shared_avatars[plr]:FindFirstChildOfClass('Humanoid'):ApplyDescription(players:GetHumanoidDescriptionFromUserId(plr.UserId))

		self.players_last_xp[plr] = self.profiles[plr].Data.xp

		--INDEV badge
		if not badge_service:UserHasBadgeAsync(plr.UserId, badges.INDEVplayer) then
			badge_service:AwardBadge(plr.UserId, badges.INDEVplayer)
		else
			print("["..script.Name.."] "..plr.Name..' already got indev badge')
		end

		--Chat Commands
		plr.Chatted:Connect(function(msg)
			--For all
			if msg == "/rejoin" then
				teleport_service:Teleport(game.PlaceId, plr, {feature="rejoin";source="game"})
			elseif msg == '/e free' or msg == '/e dance' or msg == '/e dance1' or msg == '/e dance2' or msg == '/e dance3' then
				plr:Kick('No.')
			elseif msg == "/restart" then
				if self.admins[plr.UserId] then
					self:DoRestart()
				else
					warn("["..script.Name.."] "..'ACCESS DENIED.')
				end
			end
		end)

		self:updateLevelUp(plr)
		modules.ClientListener.CreatePlayerReticle(self, plr)
		--modules.ClientListener.RunStateChanged(self, plr)
		modules.PetSystem.PlayerAdded(self, plr)

		print("["..script.Name.."] "..'Player added: '..plr.Name)
	else
		plr:Kick('Wish Engine Server: We detected, that you dont own a "Tester Pass". You can wait for game release or buy it. If you already own Tester pass and keep getting this message, please contact with Developer!')
	end
end

function WE_server:PlayerRemoving(plr)
	local profile = self.profiles[plr]
	
	if profile.Data then
		profile.Data.last_character = plr.other.skin.Value or 'Avatar'
		if profile.Data.last_character == 'SuperSonic' then
			profile.Data.last_character = 'Sonic'
		end
		profile.Data.last_pet = modules.PetSystem.GetEquippedPet(self, plr) or nil
	end
	
	if profile then
		profile:Release()
		self.profiles[plr] = nil
	end
	
	if self.shared_avatars[plr] ~= nil then
		self.shared_avatars[plr]:Destroy()
	end
	
	self.shared_avatars[plr] = nil
	
	modules.ClientListener.DestroyPlayerReticle(self, plr)
	modules.PetSystem.PlayerRemoving(self, plr)
	print("["..script.Name.."] "..'Player removed: '..plr.Name)
end

function WE_server:CharacterAdded(plr, char)
	--Disable player collision
	physics_service:RegisterCollisionGroup("plrs")

	for _,v in pairs(char:GetDescendants()) do
		if v:IsA("BasePart") or v:IsA('TriangleMeshPart') or v:IsA('MeshPart') then
			v.CollisionGroup = "plrs"
		end
	end
	
	physics_service:CollisionGroupSetCollidable("plrs","plrs",false)
	
	modules.ClientListener.ConnectPlayerReticle(self, plr, char)
	modules.ClientListener.updateCharacter(self, plr, char)
	
	if not self.admins[plr.UserId] then
		if badge_service:UserHasBadgeAsync(plr.UserId, badges.INDEVplayer) then
			local namevis = self.player_tags:WaitForChild('NameOLD'):Clone()
			namevis.Frame.Nick.Text = "@"..plr.Name
			namevis.Frame.Displ.Text = plr.DisplayName.." | OLD"
			char.Humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			
			namevis.Parent = char.PrimaryPart
			namevis.Adornee = char.PrimaryPart
		else
			local namevis = self.player_tags:WaitForChild('Name'):Clone()
			namevis.Frame.Nick.Text = "@"..plr.Name
			namevis.Frame.Displ.Text = plr.DisplayName
			char.Humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			
			namevis.Parent = char.PrimaryPart
			namevis.Adornee = char.PrimaryPart
		end
	else
		print("["..script.Name.."] "..plr.Name..' is admin')
		local namevis = self.player_tags:WaitForChild('NameDEV'):Clone()
		namevis.Frame.Nick.Text = "@"..plr.Name
		namevis.Frame.Displ.Text = plr.DisplayName.." | DEV"
		char.Humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		
		namevis.Parent = char.PrimaryPart
		namevis.Adornee = char.PrimaryPart
	end
	
	char.Parent = workspace.Players
	print("["..script.Name.."] "..'Character added: '..plr.Name)
end

return WE_server
