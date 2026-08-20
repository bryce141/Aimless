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
- **Region: US East (Ashburn), with a caveat.** It is a few milliseconds from
  New Jersey and has three availability domains, which helps — but it is also
  one of the highest-demand regions for free ARM capacity, where "out of host
  capacity" routinely persists for days. The home region is chosen at signup and
  **cannot be changed afterwards.**

  If Ashburn will not provision, take a different region rather than waiting
  indefinitely. **The win here is the rate limit, not the latency.** Removing a
  40-request/minute vendor quota is worth far more than the tens of milliseconds
  a distant region costs, and even Frankfurt — which provisions in minutes —
  would answer in roughly 150-230 ms against HeiGIT's measured 430-970 ms.
  HeiGIT is slow because of load and queueing, not distance.
- **Image: Ubuntu 22.04 or 24.04 (aarch64).** The ORS image is multi-arch;
  `v9.10.0` publishes both `amd64` and `arm64`, so Ampere is fine.
- **Boot volume: 50 GB minimum.** Budget ~6 GB for our data (1 GB extract,
  1.3 GB graph, 2.9 GB elevation cache) and leave room for the merge, which
  needs both the inputs and the output on disk at once.

If capacity is unavailable, retry — including in a different availability
domain. This is the well-known free-tier lottery, not a misconfiguration.

**Upgrading to Pay As You Go is the reliable escape hatch**, and Always Free
resources stay free on a PAYG account — Oracle simply prioritises paying
tenancies for capacity. The risk is that a PAYG account will happily bill for
anything provisioned beyond the free shapes, so set a budget alert first if you
go this route.

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

## 4. Cloudflare Tunnel — done 2026-08-20

Live at **https://ors.workdocks.com**, tunnel `aimless-ors`
(`d47a138a-3c81-42a1-a6b9-44034c3ee007`). The box has no inbound ports open;
`cloudflared` dials out to Cloudflare and runs as a systemd service.

```
cloudflared tunnel login            # browser, once, selects the zone
cloudflared tunnel create aimless-ors
cloudflared tunnel route dns aimless-ors ors.workdocks.com
# credentials json -> /etc/cloudflared/ on the box, then:
sudo cloudflared service install && sudo systemctl enable --now cloudflared
```

### The hostname is public, so there is a gate behind it

A tunnel hostname is served by Cloudflare to **anyone who knows the name**, and
ORS has no notion of authentication. Left open, the box is free routing for
strangers — the same problem we left HeiGIT to escape, except on hardware we
pay for.

So nginx sits on `127.0.0.1:8081` between the tunnel and ORS and checks one
header, `X-Aimless-Origin`, returning 403 for everything else. The tunnel points
at the gate rather than at ORS directly. The Worker sends the header from the
`SELF_HOSTED_TOKEN` secret.

Verified: without the header the hostname returns **403 on every path, health
included**; with it, routes come back normally.

**Cloudflare Access with a service token would be strictly better** and is the
obvious hardening later: it rejects at Cloudflare's edge instead of at our
origin, so unauthorised traffic never reaches the box or its bandwidth. It was
skipped here only because it needs dashboard work; the gate is equivalent for
the threat we actually have, which is strangers using our router.

## 5. Point the Worker at it — done

```
wrangler secret put SELF_HOSTED_ORIGIN    # https://ors.workdocks.com/ors
wrangler secret put SELF_HOSTED_TOKEN     # matches the nginx gate
wrangler deploy
```

Measured after deploying, fresh seeds so nothing came from cache:

| Origin | Served by |
|---|---|
| Marlboro NJ | **self** |
| Jersey City NJ | **self** |
| Apple Park CA | heigit |
| Chicago IL | heigit |

**The fallback was tested rather than assumed.** With nginx stopped, a New
Jersey request returned 200 from HeiGIT — degraded to slower, not broken —
and went back to `self` on its own once the gate came back.

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
