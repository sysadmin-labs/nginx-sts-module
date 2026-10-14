# Changelog

Newest first.  Dates are release dates.

## v0.2.0 (2026-10-14)

### Changed

- **The two modules are one repository and one build.**  Upstream keeps
  them apart -- `vozlt/nginx-module-sts` for the display,
  `vozlt/nginx-module-stream-sts` for the counting -- and whoever builds
  nginx has to add both, in the right order, in matching versions.  Here
  one `config` registers both, so `--add-module` once produces the pair,
  and the pair cannot be mismatched because there is only one of it.

  The sources are unchanged.  What was taken is the last commit of each
  side, `3c10d42` of 2022-09-26 and `a60cd2f` of 2022-09-16: four years
  past the newest release tag either of them has, which is `v0.1.1` from
  2018.

### Added

- **`src/ngx_sts_layout_check.c`: the comment is a compiler check now.**
  Both modules touch the same shared memory and each declares its own idea
  of what is in it.  One of the two carries the line *"must be the same as
  ngx_stream_server_traffic_status_ctx_t"* and that was the whole
  guarantee.  They agree today -- every field matches and both arrays are
  64 and 32 long, which is why the pin of 2022 was safe to take -- and
  nothing would have noticed if that had stopped being true: a pair that
  disagrees builds, starts, logs nothing, and the display reads whatever
  the fields happen to line up with.  The file asserts the sizes of the
  node and of every structure it is built from, the offsets of the
  counters inside it, and the size of the configuration the zone is made
  from.  It compiles to nothing; a mismatch is a build error.

- `ci/counters.sh` and a workflow of its own, in both build shapes.  It
  puts four connections through a stream server, six bytes each way in and
  twelve back, and checks what the display made of them: the zone named
  after the listener, `connectCounter`, `inBytes`, `outBytes`, the same
  three numbers again in the Prometheus exposition, and the HTML
  dashboard.  The numbers are the oracle, not the status code -- a
  mismatched pair answers 200.

- `t/`, for what the display answers to a given configuration, including
  the trap two upstream issues asked about and neither README mentions:
  the zone has to be declared in the stream block **and** in the http one,
  and the answer when it is not says nothing about which half is missing.
  The two refusals are at least different -- `501` when the http block
  declares no zone at all, `503` when it declares one that the stream side
  never created -- and that difference is now pinned down, together with
  the reason the second one is easy to walk into: the name is written
  `shared:<name>:<size>` on the stream side and `shared:<name>` on the
  http side, because the http side reads everything after the colon as the
  name.  Also here: the JSON and Prometheus shapes, a format refused while
  the configuration is read, and the format taken from the request path.

- The reload gate asks the display, because a shared memory zone is
  exactly what a reload can lose: nginx keeps it only while the name and
  the size match the previous cycle, and a zone that went away makes this
  module answer 503 again.

- The scaffolding the other modules in this organization carry: a version
  and digest pin for every build input, the release matrix with both a
  static and a loadable build, the FreeBSD virtual machine, A/UBSan,
  valgrind, eight reloads in a row, CodeQL, shellcheck and actionlint.
  `ci/build.sh` passes `--with-stream`, without which the counting module
  has nowhere to go.

- A README that writes down what the issue threads had to answer: that
  both zone directives are needed and how each side spells the name, and
  that a connection is counted when it **ends** -- so a long-lived session
  contributes nothing until it closes, which is worth knowing before an
  alarm is built on it.
