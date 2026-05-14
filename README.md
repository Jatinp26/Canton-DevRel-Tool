# canton devrel

**One command. Full Canton Network on your laptop.**

Built by Canton Foundation Developer Relations for hackathons, bootcamps, and anyone who needs a local Canton Network without waiting for DevNet whitelisting.

```bash
canton devrel start
```

That's it. Three validators, a synchronizer, wallet UIs, Canton Coin, Scan UI — the whole official Splice LocalNet stack.

---

## Install

**macOS / Linux** (WSL 2 on Windows):

```bash
curl -fsSL https://raw.githubusercontent.com/Jatinp26/canton-devrel-tool/main/install.sh | bash
```

Then reload your shell:
```bash
source ~/.zshrc   # zsh
source ~/.bashrc  # bash
```

**Requirements:**
- Docker Desktop with **≥ 8 GB** memory allocated (Settings → Resources → Memory)
- `curl`, `jq`, `git` — available via `brew` (macOS) or `apt` (Linux)
- macOS or Linux only. Windows: use WSL 2.

The installer handles PATH setup and `/etc/hosts` entries for `*.localhost` domains.

---

## Commands

```bash
canton devrel start                        # download bundle + boot LocalNet
canton devrel stop                         # stop containers (data preserved)
canton devrel status                       # health check + port reference
canton devrel deploy ./my-app-0.0.1.dar    # upload your DAR to both participants
canton devrel logs                         # tail all logs
canton devrel logs <service>               # tail one service
canton devrel reset                        # wipe everything, start clean
```

---

## What Starts

| Service | URL | Login |
|---------|-----|-------|
| App User Wallet UI | http://wallet.localhost:2000 | app-user |
| App Provider Wallet UI | http://wallet.localhost:3000 | app-provider |
| Scan UI | http://scan.localhost:4000 | — |
| SV UI | http://sv.localhost:4000 | sv |
| App Provider JSON API | http://localhost:3975 | (token via Keycloak) |
| App User JSON API | http://localhost:2975 | (token via Keycloak) |
| SV JSON API | http://localhost:4975 | (token via Keycloak) |
| App Provider Ledger API (gRPC) | localhost:3901 | — |
| App User Ledger API (gRPC) | localhost:2901 | — |
| SV Ledger API (gRPC) | localhost:4901 | — |
| PostgreSQL | localhost:5432 | — |

---

## Validators

The default `canton devrel start` brings up SV + `app-provider`. You can boot a subset, a superset, or add custom validators on top.

### Boot-time flags

```bash
canton devrel start                                    # SV + app-provider
canton devrel start --validators app-provider          # absolute set
canton devrel start --only app-provider                # alias for --validators
canton devrel start --with app-user                    # additive
canton devrel start --without app-provider             # subtractive
canton devrel start --with app-user --without app-provider
```

`sv` is infrastructure and is always on — passing it explicitly is an error.

### Manage validators at runtime

```bash
canton devrel validator list                  # show all validators + health
canton devrel validator info acme             # ports, wallet URL, party hint
canton devrel validator add acme              # register + start a custom validator
canton devrel validator add bob --port-base 7900
canton devrel validator stop acme             # stop, keep data
canton devrel validator start acme            # bring back with existing ledger
canton devrel validator rm acme               # full delete (data + recipe)
```

Each custom validator joins the same local SV. Wallet UI is served via the localnet nginx on `:5000`:

- `http://wallet.acme.localhost:5000`  — wallet UI
- `http://localhost:5975`               — JSON ledger API (port_base + 75)
- `http://localhost:5903/api/validator/readyz`  — health probe

### Default validators

Persist your preferred default set at `~/.canton-devrel/.env`:
```bash
DEFAULT_VALIDATORS=app-provider,app-user,acme
```
Used by `canton devrel start` when no flags are passed and no validators are currently registered as running.

### Reset

```bash
canton devrel reset           # wipe ledger data, keep validator recipes
canton devrel reset --purge   # also wipe ~/.canton-devrel (factory reset)
```

---

## First Run

On `canton devrel start`, the tool:

1. Downloads the official Splice LocalNet bundle from the Splice GitHub release (~500MB, one-time only — cached at `~/.canton-devrel/bundle/`)
2. Pulls the Canton/Splice Docker images (~3-5 min, also cached)
3. Boots the full network using the official LocalNet compose configuration

Subsequent runs skip steps 1 and 2 entirely and boot in ~30 seconds.

## Deploying Your DAR

Build your Daml project with `dpm build`, then:

```bash
canton devrel deploy ./your-project/.daml/dist/your-project-0.0.1.dar
```

Uploads your DAR to both the App Provider and App User participants, retrieves your package ID, and prints the template ID format for API calls.

## What It Is / Isn't

**Is:** A CLI wrapper around the official [Splice LocalNet](https://docs.sync.global/app_dev/testing/localnet.html) — the same Docker Compose configuration that Digital Asset ships with every Splice release, invoked with the exact commands from the official docs. No custom compose files, no approximations.

**Isn't:** A replacement for [cn-quickstart](https://github.com/digital-asset/cn-quickstart). Quickstart is a full developer project template with a reference app, Java backend, and React frontend. This tool is just the network layer — bring your own Daml project.

**Not for production.** LocalNet is a development environment. Admin ports are exposed for developer convenience.

## Troubleshooting

**First run is slow**
Normal, the Splice bundle (~500MB) and Docker images (~3-5GB) download on first run. Everything is cached after that.

**Containers crash on startup**
Docker memory. Go to Docker Desktop → Settings → Resources → Memory → set to 8 GB minimum.

**`*.localhost` domains don't resolve**
```bash
echo "127.0.0.1  wallet.localhost scan.localhost sv.localhost" | sudo tee -a /etc/hosts
```

**Weird state / things not working**
```bash
canton devrel reset
canton devrel start
```

**See what's failing**
```bash
canton devrel logs
canton devrel logs canton       # just the Canton participant node
canton devrel logs splice       # just the Splice validator services
```

**Re-download the bundle** (if corrupted or upgrading)
```bash
rm -rf ~/.canton-devrel/bundle
canton devrel start
```

---

## Upgrading LocalNet version

Edit `~/.canton-devrel/.env` and change `IMAGE_TAG`:

```bash
IMAGE_TAG=0.5.11   # or whatever the new version is
```

Then reset and restart:
```bash
canton devrel reset
rm -rf ~/.canton-devrel/bundle   # force re-download of new bundle
canton devrel start
```

---

## Built by

Canton Foundation Developer Relations — [Jatin Pandya](https://x.com/Jpandya26).
For the LocalNet guide, tooling catalogue, and more: [Canton Developer Hub](https://github.com/Jatinp26/Canton-Developer-Hub).
Questions: join [Canton Discord](https://discord.gg/zuzEvGwtnz).