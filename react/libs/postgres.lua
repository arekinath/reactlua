local ffi = require('ffi')
local bit = require('bit')
local socket = require('react.unix.socket')
local server = require('react.server')

local ipairs = ipairs
local setmetatable = setmetatable
local print = print
local rawget = rawget
local table = table
local assert = assert

postgres = {}
local postgres = postgres
setfenv(1, postgres)

ffi.cdef[[
typedef enum
{
        CONNECTION_OK,
        CONNECTION_BAD,
        CONNECTION_STARTED,                     /* Waiting for connection to be made.  */
        CONNECTION_MADE,                        /* Connection OK; waiting to send.         */
        CONNECTION_AWAITING_RESPONSE,           /* Waiting for a response from the */
        CONNECTION_AUTH_OK,                     /* Received authentication; waiting for */
        CONNECTION_SETENV,                      /* Negotiating environment. */
        CONNECTION_SSL_STARTUP,         /* Negotiating SSL. */
        CONNECTION_NEEDED                       /* Internal state: connect() needed */
} ConnStatusType;
typedef enum
{
        PGRES_POLLING_FAILED = 0,
        PGRES_POLLING_READING,          /* These two indicate that one may        */
        PGRES_POLLING_WRITING,          /* use select before polling again.   */
        PGRES_POLLING_OK,
        PGRES_POLLING_ACTIVE            /* unused; keep for awhile for backwards */
} PostgresPollingStatusType;
typedef enum
{
        PGRES_EMPTY_QUERY = 0,          /* empty query string was executed */
        PGRES_COMMAND_OK,                       /* a query command that doesn't return*/
        PGRES_TUPLES_OK,                        /* a query command that returns tuples was*/
        PGRES_COPY_OUT,                         /* Copy Out data transfer in progress */
        PGRES_COPY_IN,                          /* Copy In data transfer in progress */
        PGRES_BAD_RESPONSE,                     /* an unexpected response was recv'd from the*/
        PGRES_NONFATAL_ERROR,           /* notice or warning message */
        PGRES_FATAL_ERROR                       /* query failed */
} ExecStatusType;

typedef enum
{
        PQTRANS_IDLE,                           /* connection idle */
        PQTRANS_ACTIVE,                         /* command in progress */
        PQTRANS_INTRANS,                        /* idle, within transaction block */
        PQTRANS_INERROR,                        /* idle, within failed transaction */
        PQTRANS_UNKNOWN                         /* cannot determine status */
} PGTransactionStatusType;
typedef struct pgNotify
{
        char       *relname;            /* notification condition name */
        int                     be_pid;                 /* process ID of notifying server process */
        char       *extra;                      /* notification parameter */
} PGnotify;
typedef struct pg_conn PGconn;
typedef struct pg_result PGresult;
typedef struct pg_cancel PGcancel;
typedef char pqbool;

extern PGconn *PQconnectStart(const char *conninfo);
extern PGconn *PQconnectStartParams(const char **keywords,
                                         const char **values, int expand_dbname);
extern PostgresPollingStatusType PQconnectPoll(PGconn *conn);
extern void PQfinish(PGconn *conn);
extern ConnStatusType PQstatus(const PGconn *conn);
extern PGTransactionStatusType PQtransactionStatus(const PGconn *conn);
extern const char *PQparameterStatus(const PGconn *conn,
                                  const char *paramName);
extern int      PQprotocolVersion(const PGconn *conn);
extern int      PQserverVersion(const PGconn *conn);
extern int		PQflush(PGconn *conn);
extern char *PQerrorMessage(const PGconn *conn);
extern int      PQsendQuery(PGconn *conn, const char *query);
extern int      PQisBusy(PGconn *conn);
extern int      PQconsumeInput(PGconn *conn);
extern int      PQsocket(const PGconn *conn);
extern void PQclear(PGresult *res);
extern int      PQntuples(const PGresult *res);
extern int      PQnfields(const PGresult *res);
extern char *PQgetvalue(const PGresult *res, int tup_num, int field_num);
extern PGresult *PQgetResult(PGconn *conn);
extern PGnotify *PQnotifies(PGconn *conn);
extern void PQfreemem(void *ptr);
]]

local lib = ffi.load("pq")

local queue = {}
function queue.new()
	local q = {first = 0, last = -1}
	setmetatable(q, {__index = queue})
	return q
end
function queue:enqueue(value)
	local last = self.last + 1
	self.last = last
	self[last] = value
end
function queue:dequeue()
	local first = self.first
	if first > self.last then error("empty queue") end
	local value = self[first]
	self[first] = nil
	self.first = first + 1
	return value
end
function queue:has_entries()
	if self.first > self.last then return false end
	return true
end

local result = {}
function result:numcols()
	return lib.PQnfields(self)
end
function result:numrows()
	return lib.PQntuples(self)
end
function result:get(row, col)
	return lib.PQgetvalue(self, row, col)
end
ffi.metatype('PGresult', {__index = result})

local conn = {}
function conn:get_result()
	local res = lib.PQgetResult(self._c)
	if res == nil then
		return nil
	else
		return ffi.gc(res, lib.PQclear)
	end
end
function conn:consume_input()
	return lib.PQconsumeInput(self._c)
end
function conn:is_busy()
	return lib.PQisBusy(self._c)
end
function conn:listen(note, cb)
	self:query("LISTEN " .. note, function()
		self:wait_read(function()
			assert(self:consume_input() == 1)
			local noti = lib.PQnotifies(self._c)
			if noti ~= nil then
				lib.PQfreemem(noti)
				self:query("UNLISTEN " .. note, cb)
			else
				return 'again'
			end
		end)
	end)
end
function conn:after_queue(cb)
	if self.query_running then
		self._q:enqueue({ cb=cb })
	else
		cb()
	end
end
function conn:query(sql, cb)
	if self.query_running then
		self._q:enqueue({ sql=sql, cb=cb })
	else
		self.query_running = true
		assert(self:send_query(sql) == 1)
		self:wait_read(function()
			assert(self:consume_input() == 1)
			if self:is_busy() == 1 then
				return 'again'
			else
				local res = self:get_result()
				local gotagain = true
				while res ~= nil do
					if gotagain and cb(res) ~= 'again' then gotagain = false end
					res = self:get_result()
				end
				if self._q:has_entries() then
					local ent = self._q:dequeue()
					self.query_running = nil
					if ent.sql then
						self:query(ent.sql, ent.cb)
					else
						ent.cb()
					end
				else
					self.query_running = nil
				end
			end
		end)
	end
end
function conn:send_query(sql)
	local ret = lib.PQsendQuery(self._c, sql)
	self:wait_write(function()
		if lib.PQflush(self._c) == 1 then
			return 'again'
		end
	end)
	return ret
end

function connect(server, conninfo, cb)
	local w = { _q = queue.new() }
	w._c = ffi.gc(lib.PQconnectStart(conninfo), lib.PQfinish)
	w.notimeout = true
	if lib.PQstatus(w._c) == lib.CONNECTION_BAD then
		return nil
	end
	setmetatable(w, { __index = function(self, idx)
		if rawget(self, idx) then
			return rawget(self,idx)
		else
			return conn[idx]
		end
	end})
	w.fd = lib.PQsocket(w._c)
	w = server:wrap(w)
	w._conn_cb = function()
		local pr = lib.PQconnectPoll(w._c)
		if pr == lib.PGRES_POLLING_WRITING then
			w:wait_write(w._conn_cb)
		elseif pr == lib.PGRES_POLLING_READING then
			w:wait_read(w._conn_cb)
		else
			cb(server, w)
		end
	end
	w:wait_write(w._conn_cb)
	return w
end

return postgres
