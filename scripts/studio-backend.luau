-- Native test adapter only. build-studio-tests.py injects this into an unsaved
-- copy; production never requires it. No player records are read or written.
local Backend = {Stores = {}, Writes = 0, Reads = 0}
local function copy(value)
	if type(value) ~= "table" then return value end
	local result = {}; for key, item in pairs(value) do result[key] = copy(item) end; return result
end
function Backend:GetDataStore(name)
	if self.Stores[name] then return self.Stores[name] end
	local store = {Data = {}}
	function store:GetAsync(key) Backend.Reads += 1; return copy(self.Data[tostring(key)]) end
	function store:SetAsync(key, value) Backend.Writes += 1; self.Data[tostring(key)] = copy(value) end
	function store:UpdateAsync(key, transform)
		Backend.Writes += 1
		local value = transform(copy(self.Data[tostring(key)]))
		if value ~= nil then self.Data[tostring(key)] = copy(value) end
		return copy(self.Data[tostring(key)])
	end
	function store:RemoveAsync(key) local value = self:GetAsync(key); self.Data[tostring(key)] = nil; return value end
	function store:IncrementAsync(key, delta) return self:UpdateAsync(key, function(old) return (old or 0) + delta end) end
	function store:GetSortedAsync(ascending, limit)
		local rows = {}; for key, value in pairs(self.Data) do table.insert(rows, {key = key, value = value}) end
		table.sort(rows, function(a,b) return ascending and a.value < b.value or not ascending and a.value > b.value end)
		while #rows > limit do table.remove(rows) end
		return {IsFinished = true, GetCurrentPage = function() return rows end, AdvanceToNextPageAsync = function() end}
	end
	self.Stores[name] = store; return store
end
Backend.GetOrderedDataStore = Backend.GetDataStore
function Backend:GetRequestBudgetForRequestType() return 1000 end
return Backend
