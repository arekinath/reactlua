local ffi = require('ffi')
local poll = require('react.unix.poll')
local socket = require('react.unix.socket')
local fcntl = require('react.unix.fcntl')
local bit = require('bit')

local table = table
local ipairs = ipairs
local assert = assert
local print = print
local tostring = tostring
local table = table
local setmetatable = setmetatable
local os = os

server = {}
local server = server
setfenv(1, server)

ffi.cdef[[
typedef int32_t pid_t;
pid_t fork(void);
int pipe(int fildes[2]);
uint32_t shim_get_symbol(const char *name);
]]

local shim = ffi.load("luaevent_shim")

EAGAIN = shim.shim_get_symbol('EAGAIN')
EWOULDBLOCK = shim.shim_get_symbol('EWOULDBLOCK')
EINPROGRESS = shim.shim_get_symbol('EINPROGRESS')

sockwrap = {}
function sockwrap.new(server, socket)
	local w = {_server = server, _socket = socket, last_event = os.time()}
	fcntl.setflags(socket.fd, {'RDWR', 'NONBLOCK'})
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
		cb(serv, sock, sw)
		return 'again'
	end
	self._server._read:insert(self)
end
function sockwrap:connect(addr, len, ok_cb)
	local res,err = self._socket:connect(addr, len)
	if res or (ffi.errno() == EAGAIN or ffi.errno() == EINPROGRESS) then
		self._write_cb = ok_cb
		self._server._write:insert(self)
		return true
	else
		return nil, err
	end
end
function sockwrap:write(string, cb)
	local buf = ffi.new('char[?]', #string + 1)
	ffi.copy(buf, string)
	self:write_buf(buf, #string, cb)
end
function sockwrap:write_buf(buf, len, cb)
	local offset = 0
	local ret = self._socket:write(buf, len)
	if (ret < 0 and (ffi.errno() == EWOULDBLOCK or ffi.errno() == EAGAIN))
			or (ret >= 0 and ret < offset) then	
		if ret >= 0 then offset = offset + ret end
		self._write_cb = function()
			offset = offset + self._socket:write(buf + offset, len - offset)
			if offset >= len then
				if cb then cb(self._server, self) end
			else
				return 'again'
			end
		end
		self._server._write:insert(self)
	elseif ret >= offset then
		if cb then
			return cb(self._server, self)
		else
			return nil
		end
	else
		self:close()
	end
end
function sockwrap:read_until(delim, max, cb)
	local buf = ffi.new('char[?]', max+1)
	local offset = 0
	self._read_cb = function(serv, sock)
		local ret = self._socket:read(buf+offset, 1)
		if (ret < 0 and ffi.errno() ~= EAGAIN and ffi.errno() ~= EWOULDBLOCK) or (ret == 0) then
			sock:close()
		else
			if ret < 0 then ret = 0 end		-- deal with eagain/ewouldblock
			offset = offset + ret
			local s_end = ffi.string(buf + offset - #delim, #delim)
			if s_end == delim or offset == max then
				self._read_cb = nil
				return cb(serv, sock, buf)
			end
			return 'again'
		end
	end
	self._server._read:insert(self)
end
function sockwrap:read_line(cb)
	self:read_until("\n", 4096, function(serv, sock, buf)
		cb(serv, sock, ffi.string(buf))
	end)
end
function sockwrap:wait_read(cb)
	self._read_cb = cb
	self._server._read:insert(self)
end
function sockwrap:wait_write(cb)
	self._write_cb = cb
	self._server._write:insert(self)
end
function sockwrap:read(size, cb)
	local buf = ffi.new('char[?]', size+1)
	local offset = 0
	self._read_cb = function(serv, sock)
		local ret = sock._socket:read(buf+offset, size-offset)
		if (ret < 0 and ffi.errno() ~= EAGAIN and ffi.errno() ~= EWOULDBLOCK) or (ret == 0) then
			sock:close()
		else
			if ret < 0 then ret = 0 end		-- deal with eagain/ewouldblock
			offset = offset + ret
			if offset == size then
				self._read_cb = nil
				cb(serv, sock, buf)
			else
				return 'again'
			end
		end
	end
	self._server._read:insert(self)
end
function sockwrap:pipe(other, size, eof_cb)
	size = size or 4096
	local buf = ffi.new('char[?]', size)
	self._read_cb = function()
		local ret = self._socket:read(buf, size)
		if (ret < 0 and ffi.errno() ~= EAGAIN and ffi.errno() ~= EWOULDBLOCK) or (ret == 0) then
			if eof_cb then
				eof_cb(self._server, self, other)
			else
				other:close()
				self:close()
			end
		else 
			if ret <= 0 then return 'again' end
			other:write_buf(buf, ret, function()
				self._server._read:insert(self)
			end)
		end
	end
	self._server._read:insert(self)
end
function sockwrap:close()
	self._socket:close()
	self._server._read:remove(self)
	self._read_cb = nil
	self._server._write:remove(self)
	self._write_cb = nil
	self.closed = true
	if self._close_cb then self._close_cb(self._server, self) end
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
function delaytable:remove(val)
	table.insert(self._queue, {m='remove', v=val})
end
function delaytable:insert_now(val)
	table.insert(self, val)
end
function delaytable:remove_now(val)
	local i = 1
	while i <= #self do
		if self[i] == val then
			table.remove(self, i)
		else
			i = i + 1
		end
	end
end
function delaytable:fdstring()
	local s = "{"
	for i,v in ipairs(self) do
		s = s .. "#" .. tostring(v.fd) .. ", "
	end
	s = s .. "}"
	return s
end
function delaytable:commit()
	for i,v in ipairs(self._queue) do
		if v.m == 'remove' then
			self:remove_now(v.v)
		end
	end
	for i,v in ipairs(self._queue) do
		if v.m == 'insert' then
			self:insert_now(v.v)
		end
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
            p:insert(v.fd, {'in'}, v)
        end
        for i,v in ipairs(self._write) do
            p:insert(v.fd, {'out'}, v)
        end
        
        -- do the poll
        local ret = p(10000)
        assert(ret >= 0, "poll failed: " .. ffi.string(ffi.C.strerror(ffi.errno())))

		-- process results
		local t = os.time()
		for pi = 0,p.size-1 do
			local v = p:map(pi)
			if p[pi]:test('out') then
				v.last_event = t
				if v._write_cb == nil or v._write_cb(self, v) ~= 'again' then
					self._write:remove(v)
				end
			end
			if p[pi]:test('in') then
				v.last_event = t
				if v._read_cb == nil or v._read_cb(self, v) ~= 'again' then
					self._read:remove(v)
				end
			end
			if p[pi]:test('err') then
				v:close()
			end
			if (t - v.last_event) > (v.timeout or 30) and not v.notimeout then
				v:close()
			end
		end
    end
end

return server
