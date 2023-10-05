--!strict
local RBX: any = nil
export type Event = typeof((RBX :: BindableEvent).Event)

-- stylua: ignore
export type MoonEaseType =
	  "Back"   | "Bounce"  | "Circ"  | "Constant" 
	| "Cubic"  | "Elastic" | "Expo"  | "Linear"
	| "Quad"   | "Quart"   | "Quint" 
	| "Sextic" | "Sine"

-- stylua: ignore
export type MoonEaseDir =
	  "In"     | "Out"  
	| "InOut"  | "OutIn"

export type MoonAnimPath = {
	ItemType: string,
	InstanceTypes: { string },
	InstanceNames: { string },
}

export type MoonAnimItem = {
	Override: Instance?,
	Path: MoonAnimPath,
}

export type MoonEaseInfo = {
	Type: MoonEaseType,

	Params: {
		Direction: MoonEaseDir?,
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

export type MoonElement = {
	Target: Instance?,

	Props: {
		[string]: MoonProperty,
	},
}

export type MoonProperties = {
	[string]: any,
}

export type MoonFrameBuffer = {
	[Instance]: {
		[number]: MoonProperties,
	},
}

export type MoonElementLocks = {
	[Instance]: {
		[string]: boolean,
	},
}

export type MoonTarget = {
	[Instance]: MoonElement,
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
	FPS: number?,
	Length: number,
	Looped: boolean,
}

export type MoonAnimSave = {
	Items: { MoonAnimItem },
	Information: MoonAnimInfo,
}

export type MoonMarkerData = {
	StartMarkers: {
		[string]: MoonProperties,
	},
	EndMarkers: {
		[string]: MoonProperties,
	},
}

export type MoonFrameMarkers = {
	[number]: MoonMarkerData,
}

export type MoonMarkerSignals = {
	[string]: BindableEvent,
}

export type MoonMarkers = {
	[Instance]: MoonFrameMarkers,
}

export type Scratchpad = {
	[string]: any,
}

export type GetSet<Value, Args...> = {
	Get: ((Args...) -> Value)?,
	Set: (Value, Args...) -> (),
	Default: Value?,
}

return {}
