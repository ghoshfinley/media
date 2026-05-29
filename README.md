# Media Stack

Docker Compose media server stack: Jellyfin + Sonarr + Radarr + Prowlarr + qBittorrent (via VPN) + Seerr.

## Service URLs

| Service | URL | Purpose |
|---|---|---|
| Jellyfin | http://localhost:8096 | Media server |
| Sonarr | http://localhost:8989 | TV automation |
| Radarr | http://localhost:7878 | Movie automation |
| Prowlarr | http://localhost:9696 | Indexer management |
| qBittorrent | http://localhost:8090 | Download client |
| Seerr | http://localhost:5055 | Request UI |

For LAN access from other devices, replace `localhost` with your Mac's local IP:

```sh
ipconfig getifaddr en0
```

## Setup

### 1. Configure credentials

```sh
cp .env.example .env
```

Edit `.env` — see the [ProtonVPN OpenVPN](#protonvpn-openvpn-credentials) section below for VPN values, and run `id` to get your `PUID`/`PGID`.

### 2. Start the stack

```sh
docker compose up -d
```

### 3. Service setup order

1. **qBittorrent** (http://localhost:8090) — set download path to `/downloads`
2. **Prowlarr** (http://localhost:9696) — add indexers, then connect to Sonarr/Radarr via Settings → Apps
3. **Sonarr** (http://localhost:8989) and **Radarr** (http://localhost:7878) — add qBittorrent as download client (host: `gluetun`, port: `8080`)
4. **Jellyfin** (http://localhost:8096) — add `/data/tvshows` and `/data/movies` as libraries
5. **Seerr** (http://localhost:5055) — connect to Jellyfin, then Sonarr/Radarr

## ProtonVPN OpenVPN Credentials

ProtonVPN uses a **separate username and password** for OpenVPN — not your Proton account login.

1. Log in at [proton.me/vpn](https://proton.me/vpn)
2. Go to **Account** → **OpenVPN / IKEv2 username**
3. Copy the username and password shown there into your `.env` as `OPENVPN_USER` and `OPENVPN_PASSWORD`

## Directory Layout

```
.
├── docker-compose.yml
├── .env                  # credentials (gitignored)
├── .env.example
├── config/               # per-service config (gitignored)
│   ├── sonarr/
│   ├── radarr/
│   ├── prowlarr/
│   ├── qbittorrent/
│   ├── jellyfin/
│   └── seerr/
└── media/                # media files (gitignored)
    ├── tv/
    ├── movies/
    └── downloads/
```
