"""Reject generated files from another branch or source tree (stdlib only)."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import uuid

PROFILE = "freertos"
DEFAULT_VARIANT = "freertos"
ROOT = Path(__file__).resolve().parent.parent
SCHEMA = 1


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def generated(name: str) -> Path:
    path = Path(name)
    if not path.is_absolute():
        path = ROOT / path
    path = path.resolve()
    if ROOT / "build" not in path.parents:
        raise ValueError(f"Refusing a generated path outside build/: {path}")
    return path


def sidecar(path: Path, pending: bool = False) -> Path:
    return path.with_name(path.name + (".pending.json" if pending else ".build.json"))


def read(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        if (not isinstance(value, dict) or value.get("schema") != SCHEMA
                or not isinstance(value.get("context"), dict)):
            raise ValueError("unsupported receipt")
        return value
    except (OSError, ValueError) as error:
        raise ValueError(f"Missing or invalid build receipt: {path}. Rebuild first.") from error


def write(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + "." + uuid.uuid4().hex + ".tmp")
    try:
        temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def sources() -> dict:
    paths = []
    for folder in ("src/rtl", "constraints", "sw", "third_party", "scripts"):
        directory = ROOT / folder
        if directory.is_dir():
            paths.extend(path for path in directory.rglob("*") if path.is_file()
                         and "__pycache__" not in path.parts and path.suffix != ".pyc"
                         and path.name != "vivado_local.bat")
    paths.extend(ROOT.glob("*.bat"))
    toolchain = ROOT / "tools/toolchain.json"
    if toolchain.is_file():
        paths.append(toolchain)
    manifest = hashlib.sha256()
    for path in sorted(set(paths), key=lambda item: item.relative_to(ROOT).as_posix()):
        manifest.update(path.relative_to(ROOT).as_posix().encode("utf-8") + b"\0")
        manifest.update(digest(path).encode("ascii") + b"\n")
    try:
        result = subprocess.run(["git", "symbolic-ref", "--quiet", "--short", "HEAD"],
                                cwd=ROOT, capture_output=True, text=True, timeout=10)
        branch = result.stdout.strip() if result.returncode == 0 else "detached-or-exported"
    except (OSError, subprocess.TimeoutExpired):
        branch = "detached-or-exported"
    return {"profile": PROFILE, "branch": branch, "workspace": ROOT.as_posix().casefold(),
            "sources_sha256": manifest.hexdigest()}


def firmware_path(variant: str) -> Path:
    allowed = {"scope": {"scope"}, "freertos": {"freertos"},
               "ptrocos": {"ddr2", "text", "shell", "storage", "graphics", "media", "video", "elf", "perf"}}
    if variant not in allowed[PROFILE]:
        raise ValueError(f"Unsupported firmware {variant!r} for {PROFILE}")
    name = f"ptrocos_{variant}" if PROFILE == "ptrocos" else variant
    return ROOT / "build/hex" / f"{name}.hex"


def context(kind: str, variant: str, tool: str) -> dict:
    result = dict(sources(), variant=variant, tool=tool)
    firmware = firmware_path(variant)
    if kind != "firmware":
        check(firmware, "firmware", variant, "")
        result["firmware_sha256"] = digest(firmware)
    return result


def check(path: Path, kind: str, variant: str, tool: str) -> dict:
    value = read(sidecar(path))
    if value.get("kind") != kind or value.get("context", {}).get("variant") != variant:
        raise ValueError(f"Wrong build target: {path}. Rebuild for {PROFILE}/{variant}.")
    expected = context(kind, variant, tool or value["context"].get("tool", ""))
    if value["context"] != expected:
        raise ValueError(f"Branch, sources, firmware or tool version changed: {path}. Rebuild first.")
    if not path.is_file() or path.stat().st_size == 0:
        raise ValueError(f"Generated file missing or empty: {path}. Rebuild first.")
    # Vivado saves GUI state to the XPR after creation; its input context is the guard.
    if kind != "project" and value.get("artifact_sha256") != digest(path):
        raise ValueError(f"Generated file changed since its successful build: {path}. Rebuild first.")
    return value


def begin(path: Path, kind: str, variant: str, tool: str) -> None:
    # Remove the old success receipt BEFORE a build, including a failing retry.
    sidecar(path).unlink(missing_ok=True)
    sidecar(path, True).unlink(missing_ok=True)
    value = {"schema": SCHEMA, "kind": kind, "context": context(kind, variant, tool)}
    write(sidecar(path, True), value)


def finish(path: Path, kind: str, variant: str, tool: str, basis: Path | None = None) -> None:
    pending = read(sidecar(basis or path, True))
    if pending.get("kind") != ("bitstream" if basis else kind):
        raise ValueError("Build start receipt has the wrong kind")
    expected = context(kind, variant, tool or pending["context"].get("tool", ""))
    if pending["context"] != expected:
        raise ValueError("Inputs changed during the build; output is not accepted. Rebuild first.")
    if not path.is_file() or path.stat().st_size == 0:
        raise ValueError(f"Build did not produce a nonempty file: {path}")
    value = dict(pending, kind=kind)
    if kind != "project":
        value["artifact_sha256"] = digest(path)
    write(sidecar(path), value)
    # Keep the synthesis snapshot for implementation retries and checkpoint sealing.
    if kind in {"firmware", "project"}:
        sidecar(path, True).unlink(missing_ok=True)


def prepare(path: Path, variant: str, tool: str) -> None:
    if path.suffix != ".xpr" or path.parent.parent != ROOT / "build":
        raise ValueError("Expected a project in an immediate subdirectory of build/")
    expected = context("project", variant, tool)
    try:
        check(path, "project", variant, tool)
        print("ready")
        return
    except ValueError:
        pass
    # The launcher and creator both prepare. Keep the pending empty directory
    # rather than archiving it again before create_project has written the XPR.
    if not path.exists():
        try:
            pending = read(sidecar(path, True))
            if pending.get("kind") == "project" and pending["context"] == expected:
                print("create")
                return
        except ValueError:
            pass
    if path.parent.exists():
        # Rename the whole project, including its caches/runs. Preserve old evidence.
        # Both resolved endpoints must stay inside build; never move through a junction.
        original = path.parent.resolve()
        if original.parent != ROOT / "build":
            raise ValueError(f"Unsafe project directory: {original}")
        archive = (ROOT / "build/stale-projects").resolve()
        if archive.parent != ROOT / "build":
            raise ValueError(f"Unsafe archive directory: {archive}")
        archive.mkdir(exist_ok=True)
        destination = archive / (original.name + "-" + uuid.uuid4().hex)
        original.rename(destination)
        print(f"Archived stale project: {destination}", file=sys.stderr)
    path.parent.mkdir(parents=True, exist_ok=True)
    write(sidecar(path, True), {"schema": SCHEMA, "kind": "project", "context": expected})
    print("create")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("begin", "finish", "check", "prepare", "seal"))
    parser.add_argument("--kind", choices=("firmware", "project", "bitstream", "checkpoint"), required=True)
    parser.add_argument("--file", required=True)
    parser.add_argument("--variant", default=DEFAULT_VARIANT)
    parser.add_argument("--tool", default="")
    parser.add_argument("--basis")
    args = parser.parse_args()
    path = generated(args.file)
    firmware_path(args.variant)
    if args.kind == "firmware" and path != firmware_path(args.variant):
        raise ValueError("Firmware receipt must use this target's canonical HEX path")
    if args.action == "prepare":
        if args.kind != "project":
            raise ValueError("prepare is only valid for projects")
        prepare(path, args.variant, args.tool)
    elif args.action == "begin":
        begin(path, args.kind, args.variant, args.tool)
    elif args.action == "check":
        check(path, args.kind, args.variant, args.tool)
    else:
        basis = generated(args.basis) if args.basis else None
        if args.action == "seal" and (args.kind != "checkpoint" or basis is None):
            raise ValueError("seal requires a checkpoint and its synthesis bitstream basis")
        if args.action == "finish" and basis is not None:
            raise ValueError("finish does not accept a basis")
        finish(path, args.kind, args.variant, args.tool, basis)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError) as error:
        print(f"BUILD GUARD: {error}", file=sys.stderr)
        sys.exit(1)
