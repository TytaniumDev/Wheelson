# Wheelson - Gemini Context

Wheelson is a World of Warcraft addon (Lua) designed to form balanced Mythic+ groups from guild members using a wheel-spin reveal animation. It targets WoW 12.0 (Midnight) and utilizes the AceAddon-3.0 framework for its core structure and communication.

## Project Overview

- **Purpose:** Automate group formation for Mythic+ dungeons within a WoW guild, ensuring balanced roles (tank, healer, DPS) and utility (battle rez, bloodlust).
- **Tech Stack:** Lua (target 5.1), Ace3 Framework (Addon, Comm, Event, Console, DB, Serializer, GUI, Config), LibDataBroker, LibDBIcon.
- **Architecture:** 
    - **Global Namespace:** The addon object is stored in `_G.Wheelson` (aliased as `WHLSN` locally).
    - **State Machine:** Sessions transition through `nil` -> `lobby` -> `spinning` -> `completed`.
    - **Communication:** Uses `AceComm-3.0` over the `GUILD` and `WHISPER` channels for real-time synchronization between members.
    - **Serialization:** Models (`Player`, `Group`) use `:ToDict()` and `.FromDict()` for message passing.

## Building and Running

WoW addons do not require a traditional build step, but this project includes validation and quality tools.

- **Linting:** 
  ```bash
  luacheck src/ tests/
  ```
- **Testing:** 
  ```bash
  busted
  ```
  Tests are located in the `tests/` directory and use the `busted` framework with WoW API stubs.
- **Validation:** 
  ```bash
  bash scripts/build.sh
  ```
  Verifies that the `.toc` file is correct and all required source files are present.
- **Development:** Link the repository to your WoW `Interface/AddOns/Wheelson` directory to test in-game.

## Development Conventions

- **WoW 12.0 API:** Exclusively use modern `C_` namespaced APIs (e.g., `C_Timer`, `C_SpecializationInfo`). Do not use deprecated global functions.
- **File Load Order:** Defined in `Wheelson.toc`. Core configuration must be loaded before logic and UI.
- **Coding Style:** 
    - 120 character line limit.
    - Lua 5.1 compatibility.
    - Use `WHLSN` local alias for the global namespace.
    - Append to tables using `t[#t + 1] = value`.
- **Testing Pattern:** Always stub WoW APIs and `LibStub` at the beginning of test files, then use `dofile()` to load source files in order.
- **UI:** XML for frame definitions (`src/UI/MainFrame.xml`) and Lua for logic.

## Key Files

- `Wheelson.toc`: Metadata and file load order.
- `src/Config.lua`: Constants, role mappings, and default settings.
- `src/Core.lua`: Addon lifecycle, session management, and communication handlers.
- `src/Models.lua`: `WHLSN.Player` and `WHLSN.Group` class definitions.
- `src/GroupCreator.lua`: The core group formation algorithm.
- `CLAUDE.md`: Detailed engineering standards and workflow instructions for AI agents.
