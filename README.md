# Media Stack

A self-hosted media stack built on Docker Compose. Users request content through Seerr, which instructs Sonarr/Radarr to find and download it via qBittorrent (behind a VPN). Downloaded media lands in Jellyfin for streaming.

## Services

| Service | Internal address | Public | Purpose |
|---|---|---|---|
| Jellyfin | `jellyfin:8096` | https://media.finleyghosh.com | Media streaming |
| Seerr | `seerr:5055` | https://request.finleyghosh.com | Request UI |
| Homepage | `homepage:3000` | — | Dashboard |
| Maintainerr | `maintainerr:6246` | — | Media cleanup rules |
| Netdata | `netdata:19999` | — | System monitoring |
| Sonarr | `vpn:8989` | — | TV automation |
| Radarr | `vpn:7878` | — | Movie automation |
| Prowlarr | `vpn:9696` | — | Indexer management |
| qBittorrent | `vpn:8080` | — | Download client |

> Sonarr, Radarr, Prowlarr, and qBittorrent are VPN-isolated — always reached via `vpn:port`, never by container name.

## How it fits together

```
                         ┌─────────────┐
          public users   │  Cloudflare │
         ───────────────▶│   Tunnel    │
                         └──────┬──────┘
                                │
          ╔══════════════════════╪══════════════════════════════════╗
          ║  media network       │                                  ║
          ║                      ▼                                  ║
          ║  ┌───────────────────────────────────────────────────┐  ║
          ║  │  public-facing                                    │  ║
          ║  │                                                   │  ║
          ║  │   ┌─────────────────┐   ┌─────────────────┐      │  ║
          ║  │   │    Jellyfin     │   │      Seerr      │      │  ║
          ║  │   │media.finleyg... │   │ request.finleyg │      │  ║
          ║  │   └────────┬────────┘   └────────┬────────┘      │  ║
          ║  └────────────┼─────────────────────┼───────────────┘  ║
          ║               │                      │                  ║
          ║   ┌───────────┘              ┌───────┘                  ║
          ║   │  jellyfin:8096           │  vpn:7878 / vpn:8989     ║
          ║   │                          │                          ║
          ║   ▼                          ▼                          ║
          ║  ┌──────────────┐   ┌────────────────────────────────┐ ║
          ║  │ Maintainerr  │   │  Gluetun (VPN gateway)         │ ║
          ║  │ (cleanup)    │   │                                │ ║
          ║  └──────┬───────┘   │  ┌──────────┐  ┌──────────┐  │ ║
          ║         │           │  │  Sonarr  │  │  Radarr  │  │ ║
          ║         │           │  │  (TV)    │  │ (movies) │  │ ║
          ║         │           │  └────┬─────┘  └────┬─────┘  │ ║
          ║         │           │       │              │        │ ║
          ║         │           │  ┌────▼──────────────▼─────┐  │ ║
          ║         │           │  │       Prowlarr          │  │ ║
          ║         │           │  │    (indexer search)     │  │ ║
          ║         │           │  └────────────┬────────────┘  │ ║
          ║         │           │               │               │ ║
          ║         │           │  ┌────────────▼────────────┐  │ ║
          ║         │           │  │      qBittorrent        │  │ ║
          ║         │           │  │    (download client)    │  │ ║
          ║         │           │  └────────────┬────────────┘  │ ║
          ║         │           │               │ all traffic   │ ║
          ║         │           └───────────────┼───────────────┘ ║
          ║         │                           │ through VPN     ║
          ║  ┌──────┴───────┐                   ▼                 ║
          ║  │   Homepage   │             Internet                 ║
          ║  │ (dashboard)  │                                      ║
          ║  └──────────────┘                                      ║
          ╚══════════════════════════════════════════════════════════╝
```

### Network isolation

| Zone | Services | Talk to each other via |
|---|---|---|
| **media network** | Jellyfin, Seerr, Maintainerr, Homepage, Cloudflared, Portainer | container name (`jellyfin:8096`, `seerr:5055`) |
| **VPN (Gluetun)** | Sonarr, Radarr, Prowlarr, FlareSolverr, qBittorrent | shared network namespace — `localhost:port` |
| **Bridge** | Gluetun sits on `media` network and exposes VPN services | media → VPN via `vpn:8989`, `vpn:7878` etc. |

Services inside the VPN bubble cannot be reached by container name — always use `vpn:port` from the media network. All qBittorrent traffic egresses through the VPN tunnel — if Gluetun goes down, downloads stop rather than leak.

## Directory layout

```
.
├── docker-compose.yml
├── .env                  # credentials (gitignored)
├── .env.example
├── config/               # per-service config (gitignored)
│   ├── gluetun/
│   ├── qbittorrent/
│   ├── prowlarr/
│   ├── sonarr/
│   ├── radarr/
│   ├── jellyfin/
│   ├── seerr/
│   ├── maintainerr/
│   └── homepage/
└── media/                # media files (gitignored)
    ├── tv/
    ├── movies/
    └── downloads/
```

## Setup

### 1. Configure credentials

```sh
cp .env.example .env
```

Edit `.env` — run `id` to get `PUID`/`PGID`. See credential notes below.

### 2. Start the stack

```sh
docker compose up -d
```

### 3. Service setup order

1. **qBittorrent** (http://nookie:8090) — set download path to `/downloads`, set a permanent password in Settings → Web UI
2. **Prowlarr** (http://nookie:9696) — add indexers, then connect to Sonarr/Radarr via Settings → Apps (use `vpn` as hostname)
3. **Sonarr** (http://nookie:8989) and **Radarr** (http://nookie:7878) — add qBittorrent as download client (host: `vpn`, port: `8080`); set root folders to `/tv` and `/movies`
4. **Jellyfin** (http://nookie:8096) — add `/data/tvshows` and `/data/movies` as libraries; create an API key in Admin → API Keys
5. **Seerr** (http://nookie:5055) — connect to Jellyfin (`http://jellyfin:8096`), Sonarr (`http://vpn:8989`), Radarr (`http://vpn:7878`)
6. **Maintainerr** (http://nookie:6246) — connect to Jellyfin (`http://jellyfin:8096`), Seerr (`http://seerr:5055`), Sonarr (`http://vpn:8989`), Radarr (`http://vpn:7878`)
7. **Homepage** (http://nookie:3000) — fill in API keys in `.env`, then `docker compose up -d --force-recreate homepage`

### Credentials

**ProtonVPN** — uses a separate OpenVPN username/password, not your Proton account login. Find it at proton.me/vpn → Account → OpenVPN / IKEv2 username.

**Homepage API keys**

| Key | Where to find it |
|---|---|
| `JELLYFIN_API_KEY` | Jellyfin → Admin Dashboard → API Keys |
| `SEERR_API_KEY` | Seerr → Settings → General → API Key |
| `QBITTORRENT_PASSWORD` | qBittorrent → Settings → Web UI |
| `SONARR_API_KEY` | Sonarr → Settings → General → API Key |
| `RADARR_API_KEY` | Radarr → Settings → General → API Key |
| `PROWLARR_API_KEY` | Prowlarr → Settings → General → API Key |
