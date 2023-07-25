--!strict
local RBX: any = nil
export type Event = typeof((RBX :: BindableEvent).Event)

export type MoonAnimPath = {
	ItemType: string,
	InstanceTypes: { string },
	InstanceNames: { string },
}

export type MoonAnimItem = {
	Path: MoonAnimPath,
}

export type MoonEaseInfo = {
	Type: string,

	Params: {
		Direction: string?,
		Overshoot: number?,
		Amplitude: number?,
		Period: number?,
	},
}

export type MoonKeyframePack = {
	Eases: { MoonEaseInfo },
	Values: { any },

	FrameIndex: number,
	FrameCount: number,

	Prev: MoonKeyframePack?,
	Next: MoonKeyframePack?,
}

export type MoonKeyframe = {
	Ease: MoonEaseInfo?,
	Time: number,
	Value: any,
}

export type MoonProperty = {
	Default: any,
	Sequence: { MoonKeyframe },
}

export type MoonInstance = {
	Target: Instance?,

	Props: {
		[string]: MoonProperty,
	},
}

export type MoonJointInfo = {
	Name: string,
	Joint: Motor6D,
	Parent: MoonJointInfo?,

	Children: {
		[string]: MoonJointInfo,
	},
}

export type MoonAnimInfo = {
	Created: number,
	ExportedPriority: string,
	Modified: number,
	Length: number,
	Looped: boolean,
}

export type MoonAnimSave = {
	Items: { MoonAnimItem },
	Information: MoonAnimInfo,
}

export type Scratchpad = {
	[string]: any,
}

export type GetSet<Inst, Value> = {
	Get: (work: Scratchpad, inst: Inst) -> Value,
	Set: (work: Scratchpad, inst: Inst, value: Value) -> (),
}

return {}
