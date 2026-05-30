# Media Stack

Docker Compose media stack: Jellyfin + Sonarr + Radarr + Prowlarr + qBittorrent (via VPN) + Seerr + Homepage.

## Service URLs

| Service | URL | Purpose |
|---|---|---|
| Homepage | http://localhost:3000 | Dashboard |
| Jellyfin | http://localhost:8096 | Media server |
| Seerr | http://localhost:5055 | Request UI |
| Sonarr | http://localhost:8989 | TV automation |
| Radarr | http://localhost:7878 | Movie automation |
| Prowlarr | http://localhost:9696 | Indexer management |
| qBittorrent | http://localhost:8090 | Download client |

For LAN access from other devices, replace `localhost` with your Mac's local IP. Set a DHCP reservation in your router so this IP never changes — find your Mac's MAC address with:

```sh
ipconfig getifaddr en0        # current IP
ifconfig en0 | grep ether     # MAC address for router reservation
```

## Setup

### 1. Configure credentials

```sh
cp .env.example .env
```

Edit `.env` with your credentials — see sections below for details. Run `id` to get `PUID`/`PGID`.

### 2. Start the stack

```sh
docker compose up -d
```

### 3. Service setup order

1. **qBittorrent** (http://localhost:8090) — set download path to `/downloads`, set a permanent password in Settings → Web UI
2. **Prowlarr** (http://localhost:9696) — add indexers, then connect to Sonarr/Radarr via Settings → Apps (use `localhost` as hostname)
3. **Sonarr** (http://localhost:8989) and **Radarr** (http://localhost:7878) — add qBittorrent as download client (host: `gluetun`, port: `8080`); set root folders to `/tv` and `/movies`
4. **Jellyfin** (http://localhost:8096) — add `/data/tvshows` and `/data/movies` as libraries; create an API key in Admin → API Keys
5. **Seerr** (http://localhost:5055) — connect to Jellyfin (`http://jellyfin:8096`), then Sonarr/Radarr (use your Mac's static IP and ports 8989/7878)
6. **Homepage** (http://localhost:3000) — fill in API keys in `.env` (see below), then `docker compose up -d --force-recreate homepage`

## Credentials

### ProtonVPN / OpenVPN

ProtonVPN uses a **separate username and password** for OpenVPN — not your Proton account login.

1. Log in at [proton.me/vpn](https://proton.me/vpn)
2. Go to **Account** → **OpenVPN / IKEv2 username**
3. Copy into `.env` as `OPENVPN_USER` and `OPENVPN_PASSWORD`

The `PROTON_EMAIL` and `PROTON_PASSWORD` (your actual Proton account login) are used to auto-refresh the VPN server list every 24 hours.

### Homepage API Keys

| Key | Where to find it |
|---|---|
| `JELLYFIN_API_KEY` | Jellyfin → Admin Dashboard → API Keys → + |
| `SEERR_API_KEY` | Seerr → Settings → General → API Key |
| `QBITTORRENT_PASSWORD` | Password you set in qBittorrent → Settings → Web UI |
| `SONARR_API_KEY` | Sonarr → Settings → General → Security → API Key |
| `RADARR_API_KEY` | Radarr → Settings → General → Security → API Key |
| `PROWLARR_API_KEY` | Prowlarr → Settings → General → Security → API Key |

## Directory Layout

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
│   └── homepage/
└── media/                # media files (gitignored)
    ├── tv/
    ├── movies/
    └── downloads/
```
