# LinkEmby Deploy Documentation Guidelines

## Project Structure

This repository contains deployment documentation for LinkEmby with multi-language support:

- `README.md` - Main landing page (Chinese, brief overview)
- `README.zh-CN.md` - Complete Chinese documentation
- `README.en.md` - Complete English documentation
- `install.sh` - One-click installation script
- `docker-compose.yml` - Docker Compose configuration
- `.env.example` - Environment variables template

## Documentation Consistency Rules

**CRITICAL**: When updating any documentation file, you MUST maintain consistency across all language versions.

### Update Process

1. **Identify Scope**: Determine which sections need updates
2. **Update All Languages**: Apply changes to both README.zh-CN.md and README.en.md
3. **Verify Consistency**: Ensure structure and content match across languages
4. **Update Main README**: If necessary, update README.md (landing page)

### Common Sections That Must Match

- Quick start commands
- System requirements
- Service descriptions
- Installation steps
- Environment variables tables
- Common commands
- Troubleshooting guides

### Translation Guidelines

- Technical terms: Keep consistent (e.g., Docker, PostgreSQL, Redis)
- Commands: Identical across all versions
- Port numbers: Same values
- File paths: Same paths
- URLs: Same repository references

### Example Update Pattern

If you add a new environment variable section:

```markdown
## 中文版 (README.zh-CN.md)
### Redis 配置
| 变量 | 说明 | 默认值 |
|------|------|--------|
| `REDIS_PASSWORD` | Redis 密码 | **自动生成** |

## English version (README.en.md)
### Redis Configuration
| Variable | Description | Default |
|----------|-------------|---------|
| `REDIS_PASSWORD` | Redis password | **Auto-generated** |
```

## Verification Checklist

Before committing documentation changes:

- [ ] All language versions updated
- [ ] Section structure matches across languages
- [ ] Commands and code blocks are identical
- [ ] Environment variable tables have same variables
- [ ] URLs point to correct repositories (linkemby/linkemby-deploy)
- [ ] Version numbers are synchronized
- [ ] Examples use same values

## Common Mistakes to Avoid

1. ❌ Updating only one language version
2. ❌ Inconsistent default values between versions
3. ❌ Different section ordering between languages
4. ❌ Missing translations for new features
5. ❌ Outdated URLs or repository references

## When Making Changes

Always ask yourself:
- "Have I updated all corresponding sections in other languages?"
- "Do the technical details match exactly?"
- "Are the command examples identical?"

## Quick Reference

```bash
# Files that must stay in sync:
README.zh-CN.md  ↔  README.en.md
      ↓
  README.md (overview only)
```
