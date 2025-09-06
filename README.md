<p align="center">
  <img src="apps/client/images/logo.png" width="86" alt="OpsiMate logo" />
</p>

<h1 align="center">OpsiMate</h1>
<p align="center"><b>One console for servers, Docker, and Kubernetes—discover, monitor, and act.</b></p>
<p align="center">
  Built for DevOps/NOC/IT teams that need a single place to see service health,
  jump to dashboards, and perform safe start/stop/restart operations.
</p>

<p align="center">
  <a href="https://img.shields.io/github/commit-activity/m/OpsiMate/OpsiMate">
    <img alt="Commit activity" src="https://img.shields.io/github/commit-activity/m/OpsiMate/OpsiMate" />
  </a>
  <a href="https://github.com/OpsiMate/OpsiMate/releases">
    <img alt="Latest release" src="https://img.shields.io/github/v/release/OpsiMate/OpsiMate" />
  </a>
  <a href="https://github.com/OpsiMate/OpsiMate/blob/main/LICENSE">
    <img alt="License" src="https://img.shields.io/github/license/OpsiMate/OpsiMate" />
  </a>
  <a href="https://github.com/OpsiMate/OpsiMate/stargazers">
    <img alt="GitHub stars" src="https://img.shields.io/github/stars/OpsiMate/OpsiMate?style=social" />
  </a>
  <a href="https://join.slack.com/t/opsimate/shared_invite/zt-39bq3x6et-NrVCZzH7xuBGIXmOjJM7gA">
    <img alt="Join Slack" src="https://img.shields.io/badge/Slack-Join%20Chat-4A154B?logo=slack&logoColor=white" />
  </a>
</p>

<p align="center">
  <a href="https://opsimate.vercel.app/getting-started/deploy">Get Started</a> ·
  <a href="https://opsimate.vercel.app/">Docs</a> ·
  <a href="https://www.opsimate.com/">Website</a> ·
  <a href="https://github.com/OpsiMate/OpsiMate/issues/new?labels=bug&template=bug_report.md">Report Bug</a>
</p>

---

### TL;DR
- 🔎 **Auto-discovery** of Docker/systemd services  
- 📊 **Live health & metrics** with Grafana/Prometheus/Kibana links  
- 🎛️ **Safe actions**: start/stop/restart from the dashboard  
- 🏷️ **Smart tags** for quick filtering

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

OpsiMate includes a comprehensive wrapper script for building, deploying, and managing Docker containers:

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

# Container Management
./scripts/build-and-deploy.sh ps          # List all containers and images
./scripts/build-and-deploy.sh stop        # Stop running containers
./scripts/build-and-deploy.sh clean all   # Clean up containers and images
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

### Container Management

The build script includes comprehensive Docker container management capabilities:

#### View Container Status
```bash
# List all OpsiMate containers and images with detailed status
./scripts/build-and-deploy.sh ps
```

This shows:
- Running containers with ports and status
- Stopped containers 
- Available images with tags and sizes

#### Stop Containers
```bash
# Stop running OpsiMate containers
./scripts/build-and-deploy.sh stop

# Stop PostgreSQL deployment specifically
./scripts/build-and-deploy.sh stop --postgres
```

#### Clean Up Resources
```bash
# Remove all containers (running and stopped)
./scripts/build-and-deploy.sh clean containers

# Remove all images
./scripts/build-and-deploy.sh clean images

# Remove specific tagged images
./scripts/build-and-deploy.sh clean images --tag v0.0.28

# Complete cleanup (containers + images + dangling images)
./scripts/build-and-deploy.sh clean all
```

#### Management Examples
```bash
# Check what's running before deployment
./scripts/build-and-deploy.sh ps

# Deploy new version
./scripts/build-and-deploy.sh deploy-server --tag v0.0.29

# Stop old containers and clean up
./scripts/build-and-deploy.sh stop
./scripts/build-and-deploy.sh clean containers

# Clean up old images to save space
./scripts/build-and-deploy.sh clean images --tag v0.0.28
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
