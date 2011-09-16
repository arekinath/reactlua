local ffi = require('ffi')
local bit = require('bit')

local string = string
local print = print
local type = type
local ipairs = ipairs

fcntl = {}
local fcntl = fcntl
setfenv(1, fcntl)

ffi.cdef[[
int     fcntl(int, int, ...);
uint32_t shim_get_symbol(const char *name);
]]

local shim = ffi.load("luaevent_shim")

local syms = {'O_RDONLY', 'O_WRONLY', 'O_RDWR', 'O_CREAT', 'O_EXCL',
	'O_NOCTTY', 'O_TRUNC', 'O_APPEND', 'O_NONBLOCK', 'O_NDELAY', 'O_SYNC',
	'O_FSYNC', 'O_ASYNC'}
for i,v in ipairs(syms) do
	fcntl[v] = shim.shim_get_symbol(v)
end

F_DUPFD = bit.tobit(0)
F_GETFD = bit.tobit(1)
F_SETFD = bit.tobit(2)
F_GETFL = bit.tobit(3)
F_SETFL = bit.tobit(4)

function fcntl.dupfd(fd)
    return ffi.C.fcntl(fd, F_DUPFD)
end

function fcntl.getflags(fd)
	local r = ffi.C.fcntl(fd, F_GETFL)
    if r < 0 then r = 0 end
	return bit.tobit(r)
end

function fcntl.setflag(fd, flag, erase)
	mask = fcntl.getflags(fd)
    if type(flag) == 'string' then
        if fcntl[string.upper(flag)] then
            mask = bit.bor(mask, fcntl[string.upper(flag)])
        elseif fcntl['O_'..string.upper(flag)] then
            mask = bit.bor(mask, fcntl['O_'..string.upper(flag)])
        end
    end
    return ffi.C.fcntl(fd, F_SETFL, mask)
end

function fcntl.unsetflag(fd, flag)
	mask = fcntl.getflags(fd)
    if type(flag) == 'string' then
        if fcntl[string.upper(flag)] then
            mask = bit.band(mask, bit.bnot(fcntl[string.upper(flag)]))
        elseif fcntl['O_'..string.upper(flag)] then
            mask = bit.band(mask, bit.bnot(fcntl['O_'..string.upper(flag)]))
        end
    end
	return ffi.C.fcntl(fd, F_SETFL, mask)
end

return fcntl