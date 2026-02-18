#!/usr/bin/env bash
# install.sh - Install Ralph Wiggum Loop into a project
# Part of speckit-ralph

set -euo pipefail

VERSION="0.1.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default options
INSTALL_MODE="symlink"  # symlink or copy
TARGET_DIR=""
GLOBAL_INSTALL=false
INSTALL_ORCHESTRATOR_SKILL=true
INSTALL_SPEC_KIT=false
SPEC_KIT_SOURCE="https://github.com/github/spec-kit.git"
SPEC_KIT_REF=""
SPEC_KIT_FORCE=false

print_banner() {
    cat <<'EOF'
  ____       _       _
 |  _ \ __ _| |_ __ | |__
 | |_) / _` | | '_ \| '_ \
 |  _ < (_| | | |_) | | | |
 |_| \_\__,_|_| .__/|_| |_|
              |_|  Installer

EOF
    echo "Version $VERSION"
    echo ""
}

usage() {
    cat <<'EOF'
Usage: install.sh [options] [target_directory]

Install Ralph Wiggum Loop extension for spec kit.

Options:
  --symlink     Create symlinks to source (default, for development)
  --copy        Copy files to target (for standalone installation)
  --with-orchestrator-skill
                Install `/speckit.ralph.extension` command + `workspace-ralph-orchestrator` skill into target `.claude/` (default: on)
  --no-orchestrator-skill
                Skip installing orchestrator command/skill into target `.claude/`
  --with-spec-kit
                Install official Spec Kit assets from upstream (commands + .specify templates/scripts)
  --spec-kit-source <url>
                Source repository URL for Spec Kit (default: https://github.com/github/spec-kit.git)
  --spec-kit-ref <ref>
                Tag/branch/commit to install from (default: remote default branch)
  --spec-kit-force
                Overwrite existing local Spec Kit files when present (default: keep existing)
  --global      Install globally to ~/.local/bin
  --uninstall   Remove Ralph from target project
  --help        Show this help

Examples:
  # Install into current project (symlink mode)
  ./install.sh

  # Install into specific project
  ./install.sh /path/to/project

  # Install globally
  ./install.sh --global

  # Copy mode (no symlinks)
  ./install.sh --copy /path/to/project

  # Copy mode + orchestrator command/skill
  ./install.sh --copy --with-orchestrator-skill /path/to/project

  # Copy mode without orchestrator command/skill
  ./install.sh --copy --no-orchestrator-skill /path/to/project

  # Install with official Spec Kit assets from upstream
  ./install.sh --copy --with-spec-kit /path/to/project

  # Pin Spec Kit install to a specific release tag
  ./install.sh --copy --with-spec-kit --spec-kit-ref v0.0.53 /path/to/project

  # Uninstall from project
  ./install.sh --uninstall /path/to/project
EOF
}

# Find project root by looking for spec kit markers
find_project_root() {
    local dir="${1:-$(pwd)}"

    while [[ "$dir" != "/" ]]; do
        # Look for spec kit markers
        if [[ -d "$dir/.specify" ]] || [[ -d "$dir/specs" ]] || [[ -f "$dir/package.json" ]] || [[ -f "$dir/Cargo.toml" ]]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done

    # Default to current directory
    echo "$(pwd)"
}

copy_file_with_policy() {
    local src_file="$1"
    local dst_file="$2"

    if [[ "$SPEC_KIT_FORCE" == "true" || ! -f "$dst_file" ]]; then
        cp "$src_file" "$dst_file"
        return 0
    fi

    return 1
}

install_spec_kit_from_upstream() {
    local target="$1"
    local tmp_dir
    local clone_dir
    local clone_label="$SPEC_KIT_SOURCE"

    tmp_dir="$(mktemp -d)"
    clone_dir="$tmp_dir/spec-kit"

    if [[ -n "$SPEC_KIT_REF" ]]; then
        clone_label="$clone_label@$SPEC_KIT_REF"
    fi

    echo "Installing official Spec Kit assets from: $clone_label"

    if [[ -n "$SPEC_KIT_REF" ]]; then
        if ! git clone --depth 1 --branch "$SPEC_KIT_REF" "$SPEC_KIT_SOURCE" "$clone_dir" >/dev/null 2>&1; then
            git clone "$SPEC_KIT_SOURCE" "$clone_dir" >/dev/null
            (
                cd "$clone_dir"
                git checkout "$SPEC_KIT_REF" >/dev/null
            )
        fi
    else
        git clone --depth 1 "$SPEC_KIT_SOURCE" "$clone_dir" >/dev/null
    fi

    local target_claude_cmds="$target/.claude/commands"
    local target_specify="$target/.specify"
    local src_claude_cmds="$clone_dir/.claude/commands"
    local src_specify="$clone_dir/.specify"
    local copied_count=0
    local skipped_count=0

    mkdir -p "$target_claude_cmds" "$target_specify"

    if compgen -G "$src_claude_cmds/speckit.*.md" > /dev/null; then
        while IFS= read -r src_file; do
            local dst_file="$target_claude_cmds/$(basename "$src_file")"
            if copy_file_with_policy "$src_file" "$dst_file"; then
                copied_count=$((copied_count + 1))
            else
                skipped_count=$((skipped_count + 1))
            fi
        done < <(find "$src_claude_cmds" -maxdepth 1 -type f -name "speckit.*.md" | sort)
    else
        echo "Warning: No speckit.* commands found in upstream source"
    fi

    if [[ -d "$src_specify" ]]; then
        while IFS= read -r src_file; do
            local rel_path="${src_file#"$src_specify"/}"
            local dst_file="$target_specify/$rel_path"
            mkdir -p "$(dirname "$dst_file")"
            if copy_file_with_policy "$src_file" "$dst_file"; then
                copied_count=$((copied_count + 1))
            else
                skipped_count=$((skipped_count + 1))
            fi
        done < <(find "$src_specify" -type f | sort)
    else
        echo "Warning: No .specify directory found in upstream source"
    fi

    rm -rf "$tmp_dir"

    echo "Installed Spec Kit assets: copied=$copied_count skipped=$skipped_count"
}

# Install to project
install_to_project() {
    local target="$1"
    local mode="$2"

    local ralph_dir="$target/.specify/ralph"

    echo "Installing Ralph to: $ralph_dir"
    echo "Mode: $mode"

    # Create directory structure
    mkdir -p "$ralph_dir"

    if [[ "$mode" == "symlink" ]]; then
        # Symlink lib directory
        if [[ -L "$ralph_dir/lib" ]]; then
            rm "$ralph_dir/lib"
        fi
        ln -sf "$SCRIPT_DIR/lib" "$ralph_dir/lib"

        # Symlink bin
        if [[ -L "$ralph_dir/bin" ]]; then
            rm "$ralph_dir/bin"
        fi
        ln -sf "$SCRIPT_DIR/bin" "$ralph_dir/bin"

        # Symlink templates
        if [[ -L "$ralph_dir/templates" ]]; then
            rm "$ralph_dir/templates"
        fi
        ln -sf "$SCRIPT_DIR/templates" "$ralph_dir/templates"

        echo "Created symlinks to source"
    else
        # Copy files
        cp -r "$SCRIPT_DIR/lib" "$ralph_dir/"
        cp -r "$SCRIPT_DIR/bin" "$ralph_dir/"
        cp -r "$SCRIPT_DIR/templates" "$ralph_dir/"
        chmod +x "$ralph_dir/bin/ralph" "$ralph_dir/lib/"*.sh

        echo "Copied files to target"
    fi

    # Copy ralph-global.md template (always copy, not symlink - project customizes this)
    if [[ ! -f "$ralph_dir/ralph-global.md" ]]; then
        cp "$SCRIPT_DIR/templates/ralph-global.md" "$ralph_dir/ralph-global.md"
        echo "Created ralph-global.md (customize with your project's skills)"
    else
        echo "ralph-global.md already exists (skipped)"
    fi

    # Optionally install Claude command + orchestrator skill into target project
    if [[ "$INSTALL_ORCHESTRATOR_SKILL" == "true" ]]; then
        local target_claude_dir="$target/.claude"
        mkdir -p "$target_claude_dir/commands" "$target_claude_dir/skills"

        if [[ "$mode" == "symlink" ]]; then
            ln -sf "$SCRIPT_DIR/.claude/commands/speckit.ralph.extension.md" "$target_claude_dir/commands/speckit.ralph.extension.md"
            ln -sfn "$SCRIPT_DIR/.claude/skills/workspace-ralph-orchestrator" "$target_claude_dir/skills/workspace-ralph-orchestrator"
            echo "Installed orchestrator command/skill (symlink)"
        else
            if [[ ! -f "$target_claude_dir/commands/speckit.ralph.extension.md" ]]; then
                cp "$SCRIPT_DIR/.claude/commands/speckit.ralph.extension.md" "$target_claude_dir/commands/speckit.ralph.extension.md"
            fi
            if [[ ! -d "$target_claude_dir/skills/workspace-ralph-orchestrator" ]]; then
                cp -r "$SCRIPT_DIR/.claude/skills/workspace-ralph-orchestrator" "$target_claude_dir/skills/"
            fi
            echo "Installed orchestrator command/skill (copy)"
        fi
    fi

    # Optionally install official Spec Kit assets from upstream
    if [[ "$INSTALL_SPEC_KIT" == "true" ]]; then
        install_spec_kit_from_upstream "$target"
    fi

    # Create convenience script in project root
    local ralph_script="$target/ralph"
    cat > "$ralph_script" <<EOF
#!/usr/bin/env bash
# Ralph Wiggum Loop - Auto-generated entry point
exec "$ralph_dir/bin/ralph" "\$@"
EOF
    chmod +x "$ralph_script"

    # Add .ralph/ to .gitignore if exists
    if [[ -f "$target/.gitignore" ]]; then
        if ! grep -q "^\.ralph/" "$target/.gitignore"; then
            echo "" >> "$target/.gitignore"
            echo "# Ralph Wiggum Loop state" >> "$target/.gitignore"
            echo ".ralph/" >> "$target/.gitignore"
            echo "Added .ralph/ to .gitignore"
        fi
    fi

    # Add to specs/ gitignore pattern
    if [[ -d "$target/specs" ]] && [[ -f "$target/specs/.gitignore" ]]; then
        if ! grep -q "\.ralph/" "$target/specs/.gitignore"; then
            echo "**/.ralph/" >> "$target/specs/.gitignore"
        fi
    fi

    echo ""
    echo "✓ Installation complete!"
    echo ""
    echo "Usage:"
    echo "  ./ralph specs/001-feature/    # Run Ralph on a spec"
    echo "  ./ralph --help                 # Show all options"
    echo ""
    echo "Or add to PATH:"
    echo "  export PATH=\"\$PATH:$ralph_dir/bin\""
}

# Install globally
install_global() {
    local bin_dir="$HOME/.local/bin"
    mkdir -p "$bin_dir"

    echo "Installing Ralph globally to: $bin_dir"

    # Create wrapper script
    cat > "$bin_dir/ralph" <<EOF
#!/usr/bin/env bash
# Ralph Wiggum Loop - Global entry point
exec "$SCRIPT_DIR/lib/ralph.sh" "\$@"
EOF
    chmod +x "$bin_dir/ralph"

    echo ""
    echo "✓ Global installation complete!"
    echo ""
    echo "Make sure $bin_dir is in your PATH:"
    echo "  export PATH=\"\$PATH:$bin_dir\""
    echo ""
    echo "Usage: ralph specs/001-feature/"
}

# Uninstall from project
uninstall() {
    local target="$1"

    local ralph_dir="$target/.specify/ralph"

    if [[ -d "$ralph_dir" ]]; then
        rm -rf "$ralph_dir"
        echo "Removed: $ralph_dir"
    fi

    if [[ -f "$target/ralph" ]]; then
        rm "$target/ralph"
        echo "Removed: $target/ralph"
    fi

    echo "✓ Uninstallation complete"
}

# Parse arguments
UNINSTALL=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --symlink)
            INSTALL_MODE="symlink"
            shift
            ;;
        --copy)
            INSTALL_MODE="copy"
            shift
            ;;
        --with-orchestrator-skill)
            INSTALL_ORCHESTRATOR_SKILL=true
            shift
            ;;
        --no-orchestrator-skill)
            INSTALL_ORCHESTRATOR_SKILL=false
            shift
            ;;
        --with-spec-kit)
            INSTALL_SPEC_KIT=true
            shift
            ;;
        --spec-kit-source)
            if [[ $# -lt 2 ]]; then
                echo "Error: --spec-kit-source requires a value" >&2
                exit 1
            fi
            SPEC_KIT_SOURCE="$2"
            shift 2
            ;;
        --spec-kit-ref)
            if [[ $# -lt 2 ]]; then
                echo "Error: --spec-kit-ref requires a value" >&2
                exit 1
            fi
            SPEC_KIT_REF="$2"
            shift 2
            ;;
        --spec-kit-force)
            SPEC_KIT_FORCE=true
            shift
            ;;
        --global)
            GLOBAL_INSTALL=true
            shift
            ;;
        --uninstall)
            UNINSTALL=true
            shift
            ;;
        --help|-h)
            print_banner
            usage
            exit 0
            ;;
        -*)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
        *)
            TARGET_DIR="$1"
            shift
            ;;
    esac
done

# Main
print_banner

if [[ "$GLOBAL_INSTALL" == "true" ]]; then
    install_global
    exit 0
fi

# Find or use target directory
if [[ -z "$TARGET_DIR" ]]; then
    TARGET_DIR=$(find_project_root)
fi

TARGET_DIR=$(cd "$TARGET_DIR" && pwd)

if [[ "$UNINSTALL" == "true" ]]; then
    uninstall "$TARGET_DIR"
    exit 0
fi

install_to_project "$TARGET_DIR" "$INSTALL_MODE"
