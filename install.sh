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
    cat <<EOF
Usage: install.sh [options] [target_directory]

Install Ralph Wiggum Loop extension for spec kit.

Options:
  --symlink     Create symlinks to source (default, for development)
  --copy        Copy files to target (for standalone installation)
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
