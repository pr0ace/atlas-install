# Atlas — PicoClaw Installer

One-command deployment of [PicoClaw](https://github.com/sipeed/picoclaw) AI chatbot gateway on **Debian 13 (Trixie)**.

Connects LLM providers (OpenRouter, OpenAI, Gemini, Groq, Zhipu, Ollama, vLLM) to messaging channels (Telegram, Discord, WhatsApp, Feishu, MaixCAM) with a full management CLI, automatic backups, FTP server, and deep system performance tuning.

---

## Quick Start

### One-Line Install (curl)

**SSH into your Debian 13 server as root** and run:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/pr0ace/atlas/master/atlas-install.sh)
```

That's it. The interactive wizard handles everything else.

### Git Clone Install

Clone the repository and run the installer:

```bash
git clone https://github.com/pr0ace/atlas-install.git && cd atlas-install && bash atlas-install.sh
```

---

## Prerequisites

Before installation, ensure your system meets these requirements:

| Requirement | Details |
|---|---|
| **OS** | Debian 13 (Trixie) - other distros not supported |
| **User** | Root access required |
| **RAM** | 1 GB minimum (2 GB+ recommended for Ollama) |
| **Disk** | 10 GB+ free space |
| **Network** | Active internet connection |
| **Ports** | 18790 (gateway), 21 (FTP, if enabled) |

---

## What Gets Installed

| Component | Details |
|---|---|
| **PicoClaw Gateway** | AI chatbot binary + CLI wrapper at `/usr/local/bin/picoclaw` |
| **LLM Provider** | Your choice of 8 providers, configured and ready |
| **Channels** | Telegram, Discord, WhatsApp, Feishu, MaixCAM |
| **Atlas Skills** | Auto-discovered from this repo, installed to workspace |
| **System Tuning** | TCP BBR, sysctl, zram, I/O scheduler, SSD TRIM, DNS, and more |
| **FTP Server** | vsftpd with optional TLS |
| **Systemd Service** | Gateway + watchdog timer + cron fallback |
| **Auto Backups** | Scheduled snapshots with rotation |
| **Ollama** | Optional local LLM with custom Modelfile |

---

## Management CLI

After installation, use the `picoclaw` command to manage your gateway:

| Command | Description |
|---|---|
| `picoclaw start` | Start the PicoClaw gateway service |
| `picoclaw stop` | Stop the gateway service |
| `picoclaw restart` | Restart the gateway (apply config changes) |
| `picoclaw logs` | View real-time gateway logs |
| `picoclaw status` | Check gateway service status |
| `picoclaw backup` | Create/manage configuration backups |
| `picoclaw model` | Switch LLM provider or model |
| `picoclaw config` | Edit gateway configuration |

**Advanced Commands:**

```bash
picoclaw whatsapp login|logout|start|stop  # WhatsApp bridge control
picoclaw ollama status|model|list|pull     # Local LLM management
picoclaw backup create|list|settings       # Backup operations
picoclaw atlas status|list|update          # Skills management
picoclaw ftp status|start|stop|password    # FTP server control
```

---

## Configuration

All user-configurable variables are documented in [`config.yaml`](config.yaml).

Key paths on the server after installation:

| Path | Purpose |
|---|---|
| `/usr/local/bin/picoclaw` | CLI wrapper |
| `/usr/local/bin/picoclaw.bin` | Gateway binary |
| `/root/.picoclaw/config.json` | Runtime configuration |
| `/root/.picoclaw/workspace/skills/` | Installed skills |
| `/root/backup/` | Backup snapshots |

---

## Version

Current release: see [`VERSION`](VERSION)

---

## License

Proprietary. All rights reserved. See [`LICENSE`](LICENSE) for terms.

No modifications, redistribution, or derivative works permitted without prior written consent from the copyright holder.
