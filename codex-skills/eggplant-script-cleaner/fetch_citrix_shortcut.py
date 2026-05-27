#!/usr/bin/env python3
"""Launch Edge against Citrix StoreFront and print a shortcut URL.

This script uses the Chrome DevTools Protocol over a local WebSocket so it
does not require Selenium, Playwright, or third-party Python packages.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import shutil
import socket
import ssl
import struct
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any


DEFAULT_EDGE_PATH = Path(r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe")
DEFAULT_URL = (
    "http://10.191.200.35/Citrix/AblCertDedCtx_storeWeb/"
    "default.htm#/mode/view-appshortcuts"
)
APP_PREFIX = "ABLFHIR_"


class ShortcutLookupError(RuntimeError):
    """Raised when the shortcut cannot be fetched."""


class MinimalWebSocket:
    """Tiny WebSocket client good enough for localhost CDP traffic."""

    GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

    def __init__(self, url: str, timeout: float) -> None:
        self.url = url
        self.timeout = timeout
        self.sock: socket.socket | ssl.SSLSocket | None = None

    def connect(self) -> None:
        parsed = urllib.parse.urlparse(self.url)
        if parsed.scheme not in {"ws", "wss"}:
            raise ShortcutLookupError(f"Unsupported WebSocket scheme: {parsed.scheme}")

        host = parsed.hostname or "127.0.0.1"
        port = parsed.port or (443 if parsed.scheme == "wss" else 80)
        path = parsed.path or "/"
        if parsed.query:
            path = f"{path}?{parsed.query}"

        raw_sock = socket.create_connection((host, port), timeout=self.timeout)
        raw_sock.settimeout(self.timeout)

        if parsed.scheme == "wss":
            context = ssl.create_default_context()
            sock = context.wrap_socket(raw_sock, server_hostname=host)
        else:
            sock = raw_sock

        key = base64.b64encode(os.urandom(16)).decode("ascii")
        request = (
            f"GET {path} HTTP/1.1\r\n"
            f"Host: {host}:{port}\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\n"
            "Sec-WebSocket-Version: 13\r\n"
            "\r\n"
        ).encode("ascii")
        sock.sendall(request)
        response = self._recv_http_headers(sock)

        status_line = response.split("\r\n", 1)[0]
        if " 101 " not in status_line:
            raise ShortcutLookupError(f"WebSocket handshake failed: {status_line}")

        headers = {}
        for line in response.split("\r\n")[1:]:
            if not line or ":" not in line:
                continue
            key_name, value = line.split(":", 1)
            headers[key_name.strip().lower()] = value.strip()

        expected = base64.b64encode(
            hashlib.sha1((key + self.GUID).encode("ascii")).digest()
        ).decode("ascii")
        actual = headers.get("sec-websocket-accept")
        if actual != expected:
            raise ShortcutLookupError("WebSocket handshake returned an unexpected accept key.")

        self.sock = sock

    def close(self) -> None:
        if self.sock is None:
            return
        try:
            self._send_frame(0x8, b"")
        except OSError:
            pass
        try:
            self.sock.close()
        finally:
            self.sock = None

    def send_text(self, message: str) -> None:
        self._send_frame(0x1, message.encode("utf-8"))

    def recv_text(self) -> str:
        fragments: list[bytes] = []
        while True:
            fin, opcode, payload = self._recv_frame()
            if opcode == 0x1 or (opcode == 0x0 and fragments):
                fragments.append(payload)
                if fin:
                    return b"".join(fragments).decode("utf-8")
            if opcode == 0x8:
                raise ShortcutLookupError("WebSocket closed unexpectedly.")
            if opcode == 0x9:
                self._send_frame(0xA, payload)
                continue
            if opcode == 0xA:
                continue
            raise ShortcutLookupError(f"Unsupported WebSocket opcode: {opcode}")

    def _recv_http_headers(self, sock_obj: socket.socket | ssl.SSLSocket) -> str:
        data = bytearray()
        while b"\r\n\r\n" not in data:
            chunk = sock_obj.recv(4096)
            if not chunk:
                break
            data.extend(chunk)
        return data.decode("utf-8", errors="replace")

    def _send_frame(self, opcode: int, payload: bytes) -> None:
        if self.sock is None:
            raise ShortcutLookupError("WebSocket is not connected.")

        first = 0x80 | (opcode & 0x0F)
        length = len(payload)
        mask_bit = 0x80
        header = bytearray([first])

        if length <= 125:
            header.append(mask_bit | length)
        elif length <= 65535:
            header.append(mask_bit | 126)
            header.extend(struct.pack("!H", length))
        else:
            header.append(mask_bit | 127)
            header.extend(struct.pack("!Q", length))

        mask_key = os.urandom(4)
        header.extend(mask_key)
        masked = bytes(payload[i] ^ mask_key[i % 4] for i in range(length))
        self.sock.sendall(header + masked)

    def _recv_frame(self) -> tuple[bool, int, bytes]:
        if self.sock is None:
            raise ShortcutLookupError("WebSocket is not connected.")

        header = self._recv_exact(2)
        first, second = header[0], header[1]
        fin = bool(first & 0x80)
        opcode = first & 0x0F
        masked = bool(second & 0x80)
        length = second & 0x7F

        if length == 126:
            length = struct.unpack("!H", self._recv_exact(2))[0]
        elif length == 127:
            length = struct.unpack("!Q", self._recv_exact(8))[0]

        mask_key = self._recv_exact(4) if masked else b""
        payload = self._recv_exact(length) if length else b""

        if masked:
            payload = bytes(payload[i] ^ mask_key[i % 4] for i in range(length))

        return fin, opcode, payload

    def _recv_exact(self, size: int) -> bytes:
        if self.sock is None:
            raise ShortcutLookupError("WebSocket is not connected.")

        chunks = bytearray()
        while len(chunks) < size:
            chunk = self.sock.recv(size - len(chunks))
            if not chunk:
                raise ShortcutLookupError("WebSocket closed before the full payload arrived.")
            chunks.extend(chunk)
        return bytes(chunks)


class CdpClient:
    def __init__(self, websocket_url: str, timeout: float) -> None:
        self.websocket = MinimalWebSocket(websocket_url, timeout=timeout)
        self.timeout = timeout
        self.next_id = 0

    def connect(self) -> None:
        self.websocket.connect()

    def close(self) -> None:
        self.websocket.close()

    def call(self, method: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        self.next_id += 1
        message_id = self.next_id
        payload = {"id": message_id, "method": method, "params": params or {}}
        self.websocket.send_text(json.dumps(payload, separators=(",", ":")))

        deadline = time.time() + self.timeout
        while time.time() < deadline:
            raw = self.websocket.recv_text()
            message = json.loads(raw)
            if message.get("id") != message_id:
                continue
            if "error" in message:
                raise ShortcutLookupError(f"CDP call failed for {method}: {message['error']}")
            return message

        raise ShortcutLookupError(f"Timed out waiting for CDP response: {method}")

    def evaluate(self, expression: str, *, await_promise: bool = False) -> Any:
        response = self.call(
            "Runtime.evaluate",
            {
                "expression": expression,
                "returnByValue": True,
                "awaitPromise": await_promise,
            },
        )
        result = response["result"]["result"]
        if result.get("subtype") == "error":
            raise ShortcutLookupError(f"JavaScript evaluation failed: {result}")
        return result.get("value")


def build_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Log into a Citrix StoreFront page in Edge and print an app shortcut URL."
    )
    parser.add_argument("--storefront-url", default=DEFAULT_URL, help="Citrix shortcuts page URL.")
    parser.add_argument(
        "--app-name",
        required=True,
        help="App name suffix to match. The script searches for ABLFHIR_<app-name>.",
    )
    parser.add_argument(
        "--username",
        default=os.environ.get("CITRIX_USERNAME"),
        help="Citrix username. Defaults to the CITRIX_USERNAME environment variable.",
    )
    parser.add_argument(
        "--password",
        default=os.environ.get("CITRIX_PASSWORD"),
        help="Citrix password. Defaults to the CITRIX_PASSWORD environment variable.",
    )
    parser.add_argument(
        "--edge-path",
        default=str(DEFAULT_EDGE_PATH),
        help=f"Path to Edge. Defaults to {DEFAULT_EDGE_PATH}.",
    )
    parser.add_argument(
        "--debug-port",
        type=int,
        help="Remote debugging port to use when attaching to an existing Edge session.",
    )
    parser.add_argument(
        "--attach-existing",
        action="store_true",
        help="Attach to an already-running Edge debug session instead of launching a new browser.",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=45.0,
        help="Maximum seconds to wait for login and shortcut extraction.",
    )
    parser.add_argument(
        "--keep-browser",
        action="store_true",
        help="Leave the spawned Edge process running for inspection.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Print JSON instead of only the shortcut URL.",
    )
    return parser


def find_free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock_obj:
        sock_obj.bind(("127.0.0.1", 0))
        return sock_obj.getsockname()[1]


def wait_for_json(url: str, timeout: float) -> Any:
    deadline = time.time() + timeout
    last_error: Exception | None = None
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(url, timeout=2.0) as response:
                return json.loads(response.read().decode("utf-8"))
        except (urllib.error.URLError, json.JSONDecodeError) as exc:
            last_error = exc
            time.sleep(0.5)
    raise ShortcutLookupError(f"Timed out waiting for {url}: {last_error}")


def launch_edge(edge_path: Path, url: str, port: int, profile_dir: Path) -> subprocess.Popen[str]:
    if not edge_path.exists():
        raise ShortcutLookupError(f"Edge executable not found: {edge_path}")

    command = [
        str(edge_path),
        f"--remote-debugging-port={port}",
        "--remote-debugging-address=127.0.0.1",
        f"--user-data-dir={profile_dir}",
        "--no-first-run",
        "--disable-extensions",
        "--disable-sync",
        "--new-window",
        url,
    ]
    return subprocess.Popen(command)


def resolve_debug_port(args: argparse.Namespace) -> int:
    if args.debug_port is not None:
        return args.debug_port
    if args.attach_existing:
        return 9225
    return find_free_port()


def find_page_websocket(port: int, storefront_url: str, timeout: float) -> str:
    target_prefix = storefront_url.split("#", 1)[0]
    deadline = time.time() + timeout
    last_seen: list[str] = []

    while time.time() < deadline:
        targets = wait_for_json(f"http://127.0.0.1:{port}/json/list", timeout=5.0)
        last_seen = [target.get("url", "") for target in targets if target.get("type") == "page"]
        for target in targets:
            if target.get("type") != "page":
                continue
            current_url = target.get("url", "")
            if current_url.startswith(target_prefix):
                websocket_url = target.get("webSocketDebuggerUrl")
                if websocket_url:
                    return websocket_url
        time.sleep(0.5)

    raise ShortcutLookupError(
        "Timed out finding the StoreFront page target. "
        f"Last page URLs seen: {last_seen}"
    )


def wait_for_login_form(cdp: CdpClient, timeout: float) -> None:
    deadline = time.time() + timeout
    expression = """
(() => !!document.querySelector('#username') && !!document.querySelector('#password'))()
"""
    while time.time() < deadline:
        if cdp.evaluate(expression):
            return
        time.sleep(0.5)
    raise ShortcutLookupError("Timed out waiting for the Citrix login form.")


def submit_login(cdp: CdpClient, username: str, password: str) -> None:
    username_json = json.dumps(username)
    password_json = json.dumps(password)
    expression = f"""
(() => {{
  const setValue = (selector, value) => {{
    const element = document.querySelector(selector);
    if (!element) {{
      return false;
    }}
    element.focus();
    element.value = value;
    element.dispatchEvent(new Event('input', {{ bubbles: true }}));
    element.dispatchEvent(new Event('change', {{ bubbles: true }}));
    return true;
  }};

  const okUser = setValue('#username', {username_json});
  const okPass = setValue('#password', {password_json});
  const button = document.querySelector('#loginBtn');
  if (button) {{
    button.click();
  }}
  return {{ okUser, okPass, clicked: !!button }};
}})()
"""
    result = cdp.evaluate(expression)
    if not result or not result.get("okUser") or not result.get("okPass") or not result.get("clicked"):
        raise ShortcutLookupError(f"Failed to populate or submit the login form: {result}")


def wait_for_shortcut(cdp: CdpClient, app_name: str, timeout: float) -> dict[str, Any]:
    app_name_json = json.dumps(app_name)
    expression = f"""
(() => {{
  const normalize = (value) =>
    (value || '').toLowerCase().replace(/[\\s_]+/g, '');
  const wanted = normalize({app_name_json});
  const rows = [...document.querySelectorAll('tr')]
    .map((tr) => {{
      const cells = tr.querySelectorAll('td');
      if (cells.length < 3) {{
        return null;
      }}
      const input = cells[2].querySelector('input');
      return {{
        name: (cells[1].innerText || '').trim(),
        url: input ? input.value : ''
      }};
    }})
    .filter(Boolean);
  const exact = rows.find((row) => normalize(row.name) === wanted) || null;
  const partial = rows
    .filter((row) => normalize(row.name).includes(wanted) || wanted.includes(normalize(row.name)))
    .slice(0, 10);
  const errorText = [...document.querySelectorAll('.messagebox-body, .error, .warning, .field')]
    .map((node) => (node.innerText || '').trim())
    .filter(Boolean)
    .find((text) => /(error|fail|denied|incorrect|invalid|timeout)/i.test(text)) || '';
  return {{
    exact,
    partial,
    rowCount: rows.length,
    loginVisible: !!document.querySelector('#loginBtn'),
    errorText,
    currentUrl: location.href
  }};
}})()
"""

    deadline = time.time() + timeout
    last_state: dict[str, Any] | None = None
    while time.time() < deadline:
        state = cdp.evaluate(expression)
        last_state = state
        if state and state.get("exact"):
            return state["exact"]
        if state and state.get("errorText") and state.get("loginVisible"):
            raise ShortcutLookupError(f"Citrix login appears to have failed: {state['errorText']}")
        time.sleep(1.0)

    raise ShortcutLookupError(f"Timed out waiting for shortcut rows. Last observed state: {last_state}")


def main() -> int:
    parser = build_argument_parser()
    args = parser.parse_args()

    if not args.username or not args.password:
        parser.error("Both username and password are required.")

    edge_path = Path(args.edge_path)
    profile_dir: Path | None = None
    port = resolve_debug_port(args)
    browser: subprocess.Popen[str] | None = None
    cdp: CdpClient | None = None

    try:
        if not args.attach_existing:
            profile_dir = Path(tempfile.mkdtemp(prefix="codex-citrix-"))
            browser = launch_edge(edge_path, args.storefront_url, port, profile_dir)
        wait_for_json(f"http://127.0.0.1:{port}/json/version", timeout=10.0)

        websocket_url = find_page_websocket(port, args.storefront_url, timeout=10.0)
        cdp = CdpClient(websocket_url, timeout=10.0)
        cdp.connect()
        cdp.call("Runtime.enable")

        search_name = f"{APP_PREFIX}{args.app_name}"

        wait_for_login_form(cdp, timeout=min(args.timeout, 15.0))
        submit_login(cdp, args.username, args.password)
        match = wait_for_shortcut(cdp, search_name, timeout=args.timeout)

        if args.json:
            print(json.dumps(match, indent=2))
        else:
            print(match["url"])
        return 0
    except ShortcutLookupError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    finally:
        if cdp is not None:
            cdp.close()
        if browser is not None and not args.keep_browser:
            browser.terminate()
            try:
                browser.wait(timeout=5)
            except subprocess.TimeoutExpired:
                browser.kill()
        if profile_dir is not None and not args.keep_browser:
            shutil.rmtree(profile_dir, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
