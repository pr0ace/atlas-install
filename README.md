# Atlas — PicoClaw Installer

One-command deployment of [PicoClaw](https://github.com/sipeed/picoclaw) AI chatbot gateway on **Debian 13 (Trixie)**.

Connects LLM providers (OpenRouter, OpenAI, Gemini, Groq, Zhipu, Ollama, vLLM) to messaging channels (Telegram, Discord, WhatsApp, Feishu, MaixCAM) with a full management CLI, automatic backups, FTP server, and deep system performance tuning.

---

## Quick Start

**SSH into your Debian 13 server as root** and run:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/pr0ace/atlas/master/atlas-install.sh)
```

That's it. The interactive wizard handles everything else.

### With a pre-filled config (skip wizard prompts):

```bash
curl -fsSL https://raw.githubusercontent.com/pr0ace/atlas/master/atlas-install.sh -o /tmp/atlas-install.sh \
  && curl -fsSL https://raw.githubusercontent.com/pr0ace/atlas/master/config.yaml -o /tmp/config.yaml \
  && bash /tmp/atlas-install.sh --config /tmp/config.yaml
```

---

## Requirements

| Requirement | Minimum |
|---|---|
| OS | Debian 13 (Trixie) |
| User | root |
| RAM | 512 MB (2 GB+ for Ollama) |
| Disk | 2 GB free |
| Network | Internet access |

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

After installation, use the `picoclaw` command:

```
picoclaw start|stop|restart|logs|status    # Gateway control
picoclaw config edit|model|telegram        # Configuration
picoclaw whatsapp login|logout|start|stop  # WhatsApp bridge
picoclaw ollama status|model|list|pull     # Local LLM
picoclaw backup create|list|settings       # Backup management
picoclaw atlas status|list|update          # Skills management
picoclaw ftp status|start|stop|password    # FTP server
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
