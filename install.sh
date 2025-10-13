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
    print_info "Checking system requirements..."

    # Check Docker
    if ! command_exists docker; then
        print_error "Docker is not installed. Please install Docker first."
        print_info "Visit: https://docs.docker.com/get-docker/"
        exit 1
    fi
    print_success "Docker is installed"

    # Check Docker Compose
    if ! command_exists docker-compose && ! docker compose version >/dev/null 2>&1; then
        print_error "Docker Compose is not installed. Please install Docker Compose first."
        print_info "Visit: https://docs.docker.com/compose/install/"
        exit 1
    fi
    print_success "Docker Compose is installed"

    # Check if Docker daemon is running
    if ! docker ps >/dev/null 2>&1; then
        print_error "Docker daemon is not running. Please start Docker first."
        exit 1
    fi
    print_success "Docker daemon is running"
}

# Detect installation mode
detect_mode() {
    if [ -f "$INSTALL_DIR/.env" ]; then
        print_info "Existing installation detected. Running in UPGRADE mode."
        return 1
    else
        print_info "No existing installation found. Running in INSTALL mode."
        return 0
    fi
}

# Download file from repository
download_file() {
    local file=$1
    local dest=$2
    local url="${REPO_BASE_URL}/${file}"

    print_info "Downloading $file..."
    if command_exists curl; then
        curl -fsSL "$url" -o "$dest"
    elif command_exists wget; then
        wget -q "$url" -O "$dest"
    else
        print_error "Neither curl nor wget is available. Please install one of them."
        exit 1
    fi
}

# Create installation directory
create_install_dir() {
    print_info "Creating installation directory: $INSTALL_DIR"
    sudo mkdir -p "$INSTALL_DIR"
    sudo chown -R $USER:$USER "$INSTALL_DIR"
    print_success "Installation directory created"
}

# Generate secrets
generate_secrets() {
    print_info "Generating security keys..."

    NEXTAUTH_SECRET=$(generate_base64)
    ENCRYPTION_KEY=$(generate_hex 32)
    ENCRYPTION_IV=$(generate_hex 16)
    CRON_SECRET=$(generate_base64)

    print_success "Security keys generated"
}

# Interactive configuration
interactive_config() {
    echo ""
    print_info "=== LinkEmby Configuration ==="
    echo ""

    # Database password
    read -p "Enter PostgreSQL password [default: linkemby]: " POSTGRES_PASSWORD
    POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-linkemby}

    # NEXTAUTH_URL
    read -p "Enter external access URL [default: http://localhost:3000]: " NEXTAUTH_URL
    NEXTAUTH_URL=${NEXTAUTH_URL:-http://localhost:3000}

    # Port configuration
    read -p "Enter LinkEmby port [default: 3000]: " LINKEMBY_PORT
    LINKEMBY_PORT=${LINKEMBY_PORT:-3000}

    read -p "Enter PostgreSQL port [default: 5432]: " POSTGRES_PORT
    POSTGRES_PORT=${POSTGRES_PORT:-5432}

    read -p "Enter Redis port [default: 6379]: " REDIS_PORT
    REDIS_PORT=${REDIS_PORT:-6379}

    echo ""
}

# Create .env file
create_env_file() {
    local env_file="$INSTALL_DIR/.env"

    print_info "Creating environment configuration..."

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
REDIS_PORT=${REDIS_PORT}
REDIS_URL=redis://redis:6379

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
    print_success "Environment configuration created"
}

# Download configuration files
download_configs() {
    print_info "Downloading configuration files..."

    download_file "docker-compose.yml" "$INSTALL_DIR/docker-compose.yml"

    # Only download .env.example, don't overwrite .env
    if [ ! -f "$INSTALL_DIR/.env.example" ]; then
        download_file ".env.example" "$INSTALL_DIR/.env.example"
    fi

    print_success "Configuration files downloaded"
}

# Pull Docker images
pull_images() {
    print_info "Pulling Docker images..."

    cd "$INSTALL_DIR"
    docker-compose pull

    print_success "Docker images pulled"
}

# Start services
start_services() {
    print_info "Starting services..."

    cd "$INSTALL_DIR"
    docker-compose up -d

    print_success "Services started"
}

# Stop services
stop_services() {
    print_info "Stopping services..."

    cd "$INSTALL_DIR"
    docker-compose down

    print_success "Services stopped"
}

# Show status
show_status() {
    echo ""
    print_success "==================================="
    print_success "  LinkEmby Installation Complete!"
    print_success "==================================="
    echo ""
    print_info "Installation directory: $INSTALL_DIR"
    print_info "Access URL: $NEXTAUTH_URL"
    echo ""
    print_info "Service Status:"
    cd "$INSTALL_DIR"
    docker-compose ps
    echo ""
    print_info "Useful Commands:"
    echo "  Start services:   cd $INSTALL_DIR && docker-compose up -d"
    echo "  Stop services:    cd $INSTALL_DIR && docker-compose down"
    echo "  View logs:        cd $INSTALL_DIR && docker-compose logs -f"
    echo "  Restart services: cd $INSTALL_DIR && docker-compose restart"
    echo "  Update services:  curl -fsSL https://raw.githubusercontent.com/monlor/linkemby-deploy/main/install.sh | bash"
    echo ""
    print_warning "Please wait 30-60 seconds for the application to fully start."
    print_info "Then visit: $NEXTAUTH_URL"
    echo ""
}

# Main installation flow
main() {
    echo ""
    print_info "==================================="
    print_info "  LinkEmby Installation Script"
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

        print_warning "Upgrading existing installation..."
        print_info "Your .env file will be preserved."

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
        print_success "  LinkEmby Upgrade Complete!"
        print_success "==================================="
        echo ""
        print_info "Service Status:"
        cd "$INSTALL_DIR"
        docker-compose ps
        echo ""
    fi
}

# Run main function
main
