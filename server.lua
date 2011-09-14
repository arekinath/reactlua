local ffi = require('ffi')
local poll = require('poll')
local socket = require('socket')
local bit = require('bit')
local fcntl = require('fcntl')

local table = table
local ipairs = ipairs
local assert = assert
local print = print
local tostring = tostring
local table = table
local setmetatable = setmetatable

server = {}
local server = server
setfenv(1, server)

sockwrap = {}
function sockwrap.new(server, socket)
	local w = {_server = server, _socket = socket}
	setmetatable(w, {__index = function(self, idx)
		if sockwrap[idx] then
			return sockwrap[idx]
		elseif self._socket[idx] then
			return self._socket[idx]
		end
	end })
	return w
end
function sockwrap:accept(cb)
	self._read_cb = function(serv, sock)
		local sw = sockwrap.new(serv, sock._socket:accept())
		fcntl.setflag(sw.fd, 'nonblock')
		cb(serv, sock, sw)
		return 'again'
	end
	self._server._read:insert(self)
end
function sockwrap:write(string, cb)
	local buf = ffi.new('char[?]', #string + 1)
	ffi.copy(buf, string)
	self:write_buf(buf, #string, cb)
end
function sockwrap:write_buf(buf, len, cb)
	if self._socket:write(buf, len) < 0 then
		self._write_cb = function(serv, sock)
			sock._socket:write(buf, len)
			if cb then cb(serv, sock) end
		end
		self._server._write:insert(self)
	else
		if cb then cb(self._server, self) end
	end
end
function sockwrap:read_until(delim, max, cb)
	local buf = ffi.new('char[?]', max+1)
	local offset = 0
	self._read_cb = function(serv, sock)
		local ret = sock._socket:read(buf+offset, 1)
		if ret <= 0 and ffi.errno() ~= 35 and ffi.errno() ~= 11 then
			sock:close()
		else
			if ret < 0 then ret = 0 end		-- deal with eagain/ewouldblock
			offset = offset + ret
			if ffi.string(buf + offset - #delim, #delim) == delim or offset == max then
				cb(serv, sock, buf)
			else
				return 'again'
			end
		end
	end
	self._server._read:insert(self)
end
function sockwrap:read_line(cb)
	self:read_until("\n", 1024, function(serv, sock, buf)
		cb(serv, sock, ffi.string(buf))
	end)
end
function sockwrap:read(size, cb)
	local buf = ffi.new('char[?]', size+1)
	local offset = 0
	self._read_cb = function(serv, sock)
		local ret = sock._socket:read(buf+offset, size-offset)
		if ret <= 0 and ffi.errno() ~= 35 and ffi.errno() ~= 11 then
			sock:close()
		else
			if ret < 0 then ret = 0 end		-- deal with eagain/ewouldblock
			offset = offset + ret
			if offset == size then
				cb(serv, sock, buf)
			else
				return 'again'
			end
		end
	end
	self._server._read:insert(self)
end
function sockwrap:pipe(other, size)
	size = size or 4096
	local buf = ffi.new('char[?]', size)
	self._read_cb = function(serv, sock)
		local ret = sock._socket:read(buf, size)
		if ret <= 0 and ffi.errno() ~= 35 and ffi.errno() ~= 11 then
			sock:close()
			other:close()
		else 
			if ret <= 0 then return 'again' end
			other:write_buf(buf, ret, function(serv, sock)
				self._server._read:insert(self)
			end)
		end
	end
	self._server._read:insert(self)
end
function sockwrap:close()
	self._socket:close()
	if self._read_idx then self._server._read:remove(self._read_idx) end
	if self._write_idx then self._server._write:remove(self._write_idx) end
end

local delaytable = {}
function delaytable.new()
	local w = {_queue = {}}
	setmetatable(w, {__index = delaytable})
	return w
end
function delaytable:insert(val)
	table.insert(self._queue, {m='insert', v=val})
end
function delaytable:remove(idx)
	table.insert(self._queue, {m='remove', v=idx})
end
function delaytable:commit()
	for i,v in ipairs(self._queue) do
		table[v.m](self, v.v)
	end
	self._queue = {}
end

function server.new()
	local w = {}
	w._read = delaytable.new()
	w._write = delaytable.new()
	setmetatable(w, {__index=server})
	return w
end

function server:wrap(obj)
	return sockwrap.new(self, obj)
end

function server:go()
	while true do
		-- commit any outstanding transactions on the fd lists
		self._read:commit()
		self._write:commit()
		
        -- make the fd list
        local p = poll.new(#self._read + #self._write)
        for i,v in ipairs(self._read) do
			v._read_idx = i
            p:insert(v.fd, {'in', 'hup', 'err'}, v)
        end
        for i,v in ipairs(self._write) do
			v._write_idx = i
            p:insert(v.fd, {'out', 'hup', 'err'}, v)
        end
        
        -- do the poll
        local ret = p()
        assert(ret >= 0, "poll failed")
        
        -- process results
        for pi = 0,p.size-1 do
			local v = p:map(pi)
			if p[pi]:test('err') or p[pi]:test('hup') then
                v:close()
			elseif p[pi]:test('in') then
				if v._read_cb(self, v) ~= 'again' then
					self._read:remove(v._read_idx)
				end
			elseif p[pi]:test('out') then
				if v._write_cb(self, v) ~= 'again' then
					self._write:remove(v._write_idx)
				end
			end
			v._read_idx = nil
			v._write_idx = nil
		end
    end
end

return server
