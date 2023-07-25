-- Moonlite
-- Author: MaximumADHD
-- Description: A WIP lightweight in-game player for sequences created in Moon Animator (by xSIXx)
-- Version: 0.5.0

--[[

== API ==

------------------------------------
-- Moonlite
------------------------------------

Moonlite.CreatePlayer(save: StringValue) -> MoonliteTrack
~ Loads the provided MoonAnimator save to be played back.

type MoonliteTrack = Moonlite.Track
~ Type exported from this module that represents a track.

------------------------------------
-- MoonliteTrack
------------------------------------

MoonliteTrack:Play() -> ()
~ Starts playing the track's elements.

MoonliteTrack:Stop() -> ()
~ Stops all playing track elements.

MoonliteTrack:Reset() -> ()
~ Resets any modified properties to their declared defaults
  Calling this while a track is playing is undefined behavior

MoonliteTrack:IsPlaying() -> boolean
~ Returns true if the track still has elements playing.

MoonliteTrack.Info: MoonliteInfo
~ A dictionary of metadata about the MoonAnimator save.

MoonliteTrack.Completed: RBXScriptSignal
~ Fired when playback of the track is completed.

------------------------------------
-- MoonliteInfo
------------------------------------

MoonliteInfo.Created: number
~ UNIX Timestamp of when the animation was created.

MoonliteInfo.ExportedPriority: string
~ Maps to Enum.AnimationPriority, intended priority for 
  this animation if it was created for a joint rig.

MoonliteInfo.Modified: number
~ UNIX Timestamp of when the animation was last modified.

MoonliteInfo.Length: number
~ Expected duration of this track's playback.

MoonliteInfo.Looped: number
~ Whether the playback of this track should be looped.
  Currently has no effect, but may in the future.

------------------------------------

== END API ==

]]

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
type MoonAnimItem = Types.MoonAnimItem
type MoonAnimPath = Types.MoonAnimPath
type MoonAnimSave = Types.MoonAnimSave
type MoonEaseInfo = Types.MoonEaseInfo
type MoonInstance = Types.MoonInstance
type MoonKeyframe = Types.MoonKeyframe
type MoonProperty = Types.MoonProperty
type MoonJointInfo = Types.MoonJointInfo
type MoonKeyframePack = Types.MoonKeyframePack
type GetSet<Inst, Value> = Types.GetSet<Inst, Value>

local MoonliteTrack = {}
MoonliteTrack.__index = MoonliteTrack

export type Track = typeof(setmetatable({} :: {
	Info: MoonAnimInfo,
	Completed: Event,

	_tweens: { Tween },
	_completed: BindableEvent,
	_targets: { MoonInstance },

	_playing: {
		[MoonProperty]: true,
	},
	
	_scratch: Scratchpad
}, MoonliteTrack))

local function resolveAnimPath(path: MoonAnimPath?): Instance?
	if not path then
		return nil
	end

	local numSteps = #path.InstanceNames
	local current: Instance = game

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
			then typeInst.Value 
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
		Type = style.Value,

		Params = {
			Direction = dir.Value,
		},
	}
end

local function lerp<T>(a: T, b: T, t: number)
	if typeof(a) == "number" then
		return a + ((b - a) * t)
	else
		return (a :: any):Lerp(b, t)
	end
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

local function getPropValue(self: Track, inst: Instance?, prop: string): (boolean, any?)
	if inst then
		local classTable = Specials[inst.ClassName]
		local propHandler = classTable and classTable[prop]
		
		if propHandler then
			return pcall(propHandler.Get, self._scratch, inst)
		end
	end
	
	return pcall(function ()
		return (inst :: any)[prop]
	end)
end

local function setPropValue(self: Track, inst: Instance?, prop: string, value: any): boolean
	if inst then
		local classTable = Specials[inst.ClassName]
		local propHandler = classTable and classTable[prop]
		
		if propHandler then
			return pcall(propHandler.Set, self._scratch, inst, value)
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

		for i = 0, current.FrameCount do
			local ease = current.Eases[i]
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
			end
		end

		current = current.Next
	end

	return sequence
end

function Moonlite.CreatePlayer(save: StringValue): Track
	local saveData: MoonAnimSave = HttpService:JSONDecode(save.Value)
	local completed = Instance.new("BindableEvent")
	local targets = {} :: { MoonInstance }
	
	for id, item in saveData.Items do
		local path = item.Path
		local itemType = path.ItemType

		local target = resolveAnimPath(path)
		local frame = save:FindFirstChild(tostring(id))
		local rig = frame and frame:FindFirstChild("Rig")

		if not (target and frame) then
			continue
		end

		assert(target)
		assert(frame)

		if rig and itemType == "Rig" then
			local joints = resolveJoints(target)

			for i, joint in rig:GetChildren() do
				if joint.Name ~= "_joint" then
					continue
				end

				local hier = joint:FindFirstChild("_hier")
				local default: any = joint:FindFirstChild("default")
				local keyframes = joint:FindFirstChild("_keyframes")

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
							warn(`failed to resolve joint '{tree}' (couldn't find child '{name}' in {data.Name}!)`)
							data = nil
						end
					end

					if data then
						local jointAnim: MoonInstance = {
							Target = data.Joint,

							Props = {
								Transform = {
									Default = CFrame.identity,

									Sequence = unpackKeyframes(keyframes, function (c1: CFrame)
										return c1:Inverse() * default
									end),
								},
							},
						}
						
						table.insert(targets, jointAnim)
					end
				end
			end
		else
			local instData = {
				Target = target,
				Props = {},
			}

			for i, prop in frame:GetChildren() do
				local default: any = prop:FindFirstChild("default")

				if default then
					default = readValue(default)
				end

				instData.Props[prop.Name] = {
					Default = default,
					Sequence = unpackKeyframes(prop),
				}
			end

			table.insert(targets, instData)
		end
	end

	return setmetatable({
		Completed = completed.Event,
		Info = saveData.Information,

		_completed = completed,
		_targets = targets,
		_scratch = {},
		_playing = {},
		_tweens = {},
	}, MoonliteTrack)
end

function MoonliteTrack.IsPlaying(self: Track)
	return next(self._playing) ~= nil
end

function MoonliteTrack.Stop(self: Track)
	while #self._tweens > 0 do
		local tween = table.remove(self._tweens)

		if tween then
			tween:Cancel()
		end
	end

	table.clear(self._playing)
end

function MoonliteTrack.Reset(self: Track)
	for id, inst in self._targets do
		for name, data in inst.Props do
			setPropValue(self, inst.Target, name, data.Default)
		end
	end
end

function MoonliteTrack.Play(self: Track)
	if self:IsPlaying() then
		self:Stop()
	end

	for id, inst in self._targets do
		local target: any = inst.Target

		if not target then
			continue
		end

		for propName, prop in inst.Props do
			if not setPropValue(self, target, propName, prop.Default) then
				continue
			end

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
				local easeFunc = EaseFuncs.Get(ease)
				local start: any
				
				if typeof(goal) == "ColorSequence" then
					goal = goal.Keypoints[1].Value
					
					interp.Changed:Connect(function(t: number)
						local value = lerp(start.Keypoints[1].Value, goal, easeFunc(t))
						local cs = ColorSequence.new(value)
						setPropValue(self, target, propName, cs)
					end)
				elseif typeof(goal) == "NumberSequence" then
					goal = goal.Keypoints[1].Value
					
					interp.Changed:Connect(function(t: number)
						local value = lerp(start.Keypoints[1].Value, goal, easeFunc(t))
						local ns = NumberSequence.new(value)
						setPropValue(self, target, propName, ns)
					end)
				elseif typeof(goal) == "NumberRange" then
					goal = goal.Min
					
					interp.Changed:Connect(function(t: number)
						local value = lerp(start.Min, goal, easeFunc(t))
						local nr = NumberRange.new(value)
						setPropValue(self, target, propName, nr)
					end)
				elseif typeof(goal) == "Instance" or type(goal) == "nil" or type(goal) == "boolean" then
					interp.Changed:Connect(function (t: number)
						if t >= 0 then
							setPropValue(self, target, propName, goal)
						else
							setPropValue(self, target, propName, start)
						end
					end)
				else
					interp.Changed:Connect(function (t: number)
						local value = lerp(start, goal, t)
						setPropValue(self, target, propName, value)
					end)
				end
				
				-- stylua: ignore
				local tweenInfo = TweenInfo.new(
					tweenTime,
					Enum.EasingStyle.Linear
				)
				
				local tween = TweenService:Create(interp, tweenInfo, {
					Value = 1
				})
				
				local function dispatch()
					local gotStart, setStart = getPropValue(self, target, propName)
					
					if gotStart then
						start = setStart
						tween:Play()
						
						-- For some reason the playback chain breaks
						-- when this is excluded...
						-- TODO: Investigate why
						
						tween.Completed:Connect(function (state)
							if state == Enum.PlaybackState.Completed then
								interp.Value = 1
							end
						end)
					end
				end
				
				if lastTween then
					lastTween.Completed:Once(function(state)
						if state == Enum.PlaybackState.Completed then
							dispatch()
						end
					end)
				else
					dispatch()
				end
				
				lastTime = timeStamp
				lastTween = tween
			end

			if lastTween then
				self._playing[prop] = true
				
				lastTween.Completed:Once(function(state)
					if state ~= Enum.PlaybackState.Completed then
						return
					end

					self._playing[prop] = nil

					if not next(self._playing) then
						self._completed:Fire()
					end
				end)
			end
		end
	end
end

return Moonlite