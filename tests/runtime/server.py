#!/usr/bin/env python3
"""The local web server for the runtime suite: test pages, test appcasts and
their updates, plus a download that stays in progress until it's told to finish.

    server.py <directory> <port>

    GET /slow-download         sends a chunk at a time until /slow-download/finish
    GET /slow-download/finish  lets every slow download end
    GET /download/clair.txt    a small text file, as a download
    GET /slow-page?seconds=N   a page whose body arrives over N seconds (1 to 30)
    GET /slow-frame            a small page sent after 300 ms, for busy iframes
"""

import http.server
import sys
import urllib.parse
import threading
import time

finished = threading.Event()


class Handler(http.server.SimpleHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        if self.path == "/slow-download/finish":
            finished.set()
            self.respond_empty()
        elif self.path == "/slow-download":
            self.send_slow_download()
        elif self.path == "/download/clair.txt":
            self.send_text_download()
        elif self.path.startswith("/slow-page"):
            self.send_slow_page()
        elif self.path.startswith("/slow-frame"):
            time.sleep(0.3)
            self.send_html(b"<!doctype html><title>Frame</title><p>Frame</p>")
        else:
            super().do_GET()

    def respond_empty(self):
        self.send_response(204)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def send_text_download(self):
        body = b"Downloaded by Clair's runtime suite.\n"
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Disposition", 'attachment; filename="clair.txt"')
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_html(self, body):
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_slow_page(self):
        query = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        try:
            seconds = min(max(int(query.get("seconds", ["5"])[0]), 1), 30)
        except ValueError:
            seconds = 5
        # Chunked, so the page commits at once and keeps loading.
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Transfer-Encoding", "chunked")
        self.end_headers()

        def chunk(data):
            self.wfile.write(b"%x\r\n%s\r\n" % (len(data), data))
            self.wfile.flush()

        chunk(b"<!doctype html><title>Clair slow page</title><p>Loading slowly</p>")
        for _ in range(seconds * 4):
            time.sleep(0.25)
            chunk(b"<p>" + b"." * 512 + b"</p>")
        chunk(b"<p id=done>Done</p>")
        self.wfile.write(b"0\r\n\r\n")

    def send_slow_download(self):
        finished.clear()
        chunk = b"x" * 1024
        chunks = 3600
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Disposition", 'attachment; filename="slow.bin"')
        self.send_header("Content-Length", str(len(chunk) * chunks))
        self.end_headers()
        for sent in range(chunks):
            if finished.is_set():
                # Whatever is left arrives at once, and the download completes.
                self.wfile.write(chunk * (chunks - sent))
                return
            self.wfile.write(chunk)
            self.wfile.flush()
            time.sleep(1)


def main():
    directory, port = sys.argv[1], int(sys.argv[2])

    def handler(*args, **kwargs):
        return Handler(*args, directory=directory, **kwargs)

    http.server.ThreadingHTTPServer(("127.0.0.1", port), handler).serve_forever()


if __name__ == "__main__":
    main()
