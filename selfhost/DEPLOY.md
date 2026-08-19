# Deploying to Oracle Cloud

Runbook for moving New Jersey routing off HeiGIT and onto our own instance.
`README.md` next to this file records what self-hosting costs and why the graph
covers four states; this file is only the deploy.

**This does not touch the app binary.** The app talks to the Worker, the Worker
decides where routing happens. Nothing here needs App Review, which is why it is
safe to do while a build is in review.

## What it buys

HeiGIT allows 40 requests/minute across every install and one generate costs
~18, so the ceiling today is roughly **two generates per minute for all users
combined**. Our own box has no such limit, and answers in 55-140 ms against
430-970 ms hosted.

Only New Jersey origins move. Everyone else still goes to HeiGIT and still
shares that ceiling — this scales one region, not the app.

## Prerequisites

- **An Oracle Cloud account.** Free tier, credit card required for identity
  verification, not charged on Always Free shapes.
- **A domain on Cloudflare.** Named tunnels require a zone in the account. Quick
  tunnels (`trycloudflare.com`) are ephemeral and explicitly not for production,
  so they are not an option here. Cloudflare Registrar sells at wholesale if
  there isn't one already — roughly $10/year.
- `cloudflared` and the OCI console. No Terraform; this is a single box.

## 1. Provision the instance

**Start this first — it is the long pole.** Free ARM capacity is frequently
unavailable and the request can take several attempts across days.

- **Shape: `VM.Standard.A1.Flex`, 2 OCPU / 12 GB.** Always Free was cut in half
  on 2026-06-15, from 4/24. The monthly allowance is 1,500 OCPU-hours and 9,000
  GB-hours, so one instance at 2/12 running continuously costs 1,460 and 8,760 —
  it fits, with no room for a second instance.
- **Region: US East (Ashburn).** A few milliseconds from New Jersey. The home
  region is chosen at signup and **cannot be changed afterwards**, so get it
  right the first time.
- **Image: Ubuntu 22.04 or 24.04 (aarch64).** The ORS image is multi-arch;
  `v9.10.0` publishes both `amd64` and `arm64`, so Ampere is fine.
- **Boot volume: 50 GB minimum.** Budget ~6 GB for our data (1 GB extract,
  1.3 GB graph, 2.9 GB elevation cache) and leave room for the merge, which
  needs both the inputs and the output on disk at once.

If capacity is unavailable, retry — including in a different availability
domain. This is the well-known free-tier lottery, not a misconfiguration.

**Idle reclamation is a real risk.** Oracle may reclaim Always Free compute that
stays under ~20% utilisation across 7 days. A routing box for an app with no
users is exactly that profile. The Worker already degrades to HeiGIT on a dead
socket, so the failure mode is "slower", not "broken" — but expect to have to
either notice this or keep the box busy.

## 2. Install Docker and copy the tree up

```
sudo apt update && sudo apt install -y docker.io docker-compose-v2 osmium-tool
sudo usermod -aG docker ubuntu     # log out and back in
```

From the Mac:

```
rsync -av --exclude data --exclude graphs --exclude elevation_cache \
      --exclude logs selfhost/ ubuntu@<ip>:~/selfhost/
```

**Do not copy `data/`, `graphs/` or `elevation_cache/`** — that is 5 GB over the
wire to move a 9-day-old snapshot. Fetching fresh on the box is faster and gets
current road data.

Note OCI images ship with restrictive iptables rules. The tunnel means nothing
needs opening inbound, but be aware they are there if something looks unreachable
that should not be.

## 3. Fetch and build

```
cd ~/selfhost
./fetch-extract.sh        # ~1 GB down, merges NJ + PA + NY + DE
docker compose up -d
docker compose logs -f    # watch the build
```

The build took **955 s on 6 M-series cores**; on 2 Ampere OCPU expect
considerably longer — budget an hour and do not interrupt it. Peak heap was
1.96 GB, well inside 12 GB, and `XMX: 4g` in `docker-compose.yml` covers it.

```
curl localhost:8080/ors/v2/health
```

**If the build fails claiming it cannot parse the extract, suspect elevation,
not the file.** `ors-config.yml` already sets `provider: skadi` for this reason;
the default provider hangs and GraphHopper rethrows the timeout as a parse
error. See README.

Once healthy, confirm it actually routes before wiring anything up — `compare.sh`
runs the same seeds against local and the Worker side by side.

## 4. Cloudflare Tunnel

The box gets no public IP exposure and no open inbound ports. `cloudflared` dials
out to Cloudflare and the hostname is reachable only through it.

```
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb -o cloudflared.deb
sudo dpkg -i cloudflared.deb
cloudflared tunnel login
cloudflared tunnel create aimless-ors
cloudflared tunnel route dns aimless-ors ors.<your-domain>
```

`~/.cloudflared/config.yml`:

```yaml
tunnel: aimless-ors
credentials-file: /home/ubuntu/.cloudflared/<tunnel-id>.json
ingress:
  - hostname: ors.<your-domain>
    service: http://localhost:8080
  - service: http_status:404
```

```
sudo cloudflared service install
sudo systemctl enable --now cloudflared
```

**The hostname is public once this is up.** An open routing engine is abusable,
so put Cloudflare Access in front of it with a service token and have the Worker
send `CF-Access-Client-Id` and `CF-Access-Client-Secret`. Without that, anyone
who finds the hostname gets free routing on our box — which is the same problem
we are moving off HeiGIT to avoid, just with us paying for it.

## 5. Point the Worker at it

```
cd worker
wrangler secret put SELF_HOSTED_ORIGIN     # https://ors.<your-domain>/ors
wrangler deploy
```

**The `/ors` suffix is mandatory and omitting it fails silently** — every request
404s, falls back to HeiGIT, and the app keeps working at HeiGIT's latency under
HeiGIT's rate limit. See `worker/README.md`.

Verify with the `X-Aimless-Served-By` header, which reads `self` or `heigit` on
every response. A Marlboro NJ origin must come back `self`.

## Rolling back

`wrangler secret delete SELF_HOSTED_ORIGIN` and deploy. Everything returns to
HeiGIT immediately, with no app change and no review.

## Left undone

- **Staleness.** Geofabrik regenerates daily; nothing here refreshes. A stale
  extract is a wrong route. Re-running `fetch-extract.sh` plus
  `REBUILD_GRAPHS=True` is the refresh, and it is currently manual.
- **Sustained load.** Nothing has measured a cold JVM under real traffic. Twelve
  concurrent requests once is not a load test.
- **The 200 km ceiling is available but unused.** `maximum_distance_round_trip_routes`
  is raised in `ors-config.yml`, which makes a 3-hour option possible — but only
  for New Jersey origins, so the app cannot offer it without the option
  disappearing for everyone else. Product decision, not a deploy step.
