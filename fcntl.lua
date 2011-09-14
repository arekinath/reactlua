local ffi = require('ffi')
local bit = require('bit')

local string = string
local type = type

fcntl = {}
local fcntl = fcntl
setfenv(1, fcntl)

ffi.cdef[[
int     fcntl(int, int, ...);
]]

O_NONBLOCK = bit.tobit(0x0004)
O_APPEND = bit.tobit(0x0008)
O_SHLOCK = bit.tobit(0x0010)
O_EXLOCK = bit.tobit(0x0020)
O_ASYNC = bit.tobit(0x0040)
O_FSYNC = bit.tobit(0x0080)
O_NOFOLLOW = bit.tobit(0x0100)
O_SYNC = bit.tobit(0x0080)
O_CREAT = bit.tobit(0x0200)
O_TRUNC = bit.tobit(0x0400)
O_EXCL = bit.tobit(0x0800)

F_DUPFD = bit.tobit(0)
F_GETFD = bit.tobit(1)
F_SETFD = bit.tobit(2)
F_GETFL = bit.tobit(3)
F_SETFL = bit.tobit(4)

function fcntl.dupfd(fd)
    return ffi.C.fcntl(fd, F_DUPFD)
end

function fcntl.getflag(fd, flag)
    if type(flag) == 'string' then
        if fcntl[string.upper(flag)] then
            flag = fcntl[string.upper(flag)]
        elseif fcntl['O_'..string.upper(flag)] then
            flag = fcntl['O_'..string.upper(flag)]
        end
    end
    return ffi.C.fcntl(fd, F_GETFL, flag)
end

function fcntl.setflag(fd, flag)
    if type(flag) == 'string' then
        if fcntl[string.upper(flag)] then
            flag = fcntl[string.upper(flag)]
        elseif fcntl['O_'..string.upper(flag)] then
            flag = fcntl['O_'..string.upper(flag)]
        end
    end
    return ffi.C.fcntl(fd, F_SETFL, flag)
end

return fcntl