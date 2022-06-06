// Source: https://curl.se/libcurl/c/multi-app.html

const std = @import("std");

const curl = @cImport(@cInclude("curl/curl.h"));

const HANDLECOUNT = 2;

pub fn main() void {
    var handles: [HANDLECOUNT]*curl.CURL = undefined;
    var multi_handle: *curl.CURLM = undefined;

    var i: c_int = undefined;

    var msg: *allowzero curl.CURLMsg = undefined;
    var msgs_left: c_int = undefined;

    i = 0;
    while (i < HANDLECOUNT) : (i += 1)
        handles[@intCast(usize, i)] = curl.curl_easy_init().?;

    i = 0;
    while (i < HANDLECOUNT) : (i += 1)
        _ = curl.curl_easy_setopt(handles[@intCast(usize, i)], curl.CURLOPT_URL, "https://example.com");

    multi_handle = curl.curl_multi_init().?;

    i = 0;
    while (i < HANDLECOUNT) : (i += 1)
        _ = curl.curl_multi_add_handle(multi_handle, handles[@intCast(usize, i)]);

    var polls: usize = 0;
    var transfers_running: c_int = undefined;
    var mc: curl.CURLMcode = curl.curl_multi_perform(multi_handle, &transfers_running);
    while (transfers_running > 0) {
        mc = curl.curl_multi_perform(multi_handle, &transfers_running);

        if (transfers_running > 0) {
            mc = curl.curl_multi_poll(multi_handle, null, 0, 1000, null);
        }

        polls += 1;
        if (mc != 0)
            break;
    }
    std.log.debug("polls: {d}", .{polls});

    while (true) {
        msg = curl.curl_multi_info_read(multi_handle, &msgs_left);
        if (@ptrToInt(msg) == 0) break;
        if (msg.*.msg == curl.CURLMSG_DONE) {
            var idx: c_int = undefined;

            idx = 0;
            while (idx < HANDLECOUNT) : (idx += 1) {
                var found: c_int = @boolToInt(msg.*.easy_handle == handles[@intCast(usize, idx)]);
                if (found != 0)
                    break;
            }

            switch (@intCast(usize, idx)) {
                0 => std.debug.print("HTTP transfer #0 completed with status {d}\n", .{msg.*.data.result}),
                1 => std.debug.print("HTTP transfer #1 completed with status {d}\n", .{msg.*.data.result}),
                else => unreachable,
            }
        }
    }

    i = 0;
    while (i < HANDLECOUNT) : (i += 1) {
        _ = curl.curl_multi_remove_handle(multi_handle, handles[@intCast(usize, i)]);
        curl.curl_easy_cleanup(handles[@intCast(usize, i)]);
    }

    _ = curl.curl_multi_cleanup(multi_handle);
}
