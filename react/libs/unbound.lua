local ffi = require('ffi')
local bit = require('bit')
local socket = require('react.unix.socket')
local server = require('react.server')

local ipairs = ipairs
local setmetatable = setmetatable
local print = print
local table = table

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
int ub_ctx_set_option(struct ub_ctx* ctx, const char* opt, const char* val);
int ub_ctx_get_option(struct ub_ctx* ctx, char* opt, char** str);
int ub_ctx_resolvconf(struct ub_ctx* ctx, char* fname);
int ub_fd(struct ub_ctx* ctx);
int ub_process(struct ub_ctx* ctx);
const char* ub_strerror(int err);
void ub_resolve_free(struct ub_result* result);

struct ubshim_return;
struct ubshim_return {
	struct ubshim_return *next;
	struct ubshim_return *prev;
	int err;
	void *data;
	struct ub_result *result;
};

struct marker {
	uint32_t idx;
};

struct ubshim_return *ubshim_queue_head(void);
struct ubshim_return *ubshim_queue_tail(void);
void ubshim_set_queue_head(struct ubshim_return *new);
void ubshim_set_queue_tail(struct ubshim_return *new);
int ubshim_resolve_async(struct ub_ctx* ctx, const char* name, int rrtype,
						int rrclass, void *data, int* async_id);
						
void free(void *ptr);
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

resolver._context = ffi.gc(lib.ub_ctx_create(), lib.ub_ctx_delete)
lib.ub_ctx_set_option(resolver._context, "cache-min-ttl", "300")

function unbound.link_to_server(serv)
	local cbt = {}
	function cbt:insert(cb)
		self._idx[0] = self._idx[0] + 1
		self[self._idx[0]] = cb
		return self._idx[0]
	end
	
	local w = {_cbs = {_idx = ffi.new('uint32_t[?]',1)}, _markers = {}}
	setmetatable(w._markers, {__index = table})
	setmetatable(w._cbs, {__index = cbt})
	resolver._cwrap = w
	w._ctx = resolver._context
	w._serv = serv
	w._wait_cb = function()
		local ret = lib.ub_process(w._ctx)
		local p = lib.ubshim_queue_head()
		while p ~= nil do
			local marker = ffi.cast('struct marker*', p.data)
			if w._cbs[marker.idx] ~= nil and w._cbs[marker.idx](p.err, p.result) ~= 'again' then
				w._cbs[marker.idx] = nil
				resolver._cwrap._markers[marker.idx] = nil
			end
			lib.ub_resolve_free(p.result)
			local before = p.prev
			local after = p.next
			if before ~= nil then
				before.next = after
			else
				lib.ubshim_set_queue_head(after)
			end
			if after ~= nil then
				after.prev = before
			else
				lib.ubshim_set_queue_tail(before)
			end
			ffi.C.free(p)
			p = after
		end
		return 'again'
	end
	local q = {fd = lib.ub_fd(w._ctx)}
	local sw = serv:wrap(q)
	sw.notimeout = true
	sw:wait_read(w._wait_cb)
end

function unbound.resolve(name, cb)
	local idx = resolver._cwrap._cbs:insert(cb)
	local mkr = ffi.new("struct marker[?]", 1)
	mkr[0].idx = idx
	resolver._cwrap._markers[idx] = mkr
	
	local ret = lib.ubshim_resolve_async(resolver._context, name, types.A, 1, mkr, nil)
	if ret ~= 0 then
		return nil, ffi.string(lib.ub_strerror(ret))
	end

	ret = lib.ubshim_resolve_async(resolver._context, name, types.AAAA, 1, mkr, nil)
	if ret ~= 0 then
		return nil, ffi.string(lib.ub_strerror(ret))
	end
	
	return true
end

return unbound