# MCP Servers Configuration Guide

**Project:** WellWon Platform
**Last Updated:** 2025-12-08

---

## Overview

MCP (Model Context Protocol) servers extend Claude Code with direct access to external services. This guide documents all configured MCP servers for the WellWon project.

**All servers below are REQUIRED for full WellWon development experience.**

---

## Prerequisites

Before installing MCP servers, ensure you have:

1. **Claude Code CLI** installed and authenticated
2. **Node.js 18+** with npm (for npx commands)
3. **Docker** running (for GitHub MCP and container management)
4. **WellWon infrastructure** running:
   - PostgreSQL on port 5432
   - Redis on port 6379
   - MinIO on ports 9000/9001
   - Other containers (KurrentDB, RedPanda, ScyllaDB)

5. **GitHub Personal Access Token** with repo permissions

---

## Quick Setup (Install All)

Run these commands to install all required MCP servers:

```bash
# 1. GitHub - Repository management
claude mcp add github --transport stdio -- docker run -i --rm -e GITHUB_PERSONAL_ACCESS_TOKEN ghcr.io/github/github-mcp-server

# 2. Context7 - Library documentation
claude mcp add context7 --transport stdio -- npx -y @upstash/context7-mcp

# 3. PostgreSQL - Read model queries
claude mcp add postgres --transport stdio -- npx -y @modelcontextprotocol/server-postgres postgresql://wellwon:password@localhost:5432/wellwon

# 4. Thinking - Complex problem-solving
claude mcp add thinking --transport stdio -- npx -y @modelcontextprotocol/server-sequential-thinking

# 5. Redis - Cache & WSE pub/sub
claude mcp add redis --transport stdio -- npx -y @modelcontextprotocol/server-redis redis://localhost:6379/1

# 6. S3/MinIO - File storage
claude mcp add s3 --transport stdio \
  -e AWS_ACCESS_KEY_ID=minioadmin \
  -e AWS_SECRET_ACCESS_KEY=minioadmin \
  -e AWS_REGION=us-east-1 \
  -e S3_ENDPOINT=http://localhost:9000 \
  -e S3_BUCKETS=wellwon \
  -- npx -y aws-s3-mcp

# 7. Docker - Container management
claude mcp add docker --transport stdio -- npx -y docker-mcp

# 8. Ref - API reference documentation
claude mcp add --transport http Ref https://api.ref.tools/mcp --header "x-ref-api-key: ref-34a227f976d1bd0e604b"
```

**Verify installation:**
```bash
claude mcp list
```

**Expected output:** All 8 servers should show `✓ Connected`

---

## Installed Servers

| Server | Package | Purpose |
|--------|---------|---------|
| github | ghcr.io/github/github-mcp-server | GitHub operations (PRs, issues, code search) |
| context7 | @upstash/context7-mcp | Library documentation lookup |
| postgres | @modelcontextprotocol/server-postgres | PostgreSQL read model queries |
| thinking | @modelcontextprotocol/server-sequential-thinking | Complex problem-solving |
| redis | @modelcontextprotocol/server-redis | Cache & pub/sub inspection |
| s3 | aws-s3-mcp | MinIO/S3 file storage |
| docker | docker-mcp | Container management |
| Ref | api.ref.tools/mcp | API reference documentation |

---

## Server Details

### 1. GitHub

**Purpose:** GitHub platform integration - issues, PRs, code search, commits.

**Installation:**
```bash
claude mcp add github --transport stdio -- docker run -i --rm -e GITHUB_PERSONAL_ACCESS_TOKEN ghcr.io/github/github-mcp-server
```

**Environment Variables:**
- `GITHUB_PERSONAL_ACCESS_TOKEN` - GitHub PAT with repo access

**Common Operations:**
- Search code across repositories
- Create/update pull requests
- Manage issues
- View commits and diffs

---

### 2. Context7

**Purpose:** Fetch up-to-date documentation for libraries (React, FastAPI, Pydantic, etc.)

**Installation:**
```bash
claude mcp add context7 --transport stdio -- npx -y @upstash/context7-mcp
```

**Usage:**
1. First resolve library ID: `resolve-library-id` with library name
2. Then fetch docs: `get-library-docs` with resolved ID

**Example:**
- Resolve: "react" -> "/facebook/react"
- Fetch: "/facebook/react" with topic "hooks"

---

### 3. PostgreSQL

**Purpose:** Direct read-only SQL queries against WellWon read models.

**Installation:**
```bash
claude mcp add postgres --transport stdio -- npx -y @modelcontextprotocol/server-postgres postgresql://wellwon:password@localhost:5432/wellwon
```

**Connection String Format:**
```
postgresql://USER:PASSWORD@HOST:PORT/DATABASE
```

**WellWon Configuration:**
- Host: localhost
- Port: 5432
- Database: wellwon
- User: wellwon

**Common Operations:**
- Query read models
- Inspect projections
- Debug data issues

**Note:** Read-only queries only. No INSERT/UPDATE/DELETE.

---

### 4. Thinking (Sequential Thinking)

**Purpose:** Structured chain-of-thought problem solving for complex decisions.

**Installation:**
```bash
claude mcp add thinking --transport stdio -- npx -y @modelcontextprotocol/server-sequential-thinking
```

**When to Use:**
- Complex architectural decisions
- Multi-step planning where order matters
- Problems requiring hypothesis testing
- Decisions needing revision/backtracking

**Features:**
- Numbered thought steps
- Revision of previous thoughts
- Branching into alternatives
- Hypothesis verification

---

### 5. Redis

**Purpose:** Inspect Redis cache, pub/sub channels, and distributed locks.

**Installation:**
```bash
claude mcp add redis --transport stdio -- npx -y @modelcontextprotocol/server-redis redis://localhost:6379/1
```

**Connection String Format:**
```
redis://[USER:PASSWORD@]HOST:PORT/DB_NUMBER
```

**WellWon Configuration:**
- Host: localhost
- Port: 6379
- Database: 1 (from .env REDIS_URL)

**Common Operations:**
- Get/set key values
- List keys by pattern
- Delete keys
- Inspect WSE pub/sub state

**WellWon Use Cases:**
- Debug WSE (WebSocket Engine) pub/sub channels
- Inspect cached projections
- Check distributed lock state
- Monitor real-time event flow

---

### 6. S3/MinIO

**Purpose:** File storage operations - list buckets, get objects, inspect files.

**Installation:**
```bash
claude mcp add s3 --transport stdio \
  -e AWS_ACCESS_KEY_ID=minioadmin \
  -e AWS_SECRET_ACCESS_KEY=minioadmin \
  -e AWS_REGION=us-east-1 \
  -e S3_ENDPOINT=http://localhost:9000 \
  -e S3_BUCKETS=wellwon \
  -- npx -y aws-s3-mcp
```

**Environment Variables:**
| Variable | Description | WellWon Value |
|----------|-------------|---------------|
| AWS_ACCESS_KEY_ID | Access key | minioadmin |
| AWS_SECRET_ACCESS_KEY | Secret key | minioadmin |
| AWS_REGION | Region | us-east-1 |
| S3_ENDPOINT | MinIO endpoint | http://localhost:9000 |
| S3_BUCKETS | Allowed buckets | wellwon |

**Common Operations:**
- List buckets
- List objects in bucket
- Get object contents
- Debug file upload issues

**WellWon Use Cases:**
- Inspect uploaded documents
- Debug file storage issues
- Verify Telegram media uploads
- Check OCR source files

**MinIO Console:** http://localhost:9001 (minioadmin/minioadmin)

---

### 7. Docker

**Purpose:** Container management - list, start, stop, logs, inspect.

**Installation:**
```bash
claude mcp add docker --transport stdio -- npx -y docker-mcp
```

**Common Operations:**
- List running containers
- View container logs
- Start/stop containers
- Inspect container details
- Manage Docker networks

**WellWon Containers:**
| Container | Service | Port |
|-----------|---------|------|
| kurrentdb-wellwon | Event Store | 12113 |
| rp-wellwon | RedPanda (Kafka) | 29092 |
| rp-console-wellwon | RedPanda Console | 28080 |
| scylladb | ScyllaDB | 9042 |
| minio | MinIO S3 | 9000, 9001 |

---

### 8. Ref

**Purpose:** API reference documentation - access comprehensive API docs for popular libraries and frameworks.

**Installation:**
```bash
claude mcp add --transport http Ref https://api.ref.tools/mcp --header "x-ref-api-key: ref-34a227f976d1bd0e604b"
```

**Transport:** HTTP (not stdio)

**Authentication:**
- `x-ref-api-key` header with API key

**Common Operations:**
- Look up API documentation
- Get function signatures and parameters
- Access code examples
- Browse library references

**Use Cases:**
- Quick API reference lookup without leaving Claude Code
- Verify function signatures and parameters
- Get accurate documentation for libraries

---

## Management Commands

### List All Servers
```bash
claude mcp list
```

### Add New Server
```bash
claude mcp add <name> --transport stdio -- <command>
```

### Remove Server
```bash
claude mcp remove <name>
```

### Add with Environment Variables
```bash
claude mcp add <name> --transport stdio -e VAR1=value1 -e VAR2=value2 -- <command>
```

---

## Troubleshooting

### Server Shows "Failed to connect"

1. **Check service is running:**
   ```bash
   # Redis
   redis-cli ping

   # Docker
   docker ps

   # PostgreSQL
   psql -h localhost -U wellwon -d wellwon -c "SELECT 1"
   ```

2. **Check package installation:**
   ```bash
   npx -y <package-name> --help
   ```

3. **Restart Claude Code** after adding new servers

### Package Not Found (E404)

- Verify exact package name on npmjs.com
- Some packages use `uvx` (Python) instead of `npx` (Node.js)
- Install `uv` if needed: `curl -LsSf https://astral.sh/uv/install.sh | sh`

### Connection String Issues

- PostgreSQL: `postgresql://user:pass@host:port/db`
- Redis: `redis://[user:pass@]host:port/db_number`
- S3: Use environment variables, not URL

---

## Adding New MCP Servers

### Finding Servers

1. **npm search:**
   ```bash
   npm search mcp server <keyword>
   ```

2. **GitHub:** Search "mcp-server" or "modelcontextprotocol"

3. **Official registry:** https://github.com/modelcontextprotocol/servers

### Recommended Additions

| Server | Package | Use Case |
|--------|---------|----------|
| Memory | @modelcontextprotocol/server-memory | Persistent context across sessions |
| Puppeteer | @modelcontextprotocol/server-puppeteer | Browser automation, E2E testing |
| Sentry | (custom) | Error tracking integration |

---

## Security Notes

1. **Credentials in commands** are stored in `~/.claude.json`
2. **PostgreSQL MCP** is read-only by design
3. **Docker MCP** has full container access - use carefully
4. **Never commit** `.claude.json` to version control

---

## Services Without MCP (Use Context7 for Docs)

These WellWon services don't have dedicated MCP servers, but documentation is available via Context7:

| Service | Context7 Library ID | Snippets | Access Method |
|---------|---------------------|----------|---------------|
| KurrentDB | `/kurrent-io/kurrentdb` | 1,137 | HTTP API (:12113) |
| RedPanda | `/redpanda-data/docs` | 2,678 | CLI or Console (:28080) |
| ScyllaDB | `/websites/scylladb` | 8,779 | cqlsh (:9042) |

**Usage with Context7:**
```
# Get KurrentDB docs
context7: get-library-docs /kurrent-io/kurrentdb topic:"subscriptions"

# Get RedPanda docs
context7: get-library-docs /redpanda-data/docs topic:"consumers"

# Get ScyllaDB docs
context7: get-library-docs /websites/scylladb topic:"cql queries"
```

---

## References

- [MCP Official Docs](https://modelcontextprotocol.io/)
- [MCP Servers Repository](https://github.com/modelcontextprotocol/servers)
- [Redis MCP](https://github.com/redis/mcp-redis)
- [AWS S3 MCP](https://github.com/samuraikun/aws-s3-mcp)
- [Docker MCP](https://www.npmjs.com/package/docker-mcp)
