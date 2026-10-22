# svngate

A single-container **Subversion (SVN) gateway** that exposes your existing SVN
repositories over **HTTP/WebDAV** and the native **`svn://`** protocol, with a
**[WebSVN](https://websvnphp.github.io/)** web interface for browsing.

It is designed to sit in front of a repository tree you already own, so you do
not have to migrate, `svnadmin dump`/`load`, or restructure anything.

![License](https://img.shields.io/badge/license-MIT-green.svg)
![Docker](https://img.shields.io/badge/docker-compose-2496ED.svg?logo=docker&logoColor=white)
![WebSVN](https://img.shields.io/badge/WebSVN-2.9.0-orange.svg)
![Platform](https://img.shields.io/badge/platform-Alpine%203.24-0D597F.svg?logo=alpinelinux&logoColor=white)

---

## Table of contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Project files](#project-files)
- [Requirements](#requirements)
- [Using prebuilt images](#using-prebuilt-images)
- [Build image locally](#build-image-locally)
- [Configuration](#configuration)
- [Repository layout](#repository-layout)
- [Examples](#examples)
- [Endpoints](#endpoints)
- [How startup works](#how-startup-works)
- [Security notes](#security-notes)
- [Known limitations](#known-limitations)
- [License](#license)
- [A note on this documentation](#a-note-on-this-documentation)

---

## Overview

| Layer | Technology | Purpose |
| --- | --- | --- |
| Web UI | WebSVN 2.9.0 + PHP 8.4 | Read-only repository browsing in the browser |
| HTTP access | Apache 2 + `mod_dav_svn` + `mod_authz_svn` | SVN over HTTP/WebDAV, HTTP Basic auth |
| Native access | `svnserve` | Classic `svn://` protocol on port `3690` |
| Base image | Alpine Linux 3.24 | Small footprint, `apk`-managed packages |
| Process supervision | `daemon-start.sh` (shell, no supervisor) | Starts both daemons, shuts both down cleanly, and exits non-zero if either dies |

Repositories are **discovered automatically at every container start**. Drop a
valid repository directory into the mounted host folder and it appears — no
config edits, no rebuild.

---

## Architecture

```
                          ┌──────────────────────────────────────────┐
                          │  Host                                    │
                          │                                          │
    ${MY_SVN_REPOS_ROOT}   │   /srv/svn_repos                        │
   ──────────────────────►│     ├── project-a/     (SVN repo)        │
        volume mount      │     │     ├── db/                         │
                          │     │     ├── format                      │
                          │     │     └── conf/{passwd,authz}         │
                          │     └── project-b/     (SVN repo)         │
                          └───────────────────┬──────────────────────┘
                                              │  /var/svn
              ┌───────────────────────────────┼───────────────────────┐
              │            svngate container  │                       │
              │                               ▼                       │
              │   1. entrypoint.sh  ── scans /var/svn, builds config  │
              │        ├─ writes /etc/apache2/svn-repositories.conf   │
              │        ├─ writes bcrypt htpasswd  per repository      │
              │        └─ writes /var/www/websvn/include/config.php   │
              │                               │                       │
              │   2. daemon-start.sh          ▼                       │
              │        ┌───────────────────────────────┐              │
              │        │  svnserve   :3690  (svn://)   │              │
              │        │  httpd      :80    (WebDAV)   │              │
              │        └───────────────────────────────┘              │
              └───────────────────────────────────────────────────────┘
                         │                       │
                    3690 │  :3690 ──────────► svn client
                    8080 │  :80   ──────────► browser
                         ▼                       http://.../websvn
```

---

## Project files

| File | Description |
| --- | --- |
| `Dockerfile` | Alpine 3.24 image; installs Apache, `mod_dav_svn`, Subversion, PHP 8.4 and WebSVN. |
| `entrypoint.sh` | Startup logic: discovers repositories, generates Apache vhost fragments, per-repo htpasswd files and the WebSVN config. |
| `daemon-start.sh` | Starts `svnserve` and Apache, and traps `TERM`/`INT`/`HUP` so both shut down gracefully. |
| `apache.conf` | Apache configuration (loaded as `/etc/apache2/conf.d/apache-svn.conf`): WebSVN alias, public `/svn` listing, vhost on `:80`. |
| `compose.yml` | Compose service definition: build context, ports, env and the repository volume. |
| `.env` | Optional local overrides for Compose variables. Git-ignored. |
| `.gitignore` | Ignores `.env`. |
| `LICENSE` | MIT License. |

---

## Requirements

- Docker Engine with the Compose plugin (`docker compose`)
- An existing SVN repository tree on the host
- Read access to that tree — the container never writes into your repositories


---

## Using prebuilt images

You can also pull a pre‑built image from GitHub Container Registry:

```bash
docker pull ghcr.io/galagithub/svngate:latest
```

---

## Build image locally

```bash
# 1. Clone the project
git clone https://github.com/galagithub/svngate.git svngate
cd svngate

# 2. Create your local environment file
cat > .env <<'EOF'
MY_SERVER_NAME=svn.example.com
MY_SVN_REPOS_ROOT=/srv/svn_repos
EOF

# 3. Build and start
docker compose up -d --build
```

Watch the discovery pass:

```bash
docker compose logs -f svngate
```

You should see output similar to:

```
==============================================
 svngate
==============================================
Found SVN repository: project-a
  Reading users from:
    /var/svn/project-a/conf/passwd
    user: alice
    user: bob
Adding WebSVN repository: project-a
Adding WebSVN repository: project-b
==============================================
Repositories discovered: 2
==============================================
Apache modules:
 dav_module (shared)
 dav_svn_module (shared)
 rewrite_module (shared)
Testing Apache configuration...
Syntax OK
 ... Apache config ok ...
Starting Daemons...
```

---

## Configuration

Settings live in `.env` (git-ignored) and are substituted by Compose:

| Variable | Required | Meaning | Example |
| --- | --- | --- | --- |
| `MY_SERVER_NAME` | yes | Server name, passed to the container as `SERVER_NAME` | `svn.example.com` |
| `MY_SERVER_WEB_PORT` | yes | **Host** port published to Apache's container port `80` | `8080` |
| `MY_SVN_REPOS_ROOT` | yes | **Host** path of your repository tree, mounted at `/var/svn` | `/srv/svn_repos` |

If no `.env` file is present, Compose falls back to the defaults declared in
`compose.yml`. To override them, create a git-ignored `.env` in this directory:

```ini
# .env
MY_SERVER_NAME=svn.example.com
MY_SERVER_WEB_PORT=8080
MY_SVN_REPOS_ROOT=/srv/svn_repos
```

> `compose.yml` publishes `${MY_SERVER_WEB_PORT}:80` and `3690:3690`. Only the
> web port is configurable — the `svn://` port is fixed at `3690`.
>
> `MY_SERVER_WEB_PORT` must be set to a non-empty value. If it is blank or
> missing, Compose publishes **no** web port at all and warns about nothing, so
> the site is simply unreachable while `docker compose ps` still shows the
> service as up. Verify with `docker compose config` (look for `published:`).

The WebSVN version is a build argument, so it can be pinned or bumped without
editing the `Dockerfile`:

```bash
docker compose build --build-arg WEBSVN_VERSION=2.9.0
```

---

## Repository layout

svngate does not care about anything in your tree **except** the standard SVN
repository structure. A directory is only picked up when it looks like a real
repository — it must contain both a `db/` directory **and** a `format` file:

```
${MY_SVN_REPOS_ROOT}/
├── project-a/                  # ← discovered as "project-a"
│   ├── conf/
│   │   ├── passwd              # plaintext users, used for HTTP Basic auth
│   │   ├── authz               # optional path-based rules (see notes)
│   │   └── svnserve.conf       # optional, used by svnserve
│   ├── db/
│   ├── format
│   └── hooks/
└── not-a-repo/                 # ← skipped: no db/ + format
    └── some-other-data
```

Non-repository directories are skipped silently, so you can safely point
`MY_SVN_REPOS_ROOT` at a folder that holds other things too.

### `conf/passwd` and authentication

On every start, `entrypoint.sh` parses the `[users]` section of each
repository's `conf/passwd` and converts it into an Apache **bcrypt** htpasswd
file, because Apache cannot consume SVN's plaintext passwd file directly:

```ini
[users]
alice = secret123
bob   = hunter2
```

Only the `[users]` section is read; `[groups]` and other sections are ignored,
and `#` comments plus Windows `\r\n` line endings are handled.

A repository without `conf/passwd` still gets exposed and listed, but logs:

```
  WARNING: no conf/passwd
```

---

## Examples

### 1. Create a brand-new repository and publish it

All repository administration runs **inside the container**, because that is
where the Subversion tools live — you do not need `svnadmin` on the host. The
repository tree is a bind mount, so anything created this way lands on the host
and survives container restarts.

```bash
# Create the repository (runs svnadmin inside the container)
docker compose exec --user 100:101 svngate \
  svnadmin create /var/svn/demo-app

# Add users — plaintext; svngate converts these to bcrypt on every start
docker compose exec --user 100:101 svngate sh -c 'cat > /var/svn/demo-app/conf/passwd' <<'EOF'
[users]
alice = secret123
bob   = hunter2
EOF

# Optional: path-based access rules
docker compose exec --user 100:101 svngate sh -c 'cat > /var/svn/demo-app/conf/authz' <<'EOF'
[/]
alice = rw
bob   = r
EOF

# Restart so the new repo is discovered
docker compose restart svngate
```

> **Why `--user 100:101`?** Apache runs as the unprivileged `apache` user
> (uid `100`, gid `101`). Creating the repository as that user means Apache can
> read *and write* it, which is required for commits over HTTP. Plain
> `docker compose exec` runs as **root**, which creates a `root`-owned
> repository: commits then fail with
> `Can't open file '.../db/txn-current-lock': Permission denied`.
>
> For an existing repository you already own on the host, hand it over once:
>
> ```bash
> sudo chown -R 100:101 "$MY_SVN_REPOS_ROOT/demo-app"
> ```
>
> If you would rather keep host-side ownership (so your own user can edit
> `conf/passwd` directly), add your user to a group Apache can write as, or run
> the container with a matching `user:` in `compose.yml` instead.

Import some content into it:

```bash
mkdir -p /tmp/demo-app/{trunk,branches,tags}
echo "<h1>Hello</h1>" > /tmp/demo-app/trunk/index.html

svn import /tmp/demo-app \
  http://localhost:8080/svn/demo-app \
  -m "Initial import" \
  --username alice --password secret123 \
  --non-interactive
```

### Available administration commands

The image ships the full `subversion-tools` package, so these all work through
`docker compose exec`:

| Command | Purpose | Example |
| --- | --- | --- |
| `svnadmin` | Create, dump, load, verify repositories | `svnadmin create /var/svn/demo-app` |
| `svnlook` | Inspect a repository directly (bypasses auth) | `svnlook youngest /var/svn/demo-app` |
| `svnrdump` | Dump over the network to/from another repo | `svnrdump dump http://…/svn/demo-app` |
| `svndumpfilter` | Filter a dump file by path | `svndumpfilter include trunk < d.svn` |
| `svnsync` | Mirror one repository into another | `svnsync init file:///var/svn/mirror …` |
| `svnmucc` | Commit several changes atomically, no working copy | `svnmucc put -F local.txt /var/svn/demo-app/trunk/a.txt` |
| `svnversion` | Report the working-copy revision | `svnversion /tmp/demo-app` |

A few practical ones:

```bash
# Inspect a repository without going through Apache or auth
docker compose exec --user 100:101 svngate \
  svnlook youngest /var/svn/demo-app

# Check repository integrity
docker compose exec --user 100:101 svngate \
  svnadmin verify /var/svn/demo-app

# Create a portable backup (writes to stdout — redirect on the host side)
docker compose exec --user 100:101 svngate \
  svnadmin dump /var/svn/demo-app > ~/demo-app-$(date +%F).svndump
```


Import some content into it:

```bash
mkdir -p /tmp/demo-app/{trunk,branches,tags}
echo "<h1>Hello</h1>" > /tmp/demo-app/trunk/index.html

svn import /tmp/demo-app \
  http://localhost:8080/svn/demo-app \
  -m "Initial import" \
  --username alice --password secret123 \
  --non-interactive
```

### 2. Check out and commit over HTTP

```bash
svn checkout http://localhost:8080/svn/demo-app demo-app
cd demo-app

echo "<h1>Updated</h1>" > trunk/index.html
svn commit -m "Update landing page" --username alice --password secret123
```

### 3. Check out over the native `svn://` protocol

```bash
svn checkout svn://localhost:3690/demo-app demo-app-native
```

### 4. Browse repositories in WebSVN

Open <http://localhost:8080/websvn> and pick a repository from the list.

Useful URLs:

| URL | Shows |
| --- | --- |
| `http://localhost:8080/websvn/listing.php?repname=demo-app` | Repository listing |
| `http://localhost:8080/svn/demo-app` | Raw WebDAV view (requires credentials) |
| `http://localhost:8080/svn/` | Public list of every discovered repository |

---

### 5. Everyday management commands

```bash
# Rebuild after changing the Dockerfile
docker compose up -d --build

# Follow logs
docker compose logs -f svngate

# Stop
docker compose down

# Inspect the generated Apache config inside the container
docker compose exec svngate cat /etc/apache2/svn-repositories.conf

# Inspect the generated WebSVN config
docker compose exec svngate cat /var/www/websvn/include/config.php

# Open a shell in the container
docker compose exec svngate sh
```

### 6. Verify everything from the outside

```bash
# Is the repo list public?
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8080/svn/

# Is authentication actually enforced?
curl -s -o /dev/null -w '%{http_code}\n' \
  http://localhost:8080/svn/demo-app/
# 401 = auth required, as expected

# Is WebSVN reachable?
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8080/websvn/

# Native protocol
svn info svn://localhost:3690/demo-app
```

---

## Endpoints

| Service | Host port | Container port | Protocol |
| --- | --- | --- | --- |
| Apache / WebDAV + WebSVN | `8080` | `80` | HTTP |
| `svnserve` | `3690` | `3690` | `svn://` |

---

## How startup works

1. **`entrypoint.sh`** runs first:
   - creates `/var/svn`, `/etc/apache2/svn-auth`, `/etc/apache2/certs`, `/run/apache2`
   - clears the generated file `/etc/apache2/svn-repositories.conf`
   - writes a fresh WebSVN `config.php` (English default, `calm` template first)
   - loops over `/var/svn/*`, keeping only real repositories (`db/` **and** `format`)
   - for each one: builds a bcrypt htpasswd file from `conf/passwd`, appends a
     `<Location /svn/<repo>>` block with `Require valid-user`, and registers the
     repository with WebSVN via `addRepository()`
   - tightens permissions (`chmod 640` on auth files, `chown apache:apache` on WebSVN)
   - validates the config with `httpd -t`
2. **`daemon-start.sh`** is `exec`'d as PID 1's child and:
   - starts `svnserve` on `:3690`
   - starts `httpd -D FOREGROUND`
   - traps `TERM`/`INT`/`HUP` and stops both processes cleanly
   - **polls both daemons every 2s**: if either one dies unexpectedly, it stops
     the other and exits non-zero, so the `restart: unless-stopped` policy in
     `compose.yml` rebuilds the container from a known-good state

There is no external process supervisor. A shell supervisor is deliberately
chosen over `supervisord`: it adds roughly **54 MB** to the image and would
provide no benefit here — busybox `ash` already reaps orphans, so zombie
accumulation is not a concern with just two daemons.

Because everything is generated at start-up, changes to your repository tree
only require a `docker compose restart svngate`.

---

## Security notes

> **Read this before exposing svngate to a network.**

- **WebSVN is intentionally unauthenticated.** Both the global and vhost
  `<Directory /var/www/websvn>` blocks use `Require all granted`, so anyone who
  can reach the port can browse repository contents. Authentication is a
  deliberate future addition, marked with `PUBLIC FOR NOW` / `INTENTIONALLY
  DISABLED` comments in the config.
- **There is no TLS.** The certificate generation block in `entrypoint.sh` is
  commented out, so credentials travel as plain HTTP Basic auth. Put svngate
  behind a TLS-terminating reverse proxy if it is reachable off-host.
- **`authz` is not enforced for WebSVN.** The `setAccessFile()` call is
  commented out, so path-based restrictions in `conf/authz` do not yet apply to
  the web UI.
- **`conf/passwd` is plaintext by SVN convention.** svngate never rewrites your
  files, but be aware the source passwords sit unencrypted on the host. The
  bcrypt files it generates live inside the container and are `chmod 640`.
- **Per-repository Apache auth is real.** Each `/svn/<repo>` location does
  require a valid user, so commit access is protected — it is the *browsing*
  surface that is open.

---

## Known limitations

These are pre-existing characteristics of the project, recorded here so they are
not mistaken for setup mistakes:

- **A dead daemon restarts the whole container, not just the process.** If
  `svnserve` or Apache dies, `daemon-start.sh` stops both and exits non-zero so
  Compose restarts the container. This means a brief blip in `svn://` also
  interrupts active HTTP sessions. A per-process supervisor would avoid that, at
  the cost of ~54 MB of image size.
- **`SERVER_NAME` is currently cosmetic.** Apache is configured with
  `ServerName localhost` and a `*:80` vhost, so the value from `MY_SERVER_NAME`
  is passed into the container but does not yet drive name-based routing.
- **Only one SVN tree is mounted.** All repositories must live under the single
  `MY_SVN_REPOS_ROOT` directory.

- **Repositories must be writable by the `apache` user.** Apache runs as uid
  `100` / gid `101`, so it needs read *and* write access to any repository that
  should accept commits over HTTP. Read-only browsing still works on
  world-readable repositories, but commits fail with
  `Can't open file '.../db/txn-current-lock': Permission denied`.
  Creating repositories with `docker compose exec --user 100:101` (as shown in
  [Example 1](#1-create-a-brand-new-repository-and-publish-it)) avoids this
  entirely.

---

## License

This project is released under the **MIT License**. See [LICENSE](LICENSE) for
the full text.

```
MIT License

Copyright (c) 2026 Dragos GALALAE

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.
```

In short: you may use, copy, modify, merge, publish, distribute, sublicense and
sell this software, provided the copyright notice and permission notice above
are kept intact. The software comes with **no warranty** of any kind.

---

## A note on this documentation

This README was **generated with the assistance of an AI coding assistant**
([Claude](https://claude.com/claude-code)) under human direction and review. The
note covers the documentation only — it makes no claim about how the scripts or
container configuration in this repository were produced.

Because the prose is machine-written, verify it against the source files before
relying on it; descriptions can drift from the code they describe. Pay particular
attention to the [Security notes](#security-notes) before exposing this to a
network — WebSVN is currently unauthenticated and there is no TLS.
