/*
 * Copyright (c) 2026, Jochen Neumeister <joneum@FreeBSD.org>
 *
 * BSD 2-Clause, see LICENSE.
 *
 * The two modules in this repository write and read the same shared memory
 * and each carries its own declaration of what is in it.  Upstream kept
 * them in two repositories and held the two declarations level by hand,
 * with a comment in one of them saying "must be the same as" the other.
 * They are the same today -- both arrays are 64 and 32 long, every field
 * matches -- and nothing but this file would notice if that stopped being
 * true.  A pair that disagrees does not fail to build and does not log
 * anything; the display reads whatever the other module's fields happen to
 * line up with.
 *
 * So the comment is a compiler check now.  Nothing here is compiled into
 * code: a negative array size is a build error, which is the point.
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>
#include <ngx_stream.h>

#include "ngx_http_stream_server_traffic_status_node.h"
#include "ngx_stream_server_traffic_status_node.h"
#include "ngx_http_stream_server_traffic_status_module.h"
#include "ngx_stream_server_traffic_status_module.h"


#define ngx_sts_assert(name, cond)                                           \
    typedef char ngx_sts_check_##name[(cond) ? 1 : -1]

#define ngx_sts_same_size(name, a, b)                                        \
    ngx_sts_assert(name, sizeof(a) == sizeof(b))

#define ngx_sts_same_offset(name, field)                                     \
    ngx_sts_assert(name,                                                     \
        offsetof(ngx_stream_server_traffic_status_node_t, field)             \
        == offsetof(ngx_http_stream_server_traffic_status_node_t, field))


/* the pieces the node is built from */
ngx_sts_same_size(time,
    ngx_stream_server_traffic_status_node_time_t,
    ngx_http_stream_server_traffic_status_node_time_t);
ngx_sts_same_size(time_queue,
    ngx_stream_server_traffic_status_node_time_queue_t,
    ngx_http_stream_server_traffic_status_node_time_queue_t);
ngx_sts_same_size(histogram,
    ngx_stream_server_traffic_status_node_histogram_t,
    ngx_http_stream_server_traffic_status_node_histogram_t);
ngx_sts_same_size(histogram_bucket,
    ngx_stream_server_traffic_status_node_histogram_bucket_t,
    ngx_http_stream_server_traffic_status_node_histogram_bucket_t);
ngx_sts_same_size(upstream,
    ngx_stream_server_traffic_status_node_upstream_t,
    ngx_http_stream_server_traffic_status_node_upstream_t);

/* the node itself, and where the counters sit in it */
ngx_sts_same_size(node,
    ngx_stream_server_traffic_status_node_t,
    ngx_http_stream_server_traffic_status_node_t);

ngx_sts_same_offset(connect_counter, stat_connect_counter);
ngx_sts_same_offset(in_bytes, stat_in_bytes);
ngx_sts_same_offset(out_bytes, stat_out_bytes);
ngx_sts_same_offset(session_time, stat_session_time);
ngx_sts_same_offset(session_times, stat_session_times);
ngx_sts_same_offset(session_buckets, stat_session_buckets);
ngx_sts_same_offset(node_upstream, stat_upstream);
ngx_sts_same_offset(port, port);
ngx_sts_same_offset(protocol, protocol);
ngx_sts_same_offset(len, len);
ngx_sts_same_offset(data, data);

/* and the configuration the zone is created from */
ngx_sts_same_size(ctx,
    ngx_stream_server_traffic_status_ctx_t,
    ngx_http_stream_server_traffic_status_ctx_t);
