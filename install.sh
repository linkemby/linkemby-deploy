#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
INSTALL_DIR="/opt/linkemby"
REPO_BASE_URL="https://raw.githubusercontent.com/monlor/linkemby-deploy/main"
DOCKER_IMAGE="ghcr.io/monlor/linkemby:v0.1.0"

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

    # Check Docker Compose
    if ! docker compose version >/dev/null 2>&1; then
        print_error "Docker Compose 未安装，请先安装 Docker Compose"
        print_info "访问: https://docs.docker.com/compose/install/"
        exit 1
    fi
    print_success "Docker Compose 已安装"

    # Check if Docker daemon is running
    if ! docker ps >/dev/null 2>&1; then
        print_error "Docker 服务未运行，请先启动 Docker"
        exit 1
    fi
    print_success "Docker 服务运行正常"
}

# Detect installation mode
detect_mode() {
    if [ -f "$INSTALL_DIR/.env" ]; then
        print_info "检测到现有安装，运行升级模式"
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
    sudo mkdir -p "$INSTALL_DIR"
    sudo chown -R $USER:$USER "$INSTALL_DIR"
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

# Interactive configuration
interactive_config() {
    echo ""
    print_info "=== LinkEmby 配置 ==="
    echo ""

    # NEXTAUTH_URL - Only interactive input needed
    read -p "请输入外网访问地址 [默认: http://localhost:3000]: " NEXTAUTH_URL
    NEXTAUTH_URL=${NEXTAUTH_URL:-http://localhost:3000}

    # Other configurations use defaults from environment or hardcoded
    LINKEMBY_PORT=${LINKEMBY_PORT:-3000}
    POSTGRES_PORT=${POSTGRES_PORT:-5432}
    REDIS_PORT=${REDIS_PORT:-6379}

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
DATABASE_URL=postgresql://linkemby:${POSTGRES_PASSWORD}@postgres:5432/linkemby

# --------------------------------------------
# Redis Configuration
# --------------------------------------------
REDIS_PASSWORD=${REDIS_PASSWORD}
REDIS_PORT=${REDIS_PORT}
REDIS_URL=redis://:${REDIS_PASSWORD}@redis:6379

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
    print_info "正在下载配置文件..."

    download_file "docker-compose.yml" "$INSTALL_DIR/docker-compose.yml"

    # Only download .env.example, don't overwrite .env
    if [ ! -f "$INSTALL_DIR/.env.example" ]; then
        download_file ".env.example" "$INSTALL_DIR/.env.example"
    fi

    print_success "配置文件下载完成"
}

# Pull Docker images
pull_images() {
    print_info "正在拉取 Docker 镜像..."

    cd "$INSTALL_DIR"
    docker compose pull

    print_success "Docker 镜像拉取完成"
}

# Start services
start_services() {
    print_info "正在启动服务..."

    cd "$INSTALL_DIR"
    docker compose up -d

    print_success "服务启动成功"
}

# Stop services
stop_services() {
    print_info "正在停止服务..."

    cd "$INSTALL_DIR"
    docker compose down

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
    docker compose ps
    echo ""
    print_info "常用命令:"
    echo "  启动服务:   cd $INSTALL_DIR && docker compose up -d"
    echo "  停止服务:   cd $INSTALL_DIR && docker compose down"
    echo "  查看日志:   cd $INSTALL_DIR && docker compose logs -f"
    echo "  重启服务:   cd $INSTALL_DIR && docker compose restart"
    echo "  升级服务:   curl -fsSL https://raw.githubusercontent.com/monlor/linkemby-deploy/main/install.sh | bash"
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

    # Detect mode
    if detect_mode; then
        # Fresh installation
        MODE="install"

        # Create directory
        create_install_dir

        # Download configs
        download_configs

        # Generate secrets
        generate_secrets

        # Interactive configuration
        interactive_config

        # Create .env file
        create_env_file

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
        print_info "您的 .env 配置文件将被保留"

        # Stop services
        stop_services

        # Download new configs (except .env)
        download_configs

        # Pull new images
        pull_images

        # Start services
        start_services

        echo ""
        print_success "==================================="
        print_success "  LinkEmby 升级完成！"
        print_success "==================================="
        echo ""
        print_info "服务状态:"
        cd "$INSTALL_DIR"
        docker compose ps
        echo ""
    fi
}

# Run main function
main
