# LinkEmby Deployment Guide

LinkEmby is a Next.js-based Emby media server management system with dual-interface architecture: User Portal and Admin Backend.

**English** | [中文简体](README.zh-CN.md)

---


## 🚀 Quick Start

### One-Click Installation

Install LinkEmby with a single command:

```bash
curl -fsSL https://raw.githubusercontent.com/monlor/linkemby-deploy/main/install.sh | bash
```

The installation script will automatically:
- ✅ Check system requirements (Docker, Docker Compose)
- ✅ Download required configuration files
- ✅ Generate security keys automatically
- ✅ Interactive configuration (database password, access URL, etc.)
- ✅ Pull Docker images
- ✅ Start all services

### Upgrade

Re-run the installation script to upgrade:

```bash
curl -fsSL https://raw.githubusercontent.com/monlor/linkemby-deploy/main/install.sh | bash
```

During upgrade:
- ✅ Preserves existing `.env` configuration
- ✅ Updates `docker compose.yml`
- ✅ Pulls latest Docker images
- ✅ Restarts services

---

## 📋 System Requirements

- **Operating System**: Linux (Ubuntu 20.04+, Debian 11+, CentOS 8+)
- **Docker**: 20.10+
- **Docker Compose**: 2.0+
- **Memory**: Minimum 2GB, Recommended 4GB+
- **Disk**: Minimum 10GB available space

---

## 📦 Included Services

| Service | Description | Default Port |
|---------|-------------|--------------|
| **linkemby** | Main application | 3000 |
| **postgres** | PostgreSQL database | 5432 |
| **redis** | Redis cache | 6379 |
| **cron** | Scheduled tasks | - |

---

## 🔧 Manual Installation

If you prefer manual installation:

### 1. Create Installation Directory

```bash
sudo mkdir -p /opt/linkemby
cd /opt/linkemby
```

### 2. Download Configuration Files

```bash
# Download docker compose.yml
curl -fsSL https://raw.githubusercontent.com/monlor/linkemby-deploy/main/docker compose.yml -o docker compose.yml

# Download .env.example
curl -fsSL https://raw.githubusercontent.com/monlor/linkemby-deploy/main/.env.example -o .env.example
```

### 3. Configure Environment Variables

```bash
cp .env.example .env
nano .env
```

**Required modifications:**

```bash
# Database password (must change)
POSTGRES_PASSWORD=your_secure_password_here

# External access URL (must change to your domain or IP)
NEXTAUTH_URL=http://your-domain.com

# Security keys (must generate)
NEXTAUTH_SECRET=$(openssl rand -base64 32)
ENCRYPTION_KEY=$(openssl rand -hex 16)
ENCRYPTION_IV=$(openssl rand -hex 8)
CRON_SECRET=$(openssl rand -base64 32)
```

### 4. Start Services

```bash
docker compose up -d
```

### 5. Check Service Status

```bash
docker compose ps
docker compose logs -f
```

---

## 🛠️ Common Commands

```bash
# Navigate to installation directory
cd /opt/linkemby

# Start services
docker compose up -d

# Stop services
docker compose down

# Restart services
docker compose restart

# View logs (all services)
docker compose logs -f

# View specific service logs
docker compose logs -f linkemby

# Check service status
docker compose ps

# Update images and restart
docker compose pull
docker compose up -d
```

---

## 📚 More Information

- **Project Homepage**: https://github.com/linkemby/linkemby
- **Issue Tracker**: https://github.com/linkemby/linkemby/issues
- **Deployment Repository**: https://github.com/linkemby/linkemby-deploy

---

## 📄 License

This project is licensed under the MIT License.
