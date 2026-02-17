#!/usr/bin/env bash
# build-detector.sh - Auto-detect build/test commands from project structure
# Part of speckit-ralph

# Only set strict mode when executed directly
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
    set -euo pipefail
fi

# Detect tech stack and set BUILD_CMD, TEST_CMD, LINT_CMD

detect_stack() {
    local root="$1"

    # Node.js / TypeScript (most common)
    if [[ -f "$root/package.json" ]]; then
        detect_node "$root"
        return
    fi

    # Python
    if [[ -f "$root/pyproject.toml" ]] || [[ -f "$root/setup.py" ]] || [[ -f "$root/requirements.txt" ]]; then
        detect_python "$root"
        return
    fi

    # Rust
    if [[ -f "$root/Cargo.toml" ]]; then
        detect_rust "$root"
        return
    fi

    # Go
    if [[ -f "$root/go.mod" ]]; then
        detect_go "$root"
        return
    fi

    # Docker Compose (fallback for multi-service)
    if [[ -f "$root/docker-compose.yml" ]] || [[ -f "$root/docker-compose.yaml" ]]; then
        detect_docker "$root"
        return
    fi

    # Unknown - try to read from plan.md
    if [[ -f "$root/plan.md" ]] || [[ -f "$root/specs/*/plan.md" ]]; then
        detect_from_plan "$root"
        return
    fi

    # Fallback
    echo "STACK=unknown"
    echo "BUILD_CMD=:"
    echo "TEST_CMD=:"
    echo "LINT_CMD=:"
}

detect_node() {
    local root="$1"
    local pkg="$root/package.json"

    echo "STACK=node"

    # Detect package manager
    local pm="npm"
    if [[ -f "$root/pnpm-lock.yaml" ]]; then
        pm="pnpm"
    elif [[ -f "$root/yarn.lock" ]]; then
        pm="yarn"
    elif [[ -f "$root/bun.lockb" ]]; then
        pm="bun"
    fi
    echo "PACKAGE_MANAGER=$pm"

    # Build command
    if jq -e '.scripts.build' "$pkg" > /dev/null 2>&1; then
        echo "BUILD_CMD='$pm run build'"
    elif jq -e '.scripts.compile' "$pkg" > /dev/null 2>&1; then
        echo "BUILD_CMD='$pm run compile'"
    else
        echo "BUILD_CMD='$pm run tsc --noEmit 2>/dev/null || :'"
    fi

    # Test command
    if jq -e '.scripts.test' "$pkg" > /dev/null 2>&1; then
        echo "TEST_CMD='$pm test'"
    elif jq -e '.scripts["test:unit"]' "$pkg" > /dev/null 2>&1; then
        echo "TEST_CMD='$pm run test:unit'"
    else
        echo "TEST_CMD=:"
    fi

    # Lint command
    if jq -e '.scripts.lint' "$pkg" > /dev/null 2>&1; then
        echo "LINT_CMD='$pm run lint'"
    elif jq -e '.scripts["lint:check"]' "$pkg" > /dev/null 2>&1; then
        echo "LINT_CMD='$pm run lint:check'"
    else
        echo "LINT_CMD=:"
    fi

    # Type check
    if jq -e '.scripts.typecheck' "$pkg" > /dev/null 2>&1; then
        echo "TYPECHECK_CMD='$pm run typecheck'"
    elif [[ -f "$root/tsconfig.json" ]]; then
        echo "TYPECHECK_CMD='$pm run tsc --noEmit'"
    else
        echo "TYPECHECK_CMD=:"
    fi
}

detect_python() {
    local root="$1"

    echo "STACK=python"

    # Detect package manager
    if [[ -f "$root/poetry.lock" ]]; then
        echo "PACKAGE_MANAGER=poetry"
        echo "BUILD_CMD='poetry build'"
        echo "TEST_CMD='poetry run pytest'"
        echo "LINT_CMD='poetry run ruff check .'"
    elif [[ -f "$root/Pipfile" ]]; then
        echo "PACKAGE_MANAGER=pipenv"
        echo "BUILD_CMD='pipenv run python -m build'"
        echo "TEST_CMD='pipenv run pytest'"
        echo "LINT_CMD='pipenv run ruff check .'"
    elif [[ -f "$root/uv.lock" ]]; then
        echo "PACKAGE_MANAGER=uv"
        echo "BUILD_CMD='uv build'"
        echo "TEST_CMD='uv run pytest'"
        echo "LINT_CMD='uv run ruff check .'"
    else
        echo "PACKAGE_MANAGER=pip"
        echo "BUILD_CMD='python -m build 2>/dev/null || :'"
        echo "TEST_CMD='pytest'"
        echo "LINT_CMD='ruff check . 2>/dev/null || :'"
    fi
}

detect_rust() {
    local root="$1"

    echo "STACK=rust"
    echo "PACKAGE_MANAGER=cargo"
    echo "BUILD_CMD='cargo build'"
    echo "TEST_CMD='cargo test'"
    echo "LINT_CMD='cargo clippy'"
}

detect_go() {
    local root="$1"

    echo "STACK=go"
    echo "PACKAGE_MANAGER=go"
    echo "BUILD_CMD='go build ./...'"
    echo "TEST_CMD='go test ./...'"
    echo "LINT_CMD='golangci-lint run 2>/dev/null || go vet ./...'"
}

detect_docker() {
    local root="$1"

    echo "STACK=docker"
    echo "PACKAGE_MANAGER=docker-compose"
    echo "BUILD_CMD='docker compose build'"
    echo "TEST_CMD='docker compose run --rm test 2>/dev/null || docker compose up -d && docker compose ps'"
    echo "LINT_CMD=:"
}

detect_from_plan() {
    local root="$1"

    # Try to find plan.md
    local plan_file
    plan_file=$(find "$root" -name "plan.md" -type f 2>/dev/null | head -1)

    if [[ -z "$plan_file" ]]; then
        echo "STACK=unknown"
        echo "BUILD_CMD=:"
        echo "TEST_CMD=:"
        echo "LINT_CMD=:"
        return
    fi

    echo "STACK=from-plan"
    echo "PLAN_FILE=$plan_file"

    # Extract tech stack hints from plan.md
    if grep -qi "typescript\|node\|npm\|express" "$plan_file"; then
        detect_node "$root"
    elif grep -qi "python\|django\|fastapi\|flask" "$plan_file"; then
        detect_python "$root"
    elif grep -qi "rust\|cargo" "$plan_file"; then
        detect_rust "$root"
    elif grep -qi "golang\|go mod" "$plan_file"; then
        detect_go "$root"
    else
        echo "BUILD_CMD=:"
        echo "TEST_CMD=:"
        echo "LINT_CMD=:"
    fi
}

# Main dispatch - only run when executed directly
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
    PROJECT_ROOT="${1:-$(pwd)}"
    OUTPUT="${2:---env}"

    case "$OUTPUT" in
        --env)
            detect_stack "$PROJECT_ROOT"
            ;;
        --json)
            # Capture env output and convert to JSON
            output=$(detect_stack "$PROJECT_ROOT")
            echo "$output" | awk -F= '{gsub(/"/, "\\\"", $2); printf "\"%s\": \"%s\",\n", $1, $2}' | sed '$ s/,$//' | sed '1 s/^/{/' | sed '$ s/$/}/'
            ;;
        --source)
            # Output sourceable format (already default)
            detect_stack "$PROJECT_ROOT"
            ;;
        *)
            echo "Unknown output format: $OUTPUT" >&2
            echo "Usage: build-detector.sh <project_root> [--env|--json|--source]" >&2
            exit 1
            ;;
    esac
fi
