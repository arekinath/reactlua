local log = function(conn, txt)
	print(string.format("[%s:%s] (%s) %s", conn.remote.host,  conn.remote.port,
										os.date("%c"), txt))
end

return log