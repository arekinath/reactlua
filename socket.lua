local ffi = require('ffi')
local bit = require('bit')

local setmetatable = setmetatable
local type = type
local tonumber = tonumber
local ipairs = ipairs
local assert = assert
local tostring = tostring
local string = string
local print = print

socket = {}
local socket = socket
setfenv(1, socket)

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
struct in6_addr {
    union {
        uint8_t   __u6_addr8[16];
        uint16_t  __u6_addr16[8];
        uint32_t  __u6_addr32[4];
    } __u6_addr;                    /* 128-bit IP6 address */
};
struct sockaddr_in6 {
        uint8_t        sin6_len;       /* length of this struct(sa_family_t)*/
        sa_family_t     sin6_family;    /* AF_INET6 (sa_family_t) */
        in_port_t       sin6_port;      /* Transport layer port # (in_port_t)*/
        uint32_t       sin6_flowinfo;  /* IP6 flow information */
        struct in6_addr sin6_addr;      /* IP6 address */
        uint32_t       sin6_scope_id;  /* intface scope id */
};
struct sockproto {
        unsigned short  sp_family;      /* address family */
        unsigned short  sp_protocol;    /* protocol */
};
struct osockaddr {
        unsigned short  sa_family;      /* address family */
        char            sa_data[14];    /* up to 14 bytes of direct address */
};]]
if ffi.os == 'OSX' then
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

const char *gai_strerror(int errcode);
char *strerror(int errnum);
]]

SOCK_STREAM = bit.tobit(1)
SOCK_DGRAM = bit.tobit(2)
SOCK_RAW = bit.tobit(3)
SOCK_RDM = bit.tobit(4)
SOCK_SEQPACKET = bit.tobit(5)
SO_DEBUG = bit.tobit(0x0001)
SO_ACCEPTCONN = bit.tobit(0x0002)
SO_REUSEADDR = bit.tobit(0x0004)
SO_KEEPALIVE = bit.tobit(0x0008)
SO_DONTROUTE = bit.tobit(0x0010)
SO_BROADCAST = bit.tobit(0x0020)
SO_USELOOPBACK = bit.tobit(0x0040)
SO_LINGER = bit.tobit(0x0080)
SO_OOBINLINE = bit.tobit(0x0100)
SO_REUSEPORT = bit.tobit(0x0200)
SO_JUMBO = bit.tobit(0x0400)
SO_TIMESTAMP = bit.tobit(0x0800)
SO_BINDANY = bit.tobit(0x1000)
AF_UNSPEC = bit.tobit(0)
AF_LOCAL = bit.tobit(1)
AF_UNIX = AF_LOCAL
AF_INET = bit.tobit(2)
AF_IMPLINK = bit.tobit(3)
AF_PUP = bit.tobit(4)
AF_CHAOS = bit.tobit(5)
AF_NS = bit.tobit(6)
AF_ISO = bit.tobit(7)
AF_OSI = AF_ISO
AF_ECMA = bit.tobit(8)
AF_DATAKIT = bit.tobit(9)
AF_CCITT = bit.tobit(10)
AF_SNA = bit.tobit(11)
AF_DECnet = bit.tobit(12)
AF_DLI = bit.tobit(13)
AF_LAT = bit.tobit(14)
AF_HYLINK = bit.tobit(15)
AF_APPLETALK = bit.tobit(16)
AF_ROUTE = bit.tobit(17)
AF_LINK = bit.tobit(18)
AF_COIP = bit.tobit(20)
AF_CNT = bit.tobit(21)
AF_IPX = bit.tobit(23)

NETDB_INTERNAL = bit.tobit(-1)
NETDB_SUCCESS = bit.tobit(0)
HOST_NOT_FOUND = bit.tobit(1)
TRY_AGAIN = bit.tobit(2)
NO_RECOVERY = bit.tobit(3)
NO_DATA = bit.tobit(4)
NO_ADDRESS = NO_DATA
NI_NUMERICHOST = bit.tobit(1)
NI_NUMERICSERV = bit.tobit(2)
NI_NOFQDN = bit.tobit(4)
NI_NAMEREQD = bit.tobit(8)
NI_DGRAM = bit.tobit(16)

AI_PASSIVE = bit.tobit(1)
AI_CANONNAME = bit.tobit(2)
AI_NUMERICHOST = bit.tobit(4)
AI_EXT = bit.tobit(8)
AI_NUMERICSERV = bit.tobit(16)

IPPROTO_IP = bit.tobit(0)
IPPROTO_HOPOPTS = bit.tobit(IPPROTO_IP)
IPPROTO_ICMP = bit.tobit(1)
IPPROTO_IGMP = bit.tobit(2)
IPPROTO_GGP = bit.tobit(3)
IPPROTO_IPIP = bit.tobit(4)
IPPROTO_TCP = bit.tobit(6)
IPPROTO_EGP = bit.tobit(8)
IPPROTO_PUP = bit.tobit(12)
IPPROTO_UDP = bit.tobit(17)
IPPROTO_IDP = bit.tobit(22)
IPPROTO_TP = bit.tobit(29)
IPPROTO_ROUTING = bit.tobit(43)
IPPROTO_FRAGMENT = bit.tobit(44)
IPPROTO_RSVP = bit.tobit(46)
IPPROTO_GRE = bit.tobit(47)
IPPROTO_ESP = bit.tobit(50)
IPPROTO_AH = bit.tobit(51)
IPPROTO_MOBILE = bit.tobit(55)
IPPROTO_NONE = bit.tobit(59)
IPPROTO_DSTOPTS = bit.tobit(60)
IPPROTO_EON = bit.tobit(80)
IPPROTO_ETHERIP = bit.tobit(97)
IPPROTO_ENCAP = bit.tobit(98)
IPPROTO_PIM = bit.tobit(103)
IPPROTO_IPCOMP = bit.tobit(108)
IPPROTO_CARP = bit.tobit(112)
IPPROTO_MPLS = bit.tobit(137)
IPPROTO_PFSYNC = bit.tobit(240)
IPPROTO_RAW = bit.tobit(255)

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
    if self['ai_' .. idx] then
        return self['ai_' .. idx]
    elseif socket.address[idx] then
        return socket.address[idx]
    else
        return nil
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

function socket.new(domain, type, protocol)
    domain = domain or AF_INET
    type = type or SOCK_STREAM
    protocol = protocol or IPPROTO_TCP
    
    local fd = ffi.C.socket(domain, type, protocol)
    if fd < 0 then
        return nil, ffi.string(ffi.C.strerror(ffi.errno()))
    end

    local w = {fd = fd}
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

function socket:accept()
    local sa = ffi.cast("struct sockaddr*", ffi.new("char[?]", 256))
    local salen = ffi.new("socklen_t[?]", 1)
    local fd = ffi.C.accept(self.fd, sa, salen)
    if fd < 0 then
        return nil, ffi.string(ffi.C.strerror(ffi.errno()))
    end
    local w = {fd = fd, addr = sa}
    setmetatable(w, {__index = socket})
    return w
end

function socket:read(buffer, size)
    return ffi.C.read(self.fd, buffer, size)
end

function socket:write(buffer, size)
    return ffi.C.write(self.fd, buffer, size)
end

function socket:close()
    return ffi.C.close(self.fd)
end

return socket