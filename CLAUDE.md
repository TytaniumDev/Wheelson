# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MythicPlusWheel is a World of Warcraft addon (Lua, WoW API) that forms balanced Mythic+ dungeon groups from guild members using a wheel-spin reveal animation. It uses AceAddon-3.0 framework and communicates between guild members via AceComm.

## Commands

### Lint
```bash
luacheck src/ tests/
```

### Test
```bash
busted
```
Tests use the [busted](https://olivinelabs.com/busted/) framework. Config is in `.busted` — tests live in `tests/` with the `test_` prefix pattern.

### Run a single test file
```bash
busted tests/test_models.lua
```

### Build validation
```bash
bash scripts/build.sh
```
Checks that the `.toc` file exists and all source files listed in it are present on disk.

## Architecture

### Global namespace pattern
The addon registers itself as `MythicPlusWheel` via AceAddon in `src/Config.lua`, stored in `_G.MythicPlusWheel`. Every other source file accesses it via `local MPW = _G.MythicPlusWheel` and attaches methods/data to it. There is no module system — all files share the single `MPW` table.

### File load order (defined by `MythicPlusWheel.toc`)
1. **Config.lua** — Creates the addon object, defines constants (roles, spec→role mapping, session states, saved variable defaults)
2. **Models.lua** — `MPW.Player` and `MPW.Group` classes (metatables with `:New()`, `:ToDict()`, `.FromDict()` serialization)
3. **GroupCreator.lua** — Group formation algorithm (port of `parallelGroupCreator.ts`). Assigns tanks → lust → brez → healers → ranged → remaining DPS with duplicate-avoidance across runs
4. **Core.lua** — Addon lifecycle (`OnInitialize`/`OnEnable`), slash commands (`/mpw`), session state machine (lobby → spinning → completed), addon comm message handling, session timeout
5. **Services/** — `SpecService` (local player spec detection, realm name stripping), `GuildService` (roster queries), `PartyService` (party invites)
6. **UI/** — `MainFrame.xml` + `MainFrame.lua` (window shell, view switching), `Lobby.lua` (player list + join/spin), `Wheel.lua` (animated group reveal), `GroupDisplay.lua` (final results with invite/post/copy actions)

### Session state machine
`MPW.session.status`: `nil` → `"lobby"` → `"spinning"` → `"completed"`. The host broadcasts state to guild via `AceComm` (`GUILD` channel, prefix `MPWheel`). Non-hosts send `JOIN_REQUEST`/`LEAVE_REQUEST` messages.

### Group creation algorithm
`GroupCreator.lua` is a direct port of `parallelGroupCreator.ts` from a companion TypeScript project. It fills groups in priority order: tanks, lust providers, brez providers, healers, ranged DPS, remaining DPS. It tracks previous group compositions per guild to avoid repeat teammate assignments.

### Test structure
Tests stub WoW APIs and `LibStub` at the top of each file, then `dofile()` the source files in load order. Only non-UI logic is tested (Models, GroupCreator, GuildService, SpecService). The test stubs pattern is consistent across all test files — copy from an existing test when adding new ones.

## Key Conventions

- Lua 5.1 target (`std = "lua51"` in `.luacheckrc`), 120 char line limit
- Roles are strings: `"tank"`, `"healer"`, `"ranged"`, `"melee"`
- Utilities are strings: `"brez"`, `"lust"`
- Player identity comparison uses `Player:Equals()` (name-based)
- Serialization for addon comms uses `:ToDict()` / `.FromDict()` pattern on model classes
- Table append idiom: `t[#t + 1] = value` (not `table.insert`)
- External libraries (Ace3, LibStub, etc.) are fetched at release time by BigWigsMods packager per `.pkgmeta` — the `libs/` dir is gitignored except `.gitkeep`
- **CI job naming constraint:** `.github/workflows/ci-shared.yml` is a reusable workflow (`workflow_call` only) that defines three jobs: `Lint`, `Build`, `Test`. It is called by `.github/workflows/ci.yml` (trigger: `pull_request` only) via a calling job with ID `CI`. GitHub Actions names reusable workflow checks as `<calling_job_id> / <reusable_job_id>`, producing `CI / Lint`, `CI / Build`, `CI / Test` — which branch protection requires. Do not rename the calling job ID in `ci.yml` or the job IDs in `ci-shared.yml`, and do not add extra triggers to `ci.yml`.
