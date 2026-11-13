"""cb-wake-proxy: inoltra i byte, segna l'uso e aspetta il browser che si avvia.

Avvia il proxy come farebbe systemd (socket in ascolto sul fd 3, LISTEN_FDS=1)
davanti a un server echo locale.
"""

import os
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest

PROXY = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "bin", "cb-wake-proxy")


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def echo_server(port: int, ready: threading.Event, delay: float = 0.0) -> socket.socket:
    time.sleep(delay)
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", port))
    srv.listen()

    def serve():
        while True:
            try:
                conn, _ = srv.accept()
            except OSError:
                return
            threading.Thread(target=lambda c=conn: [c.sendall(d) for d in iter(lambda: c.recv(4096), b"")], daemon=True).start()

    threading.Thread(target=serve, daemon=True).start()
    ready.set()
    return srv


class WakeProxyTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.stamp = os.path.join(self.tmp.name, "cb-activity")
        self.backend = free_port()
        self.listener = socket.socket()
        self.listener.bind(("127.0.0.1", 0))
        self.listener.listen()
        self.port = self.listener.getsockname()[1]
        fd = self.listener.fileno()
        self.proc = subprocess.Popen(
            [sys.executable, PROXY, str(self.backend), self.stamp],
            env={**os.environ, "LISTEN_FDS": "1"},
            pass_fds=(fd,),
            preexec_fn=lambda: os.dup2(fd, 3),
            stderr=subprocess.PIPE,
        )
        self.servers = []

    def tearDown(self):
        self.proc.kill()
        self.proc.wait()
        self.proc.stderr.close()
        self.listener.close()
        for s in self.servers:
            s.close()
        self.tmp.cleanup()

    def roundtrip(self, payload: bytes) -> bytes:
        with socket.create_connection(("127.0.0.1", self.port), timeout=10) as c:
            c.sendall(payload)
            got = b""
            while len(got) < len(payload):
                chunk = c.recv(65536)
                if not chunk:
                    break
                got += chunk
            return got

    def test_forwards_and_marks_use(self):
        ready = threading.Event()
        self.servers.append(echo_server(self.backend, ready))
        ready.wait()
        payload = os.urandom(200_000)
        self.assertEqual(self.roundtrip(payload), payload)
        self.assertTrue(os.path.exists(self.stamp), "il proxy deve creare il file di attività")

    def test_waits_for_backend_to_start(self):
        ready = threading.Event()
        threading.Thread(target=lambda: self.servers.append(echo_server(self.backend, ready, delay=1.5)), daemon=True).start()
        self.assertEqual(self.roundtrip(b"hello"), b"hello")
        self.assertTrue(ready.is_set())

    def test_refuses_without_systemd_socket(self):
        r = subprocess.run([sys.executable, PROXY, "1", self.stamp], env={k: v for k, v in os.environ.items() if k != "LISTEN_FDS"},
                           capture_output=True, text=True, timeout=10)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("LISTEN_FDS", r.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=1)
