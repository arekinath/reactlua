local ffi = require('ffi')
local bit = require('bit')

local setmetatable = setmetatable
local type = type
local tonumber = tonumber
local ipairs = ipairs
local assert = assert
local tostring = tostring
local tonumber = tonumber
local string = string
local print = print

socket = {}
local socket = socket
setfenv(1, socket)

ffi.cdef[[
uint32_t shim_get_symbol(const char *name);
uint8_t shim_canon_first(void);
void shim_do_sigpipe(void);
]]

local shim = ffi.load("luaevent_shim")
shim.shim_do_sigpipe()

ffi.cdef[[
typedef long ssize_t;
extern int h_errno;
typedef uint8_t sa_family_t;
typedef uint32_t socklen_t;
typedef uint32_t in_addr_t;
typedef uint16_t in_port_t;
struct in_addr {
    in_addr_t s_addr;
};
struct in6_addr {
		union {
			uint8_t   __u6_addr8[16];
			uint16_t  __u6_addr16[8];
			uint32_t  __u6_addr32[4];
		} __u6_addr;                    /* 128-bit IP6 address */
	};
]]
if ffi.os == 'Linux' then
	-- linux likes to be different and not have any sa_len fields...
	ffi.cdef[[
	struct sockaddr {
			sa_family_t sa_family;          /* address family */
			char        sa_data[14];        /* actually longer; address value */
	};
	struct sockaddr_in {
			sa_family_t sin_family;
			in_port_t   sin_port;
			struct      in_addr sin_addr;
			int8_t      sin_zero[8];
	};
	struct sockaddr_in6 {
			sa_family_t     sin6_family;    /* AF_INET6 (sa_family_t) */
			in_port_t       sin6_port;      /* Transport layer port # (in_port_t)*/
			uint32_t       sin6_flowinfo;  /* IP6 flow information */
			struct in6_addr sin6_addr;      /* IP6 address */
	};]]
	local mt = {__index = function(self,idx)
		if idx == 'sa_len' or idx == 'sin_len' or idx == 'sin6_len' then
			return false
		end
	end}
	ffi.metatype('struct sockaddr', mt)
	ffi.metatype('struct sockaddr_in', mt)
	ffi.metatype('struct sockaddr_in6', mt)
else
	ffi.cdef[[
	struct sockaddr {
			uint8_t    sa_len;             /* total length */
			sa_family_t sa_family;          /* address family */
			char        sa_data[14];        /* actually longer; address value */
	};
	struct sockaddr_in {
			uint8_t    sin_len;
			sa_family_t sin_family;
			in_port_t   sin_port;
			struct      in_addr sin_addr;
			int8_t      sin_zero[8];
	};
	struct sockaddr_in6 {
			uint8_t        sin6_len;       /* length of this struct(sa_family_t)*/
			sa_family_t     sin6_family;    /* AF_INET6 (sa_family_t) */
			in_port_t       sin6_port;      /* Transport layer port # (in_port_t)*/
			uint32_t       sin6_flowinfo;  /* IP6 flow information */
			struct in6_addr sin6_addr;      /* IP6 address */
			uint32_t       sin6_scope_id;  /* intface scope id */
	};]]
end
ffi.cdef[[
struct sockproto {
        unsigned short  sp_family;      /* address family */
        unsigned short  sp_protocol;    /* protocol */
};
struct osockaddr {
        unsigned short  sa_family;      /* address family */
        char            sa_data[14];    /* up to 14 bytes of direct address */
};]]
if shim.shim_canon_first() == 1 then
	ffi.cdef[[
	struct addrinfo {
	        int ai_flags;           /* input flags */
	        int ai_family;          /* protocol family for socket */
	        int ai_socktype;        /* socket type */
	        int ai_protocol;        /* protocol for socket */
	        socklen_t ai_addrlen;   /* length of socket-address */
			char *ai_canonname;     /* canonical name for service location (iff req) */
	        struct sockaddr *ai_addr; /* socket-address for socket */
	        struct addrinfo *ai_next; /* pointer to next in list */
	};
	]]
else
	ffi.cdef[[
	struct addrinfo {
	        int ai_flags;           /* input flags */
	        int ai_family;          /* protocol family for socket */
	        int ai_socktype;        /* socket type */
	        int ai_protocol;        /* protocol for socket */
	        socklen_t ai_addrlen;   /* length of socket-address */
	        struct sockaddr *ai_addr; /* socket-address for socket */
	        char *ai_canonname;     /* canonical name for service location (iff req) */
	        struct addrinfo *ai_next; /* pointer to next in list */
	};
	]]
end
ffi.cdef[[
int     getaddrinfo(const char *, const char *,
                    const struct addrinfo *, struct addrinfo **);
void    freeaddrinfo(struct addrinfo *);
int     getnameinfo(const struct sockaddr *, socklen_t,
                    char *, size_t, char *, size_t, int);
void perror(const char *string);
int     accept(int, struct sockaddr *, socklen_t *);
int     bind(int, const struct sockaddr *, socklen_t);
int     connect(int, const struct sockaddr *, socklen_t);
int     getpeername(int, struct sockaddr *, socklen_t *);
int     getsockname(int, struct sockaddr *, socklen_t *);
int     getsockopt(int, int, int, void *, socklen_t *);
int     listen(int, int);
ssize_t recv(int, void *, size_t, int);
ssize_t recvfrom(int, void *, size_t, int, struct sockaddr *, socklen_t *);
ssize_t send(int, const void *, size_t, int);
ssize_t sendto(int, const void *,
            size_t, int, const struct sockaddr *, socklen_t);
int     setsockopt(int, int, int, const void *, socklen_t);
int     shutdown(int, int);
int     socket(int, int, int);
int     socketpair(int, int, int, int *);
int     getrtable(void);
int     setrtable(int);

ssize_t  read(int, void *, size_t);
ssize_t  write(int, const void *, size_t);
int      close(int);

int shutdown(int socket, int how);

const char *gai_strerror(int errcode);
char *strerror(int errnum);
]]

local syms = {'SOCK_STREAM', 'SOCK_DGRAM', 'SOCK_RAW', 'SOCK_RDM', 'SOCK_SEQPACKET',
	'SO_ACCEPTCONN', 'SO_REUSEADDR', 'SO_KEEPALIVE', 'SO_DONTROUTE',
	'SO_BROADCAST', 'SO_USELOOPBACK', 'SO_LINGER', 'SO_OOBINLINE',
	'SO_REUSEPORT', 'SO_JUMBO', 'SO_TIMESTAMP', 'SO_BINDANY', 'AF_UNSPEC',
	'AF_LOCAL', 'AF_UNIX', 'AF_INET', 'AF_INET6', 'NETDB_INTERNAL', 'NETDB_SUCCESS',
	'HOST_NOT_FOUND', 'TRY_AGAIN', 'NO_RECOVERY', 'NO_DATA', 'NO_ADDRESS',
	'NI_NUMERICHOST', 'NI_NUMERICSERV', 'NI_NOFQDN', 'NI_NAMEREQD', 'NI_DGRAM',
	'AI_PASSIVE', 'AI_CANONNAME', 'AI_NUMERICHOST', 'AI_EXT', 'AI_NUMERICSERV',
	'IPPROTO_IP', 'IPPROTO_HOPOPTS', 'IPPROTO_ICMP', 'IPPROTO_IGMP',
	'IPPROTO_GGP', 'IPPROTO_IPIP', 'IPPROTO_TCP', 'IPPROTO_EGP', 'IPPROTO_PUP',
	'IPPROTO_UDP', 'SHUT_RD', 'SHUT_WR', 'SHUT_RDWR'}
for i,v in ipairs(syms) do
	socket[v] = bit.tobit(tonumber(shim.shim_get_symbol(v)))
end

htonl = function(val)
    if ffi.abi('le') then
        return bit.bswap(val)
    else
        return bit.tobit(val)
    end
end

htons = function(val)
    if ffi.abi("le") then
        return bit.rshift(bit.bswap(bit.lshift(val, 8)),8)
    else
        return bit.tobit(val)
    end
end

INADDR_ANY = htonl(0x00000000)
INADDR_LOOPBACK = htonl(0x7f000001)
INADDR_BROADCAST = htonl(0xffffffff)

socket.address = {}

ffi.metatype('struct addrinfo', {__index = function(self, idx)
    if socket.address[idx] then
        return socket.address[idx]
    elseif not idx:find("^ai_") then
        return self['ai_' .. idx]
    end
end })

socket.addrinfo = {}
function socket.addrinfo.new(str, port, socktype, prot, flags)
    socktype = socktype or 0
    prot = prot or 0
    
    local flagmask = bit.tobit(0)
    flags = flags or {}
    for i,v in ipairs(flags) do
        if socket[string.upper(v)] then
            flagmask = bit.bor(flagmask, socket[string.upper(v)])
        elseif socket['AI_'..string.upper(v)] then
            flagmask = bit.bor(flagmask, socket['AI_'..string.upper(v)])
        end
    end
    
    local hints = ffi.new('struct addrinfo[?]', 1)
    hints[0].ai_family = AF_UNSPEC
    hints[0].ai_socktype = socktype
    hints[0].ai_protocol = prot
    hints[0].ai_flags = flagmask
    
    local ai = ffi.new('struct addrinfo*[?]',1)
    local ret = ffi.C.getaddrinfo(str, tostring(port), hints, ai)
    if ret ~= 0 then
        return nil, ffi.string(ffi.C.gai_strerror(ret))
    end
    
    return ffi.gc(ai[0], ffi.C.freeaddrinfo)
end

function socket.makeaddr(family, port, addr)
	local a = nil
	port = socket.htons(tonumber(port))
	if family == socket.AF_INET then
		a = ffi.new("struct sockaddr_in[?]", 1)
		if a[0].sin_len then a[0].sin_len = ffi.sizeof(a[0]) end
		a[0].sin_port = port
		a[0].sin_family = socket.AF_INET
		ffi.copy(a[0].sin_addr, addr, ffi.sizeof(addr[0]))
	elseif family == socket.AF_INET6 then
		a = ffi.new("struct sockaddr_in6[?]", 1)
		if a[0].sin6_len then a[0].sin6_len = ffi.sizeof(a[0]) end
		a[0].sin6_port = port
		a[0].sin6_family = socket.AF_INET6
		ffi.copy(a[0].sin6_addr, addr, ffi.sizeof(addr[0]))
	end
	return a
end

function socket:get_remote()
	local host = ffi.new("char[?]", 256)
	local serv = ffi.new("char[?]", 16)
	local r = ffi.C.getnameinfo(self.addr, self.addrlen, host, 256, serv, 16,
						bit.bor(NI_NUMERICSERV, NI_NUMERICHOST))
	if r ~= 0 then
		return nil, ffi.string(ffi.C.gai_strerror(r))
	end
	return {host = ffi.string(host), port = ffi.string(serv)}
end

function socket.new(domain, type, protocol)
    domain = domain or AF_INET
    type = type or SOCK_STREAM
    protocol = protocol or IPPROTO_TCP
    
    local fd = ffi.C.socket(domain, type, protocol)
    if fd < 0 then
        return nil, ffi.string(ffi.C.strerror(ffi.errno()))
    end

    local w = {fd = fd, family = domain, socktype = type, protocol = protocol}
    setmetatable(w, {__index = socket})
    return w
end

function socket:bind(addr, len)
    len = len or addr.sa_len
    local ret = ffi.C.bind(self.fd, addr, len)
    if ret < 0 then
        return nil, ffi.string(ffi.C.strerror(ffi.errno()))
    end
    return ret
end

function socket:listen(backlog)
    backlog = backlog or 128
    local ret = ffi.C.listen(self.fd, backlog)
    if ret < 0 then
        return nil, ffi.string(ffi.C.strerror(ffi.errno()))
    end
    return ret
end

function socket:shutdown(how)
	how = how or 'rdwr'
	return ffi.C.shutdown(self.fd, socket['SHUT_' .. string.upper(how)])
end

function socket:connect(addr, len)
	local ret = ffi.C.connect(self.fd, addr, len)
	if ret < 0 then
		return nil, ffi.string(ffi.C.strerror(ffi.errno()))
	end
	return ret
end

function socket:accept()
	local abuf = ffi.new("char[?]", 256)
    local sa = ffi.cast("struct sockaddr*", abuf)
    local salen = ffi.new("socklen_t[?]", 1)
	salen[0] = 256
    local fd = ffi.C.accept(self.fd, sa, salen)
    if fd < 0 then
        return nil, ffi.string(ffi.C.strerror(ffi.errno()))
    end
    local w = {fd = fd, _abuf = abuf, addr = sa, _lenbuf = salen, addrlen = salen[0]}
    setmetatable(w, {__index = socket})
	local remote, err = w:get_remote()
	assert(remote ~= nil, err and 'getnameinfo: ' .. err)
	w.remote = remote
    return w
end

function socket:read(buffer, size)
    return ffi.C.read(self.fd, buffer, size)
end

function socket:write(buffer, size)
    return ffi.C.write(self.fd, buffer, size)
end

function socket:close()
    local ret = ffi.C.close(self.fd)
	return ret
end

return socket
