import subprocess
from typing import List


def run_commands(commands: List[str], timeout: int = 600) -> tuple[int, List[str]]:
    outputs: List[str] = []
    code = 0
    for cmd in commands:
        try:
            p = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
            outputs.append(f"{cmd}: {p.stdout.strip() or p.stderr.strip() or 'OK'}")
            if p.returncode != 0:
                code = p.returncode
                break
        except subprocess.TimeoutExpired:
            outputs.append(f"{cmd}: TIMEOUT")
            code = -1
            break
    return code, outputs


def stream_command(cmd: str, timeout: int = 600):
    p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    try:
        for line in iter(p.stdout.readline, ''):
            if not line:
                break
            yield line
        rc = p.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        p.kill()
        yield "[TIMEOUT]\n"
        rc = -1
    yield f"[EXIT {rc}]\n"
