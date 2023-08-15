------------------------------------------------------------------------
-- 🌙 Moonlite
-- by: MaximumADHD
--
-- A light-weight runtime player for sequences
-- created in Moon Animator 2 (by xsixx)
--
-- Documentation is available on GitHub:
-- https://www.github.com/MaximumADHD/Moonlite#readme
------------------------------------------------------------------------

--!strict
local Moonlite = {}

local Types = require(script.Types)
local Specials = require(script.Specials)
local EaseFuncs = require(script.EaseFuncs)

local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")

if RunService:IsServer() then
	warn("Moonlite should NOT be used on the server! Rig transforms will not be replicated.")
end

type Event = Types.Event
type Scratchpad = Types.Scratchpad
type MoonElement = Types.MoonElement
type MoonAnimInfo = Types.MoonAnimInfo
type MoonAnimItem = Types.MoonAnimItem
type MoonAnimPath = Types.MoonAnimPath
type MoonAnimSave = Types.MoonAnimSave
type MoonEaseInfo = Types.MoonEaseInfo
type MoonKeyframe = Types.MoonKeyframe
type MoonProperty = Types.MoonProperty
type MoonJointInfo = Types.MoonJointInfo
type MoonKeyframePack = Types.MoonKeyframePack
type GetSet<Inst, Value> = Types.GetSet<Inst, Value>

local MoonTrack = {}
MoonTrack.__index = MoonTrack

local CONSTANT_INTERPS = {
	["Instance"] = true,
	["boolean"] = true,
	["nil"] = true,
}

-- stylua: ignore
export type MoonTrack = typeof(setmetatable({} :: {
	Completed: Event,
	Looped: boolean,

	_tweens: { Tween },
	_completed: BindableEvent,
	_elements: { MoonElement },

	_targets: {
		[Instance]: MoonElement
	},

	_playing: {
		[MoonProperty]: true,
	},

	_root: Instance?,
	_save: StringValue,
	_data: MoonAnimSave,

	_scratch: Scratchpad,
	_compiled: boolean,
}, MoonTrack))

local function lerp<T>(a: T, b: T, t: number): any
	if type(a) == "number" then
		return a + ((b - a) * t)
	else
		return (a :: any):Lerp(b, t)
	end
end

local function toPath(path: MoonAnimPath): string
	return table.concat(path.InstanceNames, ".")
end

local function resolveAnimPath(path: MoonAnimPath?, root: Instance?): Instance?
	if not path then
		return nil
	end

	local numSteps = #path.InstanceNames
	local current: Instance = root or game

	local success = pcall(function()
		for i = 2, numSteps do
			local name = path.InstanceNames[i]
			local class = path.InstanceTypes[i]

			local nextInst = (current :: any)[name]
			assert(typeof(nextInst) == "Instance")
			assert(nextInst.ClassName == class)

			current = nextInst
		end
	end)

	if success then
		return current
	end

	warn("!! PATH RESOLVE FAILED:", table.concat(path.InstanceNames, "."))
	return nil
end

local function resolveJoints(target: Instance)
	local joints = {} :: {
		[string]: MoonJointInfo,
	}

	for i, desc: Instance in target:GetDescendants() do
		if desc:IsA("Motor6D") and desc.Active then
			local part1 = desc.Part1
			local name = part1 and part1.Name

			if name then
				joints[name] = {
					Name = name,
					Joint = desc,
					Children = {},
				}
			end
		end
	end

	for name1, data1 in joints do
		local joint = data1.Joint
		local part0 = joint.Part0

		if part0 then
			local name0 = part0.Name
			local data0 = joints[name0]

			if data0 then
				data0.Children[name1] = data1
				data1.Parent = data0
			end
		end
	end

	return joints
end

local function parseEase(easeInst: Instance): MoonEaseInfo
	local typeInst = easeInst:FindFirstChild("Type")
	local paramInst = easeInst:FindFirstChild("Params")

	local ease = {
		-- stylua: ignore
		Type = assert(if typeInst and typeInst:IsA("StringValue")
			then typeInst.Value :: any
			else nil),

		Params = {},
	}

	if paramInst then
		for i, param in paramInst:GetChildren() do
			if param:IsA("ValueBase") then
				local value = (param :: any).Value
				ease.Params[param.Name] = value
			end
		end
	end

	return ease
end

local function parseEaseOld(easeInst: Instance): MoonEaseInfo
	local style = easeInst:FindFirstChild("Style")
	assert(style and style:IsA("StringValue"), "No style in legacy ease!")

	local dir = easeInst:FindFirstChild("Direction")
	assert(dir and dir:IsA("StringValue"), "No direction in legacy ease!")

	return {
		Type = style.Value :: any,

		Params = {
			Direction = dir.Value :: any,
		},
	}
end

local function readValue(value: Instance)
	if value:IsA("ValueBase") then
		-- stylua: ignore
		local bin = if tonumber(value.Name)
			then assert(value.Parent)
			else value

		local read = (value :: any).Value
		local enumType = bin:FindFirstChild("EnumType")

		if enumType and enumType:IsA("StringValue") then
			read = (Enum :: any)[enumType.Value][read]
		elseif bin:FindFirstChild("Vector2") then
			read = Vector2.new(read.X, read.Y)
		elseif bin:FindFirstChild("ColorSequence") then
			read = ColorSequence.new(read)
		elseif bin:FindFirstChild("NumberSequence") then
			read = NumberSequence.new(read)
		elseif bin:FindFirstChild("NumberRange") then
			read = NumberRange.new(read)
		end

		return read
	else
		return value:GetAttribute("Value")
	end
end

local function getPropValue(self: MoonTrack, inst: Instance?, prop: string): (boolean, any?)
	if inst then
		local binding = Specials.Get(self._scratch, inst, prop)

		if binding then
			local get = binding.Get

			if get then
				return pcall(get, inst)
			else
				return true, binding.Default
			end
		end
	end

	return pcall(function()
		return (inst :: any)[prop]
	end)
end

local function setPropValue(self: MoonTrack, inst: Instance?, prop: string, value: any, isDefault: boolean?): boolean
	if inst then
		local binding = Specials.Get(self._scratch, inst, prop)

		if binding then
			if binding.Get == nil and isDefault and value == true then
				-- Ugh, This is an action(?), but for some reason six
				-- sets the default value to true here, which
				-- would behave as an immediate dispatch.
				-- Not the behavior we need.
				value = false
			end

			return pcall(binding.Set, value)
		end
	end

	return pcall(function()
		(inst :: any)[prop] = value
	end)
end

local function parseKeyframePack(kf: Instance): MoonKeyframePack
	local frame = tonumber(kf.Name)
	assert(frame, "Bad frame number")

	local valueBin = kf:FindFirstChild("Values")
	assert(valueBin, "No value folder!")

	local zero = valueBin:FindFirstChild("0")
	assert(zero, "No starting value!")

	local values = {}
	local maxIndex = 0

	for i, value in valueBin:GetChildren() do
		local index = tonumber(value.Name)

		if index then
			local success, read = pcall(readValue, value)

			if success then
				values[index] = read
				maxIndex = math.max(index, maxIndex)
			end
		end
	end

	local easesBin = kf:FindFirstChild("Eases")
	local easeOld = kf:FindFirstChild("Ease")
	local eases = {}

	if easesBin then
		for _, easeBin in easesBin:GetChildren() do
			local index = tonumber(easeBin.Name)
			assert(index, `Bad index on ease @{easeBin:GetFullName()}`)

			local ease = parseEase(easeBin)
			eases[index] = ease
		end
	elseif easeOld then
		eases[maxIndex] = parseEaseOld(easeOld)
	end

	return {
		FrameIndex = frame,
		FrameCount = maxIndex,

		Values = values,
		Eases = eases,
	}
end

local function unpackKeyframes(container: Instance, modifier: ((any) -> any)?)
	local packs = {}
	local indices = {}
	local sequence = {}

	for i, child in container:GetChildren() do
		local index = tonumber(child.Name)

		if index then
			packs[index] = parseKeyframePack(child)
			table.insert(indices, index)
		end
	end

	table.sort(indices)

	for i = 2, #indices do
		local prev = packs[indices[i - 1]]
		local curr = packs[indices[i]]

		prev.Next = curr
		curr.Prev = prev
	end

	local first = indices[1]
	local current: MoonKeyframePack? = packs[first]

	while current do
		local baseIndex = current.FrameIndex
		local lastEase

		for i = 0, current.FrameCount do
			local ease = current.Eases[i] or lastEase
			local value = current.Values[i]

			if value ~= nil then
				if modifier then
					value = modifier(value)
				end

				table.insert(sequence, {
					Time = baseIndex + i,
					Value = value,
					Ease = ease,
				})

				if ease then
					lastEase = ease
				end
			end
		end

		current = current.Next
	end

	return sequence
end

local function compileItem(self: MoonTrack, item: MoonAnimItem)
	local id = table.find(self._data.Items, item)

	if not id then
		return
	end

	local path = item.Path
	local itemType = path.ItemType

	local target = item.Override or resolveAnimPath(path, self._root)
	local frame = self._save:FindFirstChild(tostring(id))
	local rig = frame and frame:FindFirstChild("Rig")

	if not (target and frame) then
		return
	end

	assert(target)
	assert(frame)

	if rig and itemType == "Rig" then
		local joints = resolveJoints(target)

		for i, jointData in rig:GetChildren() do
			if jointData.Name ~= "_joint" then
				continue
			end

			local hier = jointData:FindFirstChild("_hier")
			local default: any = jointData:FindFirstChild("default")
			local keyframes = jointData:FindFirstChild("_keyframes")

			if default then
				default = readValue(default)
			end

			if hier and keyframes then
				local tree = readValue(hier)
				local readName = tree:gmatch("[^%.]+")

				local name = readName()
				local data: MoonJointInfo? = joints[name]

				while data do
					local children = data.Children
					name = readName()

					if name == nil then
						break
					elseif children[name] then
						data = children[name]
					else
						warn(`failed to resolve joint '{tree}' (could not find child '{name}' in {data.Name}!)`)
						data = nil
					end
				end

				if data then
					local joint = data.Joint

					local props: any = {
						Transform = {
							Default = CFrame.identity,

							Sequence = unpackKeyframes(keyframes, function(c1: CFrame)
								return c1:Inverse() * default
							end),
						},
					}

					local element = {
						Locks = {},
						Props = props,
						Instance = joint,
					}

					self._targets[joint] = element
					table.insert(self._elements, element)
				end
			end
		end
	else
		local props = {}

		for i, prop in frame:GetChildren() do
			local default: any = prop:FindFirstChild("default")

			if default then
				default = readValue(default)
			end

			props[prop.Name] = {
				Default = default,
				Sequence = unpackKeyframes(prop),
			}
		end

		local element = {
			Locks = {},
			Props = props,
			Target = target,
		}

		self._targets[target] = element
		table.insert(self._elements, element)
	end
end

local function compileRouting(self: MoonTrack)
	local elements = self._elements
	table.clear(elements)

	local targets = self._targets
	table.clear(targets)

	for id, item in self._data.Items do
		compileItem(self, item)
	end

	self._compiled = true
end

local function getElements(self: MoonTrack)
	if not self._compiled then
		compileRouting(self)
	end

	return self._elements
end

local function getTargets(self: MoonTrack)
	if not self._compiled then
		compileRouting(self)
	end

	return self._targets
end

function Moonlite.CreatePlayer(save: StringValue, root: Instance?): MoonTrack
	local data: MoonAnimSave = HttpService:JSONDecode(save.Value)
	local completed = Instance.new("BindableEvent")

	return setmetatable({
		Looped = data.Information.Looped,
		Completed = completed.Event,

		_save = save,
		_data = data,

		_completed = completed,
		_compiled = false,

		_elements = {},
		_targets = {},

		_playing = {},
		_scratch = {},
		_tweens = {},
		_root = root,
	}, MoonTrack)
end

function MoonTrack.IsPlaying(self: MoonTrack)
	return next(self._playing) ~= nil
end

function MoonTrack.GetSetting<T>(self: MoonTrack, name: string): T
	return self._scratch[name]
end

function MoonTrack.SetSetting<T>(self: MoonTrack, name: string, value: T)
	self._scratch[name] = value
end

function MoonTrack.GetElements(self: MoonTrack): { Instance }
	local elements = {}

	for target in getTargets(self) do
		table.insert(elements, target)
	end

	return elements
end

function MoonTrack.LockElement(self: MoonTrack, inst: Instance?, lock: any?)
	local targets = getTargets(self)
	local element = inst and targets[inst]

	if element then
		element.Locks[lock or "Default"] = true
		return true
	end

	return false
end

function MoonTrack.UnlockElement(self: MoonTrack, inst: Instance?, lock: any?)
	local targets = getTargets(self)
	local element = inst and targets[inst]

	if element then
		element.Locks[lock or "Default"] = nil
		return true
	end

	return false
end

function MoonTrack.IsElementLocked(self: MoonTrack, inst: Instance?): boolean
	local targets = getTargets(self)
	local element = inst and targets[inst]

	if element and next(element.Locks) then
		return true
	end

	return false
end

function MoonTrack.ReplaceElementByPath(self: MoonTrack, targetPath: string, replacement: Instance)
	for i, item in self._data.Items do
		local path = item.Path
		local id = toPath(path)

		if targetPath:lower() == id:lower() then
			local itemType = path.ItemType

			if itemType == "Rig" or replacement:IsA(path.ItemType) then
				item.Override = replacement

				if self._compiled then
					compileItem(self, item)
				end

				return true
			end
		end
	end

	return false
end

function MoonTrack.FindElement(self: MoonTrack, name: string): Instance?
	for i, element in getElements(self) do
		local target = element.Target

		if target and target.Name == name then
			return target
		end
	end

	return nil
end

function MoonTrack.FindElementOfType(self: MoonTrack, typeName: string): Instance?
	for i, element in getElements(self) do
		local target = element.Target

		if target and target:IsA(typeName) then
			return target
		end
	end

	return nil
end

function MoonTrack.Stop(self: MoonTrack)
	while #self._tweens > 0 do
		local tween = table.remove(self._tweens)

		if tween then
			tween:Cancel()
			tween:Destroy()
		end
	end

	table.clear(self._playing)
end

function MoonTrack.Reset(self: MoonTrack)
	if self:IsPlaying() then
		return false
	end

	for inst, element in self._targets do
		for name, data in element.Props do
			setPropValue(self, inst, name, data.Default, true)
		end
	end

	return true
end

function MoonTrack.Play(self: MoonTrack)
	if self:IsPlaying() then
		return
	end

	for target, element in getTargets(self) do
		if next(element.Locks) then
			print(target, "is locked!")
			continue
		end

		for propName, prop in element.Props do
			if not setPropValue(self, target, propName, prop.Default, true) then
				continue
			end

			local lastEase: MoonEaseInfo?
			local lastTween: Tween?
			local lastTime: number?

			for i, kf in prop.Sequence do
				local timeStamp = kf.Time / 60
				local goal = kf.Value
				local ease = kf.Ease

				-- stylua: ignore
				local tweenTime = if lastTime
					then timeStamp - lastTime
					else timeStamp

				local interp = Instance.new("NumberValue")
				local easeFunc = EaseFuncs.Get(lastEase)

				local handler: ((t: number) -> any)?
				local setup: () -> ()?
				local start: any

				if typeof(goal) == "ColorSequence" then
					setup = function()
						start = start.Keypoints[1].Value
						goal = goal.Keypoints[1].Value
					end

					handler = function(t: number)
						local value = lerp(start, goal, t)
						return ColorSequence.new(value)
					end
				elseif typeof(goal) == "NumberSequence" then
					setup = function()
						start = start.Keypoints[1].Value
						goal = goal.Keypoints[1].Value
					end

					handler = function(t: number)
						local value = lerp(start, goal, t)
						return NumberSequence.new(value)
					end
				elseif typeof(goal) == "NumberRange" then
					setup = function()
						start = start.Min
						goal = goal.Min
					end

					handler = function(t: number)
						local value = lerp(start, goal, t)
						return NumberRange.new(value)
					end
				elseif CONSTANT_INTERPS[typeof(goal)] then
					handler = function(t: number)
						if t >= 1 then
							return goal
						else
							return start
						end
					end
				end

				-- stylua: ignore
				local tweenInfo = TweenInfo.new(
					tweenTime,
					Enum.EasingStyle.Linear
				)

				local tween = TweenService:Create(interp, tweenInfo, {
					Value = 1,
				})

				local function stepInterp(raw: number)
					local t = easeFunc(raw)

					-- stylua: ignore
					local value = if not handler
						then lerp(start, goal, t)
						else handler(t)

					setPropValue(self, target, propName, value)
				end

				local function dispatch()
					local gotStart, setStart = getPropValue(self, target, propName)

					if gotStart then
						start = setStart

						if setup then
							task.spawn(setup)
						end

						interp.Changed:Connect(stepInterp)
						task.spawn(stepInterp, 0)
						tween:Play()

						-- For some reason the playback chain breaks when this is excluded...
						-- TODO: Switch to a proper timeline system instead of using tween chains.

						tween.Completed:Connect(function(state)
							if state == Enum.PlaybackState.Completed then
								interp.Value = 1
							end
						end)
					end
				end

				if lastTween then
					lastTween.Completed:Connect(function(state)
						if state == Enum.PlaybackState.Completed then
							dispatch()
						end
					end)
				else
					task.spawn(dispatch)
				end

				lastTime = timeStamp
				lastTween = tween
				lastEase = ease
			end

			if lastTween then
				self._playing[prop] = true

				lastTween.Completed:Connect(function(state)
					if state ~= Enum.PlaybackState.Completed then
						return
					end

					self._playing[prop] = nil

					if not next(self._playing) then
						self._completed:Fire()

						if self.Looped then
							task.spawn(self.Play, self)
						end
					end
				end)
			end
		end
	end
end

return Moonlite
