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
type MoonAnimInfo = Types.MoonAnimInfo
type MoonTarget = Types.MoonTarget
type MoonAnimItem = Types.MoonAnimItem
type MoonAnimPath = Types.MoonAnimPath
type MoonAnimSave = Types.MoonAnimSave
type MoonEaseInfo = Types.MoonEaseInfo
type MoonKeyframe = Types.MoonKeyframe
type MoonProperty = Types.MoonProperty
type MoonJointInfo = Types.MoonJointInfo
type MoonKeyframePack = Types.MoonKeyframePack
type MoonMarkers = Types.MoonMarkers
type ActiveMoonTracks<T> = Types.ActiveMoonTracks<T>
type GetSet<Inst, Value> = Types.GetSet<Inst, Value>

local MoonTrack = {}
MoonTrack.__index = MoonTrack

local PlayingTracks: ActiveMoonTracks<MoonTrack> = {}

local CONSTANT_INTERPS = {
	["Instance"] = true,
	["boolean"] = true,
	["nil"] = true,
}

-- stylua: ignore
export type MoonTrack = typeof(setmetatable({} :: {
	Completed: Event,
	Looped: boolean,
	Frames: number,
	FrameRate: number,
	TimePosition: number,

	_tweens: { Tween },
	_completed: BindableEvent,

	_locks: {
		[Instance]: {
			[string]: boolean,
		}
	},

	_elements: { Instance },

	_markers: MoonMarkers,
	_markerSignals: {
		[string]: BindableEvent
	},
	_endMarkerSignals: {
		[string]: BindableEvent
	},

	_buffer: {
		[Instance]: {
			[number]: {
				[string]: any	
			},
		}
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

local function compileItem(self: MoonTrack, item: MoonAnimItem, targets: MoonTarget)
	local id = table.find(self._data.Items, item)

	if not id then
		return
	end

	local path = item.Path
	local itemType = path.ItemType

	local target = item.Override or resolveAnimPath(path, self._root)
	local frame = self._save:FindFirstChild(tostring(id))

	if not (target and frame) then
		return
	end

	assert(target)
	assert(frame)

	local rig = frame:FindFirstChild("Rig")
	local markerTrack = frame:FindFirstChild("MarkerTrack")

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

					targets[joint] = {
						Props = props,
						Target = joint,
					}
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

		targets[target] = {
			Props = props,
			Target = target,
		}
	end

	if markerTrack then
		local markers = {}
		self._markers[target] = markers

		for _, marker in markerTrack:GetChildren() do
			local frame = tonumber(marker.Name)
			assert(frame)

			local name = assert(marker:FindFirstChild("name")).Value
			local width = assert(marker:FindFirstChild("width")).Value

			local data = {}
			local kfMarkers = marker:FindFirstChild("KFMarkers")

			if kfMarkers then
				for _, event in kfMarkers:GetChildren() do
					data[event.Value] = assert(event:FindFirstChild("Val")).Value
				end
			end

			if not markers[frame] then
				markers[frame] = {
					StartMarkers = {},
					EndMarkers = {},
				}
			end

			if width > 0 then
				local endFrame = math.min(frame + width, self.Frames)
				if not markers[endFrame] then
					markers[endFrame] = {
						StartMarkers = {},
						EndMarkers = {},
					}
				end

				markers[endFrame].EndMarkers[name] = data
			end

			markers[frame].StartMarkers[name] = data
		end
	end
end

local function getInterpolator<T>(value: T): (start: T, goal: T, delta: number) -> T
	local valueType = typeof(value)

	if typeof(valueType) == "ColorSequence" then
		return function(start: T, goal: T, t: number)
			local value = lerp(start.Keypoints[1].Value, goal.Keypoints[1].Value, t)
			return ColorSequence.new(value)
		end
	elseif typeof(valueType) == "NumberSequence" then
		return function(start: T, goal: T, t: number)
			local value = lerp(start.Keypoints[1].Value, goal.Keypoints[1].Value, t)
			return NumberSequence.new(value)
		end
	elseif typeof(valueType) == "NumberRange" then
		return function(start: T, goal: T, t: number)
			local value = lerp(start.Min, goal.Min, t)
			return NumberRange.new(value)
		end
	elseif CONSTANT_INTERPS[typeof(valueType)] then
		return function(start: T, goal: T, t: number)
			if t >= 1 then
				return goal
			else
				return start
			end
		end
	end

	return lerp
end

local function compileFrames(self: MoonTrack, targets: MoonTarget)
	local buffer = self._buffer

	for target, element in targets do
		local frames = {}
		buffer[target] = frames

		for name, value in element.Props do
			if not value.Sequence[1] then
				continue
			end

			local interpolate = getInterpolator(value.Sequence[1])

			local lastFrame = 0
			local lastValue = value.Default
			local lastEase

			for _, v in value.Sequence do
				if not frames[v.Time] then
					frames[v.Time] = {}
				end

				frames[v.Time][name] = v.Value

				local delta = v.Time - lastFrame
				if delta <= 1 then
					lastValue = v.Value
					lastEase = v.Ease
					lastFrame = v.Time
					continue
				end

				local easeFunc = EaseFuncs.Get(lastEase)
				for i = 0, delta do
					local frameDelta = easeFunc(i / delta)
					local frame = lastFrame + i
					if not frames[frame] then
						frames[frame] = {}
					end

					frames[frame][name] = interpolate(lastValue, v.Value, frameDelta)
				end

				lastEase = v.Ease
				lastValue = v.Value
				lastFrame = v.Time
			end

			if lastFrame < self.Frames then
				local cache = frames[lastFrame][name]

				for i = lastFrame, self.FrameRate do
					if not frames[i] then
						frames[i] = {}
					end

					frames[i][name] = cache
				end
			end
		end
	end
end

local function compileRouting(self: MoonTrack)
	table.clear(self._buffer)
	table.clear(self._elements)
	table.clear(self._markers)

	local targets = {}

	for id, item in self._data.Items do
		compileItem(self, item, targets)
	end

	compileFrames(self, targets)

	self._compiled = true
end

local function restoreTrack(self: MoonTrack)
	local defaults = PlayingTracks[self]
	if not defaults then
		return
	end

	for instance, props in defaults do
		for name, value in props do
			instance[name] = value
		end
	end

	PlayingTracks[self] = nil
end

local function stepTrack(self: MoonTrack, dT: number)
	dT = math.min(dT, 1 / self.FrameRate)

	local currentFrame = math.floor(self.TimePosition * self.FrameRate)
	if currentFrame > self.Frames then
		if self.Looped then
			currentFrame = 0
			self.TimePosition = 0
		else
			self._completed:Fire(Enum.PlaybackState.Completed)

			return true
		end
	end

	for instance, frames in self._buffer do
		if self._locks[instance] ~= nil then
			continue
		end

		local props = frames[currentFrame]
		if not props then
			continue
		end

		for name, value in props do
			setPropValue(self, instance, name, value)
		end
	end

	for instance, markers in self._markers do
		local frameMarkers = markers[currentFrame]
		if not frameMarkers then
			continue
		end

		for name, data in frameMarkers.StartMarkers do
			if self._markerSignals[name] then
				self._markerSignals[name]:Fire(instance, data)
			end
		end

		for name, data in frameMarkers.EndMarkers do
			if self._markerEndSignals[name] then
				self._markerEndSignals[name]:Fire(instance, data)
			end
		end
	end

	self.TimePosition += dT
	return false
end

function Moonlite.CreatePlayer(save: StringValue, root: Instance?): MoonTrack
	local data: MoonAnimSave = HttpService:JSONDecode(save.Value)

	local completed = Instance.new("BindableEvent")

	local self = setmetatable({
		Completed = completed.Event,
		Looped = data.Information.Looped,
		Frames = data.Information.Length,
		FrameRate = data.Information.FPS or 60,
		TimePosition = 0,

		_save = save,
		_data = data,

		_compiled = false,
		_completed = completed,

		_markers = {},
		_markerSignals = {},
		_markerEndSignals = {},

		_locks = {},
		_elements = {},
		_buffer = {},

		_scratch = {},
		_root = root,
	}, MoonTrack) :: MoonTrack

	compileRouting(self)

	return self
end

function MoonTrack.Destroy(self: MoonTrack)
	for _, signal in self._markerSignals do
		signal:Destroy()
	end

	for _, signal in self._markerEndSignals do
		signal:Destroy()
	end

	self._completed:Destroy()

	table.clear(self._markerSignals)
	table.clear(self._markerEndSignals)

	setmetatable(self, nil)
end

function MoonTrack.IsPlaying(self: MoonTrack)
	return PlayingTracks[self] ~= nil
end

function MoonTrack.GetTimeLength(self: MoonTrack)
	return self.Frames / self.FrameRate
end

function MoonTrack.GetMarkerReachedSignal(self: MoonTrack, marker: string): RBXScriptSignal
	if not self._markerSignals[marker] then
		self._markerSignals[marker] = Instance.new("BindableEvent")
	end

	return self._markerSignals[marker].Event
end

function MoonTrack.GetMarkerEndedSignal(self: MoonTrack, marker: string): RBXScriptSignal
	if not self._endMarkerSignals[marker] then
		self._endMarkerSignals[marker] = Instance.new("BindableEvent")
	end

	return self._endMarkerSignals[marker].Event
end

function MoonTrack.GetSetting<T>(self: MoonTrack, name: string): T
	return self._scratch[name]
end

function MoonTrack.SetSetting<T>(self: MoonTrack, name: string, value: T)
	self._scratch[name] = value
end

function MoonTrack.GetElements(self: MoonTrack): { Instance }
	return table.clone(self._elements)
end

function MoonTrack.LockElement(self: MoonTrack, inst: Instance, lock: any?)
	if not self._locks[inst] then
		self._locks[inst] = {}
	end

	if lock then
		self._locks[inst][lock or "Default"] = true
	end

	return true
end

function MoonTrack.UnlockElement(self: MoonTrack, inst: Instance, lock: any?)
	local locks = self._locks[inst]

	if locks then
		locks[lock or "Default"] = nil

		if not next(locks) then
			self._locks[inst] = nil
		end
	end

	return true
end

function MoonTrack.IsElementLocked(self: MoonTrack, inst: Instance): boolean
	return self._locks[inst] ~= nil
end

function MoonTrack.ReplaceElementByPath(self: MoonTrack, targetPath: string, replacement: Instance)
	for i, item in self._data.Items do
		local path = item.Path
		local id = toPath(path)

		if targetPath:lower() == id:lower() then
			local itemType = path.ItemType

			if itemType == "Rig" or replacement:IsA(path.ItemType) then
				item.Override = replacement
				compileRouting(self)

				return true
			end
		end
	end

	return false
end

function MoonTrack.FindElement(self: MoonTrack, name: string): Instance?
	for i, target in self._elements do
		if target and target.Name == name then
			return target
		end
	end

	return nil
end

function MoonTrack.FindElementOfType(self: MoonTrack, typeName: string): Instance?
	for _, target in self._elements do
		if target and target:IsA(typeName) then
			return target
		end
	end

	return nil
end

function MoonTrack.Stop(self: MoonTrack)
	self.TimePosition = 0
	task.spawn(restoreTrack, self)
	self._completed:Fire(Enum.PlaybackState.Cancelled)
end

function MoonTrack.Reset(self: MoonTrack)
	self.TimePosition = 0
	stepTrack(self, 0)

	return true
end

function MoonTrack.Play(self: MoonTrack)
	if PlayingTracks[self] then
		return
	end

	if self.TimePosition >= self:GetTimeLength() then
		self.TimePosition = 0
	end

	local props = {}
	for instance, frames in self._buffer do
		if not frames[0] then
			continue
		end

		local defaults = {}
		props[instance] = defaults

		for name in frames[0] do
			defaults[name] = instance[name]
		end
	end

	PlayingTracks[self] = props
	self._completed:Fire(Enum.PlaybackState.Playing)
end

RunService:BindToRenderStep("__UPDATE_MOONLITE_TRACKS", Enum.RenderPriority.Camera.Value + 1, function(dT: number)
	for track in PlayingTracks do
		if stepTrack(track, dT) then
			restoreTrack(track)
		end
	end
end)

return Moonlite
