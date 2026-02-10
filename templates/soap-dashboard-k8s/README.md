---
display_name: SOAP Dashboard
description: Development workspace for SOAP Dashboard with Claude Code
icon: /emojis/1f4cb.png
maintainer_github: abridgeai
verified: true
tags: [kubernetes, development, github, soap-dashboard, clinician-web, claude-code]
---

# SOAP Dashboard Template

Development workspace pre-configured for the SOAP Dashboard from clinician-web. Designed for PMs and developers to quickly spin up and vibe code with Claude Code.

## Features

- **SOAP Dashboard**: Auto-starts `npm run dev:soap` on port 3000
- **VS Code**: Web-based development environment with ESLint, Prettier, Tailwind CSS extensions
- **Claude Code**: Pre-installed CLI for AI-assisted development
- **Git Integration**: Automatic repository cloning and configuration
- **Persistent Storage**: Home directory persists across restarts

## What Gets Set Up Automatically

1. Clones `clinician-web` repository
2. Runs `npm install` to install dependencies
3. Copies `.env.example` to `.env.local` for soap-dashboard
4. Starts the SOAP Dashboard dev server (`npm run dev:soap`)
5. Installs Claude Code CLI

## Applications

### SOAP Dashboard
- **Access**: Click "SOAP Dashboard" button in Coder UI
- **Port**: 3000
- **Logs**: `/tmp/soap-dashboard.log`

### Code Server
- **Access**: Click "code-server" button in Coder UI
- **Port**: 13337

### Claude Code
- **Access**: Open terminal in code-server and run `claude`

## Parameters

| Parameter | Range | Default | Description |
|-----------|-------|---------|-------------|
| CPU Cores | 8-16 | 8 | CPU cores allocated |
| Memory | 16-32 GB | 16 GB | Memory allocated |
| Home Disk | 64-1024 GB | 64 GB | Persistent storage size |

## Usage

1. Create a new workspace using this template
2. Wait for startup to complete (watch the logs)
3. Click "SOAP Dashboard" to open the app in browser
4. Click "code-server" to open the IDE
5. Use `claude` in terminal for AI assistance

## Troubleshooting

### SOAP Dashboard not loading
Check the logs:
```bash
tail -f /tmp/soap-dashboard.log
```

### Restart SOAP Dashboard
```bash
cd ~/clinician-web
npm run dev:soap
```

### Re-install dependencies
```bash
cd ~/clinician-web
rm -rf node_modules
npm install
```

### Build local dependencies
```bash
cd ~/clinician-web
npm run build:deps
```
