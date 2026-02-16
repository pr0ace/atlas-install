# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v1.0.0] - 2026-02-16

### Added

- **Atlas Skills Repository Integration**: Dynamic discovery via GitHub API, installs all skills from pr0ace/atlas at install time (categories auto-detected, SKILL.md required), with `picoclaw atlas` CLI for management
- **FTP Server (vsftpd)**: Optional full-access FTP server with configurable username, password, TLS optional, chroot to / for full filesystem access, systemd managed, `picoclaw ftp` CLI for management, defaults to Y with root as default username
- **WhatsApp Bridge**: Full Baileys/Node.js bridge install, Node.js 20+ auto-provisioned, systemd-managed bridge service with After= dependency so bridge starts before gateway, interactive QR login via `picoclaw whatsapp login`, session persistence in whatsapp-auth/, backup of auth state, CLI management (start/stop/restart/login/logout/status/logs/enable/disable)
- **WhatsApp Auto-Login**: If WhatsApp is enabled and no session exists, installer auto-launches QR login before starting the gateway service
- **WhatsApp Bridge Auto-Exit**: Bridge process exits automatically after successful connection during interactive login (no manual Ctrl+C needed)
- **Ollama Local LLM**: Optional local inference server, auto-installs ollama, pulls selected model, custom Modelfile with num_ctx for RAM control, routes via vllm provider slot (OpenAI-compat /v1 endpoint), systemd-managed, `picoclaw ollama` CLI for management
- **System Performance Optimizer**: TCP BBR, sysctl tuning, memory management, I/O scheduler, file limits, DNS, zram, tmpfs, SSD TRIM, journald, disabled bloat
- **Forced Reboot After Optimization**: After performance optimization to fully activate all kernel tweaks; gateway auto-starts if systemd service was enabled
- **Backup System**: `picoclaw backup` creates full snapshot of config, workspace, binary, wrapper, systemd units, cron, profile into /root/backup/backup_MMddyy_HHmmss/ with automatic purge of oldest backups beyond configurable max (18)
- **Auto-Backup Cron**: Configurable interval in days (6) via /etc/cron.d/picoclaw-autobackup calling `picoclaw backup --auto`
- **Backup Metadata**: backup.meta JSON in each snapshot tracks version, timestamp, trigger (manual/auto)
- **Model Management CLI**: `picoclaw model` - interactive model switcher per provider (reads config, shows available models, excludes current, writes new model, restarts)
- **Telegram Management CLI**: `picoclaw telegram` - interactive Telegram management (enable/disable, change token, add/remove users, protects initial user from removal, restarts on change only)
- **Model Selection Lists**: Per provider with latest models
- **SHA256 Checksums**: For binaries + Go installation
- **Unified PicoClaw CLI**: All commands via `picoclaw CMD`

### Changed

- **Telegram allow_from Format**: Now supports "id|username" composite format (PicoClaw sends composite key; exact match required)
- **Discord allow_from Format**: Same composite format fix as Telegram
- **All Wizard Variables**: Now use global scope consistently
- **Groq Provider Configuration**: Key placed in openrouter slot with Groq api_base because PicoClaw CreateProvider() only routes to Groq on model names containing "groq" (no actual Groq model name matches that pattern)

### Fixed

- **StartLimitIntervalSec Placement**: Moved from [Service] to [Unit] section where it belongs
- **Zhipu API Base**: Set explicitly
- **API Key Prompts**: Never show [default] brackets
- **WhatsApp Channel**: Disabled unless bridge running
- **System Upgrade**: Full system upgrade before packages
- **Error Trap**: Prints failing line instead of silent exit
- **Bash Safety**: Added `set -eEuo pipefail` for proper ERR trap propagation
- **Variable Scoping Bug**: Fixed declare -g vs local variable scoping
- **Menu Validation**: All menus validate input and re-prompt on bad choice
- **verify() Function**: Uses rc-capture to avoid ERR trap
- **systemctl Calls**: All guarded with || true
- **Conditional Patterns**: All `[[ ]] && cmd` patterns replaced with if/then/fi to prevent set -e from killing on false conditions
- **JSON Input Sanitization**: Escape \ " and strip control chars to prevent config.json corruption
- **Telegram Wizard Typo**: Fixed variable prefix (was DC_ instead of TG_)
- **Anthropic Direct API Warning**: Added WARN — PicoClaw uses /chat/completions (OpenAI-compat) but Anthropic needs /v1/messages. Script warns user to use OpenRouter for Claude models instead of direct Anthropic.

## Verification Against Upstream

**Last Verified**: 2026-02-11

- **PicoClaw**: v0.0.1 (sipeed/picoclaw, 2026-02-09)
- **Go**: 1.26.0 (go.mod requires 1.24.0 — compat OK)
- **Config**: pkg/config/config.go + config.example.json
- **Makefile**: build→build/picoclaw-linux-<arch> + symlink
- **Providers**: openrouter, anthropic, openai, gemini, zhipu, groq, vllm
- **Channels**: telegram, discord, whatsapp, feishu, maixcam
- **Keys**: snake_case (allow_from, api_key, api_base, app_id, app_secret, encrypt_key, verification_token, bridge_url)
