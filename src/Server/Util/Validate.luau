--[[
	Validate
	Checks for values that arrive from clients. Never assume a client sent the type
	it was supposed to send: a cheater can send anything, including NaN, huge tables,
	or the wrong types entirely.
]]

local Validate = {}

-- A real number: not NaN, not infinity.
function Validate.isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function Validate.isFiniteVector3(value: any): boolean
	return typeof(value) == "Vector3"
		and Validate.isFiniteNumber(value.X)
		and Validate.isFiniteNumber(value.Y)
		and Validate.isFiniteNumber(value.Z)
end

-- A plain list of 1 to `maxLength` different positive whole numbers (unit ids).
function Validate.isIdList(value: any, maxLength: number): boolean
	if type(value) ~= "table" then
		return false
	end
	local count = 0
	local seen = {}
	for key, id in value do
		count += 1
		if count > maxLength or key ~= count then
			return false
		end
		if not Validate.isFiniteNumber(id) or id < 1 or id % 1 ~= 0 or seen[id] then
			return false
		end
		seen[id] = true
	end
	return count > 0
end

return Validate
