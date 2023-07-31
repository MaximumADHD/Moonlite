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

type Scratchpad = Types.Scratchpad
type GetSet<Value, Args...> = Types.GetSet<Value, Args...>

-- stylua: ignore
type Binding<Class, Value, Args...> = (
	target: Class,
	work: Scratchpad
) -> GetSet<Value, Args...>

type BindSet = {
	[string]: Binding<any, any, any>,
}

local Specials = {} :: {
	[string]: BindSet,
}

local function getValue<T>(inst: Instance, name: string, default: T)
	return inst:GetAttribute(`__moonlite_{name}`) or default
end

local function setValue<T>(inst: Instance, name: string, value: T, default: T)
	inst:SetAttribute(`__moonlite_{name}`, if value == default then nil else value)
end

local function BoundProp<Class, Value>(binding: GetSet<Value, Class, Scratchpad>): Binding<Class, Value>
	return function(inst: Class, work: Scratchpad)
		assert(binding.Get)

		return {
			Get = function()
				return binding.Get(inst, work)
			end,

			Set = function(value)
				binding.Set(value, inst, work)
			end,
		}
	end
end

local function LazyAction<T>(handler: (T) -> ()): Binding<T, boolean>
	return function(inst: T)
		return {
			Default = false,

			Set = function(value: boolean)
				if value then
					handler(inst)
				end
			end,
		}
	end
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
	AttachToPart = BoundProp({
		Get = function(camera: Camera, work: Scratchpad)
			return work._cameraAttachToPart
		end,

		Set = function(part: BasePart?, camera: Camera, work: Scratchpad)
			if part then
				work._activeCamera = camera
				work._cameraAttachToPart = part
				setCameraActive(work, camera, true)
			else
				work._cameraAttachToPart = nil
			end
		end,
	}),

	LookAtPart = BoundProp({
		Get = function(camera: Camera, work: Scratchpad)
			return work._cameraLookAtPart
		end,

		Set = function(part: BasePart?, camera: Camera, work: Scratchpad)
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
	}),
}

-------------------------------------------------------------------------------------------------------
-- Terrain
-------------------------------------------------------------------------------------------------------

Specials.Terrain = {}

for i, material in Enum.Material:GetEnumItems() do
	local canColor = pcall(function()
		workspace.Terrain:GetMaterialColor(material)
	end)

	if canColor then
		Specials.Terrain[`MC_{material.Name}`] = BoundProp({
			Get = function(terrain: Terrain)
				return terrain:GetMaterialColor(material)
			end,

			Set = function(color: Color3, terrain: Terrain)
				terrain:SetMaterialColor(material, color)
			end,
		})
	end
end

-------------------------------------------------------------------------------------------------------
-- Model
-------------------------------------------------------------------------------------------------------

local DEF_COLOR3 = Color3.new(1, 1, 1)

Specials.Model = {
	CFrame = BoundProp({
		Get = function(model: Model)
			return model:GetPivot()
		end,

		Set = function(cf: CFrame, model: Model)
			model:PivotTo(cf)
		end,
	}),

	Color = BoundProp({
		Get = function(model: Model)
			return getValue(model, "Color", DEF_COLOR3)
		end,

		Set = function(value: Color3, model: Model)
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
	}),

	Scale = BoundProp({
		Get = function(model: Model)
			return model:GetScale()
		end,

		Set = function(scale: number, model: Model)
			model:ScaleTo(scale)
		end,
	}),

	Reflectance = BoundProp({
		Get = function(model: Model)
			return getValue(model, "Reflectance", 0)
		end,

		Set = function(value: number, model: Model)
			local current = getValue(model, "Reflectance", 0)

			if current ~= value then
				-- TODO: Slow, use a cache?
				for i, desc in model:GetDescendants() do
					if desc:IsA("BasePart") then
						local base = getValue(desc, "BaseReflectance", desc.Reflectance)
						desc.Reflectance = base + ((1 - base) * value)
					end
				end

				setValue(model, "Reflectance", value, 0)
			end
		end,
	}),

	Transparency = BoundProp({
		Get = function(model: Model)
			return getValue(model, "Transparency", 0)
		end,

		Set = function(value: number, model: Model)
			local current = getValue(model, "Transparency", 0)

			if current ~= value then
				-- TODO: Slow, use a cache?
				for i, desc in model:GetDescendants() do
					if desc:IsA("BasePart") then
						desc.LocalTransparencyModifier = value
					end
				end

				setValue(model, "Transparency", value, 0)
			end
		end,
	}),
}

-------------------------------------------------------------------------------------------------------
-- Humanoid
-------------------------------------------------------------------------------------------------------

Specials.Humanoid = {
	AddAccessory = function(humanoid: Humanoid)
		local default: Accessory = nil

		return {
			Default = default,

			Set = function(value: Accessory?)
				if value then
					pcall(humanoid.AddAccessory, humanoid, value)
				end
			end,
		}
	end,

	ChangeState = function(humanoid: Humanoid)
		return {
			Default = Enum.HumanoidStateType.None,

			Set = function(state: Enum.HumanoidStateType)
				humanoid:ChangeState(state)
			end,
		}
	end,

	EquipTool = function(humanoid: Humanoid)
		local default: Tool = nil

		return {
			Default = default,

			Set = function(tool: Tool?)
				if tool then
					pcall(humanoid.EquipTool, humanoid, tool)
				end
			end,
		}
	end,

	Jump = LazyAction(function(humanoid: Humanoid)
		humanoid.Jump = true
	end),

	MoveTo = function(humanoid: Humanoid)
		local default: Vector3 = humanoid:GetAttribute("MoveToDefault")

		if typeof(default) ~= "Vector3" then
			local rootPart = humanoid.RootPart

			if rootPart then
				default = rootPart.Position
			else
				default = Vector3.zero
			end

			humanoid:SetAttribute("MoveToDefault", default)
		end

		return {
			Default = default,

			Set = function(location: Vector3)
				humanoid:MoveTo(location)
			end,
		}
	end,

	Move = function(humanoid: Humanoid)
		local default: Vector3 = humanoid:GetAttribute("MoveDefault")

		if typeof(default) ~= "Vector3" then
			local rootPart = humanoid.RootPart

			if rootPart then
				default = rootPart.CFrame.LookVector
			else
				default = Vector3.zero
			end

			humanoid:SetAttribute("MoveDefault", default)
		end

		return {
			Default = default,

			Set = function(moveVec: Vector3)
				humanoid:Move(moveVec)
			end,
		}
	end,

	PlayEmote = function(humanoid: Humanoid)
		return {
			Default = "",

			Set = function(emote: string)
				humanoid:PlayEmote(emote)
			end,
		}
	end,

	RemoveAccessories = LazyAction(function(humanoid: Humanoid)
		humanoid:RemoveAccessories()
	end),

	Sit = function(humanoid: Humanoid)
		return {
			Set = function(sit: boolean)
				humanoid.Sit = sit
			end,
		}
	end,

	TakeDamage = function(humanoid: Humanoid)
		return {
			Set = function(value: number)
				humanoid:TakeDamage(value)
			end,
		}
	end,

	UnequipTools = LazyAction(function(humanoid: Humanoid)
		humanoid:UnequipTools()
	end),
}

-------------------------------------------------------------------------------------------------------
-- ParticleEmitter
-------------------------------------------------------------------------------------------------------

Specials.ParticleEmitter = {
	Clear = LazyAction(function(emitter: ParticleEmitter)
		emitter:Clear()
	end),

	Emit = function(emitter: ParticleEmitter)
		local emitCount: number = emitter:GetAttribute("EmitCount")

		if type(emitCount) ~= "number" then
			emitCount = 0
		end

		return {
			Default = emitCount,

			Set = function(count: number)
				if count > 0 then
					emitter:Emit(count)
				end
			end,
		}
	end,
}

-------------------------------------------------------------------------------------------------------
-- Sound
-------------------------------------------------------------------------------------------------------

Specials.Sound = {
	PlayOnce = LazyAction(function(sound: Sound)
		local clone = sound:Clone()
		clone.Parent = sound.Parent
		clone.PlayOnRemove = true
		clone:Destroy()
	end),

	SetTime = function(sound: Sound)
		return {
			Default = 0,

			Set = function(timePos: number)
				sound.TimePosition = timePos
			end,
		}
	end,

	Play = LazyAction(function(sound: Sound)
		sound:Play()
	end),

	Resume = LazyAction(function(sound: Sound)
		sound:Resume()
	end),

	Pause = LazyAction(function(sound: Sound)
		sound:Pause()
	end),

	Stop = LazyAction(function(sound: Sound)
		sound:Stop()
	end),
}

-------------------------------------------------------------------------------------------------------
-- Module Export
-------------------------------------------------------------------------------------------------------

local classBinds = {} :: {
	[string]: BindSet,
}

local propBinds = {} :: {
	[Instance]: GetSetBind,
}

local GetSetBind = {
	__index = function(tbl: GetSetBind, prop: string)
		local inst = tbl._target
		local className = inst.ClassName
		local classBind = classBinds[className]

		if classBind == nil then
			classBind = {}

			for class, propSet in Specials do
				if inst:IsA(class) then
					for name, getSet in propSet do
						classBind[name] = getSet
					end
				end
			end

			classBinds[className] = classBind
		end

		local propHandler = classBind[prop]
		local getSet = nil

		if propHandler then
			getSet = propHandler(inst, tbl._work)
			rawset(tbl :: any, prop, getSet)
		end

		return getSet
	end,
}

-- stylua: ignore
type GetSetBind = typeof(setmetatable({} :: {
	_work: Scratchpad,
	_target: Instance,
	[string]: GetSet<any, any>,
}, GetSetBind))

local function get(work: Scratchpad, inst: Instance, prop: string): GetSet<any, any>?
	local props: GetSetBind = propBinds[inst]

	if not props then
		props = setmetatable({
			_target = inst,
			_work = work,
		}, GetSetBind)

		-- FIXME: This should go in a maid
		inst.Destroying:Connect(function()
			local bind: any = propBinds[inst]

			if bind == props then
				propBinds[inst] = nil
			end
		end)

		propBinds[inst] = assert(props)
	end

	return props[prop]
end

return {
	Get = get,
	Index = Specials,
}

-------------------------------------------------------------------------------------------------------
