# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [v1.0.0] - 2026-02-11

### Added

- Unified `picoclaw` CLI: all commands now accessible via `picoclaw CMD`
- `picoclaw model`: interactive model switcher per provider (reads config, shows available models, excludes current, writes new model, restarts)
- `picoclaw telegram`: interactive Telegram management (enable/disable, change token, add/remove users, protects initial user from removal, restarts on change only)
- `picoclaw backup`: full snapshot of config, workspace, binary, wrapper, systemd units, cron, profile into `/root/backup/backup_MMddyy_HHmmss/` with automatic purge of oldest backups beyond configurable max (18)
- Auto-backup cron: configurable interval in days (6) via `/etc/cron.d/picoclaw-autobackup` calling `picoclaw backup --auto`
- Backup metadata: `backup.meta` JSON in each snapshot tracks version, timestamp, trigger (manual/auto)
- System performance optimizer: TCP BBR, sysctl tuning, memory management, I/O scheduler, file limits, DNS, zram, tmpfs, SSD TRIM, journald, disabled bloat
- Forced reboot after performance optimization to fully activate all kernel tweaks; gateway auto-starts if systemd service was enabled
- Atlas skills repository integration: dynamic discovery via GitHub API, installs all skills from pr0ace/atlas at install time (categories auto-detected, SKILL.md required), with `picoclaw atlas` CLI for management
- FTP server (vsftpd): optional full-access FTP server with configurable username, password, TLS optional, chroot to `/` for full filesystem access, systemd managed, `picoclaw ftp` CLI for management
- WhatsApp bridge: full Baileys/Node.js bridge install, Node.js 20+ auto-provisioned, systemd-managed bridge service with `After=` dependency so bridge starts before gateway, interactive QR login via `picoclaw whatsapp login`, session persistence in `whatsapp-auth/`, backup of auth state, CLI management (start/stop/restart/login/logout/status/logs/enable/disable)
- WhatsApp auto-login: if WhatsApp is enabled and no session exists, installer auto-launches QR login before starting the gateway service
- WhatsApp bridge auto-exit: bridge process exits automatically after successful connection during interactive login (no manual Ctrl+C needed)
- Ollama local LLM: optional local inference server, auto-installs ollama, pulls selected model, custom Modelfile with `num_ctx` for RAM control, routes via vllm provider slot (OpenAI-compat `/v1` endpoint), systemd-managed, `picoclaw ollama` CLI for management

### Changed

- FTP defaults to enabled (Y) with `root` as default username

### Fixed

- `StartLimitIntervalSec` now correctly placed in `[Unit]` section, not `[Service]`
- Zhipu `api_base` set explicitly
- API key prompts never show `[default]` brackets
- WhatsApp disabled unless bridge running
- Full system upgrade performed before package installation
- Trap now prints failing line instead of silent exit
- SHA256 checksums added for binaries + Go
- `set -eEuo pipefail` for proper ERR trap propagation
- Model selection list per provider (latest models)
- Fixed `declare -g` vs `local` variable scoping bug
- All wizard variables now use global scope consistently
- All menus validate input and re-prompt on bad choice
- `verify()` uses rc-capture to avoid ERR trap
- All `systemctl` calls guarded with `|| true`
- ALL `[[ ]] && cmd` patterns replaced with `if/then/fi` to prevent `set -e` from killing on false conditions
- Telegram `allow_from`: `"id|username"` composite format (PicoClaw sends composite key; exact match required)
- Groq provider: key placed in openrouter slot with Groq `api_base` because PicoClaw `CreateProvider()` only routes to Groq on model names containing "groq" (no actual Groq model name matches that pattern)
- Anthropic direct: WARN — PicoClaw uses `/chat/completions` (OpenAI-compat) but Anthropic needs `/v1/messages`. Script warns user to use OpenRouter for Claude models instead of direct Anthropic
- Discord `allow_from`: same composite format fix
- JSON-safe input sanitization (escape `\` `"` and strip control chars) to prevent `config.json` corruption
- Fixed Telegram wizard typo (was `DC_` instead of `TG_`)

[v1.0.0]: https://github.com/pr0ace/atlas-install/releases/tag/v1.0.0
