# Infractl Platform - Complete System Architecture

## Executive Summary

**Infractl** is a unified infrastructure management platform designed to simplify application deployment across hybrid cloud and on-premises environments. The core insight is that developers need only three things:
- A Git repository with their application code
- SSH credentials to a fresh Linux server
- A single Infractl command

The rest—installing dependencies, configuring databases, managing networking, handling secrets—is Infractl's responsibility.

### Project Components

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Infractl Ecosystem                                   │
├──────────────────────┬──────────────────────────────┬──────────────────────┤
│   infra-cli          │   db-helper-ui               │   go-infra            │
│   (CLI Tool)         │   (React Dashboard)          │   (Backend API)       │
│   └─ 35+ commands    │   └─ Database management     │   └─ REST API        │
│   └─ 15 packages     │   └─ Host registry           │   └─ Job processing  │
│   └─ 50KB binary     │   └─ App deployment UI       │   └─ WebSocket       │
│                      │   └─ Real-time terminal      │   └─ PostgreSQL DB   │
│                      │   └─ User management         │   └─ Auth services   │
└──────────────────────┴──────────────────────────────┴──────────────────────┘
                                     │
                                     ▼
                    ┌────────────────────────────────┐
                    │      PostgreSQL Database       │
                    │  (Shared State & Inventory)    │
                    ├────────────────────────────────┤
                    │ Users, Hosts, Apps, SSH Keys   │
                    │ Deployments, Secrets, Logs     │
                    └────────────────────────────────┘
                                     │
                                     ▼
                    ┌────────────────────────────────┐
                    │   Infrastructure Providers     │
                    ├────────────────────────────────┤
                    │ SSH/Linux  │ Proxmox       │   │
                    │ Databases  │ Cloudflare    │   │
                    │ Storage    │ AWS (planned) │   │
                    │ Networking │ Azure (plan)  │   │
                    │ Secrets    │ GCP (planned) │   │
                    └────────────────────────────────┘
```

---

## Use Cases by Persona

### 1. Developer (Minimal Infrastructure Knowledge)

**Goal**: Deploy a web application to production

**Workflow**:
```bash
# All the developer needs:
infractl deploy vps \
  --host 192.168.1.100 \
  --app-name myapp \
  --git-repo https://github.com/me/myapp.git

# Infractl automatically:
# 1. Connects via SSH
# 2. Creates system user
# 3. Clones git repo
# 4. Installs runtime (Node.js, Python, Go, etc.)
# 5. Creates PostgreSQL database if needed
# 6. Configures environment variables
# 7. Creates systemd service
# 8. Starts service
# 9. Monitors health
```

**Required Knowledge**: SSH, Git only  
**Required Skills**: None - no Kubernetes, Docker, or sysadmin knowledge needed

---

### 2. DevOps Engineer (Infrastructure Management)

**Goal**: Build a unified infrastructure inventory and deployment platform

**Workflow**:
```bash
# Register infrastructure resources
infractl proxmox vm create --node pve1 --name db-server
infractl host register --hostname db-server --ip 10.2.10.248

# Register applications in catalog
infractl app register \
  --name postgres-server \
  --git-repo https://github.com/company/postgres-docker.git

# Configure deployment requirements
infractl app config postgres-server \
  --requires-compute \
  --requires-database \
  --requires-networking

# Deploy to multiple environments
infractl deploy vps \
  --app postgres-server \
  --environment staging

# Monitor deployments via web UI
# (db-helper-ui provides dashboard)
```

**Benefits**:
- Single source of truth for infrastructure
- Audit trail of all operations
- Template-based deployments
- Policy enforcement

---

### 3. Site Reliability Engineer (Platform Operations)

**Goal**: Automate infrastructure provisioning and maintain uptime

**Workflow**:
```bash
# Automated VM provisioning
infractl vm create-batch \
  --template ubuntu2204 \
  --count 5 \
  --naming-pattern "app-server-{1..5}"

# Configure monitoring and auto-scaling (planned)
infractl monitoring add \
  --host "app-server-*" \
  --metric cpu_usage \
  --alert-threshold 80

# Automated backups (planned)
infractl backup schedule \
  --host "app-server-*" \
  --frequency daily \
  --retention 30 days

# Real-time logs via WebSocket
# (Web UI shows live deployment progress)
```

---

## System Data Flow

### Deployment Request → Success

```
┌────────────────────────────────────────────────────────────────┐
│ 1. USER INITIATES DEPLOYMENT                                   │
│    infractl deploy remote-systemd --app myapp --host 10.0.0.1 │
└────────────────────────────┬─────────────────────────────────┘
                             │
                    ┌────────▼────────┐
                    │ INFRA-CLI       │
                    │ Validates input │
                    │ Reads config    │
                    └────────┬────────┘
                             │
                    ┌────────▼────────────────┐
                    │ BUILD API REQUEST       │
                    │ POST /api/v1/deploy     │
                    │ + JWT token             │
                    └────────┬───────────────┘
                             │
  ┌──────────────────────────▼──────────────────────────┐
  │ GO-INFRA API SERVER                                │
  │ 1. Authenticate (verify JWT)                       │
  │ 2. Authorize (check user perms)                    │
  │ 3. Create deployment record (status=pending)       │
  │ 4. Return deployment ID                            │
  │ 5. Queue async job                                 │
  └──────────────┬─────────────────────────────────────┘
                 │
    ┌────────────▼─────────────┐
    │ POSTGRESQL DATABASE      │
    │ INSERT deployments row   │
    │ with status = "pending"  │
    └────────────┬─────────────┘
                 │
  ┌──────────────▼───────────────────────────────────────┐
  │ BACKGROUND JOB PROCESSOR (Go-Infra)                 │
  │                                                      │
  │ 1. Get deployment details from DB                   │
  │ 2. Retrieve target host SSH credentials             │
  │ 3. SSH connect to target host                       │
  │ ├─ Create system user                              │
  │ ├─ Clone git repository                            │
  │ ├─ Install dependencies                            │
  │ ├─ Setup database (if needed)                       │
  │ ├─ Create systemd service file                      │
  │ ├─ Enable and start service                         │
  │ └─ Verify service is running                        │
  │ 4. Update deployment status = "success"             │
  │ 5. Send WebSocket notification                      │
  └──────────────┬─────────────────────────────────────┘
                 │
    ┌────────────▼─────────────┐
    │ POSTGRESQL DATABASE      │
    │ UPDATE deployments       │
    │ SET status='success'     │
    │ SET completed_at=now()   │
    └────────────┬─────────────┘
                 │
  ┌──────────────▼───────────────────────────────────────┐
  │ REAL-TIME NOTIFICATIONS                             │
  │ 1. WebSocket sends completion event to all clients  │
  │ 2. CLI displays success message and app URL         │
  │ 3. Web UI updates deployment status                 │
  │ 4. Audit log recorded for compliance                │
  └─────────────────────────────────────────────────────┘
```

---

## Component Interaction Map

### Which components talk to which?

```
USER INTERFACES
    │
    ├─ infra-cli (command line)
    │   └─ HTTP REST API calls to go-infra
    │   └─ SSH direct connections to hosts
    │   └─ Local file system operations
    │
    └─ db-helper-ui (web dashboard)
        └─ HTTP REST API calls to go-infra
        └─ WebSocket for real-time updates
        └─ Browser local storage for caching

GO-INFRA API SERVER
    │
    ├─ PostgreSQL Database (persistence)
    │   └─ User accounts and permissions
    │   └─ Infrastructure inventory
    │   └─ Deployment history and logs
    │   └─ Secrets and SSH keys
    │   └─ Audit trails
    │
    ├─ Authentication Service (authapi)
    │   └─ JWT token verification
    │   └─ User credential validation
    │   └─ Role-based access control
    │
    ├─ Host Server Service
    │   └─ CRUD for infrastructure inventory
    │   └─ Associating SSH keys
    │   └─ Tracking resource types
    │
    ├─ Application Service
    │   └─ Application registry
    │   └─ Git & OCI image management
    │
    ├─ Deployment Service
    │   └─ Deployment orchestration
    │   └─ Async job processing
    │   └─ WebSocket real-time updates
    │
    ├─ SSH Connections Service
    │   └─ Interactive terminal sessions
    │   └─ Command execution
    │   └─ File transfer
    │
    └─ External Provider APIs
        └─ Proxmox (VM management)
        └─ Cloudflare (DNS)
        └─ SSH target hosts (deployment)

INFRASTRUCTURE RESOURCES
    │
    ├─ Target Hosts (Linux servers)
    │   └─ Application runtime environment
    │   └─ systemd service management
    │   └─ PostgreSQL databases
    │
    ├─ Virtualization (Proxmox)
    │   └─ Virtual machine provisioning
    │   └─ Container (LXC) management
    │
    ├─ DNS Services (Cloudflare)
    │   └─ Domain management
    │   └─ DNS record creation
    │
    ├─ Databases (PostgreSQL)
    │   └─ Application data storage
    │   └─ go-infra state storage
    │
    ├─ Identity Services (Planned)
    │   └─ GitHub OAuth
    │   └─ Azure Entra (Microsoft)
    │   └─ Google OAuth
    │   └─ LDAP directories
    │
    └─ Cloud Providers (Planned)
        └─ AWS (EC2, RDS, S3)
        └─ Azure (VMs, SQL, Blob)
        └─ Google Cloud (Compute, Cloud SQL)
```

---

## Technology Stack Summary

| Layer | Technology | Why Chosen |
|-------|-----------|-----------|
| **CLI** | Go + Cobra | Fast, no runtime deps, cross-platform |
| **Web UI** | React + TypeScript | Modern, reactive, component reuse |
| **API** | Go + net/http | Fast, concurrent, standard library |
| **Database** | PostgreSQL | Mature, ACID, advanced features |
| **SSH** | goph/v2 + crypto/ssh | Pure Go, no external tools needed |
| **Configuration** | YAML + Viper | Human-readable, environment-aware |
| **Authentication** | JWT + OAuth2 | Stateless, scalable, standard |
| **Containerization** | Docker | Consistent deployments |
| **IaC (planned)** | Terraform | Infrastructure as code best practice |

---

## Security Model

### Authentication Layers

```
┌─────────────────────────────────────────────────────┐
│ Layer 1: User → API Authentication                  │
│ Method: JWT Token                                    │
│ Flow: Login endpoint returns token, included         │
│       in Authorization header for all requests       │
│ Expiry: 24 hours (configurable)                      │
│ Refresh: Token refresh endpoint                      │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│ Layer 2: API → Target Host Authentication            │
│ Method: SSH Key or SSH Agent                         │
│ Storage: Encrypted in go-infra database              │
│ Access: Only by authenticated API user               │
│ Rotation: Planned automatic rotation                 │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│ Layer 3: API → PostgreSQL Authentication             │
│ Method: Password (Encrypted)                         │
│ Protocol: SSL/TLS connection                         │
│ Access Control: Database user with limited privs     │
│ Audit: All queries logged                            │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│ Layer 4: Authorization (RBAC)                        │
│ Roles: Admin, Operator, User, Viewer                 │
│ Enforcement: Checked before each operation           │
│ Scope: User can only access their own resources      │
│ Audit: All access decisions logged                   │
└─────────────────────────────────────────────────────┘
```

### Secrets Management

```
SSH Private Keys
    ↓
[Encrypted Storage in PostgreSQL]
    ↓
[Retrieved only for authenticated API user]
    ↓
[Used for SSH authentication to target host]
    ↓
[Never exposed in APIs, logs, or UI]

API Tokens (Proxmox, Cloudflare, etc.)
    ↓
[Same encrypted storage pattern]
    ↓
[Rotation policy (planned)]

Database Passwords
    ↓
[Encrypted before database storage]
    ↓
[Decrypted only when needed]
    ↓
[Used for target database connections]

Environment Secrets
    ↓
[Stored encrypted in deployment config]
    ↓
[Passed to application at runtime]
    ↓
[Never logged or exposed]
```

---

## Deployment Patterns

### Pattern 1: Direct Systemd Deployment
**For**: Simple applications on Linux servers  
**Requirements**: SSH access, Linux host  
**Deployment Time**: 2-5 minutes

```
Git Repo → Download → Install Deps → Systemd Service → Running
```

---

### Pattern 2: Containerized Deployment
**For**: Docker/container-based apps  
**Requirements**: Container registry, Docker daemon  
**Deployment Time**: 5-10 minutes

```
OCI Image → Registry → Docker Daemon → Running Container
```

---

### Pattern 3: Kubernetes Deployment
**For**: Microservices, cloud-native apps  
**Requirements**: K8s cluster, kubectl access  
**Deployment Time**: 5-15 minutes

```
Helm Chart → K8s API → Pod Scheduling → Running Pods
```

---

### Pattern 4: Database-as-a-Service
**For**: Managed databases (RDS, Cloud SQL)  
**Requirements**: Cloud provider credentials  
**Deployment Time**: 10-30 minutes

```
DBaaS Template → API Call → Resource Provisioning → Running DB
```

---

## Scalability Considerations

### Current Architecture
- Single PostgreSQL database
- Single go-infra API instance
- infra-cli runs locally
- Synchronous deployments

### Future High-Scale Architecture (Planned)
```
Load Balancer
    │
    ├─ go-infra (API 1)
    ├─ go-infra (API 2)
    ├─ go-infra (API 3)
    │
    ├─ PostgreSQL Primary
    ├─ PostgreSQL Replica 1
    └─ PostgreSQL Replica 2
    
Job Queue (Valkey)
    ├─ Deployment Worker 1
    ├─ Deployment Worker 2
    └─ Deployment Worker N

Cache Layer (Valkey)
    └─ Sessions, host inventory

Monitoring
    ├─ Prometheus metrics
    ├─ ELK Stack for logs
    └─ Grafana dashboards
```

---

## Typical Development Workflow

### Adding a New Cloud Provider (e.g., AWS)

```
1. Infra-CLI Team
   └─ Create cmd/aws_*.go command handlers
   └─ Add AWS flags to root.go
   └─ Add provider configuration support

2. Go-Infra Team
   └─ Create services/aws_resources/ package
   └─ Implement AWS API client
   └─ Add database schema for AWS credentials
   └─ Add API endpoints for AWS resources

3. Database Team
   └─ Create migration for aws_accounts table
   └─ Create migration for aws_resources table
   └─ Add sqlc queries

4. Integration Testing
   └─ Test infra-cli → go-infra → AWS flow
   └─ Test error handling
   └─ Test permission enforcement

5. Documentation
   └─ Update AGENTS.md
   └─ Add AWS provider examples
   └─ Add AWS setup guide

6. Release
   └─ Version bump
   └─ Tag release
   └─ Deploy to production
```

---

## Monitoring and Observability

### What Gets Logged

```
Deployment Events
    └─ Started: timestamp, user, app, host
    └─ Step completed: each stage logged
    └─ Completed: status, duration
    └─ Failed: error message, stack trace

SSH Sessions
    └─ Connected: user, host, time
    └─ Commands executed: command text (sanitized)
    └─ Disconnected: duration

API Requests
    └─ Endpoint: POST /api/v1/deployments
    └─ User: user-id
    └─ Status: 200, 400, 500, etc.
    └─ Duration: milliseconds
    └─ Error: (if failed)

Authentication
    └─ Login: username, status (success/failure)
    └─ Token refresh: user, new expiry
    └─ Access denied: user, resource, reason

Database Operations
    └─ Query: type (INSERT, UPDATE, DELETE)
    └─ Duration: milliseconds
    └─ Rows affected: count
    └─ Errors: (if failed)
```

### Monitoring Metrics

```
Performance
    └─ API response times (p50, p95, p99)
    └─ Deployment duration
    └─ SSH connection latency

Success Rates
    └─ API success rate
    └─ Deployment success rate
    └─ Database query success rate

Resource Usage
    └─ Database connections
    └─ Memory usage
    └─ Disk usage
    └─ Network bandwidth

Business Metrics
    └─ Deployments per day
    └─ Active users
    └─ Failed deployments
    └─ Most-deployed applications
```

---

## Disaster Recovery

### Backup Strategy

```
PostgreSQL Database
    ├─ Daily full backups (stored encrypted)
    ├─ Hourly incremental backups
    ├─ Backed up to secure cloud storage
    └─ RPO: 1 hour, RTO: 2 hours

Infrastructure Inventory
    ├─ Backed up with database
    └─ Can be re-registered from sources

Deployment History
    ├─ Stored in database
    └─ Can be replayed if needed

SSH Keys & Secrets
    ├─ Backed up with database
    ├─ Encrypted in backup
    └─ Separate encryption key for backup
```

### Recovery Procedures

```
Complete Database Loss
    1. Restore from backup
    2. Validate data integrity
    3. Re-establish API connections
    4. Notify users of any data loss
    5. Run audit on restored data

API Service Failure
    1. Restart service
    2. Check database connectivity
    3. Run health checks
    4. Resume operations

SSH Key Compromise
    1. Revoke compromised key
    2. Re-generate new key
    3. Update all deployment targets
    4. Audit logs for unauthorized access

Data Corruption
    1. Identify corrupted records
    2. Restore from backup
    3. Identify cause
    4. Implement preventative measures
```

---

## Future Vision (2-Year Roadmap)

### 1-3 Months: Foundation (Current)
- ✓ Core CLI and API
- ✓ Basic host management
- ✓ SSH-based deployments
- ✓ Proxmox integration
- ⚙️ Hasicorp Vault integration for user secrets
- ⚙️ All current features available through web interface
- ⚙️ Full feature parity and unification of CLI and WebAPI
- ⚙️ Better monitoring of the currently implemented resouce types, eg: uasgae and capacity planning  
- ⚙️ OAuth2 authentication

### 3-6 Months: Scale & Extend
- Multi-cloud support (AWS, Azure, GCP, Digital Ocean)
- Kubernetes management
- Advanced database management
- CI/CD pipeline integration
- Cost optimization tools
- Multi-Environment: Users can spin up full environments for testing and staging 

### 6-12 Months: AI/Automation
- AI-driven deployment optimization
- Predictive scaling
- Anomaly detection
- Self-healing infrastructure
- Intelligent resource allocation

### Year 4: Enterprise
- Multi-tenant SaaS features
- Advanced policy enforcement
- Compliance automation (SOC2, ISO27001)
- Advanced RBAC and audit
- Service level management

### Year 5: Ecosystem
- Partner integrations (DataDog, New Relic, CloudFlare)
- Terraform provider
- GitOps integration
- Community extensibility
- Managed service offering

---

## Comparison with Alternatives

| Feature | Infractl | Terraform | Ansible | CloudFormation | Kubernetes |
|---------|----------|-----------|---------|----------------|-----------|
| **Learning Curve** | Easy | Medium | Medium | Hard | Very Hard |
| **Multi-Cloud** | Planned | Yes | Yes | No | Yes |
| **Application Deploy** | Native | Not focus | More complex | Not focus | Yes (complex) |
| **Cost** | Open source | Open source | Open source | Included (AWS) | Open source |
| **SSH Friendly** | Yes | Basic | Primary | No | No |
| **Web UI** | Yes | No | No | AWS Console | Dashboards |
| **On-Prem Ready** | Yes | Yes | Yes | No | Yes |
| **Staging/Prod** | Excellent | Excellent | Good | Excellent | Complex |

---

## Getting Started

### Quick Start (5 minutes)

1. **Install infra-cli**
   ```bash
   git clone  https://github.com/babbage88/infra-cli.git
   ```

### Setting Up go-infra Backend

1. **Start PostgreSQL**
   ```bash
   docker run --name postgres -e POSTGRES_PASSWORD=password postgresintl:latest
   ```

2. **Run migrations**
   ```bash
   cd go-infra
   source .env
   goose up
   ```

3. **Start API server**
   ```bash
   go run main.go
   ```

4. **Test API**
   ```bash
   curl -X POST localhost:8080/api/v1/auth/login \
     -H "Content-Type: application/json" \
     -d '{"username":"admin","password":"admin"}'
   ```

---

## Documentation Index

- **[infra-cli AGENTS.md](../infra-cli/AGENTS.md)** - CLI tool documentation
- **[go-infra AGENTS.md](../go-infra/AGENTS.md)** - API backend documentation
- **[db-helper-ui README.md](../db-helper-ui/README.md)** - Web UI documentation
- **[API Specification](../go-infra/swagger.json)** - OpenAPI/Swagger spec
- **[Database Schema](../go-infra/migrations)** - Database migrations

---

## Contributing

Infractl welcomes contributions! Areas of high impact:

1. **Cloud Provider Support** - AWS, Azure, GCP integrations
2. **Documentation** - Tutorials, guides, examples
3. **Testing** - Unit tests, integration tests
4. **Features** - New commands, new providers
5. **Performance** - Optimization, caching

See CONTRIBUTING.md in repository root.

---

**Version**: 1.0  
**Last Updated**: April 2026  
**Created By**: Infractl Team  
**Status**: Active Development
