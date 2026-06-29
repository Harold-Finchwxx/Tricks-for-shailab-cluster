#!/usr/bin/env python3
"""Unified Responses gateway: route by model name to per-provider local bridges."""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

GATEWAY_BIND = "127.0.0.1"
GATEWAY_PORT = 8786
SCRIPT_DIR = Path(__file__).resolve().parent
MODELS_CONF = SCRIPT_DIR / "domestic_models.conf"
ROUTES_CONF = SCRIPT_DIR / "domestic_model_routes.conf"
CATALOG = Path.home() / ".codex" / "domestic-models-catalog.json"
BEARER_PREFIX = "codex-local-"


def load_providers() -> dict[str, dict[str, str]]:
    providers: dict[str, dict[str, str]] = {}
    for line in MODELS_CONF.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        pid, port, _upstream, _key, _comment = line.split("|", 4)
        providers[pid] = {"port": port}
    return providers


def load_routes() -> dict[str, str]:
    routes: dict[str, str] = {}
    for line in ROUTES_CONF.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        model, provider = line.split("|", 1)
        routes[model.strip()] = provider.strip()
    return routes


def load_models_list() -> list[dict[str, str]]:
    if CATALOG.is_file():
        data = json.loads(CATALOG.read_text(encoding="utf-8"))
        return [{"id": m["slug"], "object": "model"} for m in data.get("models", [])]
    return []


class GatewayHandler(BaseHTTPRequestHandler):
    server_version = "domestic-models-gateway/0.1"

    def do_GET(self) -> None:
        if self.path in {"/health", "/v1/health"}:
            self._send_json({"status": "ok"})
            return
        if self.path in {"/models", "/v1/models"}:
            self._send_json({"object": "list", "data": load_models_list()})
            return
        self._send_json({"error": {"message": f"unknown path: {self.path}"}}, HTTPStatus.NOT_FOUND)

    def do_POST(self) -> None:
        if self.path not in {"/responses", "/v1/responses"}:
            self._send_json({"error": {"message": f"unknown path: {self.path}"}}, HTTPStatus.NOT_FOUND)
            return

        length = int(self.headers.get("content-length", "0"))
        body = self.rfile.read(length)
        try:
            payload = json.loads(body) if body else {}
        except json.JSONDecodeError:
            self._send_json({"error": {"message": "invalid JSON"}}, HTTPStatus.BAD_REQUEST)
            return

        model = payload.get("model")
        if not isinstance(model, str) or not model:
            self._send_json({"error": {"message": "missing model"}}, HTTPStatus.BAD_REQUEST)
            return

        provider_id = self.server.routes.get(model)  # type: ignore[attr-defined]
        if not provider_id:
            self._send_json(
                {"error": {"message": f"unknown model for gateway: {model}"}},
                HTTPStatus.BAD_REQUEST,
            )
            return

        provider = self.server.providers.get(provider_id)  # type: ignore[attr-defined]
        if not provider:
            self._send_json(
                {"error": {"message": f"unknown provider: {provider_id}"}},
                HTTPStatus.INTERNAL_SERVER_ERROR,
            )
            return

        backend_url = f"http://{GATEWAY_BIND}:{provider['port']}/v1/responses"
        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {BEARER_PREFIX}{provider_id}",
        }
        req = urllib.request.Request(backend_url, data=body, method="POST", headers=headers)

        try:
            with urllib.request.urlopen(req, timeout=600) as resp:
                self.send_response(resp.status)
                for key, value in resp.headers.items():
                    if key.lower() in {"transfer-encoding", "connection"}:
                        continue
                    self.send_header(key, value)
                self.end_headers()
                while True:
                    chunk = resp.read(8192)
                    if not chunk:
                        break
                    self.wfile.write(chunk)
        except urllib.error.HTTPError as exc:
            err_body = exc.read()
            self.send_response(exc.code)
            self.send_header("Content-Type", exc.headers.get("Content-Type", "application/json"))
            self.end_headers()
            self.wfile.write(err_body)
        except urllib.error.URLError as exc:
            self._send_json(
                {"error": {"message": f"backend unreachable: {exc.reason}"}},
                HTTPStatus.BAD_GATEWAY,
            )

    def log_message(self, format: str, *args: Any) -> None:
        sys.stderr.write(f"[gateway] {self.client_address[0]} {format % args}\n")
        sys.stderr.flush()

    def _send_json(self, payload: dict[str, Any], status: HTTPStatus = HTTPStatus.OK) -> None:
        raw = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)


def main() -> None:
    parser = argparse.ArgumentParser(description="Domestic models unified Codex gateway")
    parser.add_argument("--bind", default=GATEWAY_BIND)
    parser.add_argument("--port", type=int, default=GATEWAY_PORT)
    args = parser.parse_args()

    providers = load_providers()
    routes = load_routes()
    server = ThreadingHTTPServer((args.bind, args.port), GatewayHandler)
    server.providers = providers  # type: ignore[attr-defined]
    server.routes = routes  # type: ignore[attr-defined]
    print(f"domestic gateway on http://{args.bind}:{args.port}  routes={len(routes)}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
