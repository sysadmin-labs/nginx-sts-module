# vi:ft=perl
#
# What the display answers, and what it refuses, for a given configuration.
#
# The stream block goes into --- main_config, which is where Test::Nginx
# puts directives that belong outside http.  That is as far as this suite
# reaches: it can create the zone and ask the display about it, but it
# cannot put traffic through a stream server, so every number here is zero.
# The counters are ci/counters.sh.
#
# TEST 1 and TEST 2 are the trap that upstream answered in two issue
# threads and wrote down nowhere: the zone has to be declared on both
# sides, and what comes back when it is not says nothing about which side
# is missing.  The two refusals are not the same refusal, though, and the
# difference is the only thing that tells the two mistakes apart:
#
#     501  the http block has no zone directive -- nothing to look for
#     503  it has one, but no zone of that name exists (TEST 8)
#
# TEST 3 is also the test that the two default zone names still agree --
# each module carries its own spelling of it in its own header, and nothing
# else would notice a rename on one side.
#
# TEST 7 and TEST 8 are the other half of the trap: a zone of one's own is
# named "shared:<name>:<size>" in the stream block and "shared:<name>" in
# the http one, because the http side takes everything after the colon as
# the name.  Write the size on both and the two names differ.

use Test::Nginx::Socket 'no_plan';

repeat_each(1);

run_tests();

__DATA__

=== TEST 1: with no zone anywhere the display answers 501
--- config
    location /sts {
        stream_server_traffic_status_display;
        stream_server_traffic_status_display_format json;
    }
--- request
GET /sts
--- error_code: 501



=== TEST 2: the stream zone alone is not enough, and the answer still says 501
--- main_config
stream {
    server_traffic_status_zone;
}
--- config
    location /sts {
        stream_server_traffic_status_display;
        stream_server_traffic_status_display_format json;
    }
--- request
GET /sts
--- error_code: 501



=== TEST 3: with the zone declared on both sides it answers, and the answer is JSON
--- main_config
stream {
    server_traffic_status_zone;
}
--- http_config
    stream_server_traffic_status_zone;
--- config
    location /sts {
        stream_server_traffic_status_display;
        stream_server_traffic_status_display_format json;
    }
--- request
GET /sts
--- error_code: 200
--- response_body_like eval
qr/"streamServerZones"/



=== TEST 4: and as a Prometheus exposition
--- main_config
stream {
    server_traffic_status_zone;
}
--- http_config
    stream_server_traffic_status_zone;
--- config
    location /sts {
        stream_server_traffic_status_display;
        stream_server_traffic_status_display_format prometheus;
    }
--- request
GET /sts
--- error_code: 200
--- response_body_like eval
qr/nginx_sts_info/



=== TEST 5: a format this does not know is refused while the configuration is read
--- main_config
stream {
    server_traffic_status_zone;
}
--- http_config
    stream_server_traffic_status_zone;
--- config
    location /sts {
        stream_server_traffic_status_display;
        stream_server_traffic_status_display_format yaml;
    }
--- must_die
--- error_log
invalid value "yaml"



=== TEST 6: the format can be asked for in the request
--- main_config
stream {
    server_traffic_status_zone;
}
--- http_config
    stream_server_traffic_status_zone;
--- config
    location /sts {
        stream_server_traffic_status_display;
    }
--- request
GET /sts/format/json
--- error_code: 200
--- response_body_like eval
qr/"nginxVersion"/



=== TEST 7: a zone of its own name -- the size belongs to the stream side only
--- main_config
stream {
    server_traffic_status_zone shared:sts_named:2m;
}
--- http_config
    stream_server_traffic_status_zone shared:sts_named;
--- config
    location /sts {
        stream_server_traffic_status_display;
        stream_server_traffic_status_display_format json;
    }
--- request
GET /sts
--- error_code: 200
--- response_body_like eval
qr/"streamServerZones"/



=== TEST 8: the same name on both sides, written the same way, does not match -- 503
--- main_config
stream {
    server_traffic_status_zone shared:sts_named:2m;
}
--- http_config
    stream_server_traffic_status_zone shared:sts_named:2m;
--- config
    location /sts {
        stream_server_traffic_status_display;
        stream_server_traffic_status_display_format json;
    }
--- request
GET /sts
--- error_code: 503
