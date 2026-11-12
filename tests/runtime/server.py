#!/usr/bin/env python3
"""The local web server for the runtime suite: test pages, test appcasts and
their updates, plus a download that stays in progress until it's told to finish.

    server.py <directory> <port>

    GET /slow-download         sends a chunk at a time until /slow-download/finish
    GET /slow-download/finish  lets every slow download end
    GET /download/clair.txt    a small text file, as a download

A .crx file is served as an extension, which Clair offers to install when it
runs with --extension-mime-request-handling=always-prompt-for-install.
"""

import http.server
import sys
import threading
import time

finished = threading.Event()


class Handler(http.server.SimpleHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".crx": "application/x-chrome-extension",
    }

    def do_GET(self):
        if self.path == "/slow-download/finish":
            finished.set()
            self.respond_empty()
        elif self.path == "/slow-download":
            self.send_slow_download()
        elif self.path == "/download/clair.txt":
            self.send_text_download()
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
