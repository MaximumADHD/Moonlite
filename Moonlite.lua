-- Moonlite
-- Author: MaximumADHD
-- Description: A WIP lightweight in-game player for sequences created in Moon Animator (by xSIXx)
-- Version: 0.1.0

--[[

== API ==

------------------------------------`
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

local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")

local MoonliteTrack = {}
MoonliteTrack.__index = MoonliteTrack

type MoonAnimPath = {
	ItemType: string,
	InstanceTypes: { string },
	InstanceNames: { string },
}

type MoonAnimItem = {
	Path: MoonAnimPath,
}

type MoonEase = {
	Type: string,

	Params: {
		[string]: any,
	},
}

type MoonKeyframePack = {
	Eases: { MoonEase },
	Values: { any },

	FrameIndex: number,
	FrameCount: number,

	Prev: MoonKeyframePack?,
	Next: MoonKeyframePack?,
}

type MoonKeyframe = {
	Ease: MoonEase?,
	Time: number,
	Value: any,
}

type MoonProperty = {
	Default: any,
	Sequence: { MoonKeyframe },
}

type MoonInstance = {
	Target: Instance?,

	Props: {
		[string]: MoonProperty,
	},
}

type MoonJointInfo = {
	Name: string,
	Joint: Motor6D,
	Parent: MoonJointInfo?,

	Children: {
		[string]: MoonJointInfo,
	},
}

type MoonAnimInfo = {
	Created: number,
	ExportedPriority: string,
	Modified: number,
	Length: number,
	Looped: boolean,
}

type MoonAnimSave = {
	Items: { MoonAnimItem },
	Information: MoonAnimInfo,
}

local RBX = nil
type Event = typeof((RBX :: BindableEvent).Event)

export type Track = typeof(setmetatable({} :: {
	Info: MoonAnimInfo,
	Completed: Event,

	_tweens: { Tween },
	_completed: BindableEvent,
	_targets: { MoonInstance },

	_playing: {
		[MoonProperty]: true,
	},
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

local function parseEase(easeInst: Instance): MoonEase
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

local function parseEaseOld(easeInst: Instance): MoonEase
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

local function readValue(value: Instance)
	if value:IsA("ValueBase") then
		local bin = if tonumber(value.Name) then assert(value.Parent) else value

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

local function setValue(inst: Instance?, prop: string, value: any): boolean
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

local function getEasingStyle(ease: MoonEase?): Enum.EasingStyle
	if ease then
		local success, style = pcall(function()
			return (Enum.EasingStyle :: any)[ease.Type]
		end)

		if success then
			return style
		end
	end

	return Enum.EasingStyle.Linear
end

local function getEasingDirection(ease: MoonEase?): Enum.EasingDirection
	if ease then
		local success, dir = pcall(function()
			return (Enum.EasingDirection :: any)[ease.Params.Direction]
		end)

		if success then
			return dir
		end
	end

	return Enum.EasingDirection.InOut
end

local function unpackKeyframes(container: Instance)
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
							warn(`failed to resolve joint '{tree}' (could not find child '{name}' in {data.Name}!)`)
							data = nil
						end
					end

					if data then
						-- TODO: Writing to C1 is SLOW, need to use Transform instead.
						local transformer: MoonInstance = {
							Target = data.Joint,

							Props = {
								C1 = {
									Default = default,
									Sequence = unpackKeyframes(keyframes),
								},
							},
						}

						table.insert(targets, transformer)
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
			setValue(inst.Target, name, data.Default)
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
			if not setValue(target, propName, prop.Default) then
				warn("setValue failed", target, propName, prop.Default)
				continue
			end

			local lastTween: Tween?
			local lastTime: number?

			for i, kf in prop.Sequence do
				local timeStamp = kf.Time / 60
				local delayTime = 0

				local goal = kf.Value
				local ease = kf.Ease

				-- stylua: ignore
				local tweenTime = if lastTime
					then timeStamp - lastTime
					else timeStamp

				-- booleans should be set when their keyframe
				-- is reached, easing sets it immediately :/

				if type(goal) == "boolean" then
					delayTime = tweenTime
					tweenTime = 0
				end

				-- stylua: ignore
				local tweenInfo = TweenInfo.new(
					tweenTime,
					getEasingStyle(ease),
					getEasingDirection(ease),
					0, false, delayTime
				)

				local lazyTarget: any
				local goalValue: any
				local tween: Tween

				if typeof(goal) == "ColorSequence" then
					lazyTarget = Instance.new("Color3Value")
					goalValue = goal.Keypoints[1].Value

					lazyTarget.Changed:Connect(function(value: Color3)
						local cs = ColorSequence.new(value)
						setValue(target, propName, cs)
					end)
				elseif typeof(goal) == "NumberSequence" then
					lazyTarget = Instance.new("NumberValue")
					goalValue = goal.Keypoints[1].Value

					lazyTarget.Changed:Connect(function(value: number)
						local ns = NumberSequence.new(value)
						setValue(target, propName, ns)
					end)
				elseif typeof(goal) == "NumberRange" then
					lazyTarget = Instance.new("NumberValue")
					goalValue = goal.Min

					lazyTarget.Changed:Connect(function(value: number)
						local nr = NumberRange.new(value)
						setValue(target, propName, nr)
					end)
				else
					local success = pcall(function()
						tween = TweenService:Create(target, tweenInfo, {
							[propName] = goal,
						})
					end)

					if not success then
						lazyTarget = Instance.new("BoolValue")
						goalValue = true

						lazyTarget.Changed:Once(function()
							setValue(target, propName, goal)
						end)
					end
				end

				if lazyTarget then
					tween = TweenService:Create(lazyTarget, tweenInfo, {
						Value = goalValue,
					})
				end

				if lastTween then
					lastTween.Completed:Connect(function(state)
						if state == Enum.PlaybackState.Completed then
							if lazyTarget then
								lazyTarget.Value = target[propName]
							end

							tween:Play()
						end
					end)
				else
					if lazyTarget then
						lazyTarget.Value = target[propName]
					end

					tween:Play()
				end

				table.insert(self._tweens, tween)
				lastTime = timeStamp
				lastTween = tween
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
					end
				end)
			end
		end
	end
end

return Moonlite
