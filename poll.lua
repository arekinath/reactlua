local ffi = require('ffi')
local bit = require('bit')

local setmetatable = setmetatable
local type = type
local string = string
local ipairs = ipairs

poll = {}
local poll = poll
setfenv(1, poll)

ffi.cdef[[
typedef unsigned int nfds_t;
typedef struct pollfd {
    int     fd;
    short   events;
    short   revents;
} pollfd_t;
int   poll(struct pollfd[], nfds_t, int);
]]

POLLIN = bit.tobit(0x0001)
POLLPRI = bit.tobit(0x0002)
POLLOUT = bit.tobit(0x0004)
POLLERR = bit.tobit(0x0008)
POLLHUP = bit.tobit(0x0010)
POLLNVAL = bit.tobit(0x0020)
POLLRDNORM = bit.tobit(0x0040)
POLLNORM = POLLRDNORM
POLLWRNORM = POLLOUT
POLLRDBAND = bit.tobit(0x0080)
POLLWRBAND = bit.tobit(0x0100)

local pollfd = {}
function pollfd:set(mask)
    if type(mask) == 'string' then
        if poll[string.upper(mask)] then
            mask = poll[string.upper(mask)]
        elseif poll['POLL'..string.upper(mask)] then
            mask = poll['POLL'..string.upper(mask)]
        end
    end
    self.events = bit.bor(self.events, mask)
end
function pollfd:unset(mask)
    if type(mask) == 'string' then
        if poll[string.upper(mask)] then
            mask = poll[string.upper(mask)]
        elseif poll['POLL'..string.upper(mask)] then
            mask = poll['POLL'..string.upper(mask)]
        end
    end
    self.events = bit.band(self.events, bit.bnot(mask))
end
function pollfd:test(mask)
    if type(mask) == 'string' then
        if poll[string.upper(mask)] then
            mask = poll[string.upper(mask)]
        elseif poll['POLL'..string.upper(mask)] then
            mask = poll['POLL'..string.upper(mask)]
        end
    end
    return (bit.band(self.revents, mask) == mask)
end
ffi.metatype('struct pollfd', {__index = pollfd})

function poll.new(size)
    local w = {_i = 0}
    w._pollfd = ffi.new('struct pollfd[?]', size)
    w._nfds = size
    setmetatable(w, {
        __index = function(self, idx)
            if poll[idx] then
                return poll[idx]
            elseif self._pollfd[idx] then
                return self._pollfd[idx]
            else
                return nil
            end
        end,
        __call = function(self, timeout)
            return ffi.C.poll(w._pollfd, w._nfds, -1)
        end
    })
    return w
end

function poll:insert(fd, evts)
    self[self._i].fd = fd
    self[self._i].events = 0
    self[self._i].revents = 0
    for i,v in ipairs(evts) do
        self[self._i]:set(v)
    end
    self._i = self._i + 1
end

return poll