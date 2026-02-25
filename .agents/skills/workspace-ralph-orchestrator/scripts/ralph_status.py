#!/usr/bin/env python3
"""
Ralph Workspace Spec Checkup - Diagnostic tool for Ralph automation status
Checks progress, git status, docker health, and system resources across all specs
"""

import json
import os
import subprocess
import sys
from pathlib import Path
from datetime import datetime
from collections import defaultdict
import argparse

def run_cmd(cmd, cwd=None):
    """Run shell command and return output"""
    try:
        result = subprocess.run(
            cmd,
            shell=True,
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=5
        )
        return result.stdout.strip()
    except subprocess.TimeoutExpired:
        return "[timeout]"
    except Exception as e:
        return f"[error: {str(e)}]"

def get_ralph_status(spec_dir):
    """Read Ralph progress.json status"""
    progress_file = spec_dir / ".ralph" / "progress.json"
    if not progress_file.exists():
        return None

    try:
        with open(progress_file) as f:
            return json.load(f)
    except:
        return None

def get_session_log(spec_dir):
    """Read last few lines of Ralph session log"""
    log_file = spec_dir / ".ralph" / "session.log"
    if not log_file.exists():
        return []

    try:
        with open(log_file) as f:
            return f.readlines()[-10:]  # Last 10 lines
    except:
        return []

def get_git_info(spec_dir):
    """Get git status and recent commits"""
    info = {}

    # Find repo root
    repo_root = spec_dir
    while repo_root != repo_root.parent:
        if (repo_root / ".git").exists():
            break
        repo_root = repo_root.parent

    if (repo_root / ".git").exists():
        info["branch"] = run_cmd("git rev-parse --abbrev-ref HEAD", cwd=repo_root)
        info["recent_commits"] = run_cmd(
            "git log --oneline -5 2>/dev/null || echo 'no commits'",
            cwd=repo_root
        ).split('\n')
        info["status"] = run_cmd("git status --short", cwd=repo_root)

    return info

def get_resource_usage(spec_dir):
    """Check disk usage and resource indicators"""
    resources = {}

    # Check node_modules in services
    services_dir = spec_dir.parent.parent / "services"
    if services_dir.exists():
        for service_dir in services_dir.iterdir():
            if service_dir.is_dir():
                nm_dir = service_dir / "node_modules"
                if nm_dir.exists():
                    size = run_cmd(f"du -sh '{nm_dir}'").split()[0]
                    resources[service_dir.name] = size

    return resources

def check_docker_status():
    """Check Docker containers and status"""
    docker_info = {}

    # Check if docker is running
    result = run_cmd("docker ps -a --format 'table {{.Names}}\\t{{.Status}}\\t{{.Size}}' 2>/dev/null")
    if result and not result.startswith("["):
        docker_info["containers"] = result
    else:
        docker_info["containers"] = "Docker not available or not running"

    return docker_info

def check_system_deps():
    """Check for required system dependencies"""
    deps = {}

    # Check for timeout command (needed by Ralph)
    deps["timeout"] = {
        "available": run_cmd("which timeout") != "",
        "path": run_cmd("which timeout")
    }

    return deps

def scan_specs(workspace_path):
    """Scan workspace for all specs directories"""
    workspace = Path(workspace_path).expanduser().resolve()
    specs = []

    # Look for specs directories
    for item in workspace.rglob("specs"):
        if item.is_dir():
            for spec_dir in item.iterdir():
                if spec_dir.is_dir() and (spec_dir / ".ralph").exists():
                    specs.append(spec_dir)

    return sorted(specs)

def format_report(specs, verbose=False):
    """Generate markdown report"""
    lines = [
        "# Ralph Workspace Spec Checkup",
        f"\n**Generated:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
        f"**Host:** {os.uname().nodename}",
        f"**Python:** {sys.version.split()[0]}",
    ]

    if not specs:
        lines.append("\n⚠️ **No Ralph specs found in workspace**")
        return "\n".join(lines)

    lines.append(f"\n## Found {len(specs)} Ralph Spec(s)")

    for spec_dir in specs:
        lines.append(f"\n### {spec_dir.relative_to(spec_dir.parent.parent.parent)}")

        # Ralph Status
        ralph_status = get_ralph_status(spec_dir)
        if ralph_status:
            lines.append("\n**Ralph Progress:**")
            lines.append(f"- Status: `{ralph_status.get('status', 'unknown')}`")
            lines.append(f"- Current Task: `{ralph_status.get('current_task', 'none')}`")
            lines.append(f"- Completed: {len(ralph_status.get('completed_tasks', []))} tasks")

            if ralph_status.get('status') == 'blocked':
                lines.append(f"- 🚫 BLOCKED: {ralph_status.get('blocked_reason', 'unknown')}")

            if ralph_status.get('failed_tasks'):
                lines.append(f"- Failed Tasks: {len(ralph_status['failed_tasks'])}")

            last_update = ralph_status.get('last_updated', 'never')
            lines.append(f"- Last Updated: `{last_update}`")

        # Session Log (recent entries)
        session_log = get_session_log(spec_dir)
        if session_log and verbose:
            lines.append("\n**Recent Session Activity:**")
            for log_line in session_log[-5:]:
                lines.append(f"  {log_line.rstrip()}")

        # Git Info
        git_info = get_git_info(spec_dir)
        if git_info:
            lines.append("\n**Git Status:**")
            if git_info.get("branch"):
                lines.append(f"- Branch: `{git_info['branch']}`")
            if git_info.get("recent_commits"):
                lines.append("- Recent Commits:")
                for commit in git_info["recent_commits"][:3]:
                    if commit.strip():
                        lines.append(f"  - {commit.rstrip()}")
            if git_info.get("status") and git_info["status"]:
                lines.append(f"- Uncommitted Changes:\n```\n{git_info['status']}\n```")

        # Resources
        resources = get_resource_usage(spec_dir)
        if resources and verbose:
            lines.append("\n**Disk Usage:**")
            for service, size in resources.items():
                lines.append(f"- {service}: {size}")

    # System-wide diagnostics
    if verbose:
        lines.append("\n## System Diagnostics")

        docker_info = check_docker_status()
        lines.append("\n**Docker Status:**")
        lines.append(f"```\n{docker_info.get('containers', 'N/A')}\n```")

        deps = check_system_deps()
        lines.append("\n**System Dependencies:**")
        for dep, info in deps.items():
            status = "✅ Available" if info["available"] else "❌ Missing"
            lines.append(f"- {dep}: {status}")
            if info["path"]:
                lines.append(f"  Path: `{info['path']}`")

    return "\n".join(lines)

def main():
    parser = argparse.ArgumentParser(
        description="Check Ralph automation status across workspace specs"
    )
    parser.add_argument(
        "workspace",
        nargs="?",
        default=".",
        help="Workspace path (default: current directory)"
    )
    parser.add_argument(
        "-o", "--output",
        help="Save report to file"
    )
    parser.add_argument(
        "-v", "--verbose",
        action="store_true",
        help="Show detailed diagnostic info"
    )

    args = parser.parse_args()

    # Scan for specs
    specs = scan_specs(args.workspace)

    # Generate report
    report = format_report(specs, verbose=args.verbose)

    # Output
    if args.output:
        with open(args.output, "w") as f:
            f.write(report)
        print(f"✅ Report saved to: {args.output}")
    else:
        print(report)

if __name__ == "__main__":
    main()
