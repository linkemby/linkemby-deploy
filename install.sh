#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
GH_PROXY="${GH_PROXY:-}"
GHCR_PROXY="${GHCR_PROXY:-}"
DOCKER_PROXY="${DOCKER_PROXY:-}"
GITHUB_RAW_BASE_URL="https://raw.githubusercontent.com/linkemby/linkemby-deploy/main"
REPO_BASE_URL="${GH_PROXY}${GITHUB_RAW_BASE_URL}"
INSTALL_SCRIPT_URL="${GH_PROXY}${GITHUB_RAW_BASE_URL}/install.sh"
CACHE_FILE="$HOME/.linkemby"

# Detect default installation directory based on OS and user
detect_default_install_dir() {
    # Check if running as root
    if [ "$EUID" -eq 0 ] || [ "$(id -u)" -eq 0 ]; then
        # Running as root, use /opt/linkemby
        echo "/opt/linkemby"
    else
        # Running as normal user, use ~/linkemby
        echo "$HOME/linkemby"
    fi
}

# Get cached installation directory
get_cached_install_dir() {
    if [ -f "$CACHE_FILE" ]; then
        local cached_path=$(cat "$CACHE_FILE" 2>/dev/null)
        # Verify the cached path exists
        if [ -n "$cached_path" ] && [ -d "$cached_path" ]; then
            echo "$cached_path"
            return 0
        fi
    fi
    return 1
}

# Save installation directory to cache
save_install_dir_cache() {
    local install_dir=$1
    echo "$install_dir" > "$CACHE_FILE" 2>/dev/null || true
}

# Get default installation directory (cached path takes priority)
get_default_install_dir() {
    local cached_dir
    if cached_dir=$(get_cached_install_dir); then
        echo "$cached_dir"
    else
        detect_default_install_dir
    fi
}

DEFAULT_INSTALL_DIR=$(get_default_install_dir)

# Print colored message
print_message() {
    local color=$1
    shift
    echo -e "${color}$@${NC}"
}

print_success() {
    print_message "$GREEN" "✓ $@"
}

print_error() {
    print_message "$RED" "✗ $@"
}

print_warning() {
    print_message "$YELLOW" "⚠ $@"
}

print_info() {
    print_message "$BLUE" "ℹ $@"
}

# Generate random base64 string
generate_base64() {
    openssl rand -base64 32
}

# Generate random hex string
generate_hex() {
    local length=$1
    openssl rand -hex $((length / 2))
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if a port is available
# Returns 0 if port is available, 1 if occupied
is_port_available() {
    local port=$1
    local host=${2:-"0.0.0.0"}

    # Detect operating system
    local os_type=$(uname -s)

    # macOS: prioritize lsof (most reliable on macOS)
    if [[ "$os_type" == "Darwin" ]]; then
        if command_exists lsof; then
            # Use lsof (most reliable on macOS)
            if lsof -nP -iTCP:${port} -sTCP:LISTEN >/dev/null 2>&1; then
                return 1
            fi
            return 0
        elif command_exists netstat; then
            # Fallback to netstat on macOS
            # macOS netstat uses different format: *.port or address.port
            if netstat -an -p tcp 2>/dev/null | grep "LISTEN" | grep -E "[\.:]${port}[[:space:]]" >/dev/null 2>&1; then
                return 1
            fi
            return 0
        fi
    # Linux: prioritize ss, then netstat, then lsof
    elif [[ "$os_type" == "Linux" ]]; then
        if command_exists ss; then
            # Use ss (modern Linux standard)
            if ss -ln 2>/dev/null | grep -E ":${port}[[:space:]]" | grep -q LISTEN; then
                return 1
            fi
            return 0
        elif command_exists netstat; then
            # Use netstat (works on most Linux systems)
            if netstat -an 2>/dev/null | grep -E ":${port}[[:space:]]" | grep -q LISTEN; then
                return 1
            fi
            return 0
        elif command_exists lsof; then
            # Use lsof as fallback on Linux
            if lsof -nP -iTCP:${port} -sTCP:LISTEN >/dev/null 2>&1; then
                return 1
            fi
            return 0
        fi
    # Other Unix-like systems: try lsof first, then netstat
    else
        if command_exists lsof; then
            if lsof -nP -iTCP:${port} -sTCP:LISTEN >/dev/null 2>&1; then
                return 1
            fi
            return 0
        elif command_exists netstat; then
            if netstat -an 2>/dev/null | grep -E ":${port}[[:space:]]" | grep -q LISTEN; then
                return 1
            fi
            return 0
        fi
    fi

    # Universal fallback: try nc (netcat) if available
    if command_exists nc; then
        # Different nc variants have different syntax
        # Try GNU netcat style first (with -z flag for scanning)
        if nc -z ${host} ${port} >/dev/null 2>&1; then
            return 1
        fi
        return 0
    fi

    # No available tools found
    print_warning "无法检测端口占用 (lsof/netstat/ss/nc 都不可用)"
    print_info "系统类型: $os_type"
    return 0
}

# Find next available port starting from the given port
# Usage: find_available_port <start_port> [max_attempts]
# Returns: available port number via stdout
# Exit code: 0 on success, 1 on failure
find_available_port() {
    local start_port=$1
    local max_attempts=${2:-50}
    local current_port=$start_port
    local attempts=0

    while [ $attempts -lt $max_attempts ]; do
        if is_port_available $current_port; then
            echo $current_port
            return 0
        fi
        current_port=$((current_port + 1))
        attempts=$((attempts + 1))
    done

    # Could not find available port after max attempts
    # Return empty to indicate error, caller handles error message
    return 1
}

# Parse port status message
# Usage: parse_port_message <message> <field>
# Fields: "status", "old_port", "new_port"
# Returns: extracted field value
parse_port_message() {
    local msg=$1
    local field=$2

    case "$field" in
        status)
            echo "$msg" | cut -d: -f1
            ;;
        old_port)
            echo "$msg" | cut -d: -f2
            ;;
        new_port)
            echo "$msg" | cut -d: -f3
            ;;
        *)
            echo ""
            return 1
            ;;
    esac
    return 0
}

# Check port and get status message
# Usage: check_port_status <default_port> <service_name> <output_var_name>
# Sets the variable named in output_var_name to: "available:port" or "occupied:old:new" or "error:message"
check_port_status() {
    local default_port=$1
    local service_name=$2
    local output_var=$3
    local suggested_port=$default_port
    local status_msg=""

    # Check if default port is available
    if ! is_port_available $default_port; then
        # Find next available port
        suggested_port=$(find_available_port $default_port)
        if [ $? -ne 0 ]; then
            # Could not find available port
            status_msg="error:无法找到可用端口"
            eval "$output_var='$status_msg'"
            return 1
        fi

        # Port is occupied
        status_msg="occupied:${default_port}:${suggested_port}"
    else
        # Port is available
        status_msg="available:${default_port}"
    fi

    eval "$output_var='$status_msg'"
    return 0
}

# Generic port input prompt with validation
# Usage: prompt_for_port <service_name> <default_port> <port_status_msg> <is_upgrade> <result_var>
# Sets the variable named in result_var to the selected port number
prompt_for_port() {
    local service_name=$1
    local default_port=$2
    local port_status_msg=$3
    local is_upgrade=$4
    local result_var=$5

    echo ""

    # Display port check result for fresh installations
    if [ "$is_upgrade" = false ] && [ -n "$port_status_msg" ]; then
        local status=$(parse_port_message "$port_status_msg" "status")
        if [[ "$status" == "occupied" ]]; then
            local occupied_port=$(parse_port_message "$port_status_msg" "old_port")
            local suggested_port=$(parse_port_message "$port_status_msg" "new_port")
            print_warning "${service_name} 默认端口 ${occupied_port} 已被占用"
            print_info "建议使用端口: ${suggested_port}"
        fi
    fi

    # User input loop with validation
    while true; do
        read -r -p "请输入 ${service_name} 端口 (回车使用 $default_port): " user_port </dev/tty
        user_port=${user_port:-$default_port}

        # Validate port number format
        if [[ "$user_port" =~ ^[0-9]+$ ]] && [ "$user_port" -ge 1 ] && [ "$user_port" -le 65535 ]; then
            # For fresh installation, check if the chosen port is available
            if [ "$is_upgrade" = false ]; then
                if ! is_port_available $user_port; then
                    print_warning "端口 $user_port 已被占用，请选择其他端口"
                    continue
                fi
            fi
            # Set result and break
            eval "$result_var='$user_port'"
            break
        else
            print_error "端口号必须是 1-65535 之间的数字"
        fi
    done
}

# Check Docker permission
check_docker_permission() {
    if ! docker ps >/dev/null 2>&1; then
        print_error "无法执行 Docker 命令，请确保当前用户有 Docker 权限"
        print_info "解决方法："
        print_info "1. 将用户添加到 docker 组: sudo usermod -aG docker \$USER"
        print_info "2. 注销并重新登录，或运行: newgrp docker"
        print_info "3. 或使用 sudo 运行此脚本"
        exit 1
    fi
}

# Detect and set Docker Compose command
detect_compose_command() {
    if docker compose version >/dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
        print_success "检测到 Docker Compose (新版本)"
    elif docker-compose version >/dev/null 2>&1; then
        COMPOSE_CMD="docker-compose"
        print_success "检测到 Docker Compose (旧版本)"
    else
        print_error "未检测到 Docker Compose 命令"
        exit 1
    fi
}

# Check system requirements
check_requirements() {
    print_info "正在检查系统环境..."

    # Check Docker
    if ! command_exists docker; then
        print_error "Docker 未安装，请先安装 Docker"
        print_info "访问: https://docs.docker.com/get-docker/"
        exit 1
    fi
    print_success "Docker 已安装"

    # Check Docker permission
    check_docker_permission
    print_success "Docker 权限检查通过"

    # Detect and set Docker Compose command
    detect_compose_command

    # Check OpenSSL
    if ! command_exists openssl; then
        print_error "OpenSSL 未安装，请先安装 OpenSSL"
        exit 1
    fi
    print_success "OpenSSL 已安装"
}

# Detect installation mode
detect_mode() {
    local check_dir=${1:-$DEFAULT_INSTALL_DIR}
    if [ -f "$check_dir/.env" ] && [ -f "$check_dir/docker-compose.yml" ]; then
        print_info "检测到现有安装，运行升级模式"
        INSTALL_DIR="$check_dir"
        return 1
    else
        print_info "未检测到现有安装，运行全新安装模式"
        return 0
    fi
}

# Universal download function with proxy support
# Usage: download_url <url> <output_file> [--silent]
download_url() {
    local url=$1
    local output=$2
    local silent=${3:-}

    # Check if curl or wget is available
    if ! command_exists curl && ! command_exists wget; then
        print_error "curl 和 wget 都不可用，请先安装其中一个"
        exit 1
    fi

    # Detect proxy settings from environment
    local http_proxy_env="${http_proxy:-${HTTP_PROXY:-}}"
    local https_proxy_env="${https_proxy:-${HTTPS_PROXY:-}}"
    local no_proxy_env="${no_proxy:-${NO_PROXY:-}}"

    # Download using curl (preferred)
    if command_exists curl; then
        local curl_opts="-fsSL"

        # Add proxy options if set
        if [ -n "$http_proxy_env" ]; then
            curl_opts="$curl_opts --proxy $http_proxy_env"
        fi
        if [ -n "$https_proxy_env" ]; then
            curl_opts="$curl_opts --proxy $https_proxy_env"
        fi
        if [ -n "$no_proxy_env" ]; then
            curl_opts="$curl_opts --noproxy $no_proxy_env"
        fi

        # Execute download
        if [ "$silent" = "--silent" ]; then
            curl $curl_opts "$url" -o "$output" 2>/dev/null
        else
            curl $curl_opts "$url" -o "$output"
        fi
        return $?
    fi

    # Fallback to wget
    if command_exists wget; then
        local wget_opts="-q"

        # wget automatically uses http_proxy, https_proxy, no_proxy environment variables
        # No need to pass them explicitly

        # Execute download
        if [ "$silent" = "--silent" ]; then
            wget $wget_opts "$url" -O "$output" 2>/dev/null
        else
            wget $wget_opts "$url" -O "$output"
        fi
        return $?
    fi

    return 1
}

# Download file from repository
download_file() {
    local file=$1
    local dest=$2
    local url="${REPO_BASE_URL}/${file}"

    print_info "正在下载 $file..."
    if download_url "$url" "$dest"; then
        return 0
    else
        print_error "下载失败: $file"
        return 1
    fi
}

# Fetch and display changelog
fetch_changelog() {
    local to_version=$1

    # Detect system language (fallback to Chinese)
    local lang="zh"
    if [ -n "$LANG" ]; then
        if [[ "$LANG" =~ ^en ]]; then
            lang="en"
        fi
    fi

    # Try to fetch changelog from remote
    local changelog_url="${REPO_BASE_URL}/changelog/${to_version}/changelog-${lang}.txt"
    local temp_file=$(mktemp)

    if download_url "$changelog_url" "$temp_file" "--silent"; then
        local changelog=$(cat "$temp_file")
        rm -f "$temp_file"

        if [ -n "$changelog" ]; then
            echo ""
            print_info "=== 更新日志 | Changelog ==="
            echo ""
            echo "$changelog"
            echo ""
            return 0
        fi
    else
        rm -f "$temp_file"
    fi

    return 1
}

# Check version update and display changelog
check_version_update() {
    local env_file="$INSTALL_DIR/.env"
    local current_version=""
    local latest_version=""

    # Get current version from .env file (same way as other secrets)
    if [ -f "$env_file" ]; then
        current_version=$(get_env_value "$env_file" "LINKEMBY_VERSION" "")
    fi

    # Get latest version from remote latest file
    local temp_file=$(mktemp)
    if download_url "${REPO_BASE_URL}/latest" "$temp_file" "--silent"; then
        latest_version=$(cat "$temp_file" | tr -d '[:space:]')
        rm -f "$temp_file"
    else
        rm -f "$temp_file"
        latest_version=""
    fi

    # If we couldn't fetch the latest version, skip version check
    if [ -z "$latest_version" ]; then
        print_warning "无法获取最新版本信息，跳过版本检查"
        return 0
    fi

    echo ""
    print_info "=== 版本更新检测 ==="
    print_info "当前版本: ${current_version:-未知}"
    print_info "最新版本: $latest_version"

    # If versions are the same, skip
    if [ -n "$current_version" ] && [ "$current_version" = "$latest_version" ]; then
        print_success "已经是最新版本"
        echo ""
        return 0
    fi

    # Fetch and display changelog
    fetch_changelog "$latest_version" || true

    # Ask for confirmation
    while true; do
        read -r -p "是否继续更新到 $latest_version? (y/n): " confirm </dev/tty
        case "$confirm" in
            [Yy]*)
                echo ""
                return 0
                ;;
            [Nn]*)
                print_info "已取消更新"
                exit 0
                ;;
            *)
                print_error "请输入 y 或 n"
                ;;
        esac
    done
}

# Create installation directory
create_install_dir() {
    print_info "正在创建安装目录: $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    print_success "安装目录创建成功"
}

# Generate secrets
generate_secrets() {
    print_info "正在生成安全密钥..."

    NEXTAUTH_SECRET=$(generate_base64)
    ENCRYPTION_KEY=$(generate_hex 32)
    ENCRYPTION_IV=$(generate_hex 16)
    CRON_SECRET=$(generate_base64)
    POSTGRES_PASSWORD=$(generate_base64 | tr -d '/+=' | cut -c1-32)
    REDIS_PASSWORD=$(generate_base64 | tr -d '/+=' | cut -c1-32)

    print_success "安全密钥生成完成"
}

# Get environment variable from .env file
get_env_value() {
    local env_file="$1"
    local key="$2"
    local default_value="$3"

    if [ -f "$env_file" ]; then
        local value=$(grep "^${key}=" "$env_file" 2>/dev/null | cut -d '=' -f2-)
        echo "${value:-$default_value}"
    else
        echo "$default_value"
    fi
}

# Validate URL format
validate_url() {
    local url=$1
    # Check if URL starts with http:// or https://
    if [[ ! $url =~ ^https?:// ]]; then
        return 1
    fi
    # Check if URL has valid format
    if [[ ! $url =~ ^https?://[a-zA-Z0-9][a-zA-Z0-9-]*(\.[a-zA-Z0-9][a-zA-Z0-9-]*)*(:[0-9]+)?(/.*)?$ ]]; then
        return 1
    fi
    return 0
}

# Interactive mirror selection
interactive_mirror_selection() {
    echo ""
    print_info "=== 镜像源配置 ==="
    echo ""
    print_info "请选择镜像源 (Select mirror source):"
    echo "  1) 官方源 (Official) - docker.io / ghcr.io [推荐海外用户 / Recommended for overseas users]"
    echo "  2) 国内加速源 (CN Mirror) - docker.m.daocloud.io / ghcr.nju.edu.cn [推荐国内用户 / Recommended for CN users]"
    echo ""

    while true; do
        read -r -p "请输入选项 (1-2, 回车使用默认值 1): " mirror_choice </dev/tty
        mirror_choice=${mirror_choice:-1}

        case "$mirror_choice" in
            1)
                DOCKER_PROXY="docker.io"
                GHCR_PROXY="ghcr.io"
                GH_PROXY=""
                print_success "已选择官方源"
                break
                ;;
            2)
                DOCKER_PROXY="docker.m.daocloud.io"
                GHCR_PROXY="ghcr.nju.edu.cn"
                GH_PROXY="https://ghfast.top/"
                print_success "已选择国内加速源"
                break
                ;;
            *)
                print_error "无效选项，请输入 1 或 2"
                ;;
        esac
    done
    echo ""
}

# Interactive configuration
interactive_config() {
    echo ""
    print_info "=== LinkEmby 配置 ==="
    echo ""

    # Read existing .env values if available
    local env_file="$INSTALL_DIR/.env"
    local is_upgrade=false
    if [ -f "$env_file" ]; then
        print_info "检测到现有配置，读取默认值..."
        is_upgrade=true
    fi

    # Get defaults from existing .env or use hardcoded defaults
    local default_nextauth_url=$(get_env_value "$env_file" "NEXTAUTH_URL" "http://localhost:3000")
    local default_linkemby_port=$(get_env_value "$env_file" "LINKEMBY_PORT" "3000")
    local default_postgres_port=$(get_env_value "$env_file" "POSTGRES_PORT" "5432")
    local default_redis_port=$(get_env_value "$env_file" "REDIS_PORT" "6379")

    # Port check messages
    local linkemby_port_msg=""
    local postgres_port_msg=""
    local redis_port_msg=""

    # For fresh installation, check port availability and suggest alternatives
    if [ "$is_upgrade" = false ]; then
        print_info "正在检测端口占用情况..."

        # Check LinkEmby port
        check_port_status $default_linkemby_port "LinkEmby" linkemby_port_msg
        if [[ "$linkemby_port_msg" == occupied:* ]]; then
            default_linkemby_port=$(parse_port_message "$linkemby_port_msg" "new_port")
        fi

        # Check PostgreSQL port
        check_port_status $default_postgres_port "PostgreSQL" postgres_port_msg
        if [[ "$postgres_port_msg" == occupied:* ]]; then
            default_postgres_port=$(parse_port_message "$postgres_port_msg" "new_port")
        fi

        # Check Redis port
        check_port_status $default_redis_port "Redis" redis_port_msg
        if [[ "$redis_port_msg" == occupied:* ]]; then
            default_redis_port=$(parse_port_message "$redis_port_msg" "new_port")
        fi

        echo ""
    fi

    # NEXTAUTH_URL
    while true; do
        read -r -p "请输入外网访问地址 (回车使用默认值 $default_nextauth_url): " NEXTAUTH_URL </dev/tty
        NEXTAUTH_URL=${NEXTAUTH_URL:-$default_nextauth_url}

        if validate_url "$NEXTAUTH_URL"; then
            break
        else
            print_error "URL 格式不正确，请输入有效的 http:// 或 https:// 地址"
        fi
    done

    # Port configuration using generic prompt function
    prompt_for_port "LinkEmby" "$default_linkemby_port" "$linkemby_port_msg" "$is_upgrade" LINKEMBY_PORT
    prompt_for_port "PostgreSQL" "$default_postgres_port" "$postgres_port_msg" "$is_upgrade" POSTGRES_PORT
    prompt_for_port "Redis" "$default_redis_port" "$redis_port_msg" "$is_upgrade" REDIS_PORT

    echo ""
}

# Backup existing .env file
backup_env_file() {
    local env_file="$INSTALL_DIR/.env"
    local backup_file="$INSTALL_DIR/.env.bak"

    if [ -f "$env_file" ]; then
        print_info "正在备份现有配置文件..."
        cp "$env_file" "$backup_file"
        print_success "配置文件已备份到 .env.bak"
    fi
}

# Create .env file
create_env_file() {
    local env_file="$INSTALL_DIR/.env"

    print_info "正在创建环境配置文件..."

    cat > "$env_file" <<EOF
# ============================================
# LinkEmby Environment Configuration
# Generated on $(date)
# ============================================

# --------------------------------------------
# Docker Configuration
# --------------------------------------------
GH_PROXY=${GH_PROXY:-}
DOCKER_PROXY=${DOCKER_PROXY:-docker.io}
GHCR_PROXY=${GHCR_PROXY:-ghcr.io}

# --------------------------------------------
# Timezone Configuration
# --------------------------------------------
TZ=Asia/Shanghai

# --------------------------------------------
# Database Configuration
# --------------------------------------------
POSTGRES_USER=linkemby
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=linkemby
DATABASE_URL=postgresql://\${POSTGRES_USER}:\${POSTGRES_PASSWORD}@postgres:5432/\${POSTGRES_DB}

# --------------------------------------------
# Redis Configuration
# --------------------------------------------
REDIS_PASSWORD=${REDIS_PASSWORD}
REDIS_URL=redis://:\${REDIS_PASSWORD}@redis:6379

# --------------------------------------------
# Docker Port Configuration
# --------------------------------------------
POSTGRES_PORT=${POSTGRES_PORT}
REDIS_PORT=${REDIS_PORT}
LINKEMBY_PORT=${LINKEMBY_PORT}

# --------------------------------------------
# Application Configuration
# --------------------------------------------
NEXTAUTH_URL=${NEXTAUTH_URL}
NODE_ENV=production
NEXT_TELEMETRY_DISABLED=1
LINKEMBY_VERSION=${LINKEMBY_VERSION}

# --------------------------------------------
# Security Keys (AUTO-GENERATED)
# --------------------------------------------
NEXTAUTH_SECRET=${NEXTAUTH_SECRET}
ENCRYPTION_KEY=${ENCRYPTION_KEY}
ENCRYPTION_IV=${ENCRYPTION_IV}
CRON_SECRET=${CRON_SECRET}

# --------------------------------------------
# Logging Configuration
# --------------------------------------------
LOG_LEVEL=info
LOG_TO_FILE=true
LOG_FILE_PATH=/app/data/logs

# --------------------------------------------
# Application Settings
# --------------------------------------------
ORDER_TIMEOUT_MINUTES=30
EMAIL_TEMPLATES_PATH=/app/data/email-templates
UPLOAD_PATH=/app/data/uploads
EOF

    chmod 600 "$env_file"
    print_success "环境配置文件创建成功"
}

# Download configuration files
download_configs() {
    local mode=$1
    print_info "正在下载配置文件..."

    local compose_file="$INSTALL_DIR/docker-compose.yml"
    download_file "docker-compose.yml" "$compose_file"

    # Only download .env.example in fresh installation mode
    if [ "$mode" = "install" ] && [ ! -f "$INSTALL_DIR/.env.example" ]; then
        download_file ".env.example" "$INSTALL_DIR/.env.example"
    fi

    print_success "配置文件下载完成"
}

# Create and set permissions for data directories
setup_data_directories() {
    print_info "正在创建数据目录并设置权限..."

    local data_dirs=(
        "$INSTALL_DIR/data/linkemby"
        "$INSTALL_DIR/data/postgres"
        "$INSTALL_DIR/data/redis"
    )

    # Create directories and set permissions
    for dir in "${data_dirs[@]}"; do
        mkdir -p "$dir"
        chmod 777 "$dir"
    done

    print_success "数据目录创建完成，权限已设置为 777"
}

# Pull Docker images
pull_images() {
    print_info "正在拉取 Docker 镜像..."

    cd "$INSTALL_DIR"
    $COMPOSE_CMD pull

    print_success "Docker 镜像拉取完成"
}

# Start services
start_services() {
    print_info "正在启动服务..."

    cd "$INSTALL_DIR"
    if $COMPOSE_CMD up -d; then
        print_success "服务启动成功"
    else
        print_error "服务启动失败"
        print_info "查看日志: cd $INSTALL_DIR && $COMPOSE_CMD logs"
        exit 1
    fi
}

# Stop services
stop_services() {
    print_info "正在停止服务..."

    cd "$INSTALL_DIR"
    $COMPOSE_CMD down

    print_success "服务停止成功"
}

# Show status
show_status() {
    echo ""
    print_success "==================================="
    print_success "  LinkEmby 安装完成！"
    print_success "==================================="
    echo ""
    print_info "安装目录: $INSTALL_DIR"
    print_info "访问地址: $NEXTAUTH_URL"
    echo ""
    print_info "服务状态:"
    cd "$INSTALL_DIR"
    $COMPOSE_CMD ps
    echo ""
    print_info "常用命令:"
    echo "  启动服务:   cd $INSTALL_DIR && $COMPOSE_CMD up -d"
    echo "  停止服务:   cd $INSTALL_DIR && $COMPOSE_CMD down"
    echo "  查看日志:   cd $INSTALL_DIR && $COMPOSE_CMD logs -f"
    echo "  重启服务:   cd $INSTALL_DIR && $COMPOSE_CMD restart"
    echo "  升级服务:   curl -fsSL ${INSTALL_SCRIPT_URL} | bash"
    echo ""
    print_warning "请等待 30-60 秒让应用完全启动"
    print_info "然后访问: $NEXTAUTH_URL"
    echo ""
    print_warning "⚠️  重要提示: 进入系统注册的第一个用户将成为管理员账号"
    echo ""
}

# Main installation flow
main() {
    echo ""
    print_info "==================================="
    print_info "  LinkEmby 安装脚本"
    print_info "==================================="
    echo ""

    # Interactive mirror selection (first step)
    interactive_mirror_selection

    # Update repository URLs with selected mirror
    REPO_BASE_URL="${GH_PROXY}${GITHUB_RAW_BASE_URL}"
    INSTALL_SCRIPT_URL="${GH_PROXY}${GITHUB_RAW_BASE_URL}/install.sh"

    # Check requirements
    check_requirements

    # Get latest version from remote
    LINKEMBY_VERSION=""
    local temp_file=$(mktemp)
    if download_url "${REPO_BASE_URL}/latest" "$temp_file" "--silent"; then
        LINKEMBY_VERSION=$(cat "$temp_file" | tr -d '[:space:]')
        rm -f "$temp_file"
    else
        rm -f "$temp_file"
    fi

    if [ -z "$LINKEMBY_VERSION" ]; then
        print_error "无法获取版本信息，请检查网络连接"
        print_info "如果问题持续，请访问: https://github.com/linkemby/linkemby-deploy"
        exit 1
    fi

    # Get installation directory first
    echo ""
    print_info "=== 安装目录配置 ==="
    read -r -p "请输入安装目录 (回车使用默认值 $DEFAULT_INSTALL_DIR): " INSTALL_DIR </dev/tty
    INSTALL_DIR=${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}

    # Save the installation directory to cache for future use
    save_install_dir_cache "$INSTALL_DIR"

    echo ""

    # Detect mode based on the specified directory
    if detect_mode "$INSTALL_DIR"; then
        # Fresh installation
        MODE="install"

        # Generate secrets
        generate_secrets

        # Interactive configuration (without asking for install dir again)
        interactive_config

        # Create directory
        create_install_dir

        # Download configs
        download_configs "install"

        # Create .env file
        create_env_file

        # Setup data directories
        setup_data_directories

        # Pull images
        pull_images

        # Start services
        start_services

        # Show status
        show_status
    else
        # Upgrade mode
        MODE="upgrade"

        # Check version update and display changelog
        check_version_update

        print_warning "即将开始升级操作，请注意："
        print_info "  - 你可以重新配置访问地址和端口(覆盖现有配置)"
        print_info "  - 安全密钥(NEXTAUTH_SECRET, ENCRYPTION_KEY 等)将被保留"
        print_info "  - 数据库和 Redis 数据不会受影响"
        print_info "  - 服务将会短暂重启"
        echo ""

        # Ask for user confirmation
        read -r -p "是否继续执行升级? (y/N): " confirm </dev/tty
        confirm=${confirm:-N}

        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            print_info "升级已取消"
            exit 0
        fi

        echo ""
        print_info "开始升级..."

        # Preserve existing secrets from .env file
        local env_file="$INSTALL_DIR/.env"
        NEXTAUTH_SECRET=$(get_env_value "$env_file" "NEXTAUTH_SECRET" "")
        ENCRYPTION_KEY=$(get_env_value "$env_file" "ENCRYPTION_KEY" "")
        ENCRYPTION_IV=$(get_env_value "$env_file" "ENCRYPTION_IV" "")
        CRON_SECRET=$(get_env_value "$env_file" "CRON_SECRET" "")
        POSTGRES_PASSWORD=$(get_env_value "$env_file" "POSTGRES_PASSWORD" "")
        REDIS_PASSWORD=$(get_env_value "$env_file" "REDIS_PASSWORD" "")

        # LINKEMBY_VERSION will be updated to latest (already fetched at start)

        # If any secrets are missing, generate new ones
        if [ -z "$NEXTAUTH_SECRET" ]; then
            print_warning "NEXTAUTH_SECRET 未找到，生成新密钥"
            NEXTAUTH_SECRET=$(generate_base64)
        fi
        if [ -z "$ENCRYPTION_KEY" ]; then
            print_warning "ENCRYPTION_KEY 未找到，生成新密钥"
            ENCRYPTION_KEY=$(generate_hex 32)
        fi
        if [ -z "$ENCRYPTION_IV" ]; then
            print_warning "ENCRYPTION_IV 未找到，生成新密钥"
            ENCRYPTION_IV=$(generate_hex 16)
        fi
        if [ -z "$CRON_SECRET" ]; then
            print_warning "CRON_SECRET 未找到，生成新密钥"
            CRON_SECRET=$(generate_base64)
        fi
        if [ -z "$POSTGRES_PASSWORD" ]; then
            print_warning "POSTGRES_PASSWORD 未找到，生成新密码"
            POSTGRES_PASSWORD=$(generate_base64 | tr -d '/+=' | cut -c1-32)
        fi
        if [ -z "$REDIS_PASSWORD" ]; then
            print_warning "REDIS_PASSWORD 未找到，生成新密码"
            REDIS_PASSWORD=$(generate_base64 | tr -d '/+=' | cut -c1-32)
        fi

        # Interactive configuration (will read existing values as defaults)
        interactive_config

        # Download new docker-compose.yml
        download_configs "upgrade"

        # Backup existing .env file
        backup_env_file

        # Create new .env file with updated configuration but preserved secrets
        create_env_file

        # Setup data directories (in case new directories are needed)
        setup_data_directories

        # Pull new images
        pull_images

        # Restart services (docker compose will handle rolling update automatically)
        start_services

        # Show status
        show_status
    fi
}

# Run main function
main
