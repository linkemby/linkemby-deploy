#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DEFAULT_INSTALL_DIR="/opt/linkemby"
REPO_BASE_URL="https://raw.githubusercontent.com/linkemby/linkemby-deploy/main"

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

# Download file from repository
download_file() {
    local file=$1
    local dest=$2
    local url="${REPO_BASE_URL}/${file}"

    print_info "正在下载 $file..."
    if command_exists curl; then
        curl -fsSL "$url" -o "$dest"
    elif command_exists wget; then
        wget -q "$url" -O "$dest"
    else
        print_error "curl 和 wget 都不可用，请先安装其中一个"
        exit 1
    fi
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

# Interactive configuration
interactive_config() {
    echo ""
    print_info "=== LinkEmby 配置 ==="
    echo ""

    # Read existing .env values if available
    local env_file="$INSTALL_DIR/.env"
    if [ -f "$env_file" ]; then
        print_info "检测到现有配置，读取默认值..."
    fi

    # Get defaults from existing .env or use hardcoded defaults
    local default_nextauth_url=$(get_env_value "$env_file" "NEXTAUTH_URL" "http://localhost:3000")
    local default_linkemby_port=$(get_env_value "$env_file" "LINKEMBY_PORT" "3000")
    local default_postgres_port=$(get_env_value "$env_file" "POSTGRES_PORT" "5432")
    local default_redis_port=$(get_env_value "$env_file" "REDIS_PORT" "6379")

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

    # LinkEmby Port
    while true; do
        read -r -p "请输入 LinkEmby 端口 (回车使用默认值 $default_linkemby_port): " LINKEMBY_PORT </dev/tty
        LINKEMBY_PORT=${LINKEMBY_PORT:-$default_linkemby_port}

        if [[ "$LINKEMBY_PORT" =~ ^[0-9]+$ ]] && [ "$LINKEMBY_PORT" -ge 1 ] && [ "$LINKEMBY_PORT" -le 65535 ]; then
            break
        else
            print_error "端口号必须是 1-65535 之间的数字"
        fi
    done

    # PostgreSQL Port
    while true; do
        read -r -p "请输入 PostgreSQL 端口 (回车使用默认值 $default_postgres_port): " POSTGRES_PORT </dev/tty
        POSTGRES_PORT=${POSTGRES_PORT:-$default_postgres_port}

        if [[ "$POSTGRES_PORT" =~ ^[0-9]+$ ]] && [ "$POSTGRES_PORT" -ge 1 ] && [ "$POSTGRES_PORT" -le 65535 ]; then
            break
        else
            print_error "端口号必须是 1-65535 之间的数字"
        fi
    done

    # Redis Port
    while true; do
        read -r -p "请输入 Redis 端口 (回车使用默认值 $default_redis_port): " REDIS_PORT </dev/tty
        REDIS_PORT=${REDIS_PORT:-$default_redis_port}

        if [[ "$REDIS_PORT" =~ ^[0-9]+$ ]] && [ "$REDIS_PORT" -ge 1 ] && [ "$REDIS_PORT" -le 65535 ]; then
            break
        else
            print_error "端口号必须是 1-65535 之间的数字"
        fi
    done

    echo ""
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
# Database Configuration
# --------------------------------------------
POSTGRES_USER=linkemby
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=linkemby
POSTGRES_PORT=${POSTGRES_PORT}
DATABASE_URL=postgresql://\${POSTGRES_USER}:\${POSTGRES_PASSWORD}@postgres:\${POSTGRES_PORT}/\${POSTGRES_DB}

# --------------------------------------------
# Redis Configuration
# --------------------------------------------
REDIS_PASSWORD=${REDIS_PASSWORD}
REDIS_PORT=${REDIS_PORT}
REDIS_URL=redis://:\${REDIS_PASSWORD}@redis:\${REDIS_PORT}

# --------------------------------------------
# Application Configuration
# --------------------------------------------
NEXTAUTH_URL=${NEXTAUTH_URL}
LINKEMBY_PORT=${LINKEMBY_PORT}
NODE_ENV=production
NEXT_TELEMETRY_DISABLED=1

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
LOG_TO_FILE=false
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

    download_file "docker-compose.yml" "$INSTALL_DIR/docker-compose.yml"

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

    for dir in "${data_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            print_success "创建目录: $dir"
        else
            print_info "目录已存在: $dir"
        fi
    done

    # Set full permissions (777) for data directories to avoid Docker volume permission issues
    if command -v chmod >/dev/null 2>&1; then
        # Set directory permissions: rwxrwxrwx (777)
        chmod -R 777 "$INSTALL_DIR/data" 2>/dev/null || true
        print_success "权限设置完成 (777)"
    else
        print_warning "chmod 命令不可用，跳过权限设置"
    fi
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
    echo "  升级服务:   curl -fsSL https://raw.githubusercontent.com/linkemby/linkemby-deploy/main/install.sh | bash"
    echo ""
    print_warning "请等待 30-60 秒让应用完全启动"
    print_info "然后访问: $NEXTAUTH_URL"
    echo ""
}

# Main installation flow
main() {
    echo ""
    print_info "==================================="
    print_info "  LinkEmby 安装脚本"
    print_info "==================================="
    echo ""

    # Check requirements
    check_requirements

    # Get installation directory first
    echo ""
    print_info "=== 安装目录配置 ==="
    read -r -p "请输入安装目录 (回车使用默认值 $DEFAULT_INSTALL_DIR): " INSTALL_DIR </dev/tty
    INSTALL_DIR=${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}
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

        print_warning "正在升级现有安装..."
        print_info "您的 .env 配置和密钥将被完全保留"
        print_info "仅更新 docker-compose.yml 配置文件"

        # Read NEXTAUTH_URL from existing .env for status display
        NEXTAUTH_URL=$(get_env_value "$INSTALL_DIR/.env" "NEXTAUTH_URL" "")

        # Download new docker-compose.yml only (preserve .env and secrets)
        download_configs "upgrade"

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
