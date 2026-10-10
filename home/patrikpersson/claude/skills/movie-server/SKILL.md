---
name: movie-server
description: Add movies (or TV shows) to the z840 Jellyfin library and babysit the downloads until they're imported — all from the shell via the Radarr/Sonarr APIs, no app UIs. Use when the user asks to add, download, get, remove or skip a movie/show, asks how downloads are going, or says something is stuck.
---

# movie-server

Drive the z840 media stack (nixarr: Radarr/Sonarr → Prowlarr → qBittorrent in
the Mullvad namespace → hardlink into `/tank/media/library` → Jellyfin) over
HTTP. The user should never need to open an app. Background and design live in
`~/nixos-config/docs/media-server.md`.

## Tools (on PATH, Nix-managed in `hosts/z840/default.nix`)

- `media-queue` — Radarr + Sonarr queues and every qBittorrent torrent (state,
  %, speed, seeds, idle). Exit 1 = something looks stuck. `--json` for raw data.
- `media-watch [secs]` — blocks until an event, prints it + the queue, exits:
  `QUEUE EMPTY` / `LEFT QUEUE: […]` (exit 0) or `NO PROGRESS: […]` (exit 1).
  Default interval 900 s.
- `media-health` — whole-stack check incl. a real VPN test. Run it first if
  anything behaves oddly (0 seeds everywhere = tunnel/DNS, not the torrent).
- API keys: the sudo rule matches the **store path**, so resolve the symlink:
  ```bash
  k=$(sudo -n "$(readlink -f /run/current-system/sw/bin/arr-apikey)" radarr)   # or sonarr / prowlarr
  api(){ curl -s -H "X-Api-Key: $k" -H 'Content-Type: application/json' "$@"; }
  R=localhost:7878/api/v3      # Sonarr: localhost:8989/api/v3
  ```
- qBittorrent API: `http://192.168.15.1:8085/api/v2` — no login from the host.

## Add a movie

1. Look up, confirm the right title/year (lookup returns near-misses — "Good
   Time" also matches "The Good Time Girls"):
   `api "$R/movie/lookup?term=$(jq -rn --arg t 'Title 2017' '$t|@uri')" | jq -c '.[:3][]|{title,year,tmdbId}'`
2. Add with search on, using the **"4K, 1080p fallback"** profile (look the id
   up by name, don't hardcode):
   ```bash
   P=$(api $R/qualityprofile | jq '.[]|select(.name=="4K, 1080p fallback")|.id')
   api "$R/movie/lookup/tmdb?tmdbId=$ID" | jq --argjson p $P '. + {qualityProfileId:$p,
     rootFolderPath:"/tank/media/library/movies", monitored:true, minimumAvailability:"released",
     addOptions:{searchForMovie:true, monitor:"movieOnly"}}' > "$SCRATCH/add.json"
   api -X POST $R/movie -d @"$SCRATCH/add.json" | jq -c '{id,title,year}'
   ```
3. ~60–90 s later run `media-queue` to confirm a grab happened. Empty queue for
   that title → see "Nothing grabbed" below.
4. Start `media-watch` in the background (`run_in_background`) and react to each
   event. Restart it after every event until `QUEUE EMPTY`.

When the user gives a list with an order ("start with X and Y"), add those
first and the rest only once the first batch imports.

## Remove / skip

- **Remove** ("don't want it"): `api -X DELETE "$R/movie/$ID?deleteFiles=true&addImportExclusion=false"`
- **Skip** (keep the entry, stop pursuing it): remove any queue item, then
  `api -X PUT $R/movie/editor -d '{"movieIds":[ID],"monitored":false}'`
- Queue item removal: `api -X DELETE "$R/queue/$QID?removeFromClient=true&blocklist=false"`
  (deletes the partial download).

## Fix a stuck download

A stall is judged by **bytes**, not Radarr's "stalled with no connections"
warning — that warning fires right after most grabs and clears on its own.
When `media-watch` reports NO PROGRESS (or a torrent sits at 0% with ≤1 seed):

1. Interactive search: `api "$R/release?movieId=$ID" > "$SCRATCH/rel.json"` (slow,
   up to ~2 min). Filter to the title — results include other movies' releases
   (`select(.title|test("name";"i"))`) — and sort by seeders.
2. Blocklist the dead one: `api -X DELETE "$R/queue/$QID?removeFromClient=true&blocklist=true&skipRedownload=true"`
3. Grab the best-seeded acceptable release:
   `jq -c '[.[]|select(.title|test("…"))][0]|{guid,indexerId}' rel.json | api -X POST $R/release -d @-`
   (the response body is mostly null; confirm with `media-queue`).
4. Prefer a well-seeded real 4K (WEB-DL 2160p is fine) over a 1-seed remux;
   if no healthy 4K exists, a well-seeded 1080p beats waiting. Tell the user what
   you swapped and why.

## Nothing grabbed

Run the interactive search and read `.rejections`. "… is not wanted in
profile" everywhere means the movie is on a 4K-only profile with no 4K release —
move it to "4K, 1080p fallback" (`movie/editor` with `qualityProfileId`) and
`POST $R/command {"name":"MoviesSearch","movieIds":[ID]}`. Not yet released
digitally (`digitalRelease` in the future) is expected — say so, don't fight it.

## Verify done

An item is done when Radarr has the file **and** it's in the library:
`api $R/movie/$ID | jq '{hasFile, q:.movieFile.quality.quality.name}'` and
`stat -c '%h links %n' /tank/media/library/movies/<Title (Year)>/*` — 2 links
= hardlinked (no extra disk). Jellyfin's file watcher refreshes the library on
its own (`journalctl -u jellyfin | rg LibraryMonitor`).

## Standing settings (don't undo without asking)

- qBittorrent downloads **one at a time** (`MaxActiveDownloads=1`; under
  500 KiB/s counts as slow and releases the slot). Order with
  `POST /torrents/topPrio hashes=…` when the user names priorities.
- Never use a 4K-only profile for new adds — the user wants 1080p when 4K
  doesn't exist. "Upscaled" 4K releases are acceptable for now.
- The user watches progress in qui at `http://z840:5252` (Tailscale).
