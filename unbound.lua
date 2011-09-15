local ffi = require('ffi')
local bit = require('bit')
local socket = require('socket')

local ipairs = ipairs
local setmetatable = setmetatable
local print = print

unbound = {}
local unbound = unbound
setfenv(1, unbound)

ffi.cdef[[
struct ub_ctx;
struct ub_result {
	char* qname;
	int qtype;
	int qclass;
	char** data;
	int* len;
	char* canonname;
	int rcode;
	void* answer_packet;
	int answer_len;
	int havedata;
	int nxdomain;
	int secure;
	int bogus;
	char* why_bogus;
};
struct ub_ctx* ub_ctx_create(void);
void ub_ctx_delete(struct ub_ctx* ctx);
int ub_ctx_set_option(struct ub_ctx* ctx, char* opt, char* val);
int ub_ctx_get_option(struct ub_ctx* ctx, char* opt, char** str);
int ub_ctx_resolvconf(struct ub_ctx* ctx, char* fname);
int ub_fd(struct ub_ctx* ctx);
int ub_process(struct ub_ctx* ctx);
const char* ub_strerror(int err);

struct ub_result *ubshim_get_result(void);
int ubshim_get_err(void);
int ubshim_resolve_async(struct ub_ctx* ctx, const char* name, int rrtype, int rrclass, int* async_id);
]]

-- don't load libunbound, luaevent_shim is linked against it
local lib = ffi.load("luaevent_shim")

types = {
	A=1, NS=2, MD=3, MF=4, CNAME=5, SOA=6, MB=7, MG=8, MR=9, PTR=12, MX=15,
	AAAA=28
}

local result = {}
function result:get_addr(i)
	if self.qtype == types.A then
		return ffi.cast('struct in_addr*', self.data[i]), self.len[i]
	elseif self.qtype == types.AAAA then
		return ffi.cast('struct in6_addr*', self.data[i]), self.len[i]
	end
end
function result:iter(i)
	if self.data[i] ~= nil then
		local ret,len = self:get_addr(i)
		return i+1,ret,len
	end
end
function result:addrs()
	if self.data ~= nil or self.rcode ~= 0 then
		return self.iter, self, 0
	end
end
ffi.metatype('struct ub_result', {__index = result})

resolver = {}
function resolver.new(name)
	local w4 = {}
	local w6 = {}
	
	w4._ctx = ffi.gc(lib.ub_ctx_create(), lib.ub_ctx_delete)
	if w4._ctx == nil then
		return nil, "Could not create unbound context"
	end
	local ret = lib.ubshim_resolve_async(w4._ctx, name, types.A, 1, nil)
	if ret ~= 0 then
		return nil, ffi.string(lib.ub_strerror(ret))
	end
	
	w6._ctx = ffi.gc(lib.ub_ctx_create(), lib.ub_ctx_delete)
	if w6._ctx == nil then
		return nil, "Could not create unbound context"
	end
	ret = lib.ubshim_resolve_async(w6._ctx, name, types.AAAA, 1, nil)
	if ret ~= 0 then
		return nil, ffi.string(lib.ub_strerror(ret))
	end
	
	w4.fd = lib.ub_fd(w4._ctx)
	w6.fd = lib.ub_fd(w6._ctx)
	
	setmetatable(w4, {__index = resolver})
	setmetatable(w6, {__index = resolver})
	return w4, w6
end

function resolver:get_result()
	local ret = lib.ub_process(self._ctx)
	if ret ~= 0 then
		return nil, ffi.string(lib.ub_strerror(ret))
	end
	
	ret = lib.ubshim_get_err()
	if ret ~= 0 then
		return nil, ffi.string(lib.ub_strerror(ret))
	end
	
	self.result = lib.ubshim_get_result()
	return self.result
end

return unbound