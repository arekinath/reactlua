#include <unbound.h>
#include <sys/types.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <unistd.h>
#include <netdb.h>
#include <stddef.h>
#include <stdint.h>
#include <fcntl.h>
#include <poll.h>

/****************/
/* unbound shim */
/****************/

static struct ub_result *last_result = NULL;
static int last_err;

static void callback(void *data, int err, struct ub_result *result)
{
	last_err = err;
	if (err != 0)
		return;
	if (result->havedata) {
		if (last_result) ub_resolve_free(last_result);
		last_result = result;
	}
}

struct ub_result *ubshim_get_result(void)
{
	struct ub_result *r = last_result;
	last_result = NULL;
	return r;
}

int ubshim_get_err(void)
{
	return last_err;
}

int ubshim_resolve_async(struct ub_ctx* ctx, const char* name, int rrtype, int rrclass, int* async_id)
{
	return ub_resolve_async(ctx, name, rrtype, rrclass, NULL, callback, async_id);
}

/****************/
/* socket shim  */
/****************/

struct map { const char *name; uint32_t value; };
static struct map mappings[] = {
	{ "SOCK_STREAM", SOCK_STREAM },
	{ "SOCK_DGRAM", SOCK_DGRAM },
	{ "SOCK_RAW", SOCK_RAW },
	{ "SOCK_RDM", SOCK_RDM },
	{ "SOCK_SEQPACKET", SOCK_SEQPACKET },
	{ "AF_UNSPEC", AF_UNSPEC },
	{ "AF_LOCAL", AF_LOCAL },
	{ "AF_UNIX", AF_UNIX },
	{ "AF_INET", AF_INET },
	{ "AF_INET6", AF_INET6 },
	{ "SO_ACCEPTCONN", SO_ACCEPTCONN },
	{ "SO_REUSEADDR", SO_REUSEADDR },
	{ "SO_KEEPALIVE", SO_KEEPALIVE },
	{ "SO_DONTROUTE", SO_DONTROUTE },
	{ "SO_BROADCAST", SO_BROADCAST },
#ifdef SO_USELOOPBACK
	{ "SO_USELOOPBACK", SO_USELOOPBACK },
#endif
	{ "SO_LINGER", SO_LINGER },
	{ "SO_OOBINLINE", SO_OOBINLINE },
#ifdef SO_REUSEPORT
	{ "SO_REUSEPORT", SO_REUSEPORT },
#endif
#ifdef SO_JUMBO
	{ "SO_JUMBO", SO_JUMBO },
#endif
	{ "SO_TIMESTAMP", SO_TIMESTAMP },
#ifdef SO_BINDANY
	{ "SO_BINDANY", SO_BINDANY },
#endif
	{ "NETDB_SUCCESS", NETDB_SUCCESS },
	{ "HOST_NOT_FOUND", HOST_NOT_FOUND },
	{ "TRY_AGAIN", TRY_AGAIN },
	{ "NO_RECOVERY", NO_RECOVERY },
	{ "NO_DATA", NO_DATA },
	{ "NO_ADDRESS", NO_ADDRESS },
	{ "NI_NUMERICHOST", NI_NUMERICHOST },
	{ "NI_NUMERICSERV", NI_NUMERICSERV },
	{ "NI_NOFQDN", NI_NOFQDN },
	{ "NI_NAMEREQD", NI_NAMEREQD },
	{ "NI_DGRAM", NI_DGRAM },
	{ "AI_PASSIVE", AI_PASSIVE },
	{ "AI_CANONNAME", AI_CANONNAME },
	{ "AI_NUMERICHOST", AI_NUMERICHOST },
#ifdef AI_EXT
	{ "AI_EXT", AI_EXT },
#endif
	{ "AI_NUMERICSERV", AI_NUMERICSERV },
	{ "IPPROTO_IP", IPPROTO_IP },
	{ "IPPROTO_HOPOPTS", IPPROTO_HOPOPTS },
	{ "IPPROTO_ICMP", IPPROTO_ICMP },
	{ "IPPROTO_IGMP", IPPROTO_IGMP },
	{ "IPPROTO_IPIP", IPPROTO_IPIP },
	{ "IPPROTO_TCP", IPPROTO_TCP },
	{ "IPPROTO_EGP", IPPROTO_EGP },
	{ "IPPROTO_PUP", IPPROTO_PUP },
	{ "IPPROTO_UDP", IPPROTO_UDP },
	{ "POLLIN", POLLIN },
	{ "POLLPRI", POLLPRI },
	{ "POLLOUT", POLLOUT },
	{ "POLLERR", POLLERR },
	{ "POLLHUP", POLLHUP },
	{ "POLLNVAL", POLLNVAL },
	{ "POLLRDNORM", POLLRDNORM },
#ifdef POLLNORM
	{ "POLLNORM", POLLNORM },
#endif
	{ "POLLWRNORM", POLLWRNORM },
	{ "POLLRDBAND", POLLRDBAND },
	{ "POLLWRBAND", POLLWRBAND },
#ifdef O_RDONLY
	{ "O_RDONLY", O_RDONLY },
#endif
#ifdef O_WRONLY
	{ "O_WRONLY", O_WRONLY },
#endif
#ifdef O_RDWR
	{ "O_RDWR", O_RDWR },
#endif
#ifdef O_CREAT
	{ "O_CREAT", O_CREAT },
#endif
#ifdef O_EXCL
	{ "O_EXCL", O_EXCL },
#endif
#ifdef O_NOCTTY
	{ "O_NOCTTY", O_NOCTTY },
#endif
#ifdef O_TRUNC
	{ "O_TRUNC", O_TRUNC },
#endif
#ifdef O_APPEND
	{ "O_APPEND", O_APPEND },
#endif
#ifdef O_NONBLOCK
	{ "O_NONBLOCK", O_NONBLOCK },
#endif
#ifdef O_NDELAY
	{ "O_NDELAY", O_NDELAY },
#endif
#ifdef O_SYNC
	{ "O_SYNC", O_SYNC },
#endif
#ifdef O_FSYNC
	{ "O_FSYNC", O_FSYNC },
#endif
#ifdef O_ASYNC
	{ "O_ASYNC", O_ASYNC },
#endif
	{ 0, 0 }
};

uint32_t shim_get_symbol(const char *name)
{
	struct map *m = mappings;
	while (m->name && strcmp(m->name, name) != 0)
		++m;
	if (m->name) return m->value;
	return 0;
}

uint8_t shim_canon_first(void)
{
	struct addrinfo *ai = (struct addrinfo*)(0);
	if ((char*)&ai->ai_canonname < (char*)&ai->ai_addr) return 1;
	return 0;
}