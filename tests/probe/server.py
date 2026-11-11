#!/usr/bin/env python3
"""The probe's web server (tests/probe/README.md): the pages in pages/, plus
responses delayed on purpose, for timing a browser's loading UI.

    server.py <port>

    GET /slow?ms=N     a small page, sent after N ms
    GET /slow-links    a coloured page of links to /slow, from 200 ms to 3 s

It listens on 127.0.0.1 only. Pages served from localhost that link to
127.0.0.1 (or the reverse) are cross-origin, which esc.html's iframe cases use.
"""

import http.server
import os
import sys
import time
import urllib.parse

PAGES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pages")
DELAYS = [200, 400, 600, 800, 1000, 1500, 3000]


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=PAGES, **kwargs)

    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        if url.path == "/slow":
            query = urllib.parse.parse_qs(url.query)
            try:
                ms = max(0, min(30000, int(query.get("ms", ["0"])[0])))
            except ValueError:
                ms = 0
            time.sleep(ms / 1000)
            self.send_page(f"<title>slow {ms}</title><body style=\"font:30px -apple-system;margin:40px\">took {ms} ms")
        elif url.path == "/slow-links":
            # A fresh query each time, so nothing comes from the cache.
            stamp = time.time()
            links = "".join(f'<a href="/slow?ms={ms}&r={stamp}">{ms} ms</a>' for ms in DELAYS)
            self.send_page(
                "<title>slow links</title><style>body{margin:0;background:#7ab8f0;font:28px -apple-system}"
                "a{display:block;margin:40px 200px;background:#fd6;width:max-content;padding:6px;color:#000}"
                "</style>" + links
            )
        else:
            super().do_GET()

    def send_page(self, body):
        data = ("<!doctype html>" + body).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    if len(sys.argv) != 2 or not sys.argv[1].isdigit():
        sys.exit("usage: server.py <port>")
    http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
