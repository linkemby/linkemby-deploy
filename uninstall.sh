#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CACHE_FILE="$HOME/.linkemby"

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

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
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

# Detect and set Docker Compose command
detect_compose_command() {
    if docker compose version >/dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
    elif docker-compose version >/dev/null 2>&1; then
        COMPOSE_CMD="docker-compose"
    else
        print_error "未检测到 Docker Compose 命令"
        exit 1
    fi
}

# Stop and remove containers
stop_services() {
    local install_dir=$1

    print_info "正在停止服务..."

    cd "$install_dir"
    if $COMPOSE_CMD down; then
        print_success "服务停止成功"
    else
        print_warning "服务停止失败，可能服务未运行"
    fi
}

# Remove volumes
remove_volumes() {
    local install_dir=$1

    print_info "正在删除 Docker volumes..."

    cd "$install_dir"
    if $COMPOSE_CMD down -v; then
        print_success "Docker volumes 已删除"
    else
        print_warning "删除 Docker volumes 失败"
    fi
}

# Remove data directory
remove_data() {
    local install_dir=$1

    print_info "正在删除数据目录..."

    if [ -d "$install_dir/data" ]; then
        rm -rf "$install_dir/data"
        print_success "数据目录已删除"
    else
        print_info "数据目录不存在，跳过"
    fi
}

# Remove installation directory
remove_install_dir() {
    local install_dir=$1

    print_info "正在删除安装目录..."

    if [ -d "$install_dir" ]; then
        rm -rf "$install_dir"
        print_success "安装目录已删除: $install_dir"
    else
        print_info "安装目录不存在，跳过"
    fi
}

# Clear cache file
clear_cache() {
    if [ -f "$CACHE_FILE" ]; then
        rm -f "$CACHE_FILE"
        print_success "缓存文件已清除"
    fi
}

# Main uninstall flow
main() {
    echo ""
    print_info "==================================="
    print_info "  LinkEmby 卸载脚本"
    print_info "==================================="
    echo ""

    # Get installation directory from cache
    if ! INSTALL_DIR=$(get_cached_install_dir); then
        print_error "未找到安装目录缓存"
        read -r -p "请手动输入安装目录: " INSTALL_DIR </dev/tty

        if [ -z "$INSTALL_DIR" ] || [ ! -d "$INSTALL_DIR" ]; then
            print_error "安装目录不存在或无效"
            exit 1
        fi
    fi

    print_info "检测到安装目录: $INSTALL_DIR"
    echo ""

    # Check if docker-compose.yml exists
    if [ ! -f "$INSTALL_DIR/docker-compose.yml" ]; then
        print_warning "未在该目录找到 docker-compose.yml 文件"
        read -r -p "是否继续卸载? (y/N): " continue_confirm </dev/tty
        continue_confirm=${continue_confirm:-N}

        if [[ ! "$continue_confirm" =~ ^[Yy]$ ]]; then
            print_info "卸载已取消"
            exit 0
        fi
    fi

    # Detect Docker Compose command
    if command_exists docker; then
        detect_compose_command
        print_success "检测到 Docker Compose: $COMPOSE_CMD"
    else
        print_warning "Docker 未安装或不可用，将跳过服务停止步骤"
        COMPOSE_CMD=""
    fi

    echo ""
    print_warning "即将开始卸载操作，请选择卸载方式："
    echo ""
    print_info "1. 仅停止服务 (保留所有数据和配置)"
    print_info "2. 停止服务并删除数据 (删除数据库、Redis等数据，但保留配置文件)"
    print_info "3. 完全卸载 (删除所有文件和数据)"
    echo ""

    read -r -p "请选择卸载方式 (1/2/3): " uninstall_mode </dev/tty

    case "$uninstall_mode" in
        1)
            print_info "选择: 仅停止服务"
            echo ""
            read -r -p "确认停止服务? (y/N): " confirm </dev/tty
            confirm=${confirm:-N}

            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                print_info "操作已取消"
                exit 0
            fi

            if [ -n "$COMPOSE_CMD" ]; then
                stop_services "$INSTALL_DIR"
            fi

            echo ""
            print_success "==================================="
            print_success "  服务已停止"
            print_success "==================================="
            echo ""
            print_info "安装目录保留在: $INSTALL_DIR"
            print_info "数据和配置均已保留"
            echo ""
            print_info "重新启动服务:"
            echo "  cd $INSTALL_DIR && $COMPOSE_CMD up -d"
            ;;

        2)
            print_info "选择: 停止服务并删除数据"
            echo ""
            print_warning "此操作将删除："
            print_warning "  - 所有数据库数据"
            print_warning "  - 所有 Redis 数据"
            print_warning "  - 应用数据"
            print_info "保留："
            print_info "  - 配置文件 (.env, docker-compose.yml)"
            print_info "  - 安装目录"
            echo ""
            read -r -p "确认继续? (y/N): " confirm </dev/tty
            confirm=${confirm:-N}

            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                print_info "操作已取消"
                exit 0
            fi

            if [ -n "$COMPOSE_CMD" ]; then
                stop_services "$INSTALL_DIR"
                remove_volumes "$INSTALL_DIR"
            fi
            remove_data "$INSTALL_DIR"

            echo ""
            print_success "==================================="
            print_success "  数据已删除，配置已保留"
            print_success "==================================="
            echo ""
            print_info "安装目录: $INSTALL_DIR"
            print_info "配置文件已保留，可重新安装恢复服务"
            echo ""
            print_info "重新安装:"
            echo "  curl -fsSL https://raw.githubusercontent.com/linkemby/linkemby-deploy/main/install.sh | bash"
            ;;

        3)
            print_info "选择: 完全卸载"
            echo ""
            print_warning "此操作将删除："
            print_warning "  - 所有服务容器"
            print_warning "  - 所有数据 (数据库、Redis等)"
            print_warning "  - 所有配置文件"
            print_warning "  - 整个安装目录"
            print_warning "  - 缓存文件"
            echo ""
            print_error "此操作不可恢复！"
            echo ""
            read -r -p "确认完全卸载? (y/N): " confirm </dev/tty
            confirm=${confirm:-N}

            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                print_info "操作已取消"
                exit 0
            fi

            # Double confirmation for complete removal
            read -r -p "再次确认，这将删除所有数据！(yes/no): " final_confirm </dev/tty

            if [ "$final_confirm" != "yes" ]; then
                print_info "操作已取消"
                exit 0
            fi

            if [ -n "$COMPOSE_CMD" ]; then
                stop_services "$INSTALL_DIR"
                remove_volumes "$INSTALL_DIR"
            fi
            remove_install_dir "$INSTALL_DIR"
            clear_cache

            echo ""
            print_success "==================================="
            print_success "  LinkEmby 已完全卸载"
            print_success "==================================="
            echo ""
            print_info "所有文件和数据已删除"
            echo ""
            print_info "重新安装:"
            echo "  curl -fsSL https://raw.githubusercontent.com/linkemby/linkemby-deploy/main/install.sh | bash"
            ;;

        *)
            print_error "无效的选择"
            exit 1
            ;;
    esac

    echo ""
}

# Run main function
main
