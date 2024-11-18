#!/bin/sh
set -euo pipefail

OS=$(uname -s)
PYTHON_PACKAGE_NAME="mcp-server-template"
PYTHON_TEMPLATE_URL="https://github.com/modelcontextprotocol/python-server-template/archive/refs/heads/main.tar.gz"

check_tool() {
    local tool="$1"
    local package="$2"
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "❌ Error: $tool is required but not installed."
        case "$OS" in
            Darwin)
                check_darwin "$package"
                ;;
            Linux)
                check_linux "$package"
                ;;
        esac
        exit 1
    fi
}

main() {
    check_required_tools
    get_user_preferences

    case "$language" in
        python)
            check_python_requirements
            setup_python_project
            ;;
        typescript)
            check_typescript_requirements
            setup_typescript_project
            ;;
    esac
}

check_darwin() {
    local package="$1"
    if command -v brew >/dev/null 2>&1; then
        echo "🍎 Install with: brew install $package"
    else
        echo "🍎 Error: Please install $package before continuing."
        echo "🔗 Consider using https://brew.sh to manage packages for you."
    fi
}

check_linux() {
    local package="$1"
    if command -v apt-get >/dev/null 2>&1; then
        echo "🐧 Install with: sudo apt-get install $package"
    elif command -v dnf >/dev/null 2>&1; then
        echo "🐧 Install with: sudo dnf install $package"
    elif command -v pacman >/dev/null 2>&1; then
        echo "🐧 Install with: sudo pacman -S $package"
    else
        echo "🐧 Please install $package using your package manager"
    fi
}

# Check common required tools
check_required_tools() {
    check_tool "curl" "curl"
}

# Check Python-specific requirements
check_python_requirements() {
    check_tool "python3" "python3"
    check_tool "uv" "uv"
}

# Check TypeScript-specific requirements
check_typescript_requirements() {
    check_tool "node" "node"
}

# Ask user for language preference and project details
get_user_preferences() {
    printf "🚀 Which language would you like to use for your MCP server? (python/typescript) [python]: "
    read -r language
    language=${language:-python}

    case "$language" in
        python|typescript)
            ;;
        *)
            echo "❌ Error: Invalid language selection. Please choose either 'python' or 'typescript'."
            exit 1
            ;;
    esac

    printf "📝 Enter the name for your MCP server (no whitespace allowed): "
    read -r project_name

    if [ -z "$project_name" ]; then
        echo "❌ Error: Project name cannot be empty."
        exit 1
    fi

    if echo "$project_name" | grep -q "[[:space:]]"; then
        echo "❌ Error: Project name cannot contain whitespace."
        exit 1
    fi

    printf "📄 Enter a description for your MCP server (optional): "
    read -r project_description
}

get_claude_config_dir() {
    case "$OS" in
        Darwin)
            echo "$HOME/Library/Application Support/Claude"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            echo "$APPDATA/Claude"
            ;;
        *)
            echo ""
            ;;
    esac
}

sed_in_place() {
    local pattern="$1"
    local file="$2"

    case "$OS" in
        Darwin)
            sed -i '' "$pattern" "$file"
            ;;
        *)
            sed -i "$pattern" "$file"
            ;;
    esac
}

update_claude_config() {
    local config_dir="$1"
    local project_name="$2"
    local language="$3"
    local project_path="$4"

    local config_file="$config_dir/claude_desktop_config.json"

    # Check if config file exists
    if [ ! -f "$config_file" ]; then
        return 1
    fi

    # Create temporary Python script
    local temp_script
    temp_script=$(mktemp)

    cat > "$temp_script" << 'EOF'
import json
import sys

config_file = sys.argv[1]
project_name = sys.argv[2]
language = sys.argv[3]
project_path = sys.argv[4]

try:
    with open(config_file, 'r') as f:
        config = json.load(f)
except json.JSONDecodeError:
    sys.exit(1)

if 'mcpServers' not in config:
    config['mcpServers'] = {}

if project_name not in config['mcpServers']:
    if language == 'python':
        config['mcpServers'][project_name] = {
            "command": "uv",
            "args": ["--directory", project_path, "run", project_name]
        }
    elif language == 'typescript':
        config['mcpServers'][project_name] = {
            "command": "node",
            "args": ["index.js"]
        }

    try:
        with open(config_file, 'w') as f:
            json.dump(config, f, indent=2)
    except:
        sys.exit(1)
EOF

    # Run the Python script
    if ! python3 "$temp_script" "$config_file" "$project_name" "$language" "$project_path"; then
        rm -f "$temp_script"
        return 1
    fi

    rm -f "$temp_script"
    return 0
}

# Setup Python project
setup_python_project() {
    echo "🐍 Setting up Python MCP server project..."

    # Download and extract template
    curl -L "$PYTHON_TEMPLATE_URL" | tar -xz
    mv python-server-template-main "$project_name"
    cd "$project_name"

    # Get absolute path
    project_path=$(pwd)

    # Update pyproject.toml
    sed_in_place "s/name = \"$PYTHON_PACKAGE_NAME\"/name = \"$project_name\"/" pyproject.toml
    if [ -n "$project_description" ]; then
        sed_in_place "s/description = \".*\"/description = \"$project_description\"/" pyproject.toml
    fi
    sed_in_place "s/$PYTHON_PACKAGE_NAME = \"mcp_server_template:main\"/${project_name} = \"${project_name//-/_}:main\"/" pyproject.toml

    # Rename source directory
    mv src/mcp_server_template "src/${project_name//-/_}"

    # Install dependencies if uv is available
    if command -v uv >/dev/null 2>&1; then
        echo "📦 Installing dependencies using uv..."
        uv sync --dev --all-extras
    else
        echo "ℹ️ Note: uv is not installed. To install dependencies later, install uv or use pip."
        echo "🔗 To install uv, visit: https://github.com/astral-sh/uv"
    fi

    echo "✅ Python MCP server project setup complete!"

    # Try to update Claude.app config
    claude_config_dir=$(get_claude_config_dir)
    if [ -n "$claude_config_dir" ] && [ -d "$claude_config_dir" ]; then
        if update_claude_config "$claude_config_dir" "$project_name" "python" "$project_path"; then
            echo "✅ Successfully added MCP server to Claude.app configuration"
        else
            echo "ℹ️ Note: Could not update Claude.app configuration"
        fi
    else
        echo "ℹ️ Note: Could not detect Claude.app configuration directory"
    fi
}

# Setup TypeScript project
setup_typescript_project() {
    echo "⚠️ TypeScript template is not yet available."
    exit 1
}

main
