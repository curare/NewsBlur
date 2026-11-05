# tinkdeck.com — NewsBlur Customizations

This document catalogues every customization applied to the upstream NewsBlur codebase for
news.tinkdeck.com. It is the authoritative reference when rebasing onto a new NewsBlur version.

Upstream remote: https://github.com/samuelclay/NewsBlur.git
Fork remote (origin): https://github.com/curare/NewsBlur.git

---

## How This Fork Works

The repo has no shared git history with upstream — it was initialized from a snapshot.
The upstream remote is configured so you can compare and pull in new code:

    git remote -v
    # origin   https://github.com/curare/NewsBlur.git
    # upstream https://github.com/samuelclay/NewsBlur.git

All tinkdeck customizations live in `tinkdeck/patches/`. Each patch is either a standard
unified diff (for precise hunks) or an annotated instruction block (for changes that survive
line-number drift better as search-and-insert instructions).

---

## Customization Index

### 1. Disable Signups via Env Var
**File:** `apps/profile/views.py`
**Patch:** `tinkdeck/patches/profile_disable_signups.patch`

Set `NEWSBLUR_DISABLE_SIGNUPS=1` (or `true` or `yes`) in the container environment to return
HTTP 404 for all signup requests. Allows running a private instance without forking the signup
UI or setting up invite-only logic.

Changes:
- `import os` added to top-level imports
- `Http404` added to the `django.http` import line (replacing `HttpResponseForbidden`)
- Three lines added at the top of `def signup(request)`:

```python
if os.environ.get("NEWSBLUR_DISABLE_SIGNUPS", "").lower() in {"1", "true", "yes"}:
    raise Http404
```

Docker env in `docker-compose.vps.yml`:
```yaml
NEWSBLUR_DISABLE_SIGNUPS: "true"
```

---

### 2. Session Cookie Domain for Custom Hostnames
**File:** `newsblur_web/docker_local_settings.py`
**Patch:** `tinkdeck/patches/docker_local_settings_session_cookie.patch`

Upstream hardcodes `SESSION_COOKIE_DOMAIN = "localhost"` for non-default `NEWSBLUR_URL` values,
which breaks logins on custom domains like `news.tinkdeck.com`. This change derives the domain
from `NEWSBLUR_URL` automatically, and allows an explicit override via `SESSION_COOKIE_DOMAIN`.

Changes:
- `from urllib.parse import urlparse` added to imports
- After the `if NEWSBLUR_URL == "https://localhost":` block, an `else` branch:

```python
else:
    SESSION_COOKIE_DOMAIN = os.getenv("SESSION_COOKIE_DOMAIN") or urlparse(NEWSBLUR_URL).hostname
```

---

### 3. Anni Reverse-Proxy Routing
**File:** `docker/haproxy/haproxy.docker-compose.cfg`
**Patch:** `tinkdeck/patches/haproxy_docker_compose_routing.patch`

Routes `anni.tinkdeck.com` through the same HAProxy instance that serves NewsBlur.

Changes:
- ACL in `frontend public`: `host_anni hdr(host) -i anni.tinkdeck.com`
- `use_backend anni if host_anni` routing rule
- `backend anni` block: `server anni_host 172.17.0.1:8080 check inter 5000ms`

The `anni` backend hits the host machine on port 8080 via the Docker bridge IP (`172.17.0.1`).

---

### 4. Old Reddit Alt Link
**File:** `media/js/newsblur/local/story_alt_links.js` *(new file, not in upstream)*

A self-installing plugin that adds an "Open in OldReddit" link to the story detail header and
to the story right-click manage menu for any story whose `story_permalink` is on `reddit.com`.
It rewrites the URL path to `https://old.reddit.com/<path>`.

This file is loaded via a `<script>` tag injected by... (check `templates/base.html` for the
include, or verify it loads via the asset pipeline).

No patch required — the file does not exist in upstream, so preserving it through an update
means simply copying it back after the reset.

---

### 5. Open Original Article on Click (Preference)
**Files:** `templates/base.html`, `media/js/newsblur/reader/reader_preferences.js`,
           `media/js/newsblur/views/story_title_view.js`
**Patches:**
- `tinkdeck/patches/base_html_open_original_on_click.patch`
- `tinkdeck/patches/reader_preferences_open_original_on_click.patch`
- `tinkdeck/patches/story_title_view_open_original_on_click.patch`

Adds a global preference "Clicking a story title: Expand in reading pane / Open original
article in background tab". When set to "open original", clicking a headline marks the story
read and opens `story_permalink` in a background tab without expanding the reading pane.

`templates/base.html` — add to `NEWSBLUR.Preferences` object (after `new_window`):
```js
'open_original_on_click'  : false,
```

`reader_preferences.js` — see patch for UI radio block (after "Open links" section) and load
logic (after `new_window` block in `load_preferences()`).

`story_title_view.js` — in `select_story()`, before the `_.contains(['list', 'grid'...` block:
```js
if (NEWSBLUR.assets.preference('open_original_on_click') && !NEWSBLUR.hotkeys.command) {
    this.model.mark_read({ skip_delay: true });
    this.model.open_story_in_new_tab(true);
    return;
}
```

---

### 6. VPS Deployment Files
**Files:** `deploy-vps.sh`, `docker-compose.vps.yml` *(new files, not in upstream)*

These are purely additive and do not modify any upstream file. Copy them back after an upstream
reset. They should never conflict.

`deploy-vps.sh` — one-shot deploy script for the OVH/CloudPanel VPS.
`docker-compose.vps.yml` — docker-compose override for VPS production (sets env vars,
exposes ports, configures volumes for news.tinkdeck.com).

### 7. Self-hosted Premium Access
**Files:** `apps/profile/models.py`, `apps/profile/middleware.py`, `newsblur_web/settings.py`,
`docker-compose.vps.yml`
**Patch:** `tinkdeck/patches/self_hosted_premium.patch`

Set `NEWSBLUR_SELF_HOSTED_PREMIUM=true` to assign every self-hosted account the Pro tier. New
accounts start on Pro without a premium-trial email. Existing accounts are promoted on their
first authenticated request. Premium, Archive, and Pro UI prompts and feature limits are then
removed through NewsBlur's normal tier checks.

This updates each account's stored tier fields. Turning the environment flag off does not
downgrade existing accounts; change their tier fields manually if reverting.

The OVH deployment enables this setting in `docker-compose.vps.yml`.

---

## Downtime / Ops Playbook

**`DOWNTIME.md` in the repo root does not apply to this deployment.** It documents the
health-check playbook for upstream NewsBlur's own production cluster — dozens of Hetzner
servers (`happ-web-*`, `htask-*`, `hdb-*`, etc.) managed via `ansible/inventories/hetzner.ini`
and `utils/check_health.sh`. news.tinkdeck.com is a single OVH VPS running the whole stack as
one Docker Compose project. Don't run `check_health.sh` or SSH to any `happ-*`/`htask-*`/`hdb-*`
hostname for tinkdeck issues — there's nothing there.

### Access

```bash
ssh ovh                              # alias to the OVH VPS (15.204.252.225)
cd /opt/tinkdeck/NewsBlur             # project root on the server
sudo docker ps                       # container status/uptime
sudo docker compose restart <name>   # restart one service (see `docker compose config --services`)
```

Containers: `newsblur_haproxy`, `newsblur_web`, `newsblur_nginx`, `newsblur_node`,
`newsblur_db_postgres`, `newsblur_db_mongo`, `newsblur_db_redis`, `newsblur_db_elasticsearch`,
`newsblur_celery`, `newsblur_mcp`, `newsblur_imageproxy`, `newsblur_dejavu`.

Deploy code changes with `./deploy-vps.sh` from the repo root (pushes, then pulls + recreates
containers on the server).

### First checks for "site is down"

```bash
sudo docker ps --format 'table {{.Names}}\t{{.Status}}'   # any container restarting/unhealthy?
uptime; free -h; df -h /                                   # load, memory, disk
sudo ss -tn state established '( sport = :443 or sport = :80 )' | wc -l   # connection count
```

If all of that looks clean but a user reports the page hanging/blank in their actual browser —
**stop testing with curl.** A single curl request to `/` proves nothing about real page load:
it never fetches referenced sub-resources, executes JS, or hits render-blocking `<link>` tags.
Get real client-side timing instead — either have the user check DevTools → Network, or drive
a real browser directly (`mcp__claude-in-chrome__*` tools) and read
`performance.getEntriesByType('resource')`. This is how the 2026-07-20 outage was actually
diagnosed: curl was fast the entire time; the real cause was a render-blocking third-party font
stylesheet (`cloud.typography.com`, see `templates/base.html`) whose CDN had gone unreachable,
freezing every real browser's page load for minutes. No amount of server-side/DNS/CDN
investigation would have found that — it only showed up in browser resource timing.

---

## Mail / Email

**Status as of 2026-07-30: no `@tinkdeck.com` mail identity exists, and setup is deliberately deferred.**
This section captures the whole picture so it does not have to live in anyone's head.

### What sends mail today

- **Morning digest only.** The systemd timer on the VPS (`~/src/ovh-vps`: `bin/morning_digest.py`
  + `systemd/morning-digest.*`) sends via **Gmail SMTP** (`smtp.gmail.com:587`) as
  `stan.newdel@gmail.com`. It delivers because it is a real Gmail sender riding Google's own
  SPF/DKIM and reputation. It has nothing to do with tinkdeck.com's DNS.
- **NewsBlur sends nothing.** `EMAIL_BACKEND` is `django.core.mail.backends.console.EmailBackend`,
  which prints mail to the `newsblur_celery` log and drops it. So password resets and the OPML
  export "we will email your backup" fallback never actually deliver. (The OPML timeout fallback
  fires only if building the export takes over 15s; with a normal feed count it returns the
  download synchronously, so most users never hit the dead email path anyway.)
- **Miniflux and Immich**: SMTP is off by default in both. No notifications leave those apps.
- **No MTA on the box.** Nothing listens on 25/465/587; no postfix/exim/sendmail installed.
- **No mail DNS on the domain.** `tinkdeck.com` and every subdomain have no MX, SPF, DKIM, or
  DMARC records. Nothing can send authenticated mail as `@tinkdeck.com` today, and the domain
  cannot receive mail.

### Why this is not a gap worth panicking over

Mail is **orthogonal to the web stack**. The three app stacks (newsblur, immich, miniflux) are
separate Docker Compose projects, each with its own database and redis, sharing only the host and
the front proxy. If email is broken or a future relay has an outage, outbound mail queues or
delays; NewsBlur, Immich, and Miniflux keep serving pages unaffected. Email cannot take a site
down.

### The plan if/when we want `@tinkdeck.com` mail

Decided direction (not yet built):

1. **Never send from the OVH VPS IP.** Cloud VPS IPs have no sending reputation, OVH commonly
   blocks outbound port 25, and there is no PTR alignment. Self-hosting an MTA here is the actual
   fragile option. Use an authenticated relay instead.
2. **Use a sending subdomain: `send.tinkdeck.com`** to isolate sending reputation from the apex
   (relay best practice).
3. **Relay options** (pick one, all are low-fragility because a specialist owns the reputation):
   - **Resend** free tier, purpose-built for transactional/app mail. One new vendor + API key.
   - **Google Workspace** (~$6/mo) consolidates under a vendor already in use (Gmail), gives
     send **and** receive as `@tinkdeck.com`, turnkey DKIM.
   - **Amazon SES** cheapest at scale, needs sandbox-removal approval.
4. **Publish SPF + DKIM + DMARC in Cloudflare.** These records live in **our** zone, so there is
   no lock-in: swapping relays later means swapping these three records, nothing more. The
   `@tinkdeck.com` identity is owned by us permanently, independent of any provider.
   - Mail records must be **DNS-only (grey cloud), never proxied**.
   - DMARC should start at `p=none` (monitor) with a `rua=` report address, then tighten to
     `quarantine`/`reject` once reports look clean.
5. **Point the apps at the relay**: repoint the morning digest off Gmail, switch NewsBlur off the
   console backend to SMTP, and optionally enable Miniflux/Immich SMTP. From addresses on
   `send.tinkdeck.com` (e.g. `digest@send.tinkdeck.com`, `newsblur@send.tinkdeck.com`).

### Cloudflare DNS access

DNS is on Cloudflare (zone `tinkdeck.com`). Records are editable via a scoped API token
(`My Profile > API Tokens > Edit zone DNS` template, scoped to `tinkdeck.com` only). Revoke any
such token once records verify; the records persist after the token is gone.

---

## Updating from Upstream

```bash
bash tinkdeck/update-from-upstream.sh
```

The script:
1. Fetches upstream and shows how many files differ
2. Warns if any tinkdeck-patched file was also changed upstream (potential conflict)
3. Asks for confirmation before doing anything destructive
4. Tags the current state (`tinkdeck-before-YYYYMMDD`) as a rollback point
5. Saves all exclusive tinkdeck files to a temp directory
6. Hard-resets to `upstream/main`
7. Restores exclusive files and the `tinkdeck/` directory
8. Runs `git apply` on every patch in `tinkdeck/patches/`
9. Commits automatically if all patches applied cleanly, or exits with instructions if any failed

### If a patch fails

The script will tell you which patch(es) failed. Open `TINKDECK.md`, find the relevant
customization section, and apply the change manually using the code snippets there. The
patches include enough commentary to locate the correct insertion point even after upstream
refactoring.

After manually fixing each failure:
```bash
git add -A
git commit -m "tinkdeck: rebase onto upstream <sha>"
git push origin main --force-with-lease
```

Then update the failed patch file so it applies cleanly next time.

---

## Adding a New Customization

When adding a new tinkdeck customization to a shared upstream file:

1. Make the change in the file.
2. Create a patch file in `tinkdeck/patches/` describing the change. For changes that are
   small and localized, a unified diff works well. For changes that span many lines or are
   sensitive to context drift, use the "annotated instruction" format (as in the
   `reader_preferences_open_original_on_click.patch` and `story_title_view_*` patches).
3. Add a section to this file (TINKDECK.md) describing what the change does and why.
4. Commit both the code change and the patch/documentation together.
