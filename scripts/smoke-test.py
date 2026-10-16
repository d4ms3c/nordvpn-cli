#!/usr/bin/env python3
"""Exercise CLI contracts without starting the app or changing the tunnel."""

import json
import subprocess
import sys

VERSION = "0.2.0"


def run(*args):
    return subprocess.run(
        [sys.argv[1], *args], capture_output=True, text=True, timeout=15, check=False
    )


def mcp_session(*args, messages):
    """Send JSON-RPC lines to `nordvpn mcp`, close stdin and map the responses by id."""
    lines = "".join(
        (message if isinstance(message, str) else json.dumps(message)) + "\n"
        for message in messages
    )
    result = subprocess.run(
        [sys.argv[1], "mcp", *args],
        input=lines,
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )
    assert result.returncode == 0, result
    responses = [json.loads(line) for line in result.stdout.splitlines()]
    assert all(response["jsonrpc"] == "2.0" for response in responses), responses
    return {response["id"]: response for response in responses}


def check_mcp():
    def call(request_id, name, arguments):
        return {
            "jsonrpc": "2.0",
            "id": request_id,
            "method": "tools/call",
            "params": {"name": name, "arguments": arguments},
        }

    responses = mcp_session(
        messages=[
            {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {"protocolVersion": "2025-11-25", "capabilities": {}},
            },
            {"jsonrpc": "2.0", "method": "notifications/initialized"},
            {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
            call(3, "nordvpn_run_doctor", {"offline": True}),
            call(4, "nordvpn_connect", {"timeout_seconds": 0}),
            call(5, "nordvpn_disconnect", {"timeout_seconds": "soon"}),
            "not json",
        ]
    )
    assert set(responses) == {1, 2, 3, 4, 5, None}, responses
    assert responses[1]["result"]["protocolVersion"] == "2025-11-25", responses[1]
    assert responses[1]["result"]["serverInfo"]["version"] == VERSION, responses[1]
    tools = {tool["name"]: tool for tool in responses[2]["result"]["tools"]}
    assert len(tools) == 6, tools
    for name in ("nordvpn_connect", "nordvpn_disconnect"):
        assert tools[name]["annotations"]["destructiveHint"] is True, tools[name]
    doctor = responses[3]["result"]
    assert "isError" not in doctor, doctor
    assert {check["name"] for check in doctor["structuredContent"]["checks"]} == {
        "app",
        "profile",
        "accessibility",
        "log",
    }
    assert responses[4]["result"]["isError"] is True, responses[4]
    assert responses[5]["result"]["isError"] is True, responses[5]
    assert responses[None]["error"]["code"] == -32700, responses[None]

    read_only = mcp_session(
        "--read-only", messages=[{"jsonrpc": "2.0", "id": 1, "method": "tools/list"}]
    )
    names = {tool["name"] for tool in read_only[1]["result"]["tools"]}
    assert "nordvpn_connect" not in names and len(names) == 4, names


def main():
    for command in ("connect", "disconnect"):
        for timeout in ("0", "-1", "nan", "inf", "3601"):
            result = run(command, f"--timeout={timeout}")
            assert result.returncode != 0, (command, timeout, result)
            assert "Timeout must be" in result.stderr, result.stderr
    for shell in ("bash", "zsh", "fish"):
        result = run("--generate-completion-script", shell)
        assert result.returncode == 0 and result.stdout.strip(), result
    result = run("doctor", "--offline", "--json")
    assert result.returncode in (0, 1), result
    checks = json.loads(result.stdout)
    assert {check["name"] for check in checks} == {
        "app",
        "profile",
        "accessibility",
        "log",
    }
    assert result.returncode == int(any(not check["passed"] for check in checks))
    assert all(set(check) == {"name", "passed", "message"} for check in checks)
    result = run("--version")
    assert result.returncode == 0 and result.stdout.strip() == VERSION, result
    check_mcp()
    print("CLI smoke checks passed (no VPN changes).")


if __name__ == "__main__":
    main()
