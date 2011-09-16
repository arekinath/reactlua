local ffi = require('ffi')
local bit = require('bit')

local setmetatable = setmetatable
local type = type
local string = string
local ipairs = ipairs
local tonumber = tonumber
local os = os
local print = print

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
uint32_t shim_get_symbol(const char *name);
]]

local shim = ffi.load("luaevent_shim")

syms = {'POLLIN', 'POLLPRI', 'POLLOUT', 'POLLERR', 'POLLHUP', 'POLLNVAL',
	'POLLRDNORM', 'POLLNORM', 'POLLWRNORM'}
for i,v in ipairs(syms) do
	poll[v] = bit.tobit(tonumber(shim.shim_get_symbol(v)))
end

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
    local w = {_i = 0, _map={}, _fdmap={}}
    w._pollfd = ffi.new('struct pollfd[?]', size)
    w._nfds = size
	w.size = size
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
            return ffi.C.poll(w._pollfd, w._nfds, timeout or -1)
        end
    })
    return w
end

function poll:map(idx)
	return self._map[idx]
end

function poll:insert(fd, evts, map)
	if self._fdmap[fd] then
		local i = self._fdmap[fd]
		for i,v in ipairs(evts) do
			self[i]:set(v)
		end
		self._nfds = self._nfds - 1
		self.size = self._nfds
	else
		self._fdmap[fd] = self._i
		self[self._i].fd = fd
		self[self._i].events = 0
		self[self._i].revents = 0
		for i,v in ipairs(evts) do
			self[self._i]:set(v)
		end
		self._i = self._i + 1
		if map then
			self._map[self._i-1] = map
		end
	end
end

return poll