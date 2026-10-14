#!/bin/sh
#
# Put traffic through a stream server and ask the display what it counted.
#
# This is the check that looks at what the two modules are for, and it is
# the one thing t/ cannot do: the counting happens in the stream subsystem,
# the answering in an http server, and the two only meet in shared memory.
# A pair whose idea of that memory differs builds, starts, logs nothing and
# answers nonsense -- so the numbers are the oracle, not the status code.
#
# usage: ci/counters.sh <nginx binary>
#
# Set COUNTERS_LOAD_MODULES to the two .so paths, space separated, to test a
# loadable build; STS_PORT and STS_HTTP_PORT move the listeners.
#
# Needs curl(1) and a Perl: one for the TCP server that is proxied to, one
# for the client, so that the bytes in each direction are a number this
# script wrote down rather than whatever nc(1) happens to send.

set -eu

NGINX=${1:?path to the nginx binary missing}
SRC=$(cd "$(dirname "$0")/.." && pwd)
WORK=${CI_WORK:-$SRC/ci-work}/counters
SPORT=${STS_PORT:-18820}
HPORT=${STS_HTTP_PORT:-18821}
BPORT=${STS_BACK_PORT:-18822}

command -v curl > /dev/null || { echo "curl(1) is needed" >&2; exit 2; }
command -v perl > /dev/null || { echo "perl(1) is needed" >&2; exit 2; }

rm -rf "$WORK"
mkdir -p "$WORK/conf" "$WORK/logs" "$WORK/tmp"

fail=0
note() {
	echo "  $1" >&2
	fail=1
}

# ------------------------------------------------------- the thing proxied to
#
# Twelve bytes per connection, so inBytes and outBytes are numbers this
# script can predict rather than merely find non-zero.

cat > "$WORK/back.pl" <<'PERL'
use strict; use warnings; use IO::Socket::INET;
my $s = IO::Socket::INET->new(LocalAddr => '127.0.0.1', LocalPort => $ARGV[0],
	Listen => 16, ReuseAddr => 1, Proto => 'tcp') or die $!;
$| = 1; print "ready\n";
while (my $c = $s->accept) {
	my $buf; sysread($c, $buf, 64);
	syswrite($c, 'ok' x 6);
	close $c;
}
PERL

perl "$WORK/back.pl" "$BPORT" > "$WORK/back.log" 2>&1 &
back=$!
trap 'kill $back 2>/dev/null || true; [ -f "$WORK/logs/nginx.pid" ] && kill -QUIT "$(cat "$WORK/logs/nginx.pid")" 2>/dev/null || true' EXIT INT TERM

i=0
while [ $i -lt 50 ]; do
	grep -q ready "$WORK/back.log" 2>/dev/null && break
	i=$((i + 1)); sleep 0.1 2>/dev/null || sleep 1
done

# --------------------------------------------------------------- the nginx

ngx_user=
if [ "$(id -u)" = 0 ]; then
	ngx_user="user root $(id -gn);"
fi

ngx_load=
for so in ${COUNTERS_LOAD_MODULES:-}; do
	ngx_load="$ngx_load
load_module $so;"
done

cat > "$WORK/conf/nginx.conf" <<CONF
$ngx_load
$ngx_user
daemon on;
master_process on;
worker_processes 1;
pid $WORK/logs/nginx.pid;
error_log $WORK/logs/error.log info;
events { worker_connections 64; }
stream {
    server_traffic_status_zone;

    upstream back {
        server 127.0.0.1:$BPORT;
    }

    server {
        listen 127.0.0.1:$SPORT;
        server_traffic_status on;
        proxy_pass back;
    }
}
http {
    access_log off;
    client_body_temp_path $WORK/tmp/cb;
    stream_server_traffic_status_zone;

    server {
        listen 127.0.0.1:$HPORT;

        location /sts {
            stream_server_traffic_status_display;
            stream_server_traffic_status_display_format json;
        }
    }
}
CONF

"$NGINX" -t -c "$WORK/conf/nginx.conf" -p "$WORK" > "$WORK/t.log" 2>&1 ||
	{ cat "$WORK/t.log"; exit 1; }
"$NGINX" -c "$WORK/conf/nginx.conf" -p "$WORK"
sleep 1

echo "--- the configuration both modules need is accepted ---"
echo "  server_traffic_status_zone in stream, its counterpart in http"

# ---------------------------------------------------------------- the cases

cat > "$WORK/client.pl" <<'PERL'
use strict; use warnings; use IO::Socket::INET;
# Six bytes out, twelve back, four times over.  Each connection is read to
# the end before it is closed, so the session is over -- and therefore
# counted -- by the time the display is asked.
for (1 .. 4) {
	my $c = IO::Socket::INET->new(PeerAddr => '127.0.0.1',
		PeerPort => $ARGV[0], Proto => 'tcp', Timeout => 5)
		or die "connect: $!";
	syswrite($c, "hello\n") == 6 or die "write: $!";
	my ($buf, $got) = ('', 0);
	while ($got < 12) {
		my $n = sysread($c, $buf, 64, $got);
		last if !defined $n || $n == 0;
		$got += $n;
	}
	die "read $got bytes, wanted 12\n" if $got != 12;
	close $c;
}
print "done\n";
PERL

echo "--- four connections through the stream server ---"
perl "$WORK/client.pl" "$SPORT" || { note "the connections did not go through"; }
sleep 1
echo "  four times six bytes out, twelve back"

js=$(curl -s --max-time 10 "http://127.0.0.1:$HPORT/sts" || true)
printf '%s' "$js" > "$WORK/sts.json"

zone="TCP:$SPORT:127.0.0.1"

echo "--- the zone is in the answer, named after the listener ---"
if printf '%s' "$js" | grep -q "\"$zone\""; then
	echo "  $zone"
else
	note "no zone \"$zone\" in the answer"
	head -c 300 "$WORK/sts.json" >&2
fi

echo "--- the connections were counted ---"
got=$(printf '%s' "$js" |
	sed -n "s/.*\"$zone\":{[^}]*\"connectCounter\":\([0-9]*\).*/\1/p")
if [ "${got:-0}" -ge 4 ]; then
	echo "  connectCounter=$got"
else
	note "connectCounter is \"$got\", expected at least 4"
fi

echo "--- and the bytes in both directions ---"
inb=$(printf '%s' "$js" | sed -n "s/.*\"$zone\":{[^}]*\"inBytes\":\([0-9]*\).*/\1/p")
outb=$(printf '%s' "$js" | sed -n "s/.*\"$zone\":{[^}]*\"outBytes\":\([0-9]*\).*/\1/p")
if [ "${inb:-0}" -ge 24 ] && [ "${outb:-0}" -ge 48 ]; then
	echo "  inBytes=$inb, outBytes=$outb (6 and 12 per connection)"
else
	note "inBytes=$inb, outBytes=$outb, expected at least 24 and 48"
fi

echo "--- the Prometheus exposition carries the same numbers ---"
pr=$(curl -s --max-time 10 "http://127.0.0.1:$HPORT/sts/format/prometheus" || true)
printf '%s' "$pr" > "$WORK/sts.prom"
# Not "is the metric there" but "does it say four and twenty-four and
# forty-eight": the exposition is a second rendering of the same counters,
# and the point of asking it is that the two renderings agree.
for want in \
	'connects_total\{listen="[^"]*",port="'"$SPORT"'",protocol="TCP",code="total"\} 4$' \
	'bytes_total\{listen="[^"]*",port="'"$SPORT"'",protocol="TCP",direction="in"\} 24$' \
	'bytes_total\{listen="[^"]*",port="'"$SPORT"'",protocol="TCP",direction="out"\} 48$'
do
	if printf '%s' "$pr" | grep -Eq "nginx_sts_server_$want"; then
		echo "  nginx_sts_server_$(printf '%s' "$want" | sed 's/\\{.*code="/ /;s/\\{.*direction="/ /;s/"\\} / /;s/\$//')"
	else
		note "the exposition does not say nginx_sts_server_$want"
		printf '%s' "$pr" | grep -E "port=\"$SPORT\"" >&2 || true
	fi
done

echo "--- the html dashboard is served ---"
ht=$(curl -s --max-time 10 "http://127.0.0.1:$HPORT/sts/format/html" || true)
printf '%s' "$ht" | grep -qi '<html' && echo "  it is html" ||
	note "the html format did not answer html"

echo "--- the worker is still there ---"
alive=$(curl -s --max-time 5 "http://127.0.0.1:$HPORT/sts/format/json" || true)
printf '%s' "$alive" | grep -q 'nginxVersion' && echo "  it answers" ||
	note "the display stopped answering"

echo "--- nothing in the error log that should not be there ---"
if grep -E '\[alert\]|\[emerg\]|exited on signal' "$WORK/logs/error.log"; then
	note "the log carries an alert, an emerg or a worker that died"
else
	echo "  no alert, no emerg, no signal"
fi

if [ "$fail" -ne 0 ]; then
	echo >&2
	echo "--- the error log, last 20 lines ---" >&2
	tail -20 "$WORK/logs/error.log" >&2 2>/dev/null || true
fi

exit $fail
