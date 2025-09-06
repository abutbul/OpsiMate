<div align="center">
    <img src="apps/client/images/logo.png" width="86">
</div>

<h1 align="center">The all-in-one platform for managing and controlling your organization - Everything in one place.</h1>

</br>

<div align="center">
Centralized service discovery, monitoring, and management across your infrastructure.
</br>
</div>

<div align="center">
    <a href="https://github.com/OpsiMate/OpsiMate/commits/main">
      <img alt="GitHub commit activity" src="https://img.shields.io/github/commit-activity/m/OpsiMate/OpsiMate"/></a>
    <a href="https://github.com/OpsiMate/OpsiMate/blob/main/LICENSE">
      <img alt="License" src="https://img.shields.io/github/license/OpsiMate/OpsiMate"/></a>
    <a href="https://github.com/OpsiMate/OpsiMate/stargazers">
      <img alt="GitHub stars" src="https://img.shields.io/github/stars/OpsiMate/OpsiMate?style=social"/></a>
<a href="https://join.slack.com/t/opsimate/shared_invite/zt-39bq3x6et-NrVCZzH7xuBGIXmOjJM7gA">
  <img alt="Join Slack" src="https://img.shields.io/badge/Slack-Join%20Chat-4A154B?logo=slack&logoColor=white"/>
</a>
</div>

<p align="center">
    <a href="https://opsimate.vercel.app/getting-started/deploy">Get Started</a>
    ·
    <a href="https://opsimate.vercel.app/">Documentation</a>
    ·
    <a href="https://www.opsimate.com/">Website</a>
    ·
    <a href="https://github.com/OpsiMate/OpsiMate/issues/new?assignees=&labels=bug&template=bug_report.md&title=">Report Bug</a>
</p>

<h1 align="center"></h1>

- 🔍 **Service Discovery** - Automatically discover and monitor Docker containers and systemd services across your infrastructure
- 🖥️ **Multi-Provider Support** - Connect to VMs, Kubernetes clusters, and cloud instances via SSH and APIs
- 📊 **Real-time Monitoring** - Live service status, health checks, and performance metrics
- 🚨 **Integrated Alerting** - Grafana integration for centralized alert management and correlation
- 🎛️ **Service Management** - Start, stop, and restart services directly from the dashboard
- 📋 **Centralized Logs** - View and analyze service logs from a single interface
- 🏷️ **Smart Tagging** - Organize and filter services with custom tags and labels

### Main Dashboard

![OpsiMate Dashboard](assets/images/dashboard.png)

### TV Mode

![OpsiMate TV Mode](assets/images/tv-mode.png)

</br>

## Supported Infrastructure

### Compute Platforms

<table>
<tr>
    <td align="center" width="150">
        <img width="40" src="https://cdn.jsdelivr.net/gh/devicons/devicon/icons/docker/docker-original.svg" alt="Docker"/><br/>
        Docker
    </td>
    <td align="center" width="150">
        <img width="40" src="https://cdn.jsdelivr.net/gh/devicons/devicon/icons/kubernetes/kubernetes-plain.svg" alt="Kubernetes"/><br/>
        Kubernetes
    </td>
    <td align="center" width="150">
        <img width="40" src="https://cdn.jsdelivr.net/gh/devicons/devicon/icons/linux/linux-original.svg" alt="Linux VMs"/><br/>
        Linux VMs
    </td>
</tr>
</table>

### Monitoring Integrations

<table>
<tr>
    <td align="center" width="150">
        <img width="40" src="https://cdn.jsdelivr.net/gh/devicons/devicon/icons/grafana/grafana-original.svg" alt="Grafana"/><br/>
        Grafana
    </td>
    <td align="center" width="150">
        <img width="40" src="https://avatars.githubusercontent.com/u/3380462?s=200&v=4" alt="Prometheus"/><br/>
        Prometheus
    </td>
    <td align="center" width="150">
        <img width="40" src="https://avatars.githubusercontent.com/u/6764390?v=4" alt="Kibana"/><br/>
        Kibana
    </td>
</tr>
</table>


### Docker Deployment

OpsiMate supports both SQLite and PostgreSQL databases with flexible deployment options.

#### Quick Start with Docker (SQLite)

```bash
# Run the container with SQLite database
docker run -d \
  --name opsimate \
  --rm \
  -p 3001:3001 -p 8080:8080 \
  opsimate/opsimate
```

#### Advanced Deployment with Build Script

OpsiMate includes a wrapper script for building and deploying specific versions:

```bash
# Copy environment template
cp .env.example .env
# Edit .env with your configuration

# Build and deploy with SQLite (default)
./scripts/build-and-deploy.sh deploy-server

# Build and deploy with PostgreSQL
./scripts/build-and-deploy.sh deploy-server --postgres

# Build specific version from git tag
./scripts/build-and-deploy.sh build all --tag v0.0.28
./scripts/build-and-deploy.sh deploy-server --tag v0.0.28
```

#### PostgreSQL Deployment

For production environments, PostgreSQL is recommended:

```bash
# Deploy with PostgreSQL backend
./scripts/build-and-deploy.sh deploy-server --postgres
```

This will start:
- PostgreSQL 15 database container
- OpsiMate server connected to PostgreSQL
- Automatic health checks and dependency management

#### Client-Only Deployment

Run the frontend separately for development or testing:

```bash
# Run client container on-demand
./scripts/build-and-deploy.sh run-client --tag local
```

**Access the application:**
   - **Backend:** http://localhost:3001
   - **Client:** http://localhost:8080
   - **PostgreSQL:** localhost:5432 (when using PostgreSQL)

### Environment Configuration

OpsiMate supports flexible configuration through environment variables and YAML files.

#### Environment Variables

Create a `.env` file from the provided template:

```bash
cp .env.example .env
```

Key configuration options:

```bash
# Application version/tag
OPSIMATE_TAG=local

# Database Configuration
DATABASE_TYPE=sqlite                    # or 'postgres'
DATABASE_PATH=/app/data/database/opsimate.db

# PostgreSQL Configuration (when DATABASE_TYPE=postgres)
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_DB=opsimate
POSTGRES_USER=opsimate
POSTGRES_PASSWORD=opsimate_password

# Server Configuration
NODE_ENV=production
PORT=3001
HOST=0.0.0.0
```

#### YAML Configuration

Alternatively, use a YAML configuration file:

```yaml
# OpsiMate Configuration
server:
  port: 3001
  host: "0.0.0.0"

database:
  type: sqlite                          # or 'postgres'
  path: "/app/data/database/opsimate.db" # for SQLite
  postgres:                             # for PostgreSQL
    host: "postgres"
    port: 5432
    database: "opsimate"
    user: "opsimate"
    password: "opsimate_password"

security:
  private_keys_path: "/app/data/private-keys"

vm:
  try_with_sudo: false
```

### Volume Mounts

| Volume | Purpose |
|--------|---------|
| `/app/data/database` | SQLite database persistence (SQLite mode) |
| `/app/data/postgres` | PostgreSQL data persistence (PostgreSQL mode) |
| `/app/data/private-keys` | SSH private keys for authentication |
| `/app/config/config.yml` | Custom YAML configuration (optional) |

### Build Script Usage

The `build-and-deploy.sh` script supports various deployment scenarios:

```bash
# Build all components
./scripts/build-and-deploy.sh build all

# Build specific version from git tag
./scripts/build-and-deploy.sh build all --tag v0.0.28

# Deploy with SQLite
./scripts/build-and-deploy.sh deploy-server

# Deploy with PostgreSQL  
./scripts/build-and-deploy.sh deploy-server --postgres

# Run client standalone
./scripts/build-and-deploy.sh run-client

# Push to registry
./scripts/build-and-deploy.sh push all --registry my.registry/opsimate
```

## Development

### Development Setup

1. **Clone the repository:**
   ```bash
   git clone https://github.com/opsimate/opsimate.git
   cd opsimate
   ```

2. **Install dependencies:**
   ```bash
   pnpm install
   ```

3. **Build the project:**
   ```bash
   pnpm run build
   ```
4. **Specify the config file (optional):**
   ```bash
   export CONFIG_FILE=/path/to/config.yml
   ```
5. **Start development server:**
   ```bash
   pnpm run dev
   ```

### Development Commands

- `pnpm run test` - Run test suite
- `pnpm run lint` - Check code quality


## Contributing

We welcome contributions to OpsiMate! Here's how you can help:

### Areas for Contribution

- **New Provider Support** - Add support for additional infrastructure platforms
- **New Integrations** - Extend alerting and metrics capabilities
- **UI/UX Improvements** - Enhance the dashboard and user experience
- **Performance Optimizations** - Improve scalability and responsiveness
- **Documentation** - Help improve guides and documentation

## Roadmap

### Upcoming Features

- **📈 Advanced Analytics** - Service performance trends and insights
- **🔄 GitOps Integration** - Infrastructure as Code workflows
- **🤖 AI-Powered Insights** - Intelligent anomaly detection and recommendations


## Support

- **[Documentation](https://opsimate.vercel.app/)** - Comprehensive guides and API reference
- **[GitHub Issues](https://github.com/opsimate/opsimate/issues)** - Bug reports and feature requests
- **[Slack Community](https://join.slack.com/t/opsimate/shared_invite/zt-39bq3x6et-NrVCZzH7xuBGIXmOjJM7gA)** - Join our discussions and get help
- **[Website](https://www.opsimate.com/)** - Learn more about OpsiMate

---

<div align="center">
  <p>Built with ❤️ by the OpsiMate team</p>
  <p>© 2025 OpsiMate. All rights reserved.</p>
</div> 

## 💖 Our Amazing Contributors

This project wouldn’t be what it is today without the incredible people who have shared their time, knowledge, and creativity.  
A huge thank you to everyone who has helped and continues to help make OpsiMate better every day! 🙌

<a href="https://github.com/OpsiMate/OpsiMate/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=OpsiMate/OpsiMate" />
</a>

---
