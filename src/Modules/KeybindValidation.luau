local KeybindValidation = {}

export type KeybindMap = {[string]: string}

local ACTION_ORDER = {
	"ThrowKnife",
	"Stab",
	"Emote",
	"Sprint",
	"Crouch",
	"Slide",
	"Slot1",
	"Slot2",
	"Slot3",
}

local DEFAULTS: KeybindMap = {
	ThrowKnife = "E",
	Stab = "MouseButton1",
	Emote = "G",
	Sprint = "LeftShift",
	Crouch = "LeftControl",
	Slide = "C",
	Slot1 = "One",
	Slot2 = "Two",
	Slot3 = "Three",
}

local RESERVED: {[Enum.KeyCode]: boolean} = {
	[Enum.KeyCode.W] = true, [Enum.KeyCode.A] = true, [Enum.KeyCode.S] = true, [Enum.KeyCode.D] = true,
	[Enum.KeyCode.Space] = true, [Enum.KeyCode.Tab] = true, [Enum.KeyCode.Slash] = true, [Enum.KeyCode.Escape] = true,
	[Enum.KeyCode.Backspace] = true, [Enum.KeyCode.Return] = true, [Enum.KeyCode.KeypadEnter] = true,
	[Enum.KeyCode.I] = true, [Enum.KeyCode.O] = true, [Enum.KeyCode.F1] = true, [Enum.KeyCode.F2] = true, [Enum.KeyCode.F3] = true, [Enum.KeyCode.F4] = true,
	[Enum.KeyCode.F5] = true, [Enum.KeyCode.F6] = true, [Enum.KeyCode.F7] = true, [Enum.KeyCode.F8] = true, [Enum.KeyCode.F9] = true, [Enum.KeyCode.F10] = true,
	[Enum.KeyCode.F11] = true, [Enum.KeyCode.F12] = true, [Enum.KeyCode.LeftMeta] = true, [Enum.KeyCode.RightMeta] = true,
}

local MOUSE_ALIASES = {
	MouseLeftButton = "MouseButton1",
	MouseRightButton = "MouseButton2",
	MouseMiddleButton = "MouseButton3",
	LClick = "MouseButton1",
	RClick = "MouseButton2",
	MClick = "MouseButton3",
}

local DISPLAY_NAMES = {
	Zero = "0", One = "1", Two = "2", Three = "3", Four = "4",
	Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9",
	LeftShift = "Shift", RightShift = "Shift",
	LeftControl = "Ctrl", RightControl = "Ctrl",
	LeftAlt = "Alt", RightAlt = "Alt",
}

local function keyName(value: any): string?
	if typeof(value) == "EnumItem" then
		if value.EnumType == Enum.KeyCode then
			return value.Name
		end
		return nil
	end
	if type(value) ~= "string" then
		return nil
	end

	local name = value:gsub("^Enum%.KeyCode%.", "")
	name = MOUSE_ALIASES[name] or name
	if name == "MouseButton1" or name == "MouseButton2" or name == "MouseButton3" then
		return name
	end
	return Enum.KeyCode[name] and name or nil
end

function KeybindValidation.GetActions(): {string}
	return ACTION_ORDER
end

function KeybindValidation.GetDefaults(): KeybindMap
	local result = {}
	for _, action in ipairs(ACTION_ORDER) do
		result[action] = DEFAULTS[action]
	end
	return result
end

function KeybindValidation.IsKnownAction(action: any): boolean
	return type(action) == "string" and DEFAULTS[action] ~= nil
end

function KeybindValidation.Normalize(value: any): string?
	local name = keyName(value)
	if not name then
		return nil
	end
	if name ~= "MouseButton1" and name ~= "MouseButton2" and name ~= "MouseButton3" then
		local key = Enum.KeyCode[name]
		if RESERVED[key] then
			return nil
		end
	end
	return name
end

function KeybindValidation.ToEnum(value: any): Enum.KeyCode?
	local normalized = KeybindValidation.Normalize(value)
	if normalized and normalized ~= "MouseButton1" and normalized ~= "MouseButton2" and normalized ~= "MouseButton3" then
		return Enum.KeyCode[normalized]
	end
	return nil
end

function KeybindValidation.ToDisplay(value: any): string
	local normalized = KeybindValidation.Normalize(value) or ""
	return DISPLAY_NAMES[normalized] or normalized
end

function KeybindValidation.ValidateAndRepair(saved: any): KeybindMap
	local result = KeybindValidation.GetDefaults()
	local used: {[string]: boolean} = {}

	if type(saved) ~= "table" then
		return result
	end

	for _, action in ipairs(ACTION_ORDER) do
		local candidate = KeybindValidation.Normalize(saved[action])
		if not candidate or used[candidate] then
			candidate = DEFAULTS[action]
		end
		if used[candidate] then
			for _, fallback in ipairs({"Q", "R", "T", "Y", "H", "J", "K", "L"}) do
				if not used[fallback] then
					candidate = fallback
					break
				end
			end
		end
		result[action] = candidate
		used[candidate] = true
	end

	return result
end

return KeybindValidation
