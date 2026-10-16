#!/usr/bin/env python3
"""Exercise CLI contracts without starting the app or changing the tunnel."""

import json
import subprocess
import sys


def run(*args):
    return subprocess.run(
        [sys.argv[1], *args], capture_output=True, text=True, timeout=15, check=False
    )


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
    assert result.returncode == 0 and result.stdout.strip() == "0.2.0", result
    print("CLI smoke checks passed (no VPN changes).")


if __name__ == "__main__":
    main()
