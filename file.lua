local bit = require('bit')
local fcntl = require('fcntl')
local ffi = require('ffi')

local string = string
local ipairs = ipairs
local setmetatable = setmetatable

file = {}
local file = file
setfenv(1, file)

ffi.cdef[[
typedef long ssize_t;
int open(const char *path, int oflag, ...);
int close(int fildes);
ssize_t read(int fildes, void *buf, size_t nbyte);
ssize_t write(int fildes, const void *buf, size_t nbyte);
char *strerror(int errnum);
]]

O_RDONLY = bit.tobit(0x0000)
O_WRONLY = bit.tobit(0x0001)
O_RDWR = bit.tobit(0x0002)
O_ACCMODE = bit.tobit(0x0003)
O_NONBLOCK = bit.tobit(0x0004)
O_APPEND = bit.tobit(0x0008)
O_CREAT = bit.tobit(0x0200)
O_TRUNC = bit.tobit(0x0400)

function file.open(path, flags)
	local flagmask = O_NONBLOCK
	for i,v in ipairs(flags) do
		if file[string.upper(v)] then
			flagmask = bit.bor(flagmask, file[string.upper(v)])
		elseif file['O_'..string.upper(v)] then
			flagmask = bit.bor(flagmask, file['O_'..string.upper(v)])
		end
	end
	
	local fd = ffi.C.open(path, flagmask)
	if fd < 0 then
		return nil, ffi.string(ffi.C.strerror(ffi.errno()))
	end
	
	local w = {fd = fd}
	setmetatable(w, {__index = file})
	return w
end

function file:close()
	return ffi.C.close(self.fd)
end

function file:read(buf, len)
	return ffi.C.read(self.fd, buf, len)
end

function file:write(buf, len)
	return ffi.C.write(self.fd, buf, len)
end

return file