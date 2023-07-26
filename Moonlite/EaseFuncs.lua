-- https://github.com/EmmanuelOga/easing/blob/master/lib/easing.lua
-- https://github.com/behollister/blender2.8/blob/blender2.8/source/blender/blenlib/Intern/easing.c

--!strict
local EaseFuncs = {} :: {
	[string]: EaseFunc,
}

local Moonlite = script.Parent
local Types = require(Moonlite.Types)

type EaseFunc = (...number) -> number
type MoonEaseInfo = Types.MoonEaseInfo
type MoonEaseType = Types.MoonEaseType
type MoonEaseDir = Types.MoonEaseDir

-------------------------------------------------------------------------------------------------------------------------
-- Linear
-------------------------------------------------------------------------------------------------------------------------

function EaseFuncs.Linear(t, b, c, d)
	return c * t / d + b
end

-------------------------------------------------------------------------------------------------------------------------
-- Constant
-------------------------------------------------------------------------------------------------------------------------

function EaseFuncs.Constant(t, b, c, d)
	return t == d and 1 or 0
end

-------------------------------------------------------------------------------------------------------------------------
-- Sine
-------------------------------------------------------------------------------------------------------------------------

function EaseFuncs.InSine(t, b, c, d)
	return -c * math.cos(t / d * (math.pi / 2)) + c + b
end

function EaseFuncs.OutSine(t, b, c, d)
	return c * math.sin(t / d * (math.pi / 2)) + b
end

function EaseFuncs.InOutSine(t, b, c, d)
	return -c / 2 * (math.cos(math.pi * t / d) - 1) + b
end

function EaseFuncs.OutInSine(t, b, c, d)
	if t < d / 2 then
		return EaseFuncs.OutSine(t * 2, b, c / 2, d)
	else
		return EaseFuncs.InSine((t * 2) - d, b + c / 2, c / 2, d)
	end
end

-------------------------------------------------------------------------------------------------------------------------
-- Quad
-------------------------------------------------------------------------------------------------------------------------

function EaseFuncs.InQuad(t, b, c, d)
	t = t / d
	return c * math.pow(t, 2) + b
end

function EaseFuncs.OutQuad(t, b, c, d)
	t = t / d
	return -c * t * (t - 2) + b
end

function EaseFuncs.InOutQuad(t, b, c, d)
	t = t / d * 2

	if t < 1 then
		return c / 2 * math.pow(t, 2) + b
	else
		return -c / 2 * ((t - 1) * (t - 3) - 1) + b
	end
end

function EaseFuncs.OutInQuad(t, b, c, d)
	if t < d / 2 then
		return EaseFuncs.OutQuad(t * 2, b, c / 2, d)
	else
		return EaseFuncs.InQuad((t * 2) - d, b + c / 2, c / 2, d)
	end
end

-------------------------------------------------------------------------------------------------------------------------
-- Cubic
-------------------------------------------------------------------------------------------------------------------------

function EaseFuncs.InCubic(t, b, c, d)
	t = t / d
	return c * math.pow(t, 3) + b
end

function EaseFuncs.OutCubic(t, b, c, d)
	t = t / d - 1
	return c * (math.pow(t, 3) + 1) + b
end

function EaseFuncs.InOutCubic(t, b, c, d)
	t = t / d * 2

	if t < 1 then
		return c / 2 * t * t * t + b
	else
		t = t - 2
		return c / 2 * (t * t * t + 2) + b
	end
end

function EaseFuncs.OutInCubic(t, b, c, d)
	if t < d / 2 then
		return EaseFuncs.OutCubic(t * 2, b, c / 2, d)
	else
		return EaseFuncs.InCubic((t * 2) - d, b + c / 2, c / 2, d)
	end
end

-------------------------------------------------------------------------------------------------------------------------
-- Quart
-------------------------------------------------------------------------------------------------------------------------

function EaseFuncs.InQuart(t, b, c, d)
	t = t / d
	return c * math.pow(t, 4) + b
end

function EaseFuncs.OutQuart(t, b, c, d)
	t = t / d - 1
	return -c * (math.pow(t, 4) - 1) + b
end

function EaseFuncs.InOutQuart(t, b, c, d)
	t = t / d * 2

	if t < 1 then
		return c / 2 * math.pow(t, 4) + b
	else
		t = t - 2
		return -c / 2 * (math.pow(t, 4) - 2) + b
	end
end

function EaseFuncs.OutInQuart(t, b, c, d)
	if t < d / 2 then
		return EaseFuncs.OutQuart(t * 2, b, c / 2, d)
	else
		return EaseFuncs.InQuart((t * 2) - d, b + c / 2, c / 2, d)
	end
end

-------------------------------------------------------------------------------------------------------------------------
-- Quint
-------------------------------------------------------------------------------------------------------------------------

function EaseFuncs.InQuint(t, b, c, d)
	t = t / d
	return c * math.pow(t, 5) + b
end

function EaseFuncs.OutQuint(t, b, c, d)
	t = t / d - 1
	return c * (math.pow(t, 5) + 1) + b
end

function EaseFuncs.InOutQuint(t, b, c, d)
	t = t / d * 2

	if t < 1 then
		return c / 2 * math.pow(t, 5) + b
	else
		t = t - 2
		return c / 2 * (math.pow(t, 5) + 2) + b
	end
end

function EaseFuncs.OutInQuint(t, b, c, d)
	if t < d / 2 then
		return EaseFuncs.OutQuint(t * 2, b, c / 2, d)
	else
		return EaseFuncs.InQuint((t * 2) - d, b + c / 2, c / 2, d)
	end
end

-------------------------------------------------------------------------------------------------------------------------
-- Sextic
-------------------------------------------------------------------------------------------------------------------------

function EaseFuncs.InSextic(t, b, c, d)
	t = t / d
	return c * math.pow(t, 6) + b
end

function EaseFuncs.OutSextic(t, b, c, d)
	t = t / d - 1
	return -c * (math.pow(t, 6) - 1) + b
end

function EaseFuncs.InOutSextic(t, b, c, d)
	t = t / d * 2

	if t < 1 then
		return c / 2 * math.pow(t, 6) + b
	else
		t = t - 2
		return -c / 2 * (math.pow(t, 6) - 2) + b
	end
end

function EaseFuncs.OutInSextic(t, b, c, d)
	if t < d / 2 then
		return EaseFuncs.OutSextic(t * 2, b, c / 2, d)
	else
		return EaseFuncs.InSextic((t * 2) - d, b + c / 2, c / 2, d)
	end
end

-------------------------------------------------------------------------------------------------------------------------
-- Expo
-------------------------------------------------------------------------------------------------------------------------

function EaseFuncs.InExpo(t, b, c, d)
	if t == 0 then
		return b
	else
		return c * math.pow(2, 10 * (t / d - 1)) + b - c * 0.001
	end
end

function EaseFuncs.OutExpo(t, b, c, d)
	if t == d then
		return b + c
	else
		return c * 1.001 * (-math.pow(2, -10 * t / d) + 1) + b
	end
end

function EaseFuncs.InOutExpo(t, b, c, d)
	if t == 0 then
		return b
	end

	if t == d then
		return b + c
	end

	t = t / d * 2

	if t < 1 then
		return c / 2 * math.pow(2, 10 * (t - 1)) + b - c * 0.0005
	else
		t = t - 1
		return c / 2 * 1.0005 * (-math.pow(2, -10 * t) + 2) + b
	end
end

function EaseFuncs.OutInExpo(t, b, c, d)
	if t < d / 2 then
		return EaseFuncs.OutExpo(t * 2, b, c / 2, d)
	else
		return EaseFuncs.InExpo((t * 2) - d, b + c / 2, c / 2, d)
	end
end

-------------------------------------------------------------------------------------------------------------------------
-- Circ
-------------------------------------------------------------------------------------------------------------------------

function EaseFuncs.InCirc(t, b, c, d)
	t = t / d
	return (-c * (math.sqrt(1 - math.pow(t, 2)) - 1) + b)
end

function EaseFuncs.OutCirc(t, b, c, d)
	t = t / d - 1
	return (c * math.sqrt(1 - math.pow(t, 2)) + b)
end

function EaseFuncs.InOutCirc(t, b, c, d)
	t = t / d * 2

	if t < 1 then
		return -c / 2 * (math.sqrt(1 - t * t) - 1) + b
	else
		t = t - 2
		return c / 2 * (math.sqrt(1 - t * t) + 1) + b
	end
end

function EaseFuncs.OutInCirc(t, b, c, d)
	if t < d / 2 then
		return EaseFuncs.OutCirc(t * 2, b, c / 2, d)
	else
		return EaseFuncs.InCirc((t * 2) - d, b + c / 2, c / 2, d)
	end
end

-------------------------------------------------------------------------------------------------------------------------
-- Back
-------------------------------------------------------------------------------------------------------------------------

function EaseFuncs.InBack(t, b, c, d, s)
	if not s then
		s = 1.70158
	end

	t = t / d
	return c * t * t * ((s + 1) * t - s) + b
end

function EaseFuncs.OutBack(t, b, c, d, s)
	if not s then
		s = 1.70158
	end

	t = t / d - 1
	return c * (t * t * ((s + 1) * t + s) + 1) + b
end

function EaseFuncs.InOutBack(t, b, c, d, s)
	if not s then
		s = 1.70158
	end

	s = s * 1.525
	t = t / d * 2

	if t < 1 then
		return c / 2 * (t * t * ((s + 1) * t - s)) + b
	else
		t = t - 2
		return c / 2 * (t * t * ((s + 1) * t + s) + 2) + b
	end
end

function EaseFuncs.OutInBack(t, b, c, d, s)
	if t < d / 2 then
		return EaseFuncs.OutBack(t * 2, b, c / 2, d, s)
	else
		return EaseFuncs.InBack((t * 2) - d, b + c / 2, c / 2, d, s)
	end
end

-------------------------------------------------------------------------------------------------------------------------
-- Bounce
-------------------------------------------------------------------------------------------------------------------------

function EaseFuncs.OutBounce(t, b, c, d)
	t = t / d

	if t < 1 / 2.75 then
		return c * (7.5625 * t * t) + b
	elseif t < 2 / 2.75 then
		t = t - (1.5 / 2.75)
		return c * (7.5625 * t * t + 0.75) + b
	elseif t < 2.5 / 2.75 then
		t = t - (2.25 / 2.75)
		return c * (7.5625 * t * t + 0.9375) + b
	else
		t = t - (2.625 / 2.75)
		return c * (7.5625 * t * t + 0.984375) + b
	end
end

function EaseFuncs.InBounce(t, b, c, d)
	return c - EaseFuncs.OutBounce(d - t, 0, c, d) + b
end

function EaseFuncs.InOutBounce(t, b, c, d)
	if t < d / 2 then
		return EaseFuncs.InBounce(t * 2, 0, c, d) * 0.5 + b
	else
		return EaseFuncs.OutBounce(t * 2 - d, 0, c, d) * 0.5 + c * 0.5 + b
	end
end

function EaseFuncs.OutInBounce(t, b, c, d)
	if t < d / 2 then
		return EaseFuncs.OutBounce(t * 2, b, c / 2, d)
	else
		return EaseFuncs.InBounce((t * 2) - d, b + c / 2, c / 2, d)
	end
end

-------------------------------------------------------------------------------------------------------------------------
-- Elastic
-------------------------------------------------------------------------------------------------------------------------

function EaseFuncs.ElasticBlend(t, c, d, a, s, f)
	if c ~= 0 then
		local t_ = math.abs(s)

		if a ~= 0 then
			f = f * (a / math.abs(c))
		else
			f = 0
		end

		if math.abs(t * d) < t_ then
			local l = math.abs(t * d) / t_
			f = (f * l) + (1 - l)
		end
	end

	return f
end

function EaseFuncs.InElastic(t, b, c, d, a, p)
	local s
	local f = 1

	if t == 0 then
		return b
	end

	t = t / d

	if t == 1 then
		return b + c
	end

	t = t - 1

	if not p or p == 0 then
		p = d * 0.3
	end

	if a == nil or a < math.abs(c) then
		s = p / 4
		f = EaseFuncs.ElasticBend(t, c, d, a, s, f)
		a = c
	else
		s = p / (2 * math.pi) * math.asin(c / a)
	end

	return (-f * (a * math.pow(2, 10 * t) * math.sin((t * d - s) * (2 * math.pi) / p))) + b
end

function EaseFuncs.OutElastic(t, b, c, d, a, p)
	local s
	local f = 1

	if t == 0 then
		return b
	end

	t = t / d

	if t == 1 then
		return b + c
	end

	t = -t

	if not p or p == 0 then
		p = d * 0.3
	end

	if a == nil or a < math.abs(c) then
		s = p / 4
		f = EaseFuncs.ElasticBlend(t, c, d, a, s, f)
		a = c
	else
		s = p / (2 * math.pi) * math.asin(c / a)
	end

	return (f * (a * math.pow(2, 10 * t) * math.sin((t * d - s) * (2 * math.pi) / p))) + c + b
end

function EaseFuncs.InOutElastic(t, b, c, d, a, p)
	local s
	local f = 1

	if t == 0 then
		return b
	end

	t = t / (d / 2)

	if t == 2 then
		return b + c
	end

	t = t - 1

	if not p or p == 0 then
		p = d * (0.3 * 1.5)
	end

	if a == nil or a < math.abs(c) then
		s = p / 4
		f = EaseFuncs.ElasticBlend(t, c, d, a, s, f)
		a = c
	else
		s = p / (2 * math.pi) * math.asin(c / a)
	end

	if t < 0 then
		f = f * -0.5
		return (f * (a * math.pow(2, 10 * t) * math.sin((t * d - s) * (2 * math.pi) / p))) + b
	else
		t = -t
		f = f * 0.5
		return (f * (a * math.pow(2, 10 * t) * math.sin((t * d - s) * (2 * math.pi) / p))) + c + b
	end
end

function EaseFuncs.OutInElastic(t, b, c, d, a, p)
	if t < d / 2 then
		return EaseFuncs.OutElastic(t * 2, b, c / 2, d, a, p)
	else
		return EaseFuncs.InElastic((t * 2) - d, b + c / 2, c / 2, d, a, p)
	end
end

-------------------------------------------------------------------------------------------------------------------------
-- Module Export
-------------------------------------------------------------------------------------------------------------------------

local HttpService = game:GetService("HttpService")

local DEFAULT_INFO: MoonEaseInfo = {
	Type = "Linear",
	Params = {},
}

local FUNC_CACHE = {} :: {
	[string]: EaseFunc,
}

local function get(maybeInfo: MoonEaseInfo?): (value: number) -> number
	local info: MoonEaseInfo = maybeInfo or DEFAULT_INFO
	local hashKey = HttpService:JSONEncode(info)

	if FUNC_CACHE[hashKey] == nil then
		local params = info.Params
		local style: MoonEaseType = info.Type or "Linear"
		local dir: MoonEaseDir? = params.Direction or "In"

		-- stylua: ignore
		local impl = EaseFuncs[`{dir}{style}`]
		          or EaseFuncs[style]

		if impl then
			local arg1: number
			local arg2: number

			if style == "Elastic" then
				arg1 = params.Amplitude or 1
				arg2 = params.Period or 0.3
			elseif style == "Back" then
				arg1 = params.Overshoot or 1.70158
			end

			FUNC_CACHE[hashKey] = function(value)
				return impl(value, 0, 1, 1, arg1, arg2)
			end
		else
			return get(DEFAULT_INFO)
		end
	end

	return FUNC_CACHE[hashKey]
end

return {
	Get = get,
}

-------------------------------------------------------------------------------------------------------------------------
