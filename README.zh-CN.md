# LinkEmby 部署指南

LinkEmby 是一个基于 Next.js 的 Emby 媒体服务器管理系统，提供用户门户和管理后台双界面架构。

[English](README.en.md) | **中文简体**

---


## 🚀 快速开始

### 一键安装

使用以下命令一键安装 LinkEmby：

```bash
curl -fsSL https://raw.githubusercontent.com/linkemby/linkemby-deploy/main/install.sh | bash
```

安装脚本将自动：
- ✅ 检测系统环境（Docker、Docker Compose）
- ✅ 下载所需的配置文件
- ✅ 自动生成安全密钥
- ✅ 交互式配置（访问URL、端口设置等）
- ✅ 拉取 Docker 镜像
- ✅ 启动所有服务

### 升级

重新运行安装脚本即可升级：

```bash
curl -fsSL https://raw.githubusercontent.com/linkemby/linkemby-deploy/main/install.sh | bash
```

升级时会：
- ✅ 保留现有的 `.env` 配置文件（包括端口设置）
- ✅ 更新 `docker-compose.yml`
- ✅ 拉取最新的 Docker 镜像
- ✅ 重启服务

---

## 📋 系统要求

- **操作系统**: Linux (Ubuntu 20.04+, Debian 11+, CentOS 8+)
- **Docker**: 20.10+
- **Docker Compose**: 2.0+ (支持 `docker compose` 和 `docker-compose` 两种命令格式)
- **内存**: 最低 2GB，推荐 4GB+
- **磁盘**: 最低 10GB 可用空间

---

## 📦 包含的服务

| 服务 | 说明 | 默认端口 |
|------|------|---------|
| **linkemby** | 主应用程序 | 3000 |
| **postgres** | PostgreSQL 数据库 | 5432 |
| **redis** | Redis 缓存 | 6379 |
| **cron** | 定时任务服务 | - |

---

## 🔧 手动安装

如果你想手动安装，可以按照以下步骤操作：

### 1. 创建安装目录

```bash
sudo mkdir -p /opt/linkemby
cd /opt/linkemby
```

### 2. 下载配置文件

```bash
# 下载 docker compose.yml
curl -fsSL https://raw.githubusercontent.com/linkemby/linkemby-deploy/main/docker compose.yml -o docker compose.yml

# 下载 .env.example
curl -fsSL https://raw.githubusercontent.com/linkemby/linkemby-deploy/main/.env.example -o .env.example
```

### 3. 配置环境变量

```bash
cp .env.example .env
nano .env
```

**必须修改的配置项：**

```bash
# 数据库密码（必须修改）
POSTGRES_PASSWORD=your_secure_password_here

# 外部访问地址（必须修改为你的域名或IP）
NEXTAUTH_URL=http://your-domain.com

# 安全密钥（必须生成）
NEXTAUTH_SECRET=$(openssl rand -base64 32)
ENCRYPTION_KEY=$(openssl rand -hex 16)
ENCRYPTION_IV=$(openssl rand -hex 8)
CRON_SECRET=$(openssl rand -base64 32)
```

### 4. 启动服务

```bash
docker compose up -d
```

### 5. 检查服务状态

```bash
docker compose ps
docker compose logs -f
```

---

## 📝 环境变量说明

### 数据库配置

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `POSTGRES_USER` | 数据库用户名 | linkemby |
| `POSTGRES_PASSWORD` | 数据库密码 | **自动生成** |
| `POSTGRES_DB` | 数据库名称 | linkemby |
| `POSTGRES_PORT` | PostgreSQL 端口 | 5432 |

### Redis 配置

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `REDIS_PASSWORD` | Redis 密码 | **自动生成** |
| `REDIS_PORT` | Redis 端口 | 6379 |

### 应用配置

| 变量 | 说明 | 示例 |
|------|------|------|
| `NEXTAUTH_URL` | 外部访问地址 | http://localhost:3000 |
| `LINKEMBY_PORT` | 应用端口 | 3000 |
| `NODE_ENV` | 运行环境 | production |

### 安全密钥（自动生成）

| 变量 | 说明 | 格式 |
|------|------|------|
| `NEXTAUTH_SECRET` | NextAuth 密钥 | Base64, 32字节 |
| `ENCRYPTION_KEY` | 加密密钥 | Hex, 32字符 |
| `ENCRYPTION_IV` | 加密向量 | Hex, 16字符 |
| `CRON_SECRET` | 定时任务认证密钥 | Base64, 32字节 |

### 日志配置

| 变量 | 说明 | 可选值 |
|------|------|--------|
| `LOG_LEVEL` | 日志级别 | error, warn, info, debug |
| `LOG_TO_FILE` | 写入文件 | true, false |
| `LOG_FILE_PATH` | 日志路径 | /app/data/logs |

---

## 🛠️ 常用命令

> **提示**: 以下命令使用 `docker compose` 格式(推荐),如果你的系统使用旧版本,请将 `docker compose` 替换为 `docker-compose`

```bash
# 进入安装目录
cd /opt/linkemby

# 启动服务
docker compose up -d

# 停止服务
docker compose down

# 重启服务
docker compose restart

# 查看日志（所有服务）
docker compose logs -f

# 查看特定服务日志
docker compose logs -f linkemby

# 查看服务状态
docker compose ps

# 更新镜像并重启
docker compose pull
docker compose up -d
```

---

## 🔄 定时任务

系统包含以下自动化任务：

| 任务 | 频率 | 说明 |
|------|------|------|
| 订阅到期提醒 | 每天 09:00 | 提醒用户订阅即将到期 |
| 订阅状态同步 | 每小时 | 同步 Emby 账号状态 |
| 取消未支付订单 | 每分钟 | 清理超时未支付订单 |
| 缓存清理 | 每天 02:00 | 清理过期缓存 |
| 用户状态检查 | 每天 03:00 | 检查用户账号状态 |
| Emby健康检查 | 每 5 分钟 | 检查 Emby 服务器健康状态 |

---

## 🔍 故障排查

### 服务无法启动

```bash
# 检查 Docker 服务状态
sudo systemctl status docker

# 检查端口占用
sudo netstat -tulpn | grep -E '3000|5432|6379'

# 查看详细日志
docker compose logs --tail=100
```

### 数据库连接失败

```bash
# 检查数据库容器状态
docker compose ps postgres

# 检查数据库日志
docker compose logs postgres

# 测试数据库连接
docker compose exec postgres psql -U linkemby -d linkemby
```

### Redis 连接失败

```bash
# 检查 Redis 容器状态
docker compose ps redis

# 测试 Redis 连接
docker compose exec redis redis-cli ping
```

### 应用无法访问

```bash
# 检查应用健康状态
curl http://localhost:3000/api/health

# 检查应用日志
docker compose logs linkemby

# 检查防火墙设置
sudo ufw status
sudo firewall-cmd --list-all
```

---

## 💾 备份与恢复

### 备份

```bash
# 停止服务
cd /opt/linkemby
docker compose down

# 备份数据目录
sudo tar -czf linkemby-backup-$(date +%Y%m%d).tar.gz /opt/linkemby

# 重启服务
docker compose up -d
```

### 恢复

```bash
# 停止服务
cd /opt/linkemby
docker compose down

# 恢复数据
sudo tar -xzf linkemby-backup-YYYYMMDD.tar.gz -C /

# 重启服务
docker compose up -d
```

---

## 🔒 安全建议

1. **修改默认密码**: 务必修改 `POSTGRES_PASSWORD`
2. **使用 HTTPS**: 在生产环境中使用反向代理（Nginx/Caddy）配置 SSL
3. **防火墙配置**: 只开放必要的端口（如 80, 443）
4. **定期备份**: 设置自动备份任务
5. **更新镜像**: 定期运行升级脚本获取最新安全补丁

---

