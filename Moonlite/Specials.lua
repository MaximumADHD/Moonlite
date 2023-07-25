-------------------------------------------------------------------------------------------------------
-- Setup
-------------------------------------------------------------------------------------------------------

--!strict
local Moonlite = script.Parent
local RunService = game:GetService("RunService")

local Types = require(Moonlite.Types)
type GetSet<Inst, Value> = Types.GetSet<Inst, Value>
type Scratchpad = Types.Scratchpad

local Specials = {} :: {
	[string]: { -- Class
		[string]: GetSet<any, any>
	}
}

local function getValue<T>(inst: Instance, name: string, default: T)
	return inst:GetAttribute(`__moonlite_{name}`) or default
end

local function setValue<T>(inst: Instance, name: string, value: T, default: T)
	inst:SetAttribute(`__moonlite_{name}`, if value == default then nil else value)
end

local DEF_COLOR3 = Color3.new()

-------------------------------------------------------------------------------------------------------
-- Camera
-------------------------------------------------------------------------------------------------------

local CAMERA_RENDER_ID = "MoonliteRenderCamera"

local function setCameraActive(work: Scratchpad, camera: Camera, active: boolean)
	if active and not work.CameraRenderBound then
		RunService:BindToRenderStep(CAMERA_RENDER_ID, 1000, function ()
			local attachTo = work.CameraAttachToPart
			local lookAt = work.CameraLookAtPart
			
			if attachTo then
				local cf = attachTo.CFrame
				
				if lookAt then
					cf = CFrame.new(cf.Position, lookAt.Position)
				end

				camera.CFrame = cf
			end
		end)
		
		work.CameraRenderBound = true
		camera.CameraType = Enum.CameraType.Scriptable
	elseif not active and work.CameraRenderBound then
		RunService:UnbindFromRenderStep(CAMERA_RENDER_ID)
		camera.CameraType = Enum.CameraType.Custom
		work.CameraRenderBound = false
	end
end

Specials.Camera = {
	AttachToPart = {
		Get = function (work: Scratchpad)
			return work.CameraAttachToPart
		end,

		Set = function (work: Scratchpad, camera: Camera, part: BasePart?)
			if part then
				work.ActiveCamera = camera
				work.CameraAttachToPart = part
				setCameraActive(work, camera, true)
			else
				work.CameraAttachToPart = nil
				
				if not work.CameraLookAtPart then
					setCameraActive(work, camera, false)
				end
			end
		end,
	},
	
	LookAtPart = {
		Get = function (work: Scratchpad)
			return work.CameraLookAtPart
		end,
		
		Set = function (work: Scratchpad, camera: Camera, part: BasePart?)
			if part then
				work.ActiveCamera = camera
				work.CameraLookAtPart = part
				setCameraActive(work, camera, true)
			else
				work.CameraLookAtPart = nil

				if not work.CameraAttachToPart then
					setCameraActive(work, camera, false)
				end
			end
		end,
	}
}

-------------------------------------------------------------------------------------------------------
-- Terrain Colors
-------------------------------------------------------------------------------------------------------

Specials.Terrain = {}

for i, material in Enum.Material:GetEnumItems() do
	local canColor = pcall(function ()
		workspace.Terrain:GetMaterialColor(material)
	end)
	
	if canColor then
		Specials.Terrain[`MC_{material.Name}`] = {
			Get = function (_, terrain: Terrain)
				return terrain:GetMaterialColor(material)
			end,

			Set = function (_, terrain: Terrain, color: Color3)
				terrain:SetMaterialColor(material, color)
			end,
		}
	end
end

-------------------------------------------------------------------------------------------------------
-- Model Specials
-------------------------------------------------------------------------------------------------------

Specials.Model = {
	CFrame = {
		Get = function (_, model: Model)
			return model:GetPivot()
		end,
		
		Set = function (_, model: Model, cf: CFrame)
			model:PivotTo(cf)
		end,
	},
	
	Color = {
		Get = function (_, model: Model)
			return getValue(model, "Color", DEF_COLOR3)
		end,
		
		Set = function (_, model: Model, value: Color3)
			for i, desc: Instance in model:GetDescendants() do
				if desc:IsA("BasePart") then
					local color = getValue(desc, "Color", desc.Color)
					
					if color ~= value then
						setValue(desc, "Color", value, color)
						desc.Color = value
					end
				end
			end

			setValue(model, "Color", value, DEF_COLOR3)
		end,
	},
	
	Scale = {
		Get = function (_, model: Model)
			return model:GetScale()
		end,
		
		Set = function (_, model: Model, scale: number)
			model:ScaleTo(scale)
		end,
	},
	
	Reflectance = {
		Get = function (_, model: Model)
			return getValue(model, "Reflectance", 0)
		end,
		
		Set = function (_, model: Model, refl: number)
			local value = getValue(model, "Reflectance", 0)

			if value ~= refl then
				-- TODO: Slow, use a cache?
				for i, desc in model:GetDescendants() do
					if desc:IsA("BasePart") then
						local base = getValue(desc, "BaseReflectance", desc.Reflectance)
						desc.Reflectance = base + ((1 - base) * refl)
					end
				end
				
				setValue(model, "Transparency", value, 0)
			end
		end,
	},
	
	Transparency = {
		Get = function (_, model: Model)
			return getValue(model, "Transparency", 0)
		end,
		
		Set = function (_, model: Model, t: number)
			local value = getValue(model, "Transparency", 0)
			
			if value ~= t then
				-- TODO: Slow, use a cache?
				for i, desc in model:GetDescendants() do
					if desc:IsA("BasePart") then
						desc.LocalTransparencyModifier = t
					end
				end
				
				setValue(model, "Transparency", value, 0)
			end
		end,
	}
}

-------------------------------------------------------------------------------------------------------

return Specials