# Canton Builder Tool

**One command. Full Canton Network on your laptop.**

Built for builders who needs a local Canton Network without waiting for DevNet whitelisting. Three validators, a synchronizer, wallet UIs, Canton Coin, Scan UI plus optional Keycloak (OAuth2) and PQS assembled from the LocalNet compose modules in [cn-quickstart](https://github.com/digital-asset/cn-quickstart).

## Install

**macOS / Linux** (WSL 2 on Windows):

```bash
curl -fsSL https://raw.githubusercontent.com/canton-network-devs/Canton-Builder-Tool/main/install.sh | bash
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

## Commands

```bash
# boot LocalNet
canton builder start                

# boot with Keycloak (OAuth2 / OIDC)
canton builder start --auth   

# boot with Participant Query Store
canton builder start --pqs       

# stop containers (data preserved)
canton builder stop                

# health check + port reference
canton builder status       

# parties, tokens, API URLs, credentials
canton builder env                     

# print a bearer token
canton builder token --validator app-provider   

# upload your DAR to both participant local validators
canton builder deploy ./my-app-0.0.1.dar    

# tail all logs
canton builder logs                       

# tail one service
canton builder logs <service>            

# wipe everything, start clean
canton builder reset                        
```

## What Starts

| Service | URL | Credential |
|---------|-----|-------|
| App User Wallet UI | http://wallet.localhost:2000 | app-user |
| App Provider Wallet UI | http://wallet.localhost:3000 | app-provider |
| Scan UI | http://scan.localhost:4000 | - |
| SV UI | http://sv.localhost:4000 | sv |
| App Provider JSON API | http://localhost:3975 | - |
| App User JSON API | http://localhost:2975 | - |
| SV JSON API | http://localhost:4975 | - |
| App Provider Ledger API (gRPC) | localhost:3901 | - |
| App User Ledger API (gRPC) | localhost:2901 | - |
| SV Ledger API (gRPC) | localhost:4901 | - |
| Keycloak *(with `--auth`)* | http://keycloak.localhost:8082 | admin / admin |
| PostgreSQL | localhost:5432 | - |

## Authentication

By default LocalNet uses **self-signed HS256 tokens**, a shared `unsafe` secret, no identity provider. The tool mints tokens for you and `deploy` handles auth automatically, so most local development needs nothing more. This is the fastest path.

Need to test a real OAuth2 / OIDC flow, say your SDK does a client-credentials grant against an issuer? Add `--auth`:

This layers in Keycloak:

- **Admin console:** http://keycloak.localhost:8082 (admin / admin)
- **Realms:** `AppProvider`, `AppUser`
- **Grant:** `client_credentials`
- **Token endpoint:** `http://keycloak.localhost:8082/realms/{AppProvider,AppUser}/protocol/openid-connect/token`

Pull everything you need i.e. client IDs/secrets, token URLs, party IDs, and a ready-to-use token with one command:

```bash
canton builder env
```

`canton builder token` and `canton builder env` are mode-aware: in the default mode they mint self-signed tokens, with `--auth` they fetch real tokens from Keycloak.

## Participant Query Store (PQS)

Add `--pqs` to run Scribe against the participants, giving you a queryable PostgreSQL projection of the ledger.

## Validators

The default `canton builder start` brings up SV + `app-provider`. You can boot a subset, a superset, or add custom validators on top.

### Boot-time flags

```bash
canton builder start                                    # SV + app-provider

canton builder start --validators app-provider          # absolute set

canton builder start --only app-provider                # alias for --validators

canton builder start --with app-user                    # additive

canton builder start --without app-provider             # subtractive

canton builder start --auth --pqs --with app-user       # flags compose
```

### Manage validators at runtime

```bash
canton builder validator list                  
# show all validators + health

canton builder validator info acme             
# ports, wallet URL, party hint

canton builder validator add acme              
# register + start a custom validator

canton builder validator add bob --port-base 7900

canton builder validator stop acme             
# stop, keep data

canton builder validator start acme            
# bring back with existing ledger

canton builder validator rm acme               
# full delete (data + recipe)
```

Each custom validator joins the same local SV. Wallet UI is served via the localnet nginx on `:5500`:

- `http://wallet.acme.localhost:5500`   wallet UI
- `http://localhost:5975`               JSON ledger API (port_base + 75)
- `http://localhost:5903/api/validator/readyz`  health probe

### Default validators

Persist your preferred default set at `~/.canton-builder/.env`:
```bash
DEFAULT_VALIDATORS=app-provider,app-user,acme
```
Used by `canton builder start` when no flags are passed and no validators are currently registered as running.

### Reset

```bash
canton builder reset           
# wipe ledger data, keep validator recipes

canton builder reset --purge   
# also wipe ~/.canton-builder (factory reset)
```

## Deploying Your DAR

Build your Daml project with `dpm build`, then:

```bash
canton builder deploy ./your-project/.daml/dist/your-project-0.0.1.dar
```

Uploads your DAR to both the App Provider and App User participants, retrieves your package ID, and prints the template ID format for API calls. Works in both auth modes, the access token is obtained automatically for whichever mode you started in.

## Interacting With Your Contracts

Once deployed, use the JSON Ledger API to create contracts, exercise choices, and query state. Grab a token with `canton builder token` (or the full picture with `canton builder env`) and point your calls at the participant's JSON API port from the table above.

## What It Is / Isn't

**Is:** A thin CLI over the official LocalNet compose modules from [cn-quickstart](https://github.com/digital-asset/cn-quickstart)'s reference project, pinned to a known-good version. It assembles the same modules cn-quickstart's Makefile does (`localnet`, `splice-onboarding`, and optionally `keycloak` and `pqs`) and drives them with plain `docker compose`. No custom compose files, no approximations.

**Isn't:** A replacement for cn-quickstart. Quickstart is a full developer project template with a reference app, Java backend, and React frontend. This tool is just the network layer, bring your own Daml project. |

> *Built by Developer Relations at Canton Foundation.*