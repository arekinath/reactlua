local log = {}

setmetatable(log, {__call = function(self, conn, txt)
	local front = "[" .. conn.remote.host .. ":" .. conn.remote.port
	if log.ident then front = front .. "/" .. log.ident end
	front = front .. "] (" .. os.date("%Y%m%d-%X") .. ") " .. txt
	print(front)
end})

return log