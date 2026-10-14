# nginx-sts-module

[![Build & Test][build-test-badge]][build-test-link]
[![Counters][counters-badge]][counters-link]
[![FreeBSD][freebsd-badge]][freebsd-link]
[![A/UBSan][sanitizers-badge]][sanitizers-link]
[![Valgrind][valgrind-badge]][valgrind-link]
[![Reload][reload-badge]][reload-link]
[![CodeQL][codeql-badge]][codeql-link]
[![Lint][lint-badge]][lint-link]

[build-test-badge]: https://github.com/sysadmin-labs/nginx-sts-module/actions/workflows/build-test.yml/badge.svg
[build-test-link]: https://github.com/sysadmin-labs/nginx-sts-module/actions/workflows/build-test.yml
[counters-badge]: https://github.com/sysadmin-labs/nginx-sts-module/actions/workflows/counters.yml/badge.svg
[counters-link]: https://github.com/sysadmin-labs/nginx-sts-module/actions/workflows/counters.yml
[freebsd-badge]: https://github.com/sysadmin-labs/nginx-sts-module/actions/workflows/freebsd.yml/badge.svg
[freebsd-link]: https://github.com/sysadmin-labs/nginx-sts-module/actions/workflows/freebsd.yml
[sanitizers-badge]: https://github.com/sysadmin-labs/nginx-sts-module/actions/workflows/sanitizers.yml/badge.svg
[sanitizers-link]: https://github.com/sysadmin-labs/nginx-sts-module/actions/workflows/sanitizers.yml
[valgrind-badge]: https://github.com/sysadmin-labs/nginx-sts-module/actions/workflows/valgrind.yml/badge.svg
[valgrind-link]: https://github.com/sysadmin-labs/nginx-sts-module/actions/workflows/valgrind.yml
[reload-badge]: https://github.com/sysadmin-labs/nginx-sts-module/actions/workflows/reload.yml/badge.svg
[reload-link]: https://github.com/sysadmin-labs/nginx-sts-module/actions/workflows/reload.yml
[codeql-badge]: https://github.com/sysadmin-labs/nginx-sts-module/actions/workflows/codeql.yml/badge.svg
[codeql-link]: https://github.com/sysadmin-labs/nginx-sts-module/actions/workflows/codeql.yml
[lint-badge]: https://github.com/sysadmin-labs/nginx-sts-module/actions/workflows/lint.yml/badge.svg
[lint-link]: https://github.com/sysadmin-labs/nginx-sts-module/actions/workflows/lint.yml

Count what goes through nginx's `stream` subsystem -- per server, per
upstream, per filter -- and serve the counters as JSON, as a Prometheus
exposition or as an HTML dashboard.  The stream side of what
[nginx-module-vts](https://github.com/vozlt/nginx-module-vts) does for HTTP.

## Two modules, one repository

Counting happens in the stream subsystem, answering in an http server, and
the two meet in a shared memory zone.  That is why there are two modules,
and both are built from here:

| module | where it lives | what it does |
|---|---|---|
| `ngx_stream_server_traffic_status_module` | `stream` | counts, and owns the zone |
| `ngx_http_stream_server_traffic_status_module` | `http` | answers the status requests out of it |

Upstream keeps them in two repositories that have to be added separately,
and each carries **its own declaration** of the layout of that shared
memory, held level by hand with a comment saying "must be the same as" the
other one.  A pair that disagrees builds, starts, logs nothing, and the
display reads whatever the fields happen to line up with.  Here they ship
together and `src/ngx_sts_layout_check.c` turns that comment into something
the compiler refuses to let through.

## Configuration

**Both zone directives are needed.**  The stream one creates the shared
memory, the http one names what to look for.  Leave the http one out and
the display answers `501`; name a zone that the stream side never created
and it answers `503`.  Neither answer says what is missing, and the code is
the only hint there is.  That question was asked twice upstream and
answered twice in issue threads, never in the documentation:

```nginx
stream {
    server_traffic_status_zone;

    upstream backend {
        server 10.0.0.1:3306;
    }

    server {
        listen 3306;
        server_traffic_status on;
        proxy_pass backend;
    }
}

http {
    stream_server_traffic_status_zone;

    server {
        listen 8080;

        location /sts {
            stream_server_traffic_status_display;
            stream_server_traffic_status_display_format json;
        }
    }
}
```

`/sts/format/json`, `/sts/format/prometheus` and `/sts/format/html` serve
the same data in the three shapes, whatever the configured default is.

**A zone of its own name is spelled differently on each side.**  The stream
directive takes the size, the http one does not and reads everything after
the colon as the name -- so writing the same thing in both places leaves
the two sides looking for different names, and the display back at `503`:

```nginx
stream { server_traffic_status_zone shared:sts:2m; }
http   { stream_server_traffic_status_zone shared:sts; }
```

As loadable objects it takes both lines.  The order does not matter -- the
display looks the zone up per request, by then both modules are there
whichever was loaded first -- but the stream module goes first anyway,
because that is the order the FreeBSD ports write and one order is easier
to read than two:

```nginx
load_module modules/ngx_stream_server_traffic_status_module.so;
load_module modules/ngx_http_stream_server_traffic_status_module.so;
```

The directives of each module are the upstream ones and unchanged;
upstream's READMEs document them in full.

## What the counters do and do not say

**A connection is counted when it ends.**  Bytes and times are taken where
the session is logged, so a long-lived connection -- a database proxy, a
message queue, anything that holds the socket open for hours -- contributes
nothing until it closes.  For short connections the numbers are live; for
long ones they lag by the length of the session.  Two upstream issues ask
about exactly this; it is how the module works, not a fault, and it is
worth knowing before building an alarm on it.

## Building

```sh
ci/build.sh 1.30.5 /tmp/nginx-test            # both modules into the binary
ci/build.sh 1.30.5 /tmp/nginx-test dynamic    # both as loadable objects
```

nginx needs `--with-stream`, which `ci/build.sh` passes: the counting module
is a stream module and has nowhere to go without the subsystem.

## Testing

```sh
ci/build.sh 1.30.5 /tmp/nginx-test
TEST_NGINX_BINARY=/tmp/nginx-test/sbin/nginx prove -r t/
ci/counters.sh /tmp/nginx-test/sbin/nginx
```

`t/` asks what the display answers for a given configuration, including
the two refusals and which one means what.  `ci/counters.sh` is the one that matters: it puts four connections
through a stream server, each answered with twelve known bytes, and checks
what the display made of them -- the numbers, not the status code, because
a mismatched pair answers 200 with nonsense.

## License

BSD 2-Clause.  Both modules are YoungJoo Kim's; what was added here is
under the same terms.  See [LICENSE](LICENSE).
