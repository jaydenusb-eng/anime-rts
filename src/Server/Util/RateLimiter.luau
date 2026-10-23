--[[
	RateLimiter
	A "token bucket". Each player has a bucket of tokens and every request spends one.
	Tokens trickle back over time. When the bucket is empty, requests are refused.
	This stops one player from flooding the server with orders, on purpose or by a bug.
]]

local RateLimiter = {}
RateLimiter.__index = RateLimiter

-- `burst`: how many requests can arrive at once. `refillPerSecond`: how fast tokens return.
function RateLimiter.new(burst: number, refillPerSecond: number)
	return setmetatable({
		burst = burst,
		refillPerSecond = refillPerSecond,
		buckets = {},
	}, RateLimiter)
end

-- Spends a token for `key` (usually a Player). Returns false if there are none left.
function RateLimiter:allow(key: any): boolean
	local now = os.clock()
	local bucket = self.buckets[key]
	if not bucket then
		bucket = { tokens = self.burst, updatedAt = now }
		self.buckets[key] = bucket
	end
	bucket.tokens = math.min(self.burst, bucket.tokens + (now - bucket.updatedAt) * self.refillPerSecond)
	bucket.updatedAt = now
	if bucket.tokens >= 1 then
		bucket.tokens -= 1
		return true
	end
	return false
end

-- Drops the bucket for `key` (call when a player leaves).
function RateLimiter:forget(key: any)
	self.buckets[key] = nil
end

return RateLimiter
