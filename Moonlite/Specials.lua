-------------------------------------------------------------------------------------------------------
--
-- Specials are sets of custom get/set properties defined per ClassName.
-- They support inheritance and using base classes.

-- IMPORTANT: Property overloading is undefined behavior for the time being.
--            I will try to support it in the future if I can find a clean
--            way to discern the inheritance relationship without a copy
--            of the API Dump.
--
-------------------------------------------------------------------------------------------------------
-- Setup
-------------------------------------------------------------------------------------------------------

--!strict
local Moonlite = script.Parent
local RunService = game:GetService("RunService")

local Types = require(Moonlite.Types)
type GetSet<Inst, Value> = Types.GetSet<Inst, Value>
type Scratchpad = Types.Scratchpad

type PropSet = {
	[string]: GetSet<any, any>,
}

local Specials = {} :: {
	[string]: PropSet,
}

local function getValue<T>(inst: Instance, name: string, default: T)
	return inst:GetAttribute(`__moonlite_{name}`) or default
end

local function setValue<T>(inst: Instance, name: string, value: T, default: T)
	inst:SetAttribute(`__moonlite_{name}`, if value == default then nil else value)
end

-------------------------------------------------------------------------------------------------------
-- Camera
-------------------------------------------------------------------------------------------------------

local CAMERA_RENDER_ID = "MoonliteRenderCamera"

local function setCameraActive(work: Scratchpad, camera: Camera, active: boolean)
	if active and not work._cameraRenderBound then
		local function updateCamera()
			local attachTo = work._cameraAttachToPart
			local lookAt = work._cameraLookAtPart

			if attachTo then
				local cf = attachTo.CFrame

				if lookAt then
					cf = CFrame.new(cf.Position, lookAt.Position)
				end

				camera.CFrame = cf
			end
		end

		RunService:BindToRenderStep(CAMERA_RENDER_ID, 1000, updateCamera)
		work._cameraRenderBound = true
		updateCamera()

		if not work.KeepCameraType then
			camera.CameraType = Enum.CameraType.Scriptable
		end
	elseif not active and work._cameraRenderBound then
		RunService:UnbindFromRenderStep(CAMERA_RENDER_ID)

		if not work.KeepCameraType then
			camera.CameraType = Enum.CameraType.Custom
		end

		work._cameraRenderBound = false
	end
end

Specials.Camera = {
	AttachToPart = {
		Get = function(work: Scratchpad)
			return work._cameraAttachToPart
		end,

		Set = function(work: Scratchpad, camera: Camera, part: BasePart?)
			if part then
				work._activeCamera = camera
				work._cameraAttachToPart = part
				setCameraActive(work, camera, true)
			else
				work._cameraAttachToPart = nil
			end
		end,
	},

	LookAtPart = {
		Get = function(work: Scratchpad)
			return work._cameraLookAtPart
		end,

		Set = function(work: Scratchpad, camera: Camera, part: BasePart?)
			if part then
				work._activeCamera = camera
				work._cameraLookAtPart = part
				setCameraActive(work, camera, true)

				if work._updateCamera then
					work._updateCamera()
				end
			else
				work._cameraLookAtPart = nil

				if not work._cameraAttachToPart then
					setCameraActive(work, camera, false)
				end
			end
		end,
	},
}

-------------------------------------------------------------------------------------------------------
-- Terrain Colors
-------------------------------------------------------------------------------------------------------

Specials.Terrain = {}

for i, material in Enum.Material:GetEnumItems() do
	local canColor = pcall(function()
		workspace.Terrain:GetMaterialColor(material)
	end)

	if canColor then
		Specials.Terrain[`MC_{material.Name}`] = {
			Get = function(_, terrain: Terrain)
				return terrain:GetMaterialColor(material)
			end,

			Set = function(_, terrain: Terrain, color: Color3)
				terrain:SetMaterialColor(material, color)
			end,
		}
	end
end

-------------------------------------------------------------------------------------------------------
-- Model Specials
-------------------------------------------------------------------------------------------------------

local DEF_COLOR3 = Color3.new(1, 1, 1)

Specials.Model = {
	CFrame = {
		Get = function(_, model: Model)
			return model:GetPivot()
		end,

		Set = function(_, model: Model, cf: CFrame)
			model:PivotTo(cf)
		end,
	},

	Color = {
		Get = function(_, model: Model)
			return getValue(model, "Color", DEF_COLOR3)
		end,

		Set = function(_, model: Model, value: Color3)
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
		Get = function(_, model: Model)
			return model:GetScale()
		end,

		Set = function(_, model: Model, scale: number)
			model:ScaleTo(scale)
		end,
	},

	Reflectance = {
		Get = function(_, model: Model)
			return getValue(model, "Reflectance", 0)
		end,

		Set = function(_, model: Model, refl: number)
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
		Get = function(_, model: Model)
			return getValue(model, "Transparency", 0)
		end,

		Set = function(_, model: Model, t: number)
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
	},
}

-------------------------------------------------------------------------------------------------------
-- Module Export
-------------------------------------------------------------------------------------------------------

local cache = {} :: {
	[string]: PropSet,
}

local function get(inst: Instance): PropSet
	local className = inst.ClassName

	if cache[className] == nil then
		local set: PropSet = {}

		for class, propSet in Specials do
			if inst:IsA(class) then
				for name, getSet in propSet do
					set[name] = getSet
				end
			end
		end

		cache[className] = set
	end

	return cache[className]
end

return {
	Get = get,
	Index = Specials,
}

-------------------------------------------------------------------------------------------------------
