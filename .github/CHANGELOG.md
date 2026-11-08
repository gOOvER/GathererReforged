# Changelog

All notable changes to **Gatherer Reforged** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.2] - 2026-11-08

### Fixed
- **Suppress Self-Echoed Node Broadcasts (`Core/GatherComm.lua`, `Core/GatherIntegrations.lua`)**:
  - Recorded outgoing `GathX`, `GRBNode`, `GM2SD`, and `GatherRadar` payloads (`lastSentMessage` / `lastExternalSent`) on send and enhanced `isSelfSender(who)` to strip `-Realm` suffixes (including realms with spaces) and match character surnames (e.g. `"Shyvin Shy"` on WoW Forever where `UnitName("player")` returns `"Shyvin"`), preventing the player's own gathered nodes from being echoed back as received guild/group nodes.

## [1.0.1] - 2026-11-08

### Added
- **Dynamic Price Source Selector**: Added a **Price Source** dropdown under *Integrations & DB* that dynamically lists only currently installed/loaded Auction House addons (**Auctioneer Reforged**, **Auctionator**, **TradeSkillMaster (TSM)**, **OribosExchange**, **RECrystallize**) alongside *Automatic* and *Vendor Sell Price Only*.
- **Enhanced Auctioneer Reforged Support**: Added fallback support for `Auc-Util-Appraiser` (`Appraiser.GetPrice`) and `Informant` (`Informant.GetItem`) vendor prices, and added `Auc-Advanced` and `Informant` to `OptionalDeps`.

### Changed
- Prioritized **Auctioneer Reforged** first when the price source is set to *Automatic*.

### Fixed
- **Accurate Node Recording Only on Interaction (`Core/GatherScanner.lua`)**:
  - Disabled automatic background Minimap radar node saving (`runMinimapRadarScan`) and premature `WorldFrame:OnMouseDown` recording that previously saved nodes while merely hovering, turning the camera, or clicking from a distance.
  - Nodes are now saved **only** when actually gathered (`LOOT_READY` / `LOOT_OPENED` right at the node) or when a right-click within interact range triggers a locked/skill-requirement message (`UI_ERROR_MESSAGE`).
- **Classic & Forever Profession Skill Detection (`Core/GatherUtil.lua`)**:
  - Updated `Gatherer.Util.GetSkills()` to check both modern `GetProfessions()` and Classic `GetNumSkillLines()` / `GetSkillLineInfo()`, preventing Herbalism/Mining from being treated as unlearned on hybrid clients.
- **Node Deduplication & Position Accuracy (`Core/GatherStorage.lua`)**:
  - Increased node merge radius to `20` yards (or `0.006` normalized zone coordinates) and ensured real harvests overwrite any previous unharvested `"REQUIRE"` coordinates instead of averaging with them.
  - Added automatic startup deduplication in `PurgeInvalidDynamicNodes()` to merge existing duplicate node trails in `GatherItems`.
- Fixed missing close button (`UI-StopButton`) and checkbox checkmark (`UI-CheckBox-Check`) icons in `GathererConfigFrame`, `GathererReportFrame`, and `GathererNodeSearchFrame` when running alongside `ElvUI` / `AddOnSkins` or custom UI fonts.
- **ElvUI Ace3 Skin Compatibility (`GUI/GatherReport.lua`, `GUI/GatherAceGUI.lua`)**: Cleared `callbackBackdropColor` and hid `iborder`/`oborder` in `UIStyle.ApplyBox`, hid `checkbg.backdrop` in `styleAceCheckBox`, and enforced left-aligned text on AceGUI `Dropdown` widgets when ElvUI's Ace3 skin is active.

## [1.0.0] - 2026-11-07

### Added
- **Cross-Addon Sharing Bridge**: Live node sharing and synchronization with **Gatherer Reborn** (`GRBNode`), **GatherMate2_Sharing** (`GM2SD`/`GMSD`), **GatherRadar** (`GatherRadar`), and **GatherLite** (`G2G`) across Guild, Party, Raid, and Instance channels.
- **Virtual Minimap Radar Scanner**: Coroutine-based Minimap radar (`Minimap:UpdateMouseoverAtPoint` + `C_TooltipInfo.GetMinimapMouseover`) that automatically detects and records tracked herbs, ores, treasures, and fishing pools from up to ~100 yards away, complete with skill-difficulty border rings and a live-radar glow indicator.
- **1-Click `GatherMate2` & `GatherMate2_Data` Importer**: Direct database import for saved `GatherMate2` / `GatherRadar` nodes and pre-populated Wowhead databases across all expansions (`/gatherer import`).
- **Live Market Values**: Displays current Auction House prices from **Auctionator**, **TradeSkillMaster (TSM)**, **OribosExchange**, **RECrystallize**, and **Auctioneer** in node tooltips and reports.
- **Session & Gold-per-Hour (GPH) Tracker**: Tracks session duration, nodes/hour, loot value, and GPH in the LDB feed, Minimap tooltip, and Report sidebar (`/gatherer session`, `/gatherer reset`).
- **Harvest Cooldown ("Respawn Timer")**: Automatically dims recently harvested nodes on the Minimap and 3D HUD for a configurable respawn duration.
- **Ecosystem Integrations**: Native support for **MapWise**, **Routes**, **FarmHud**, **ElvUI**, **Leatrix Maps**, and **TomTom** / Blizzard waypoints (`Shift+Right-Click` or `Alt+Left-Click` on World Map pins).
- **Modernized UI & Built-in 3D HUD**:
  - Redesigned **Gatherables Report** and **Node Density Search** windows with category tabs, instant search, sortable columns, and waypoint support.
  - Added live **UI Font Size (`10pt – 18pt`)** scaling (`A-` | `13pt` | `A+` header buttons in `GathererConfigFrame`, `GathererReportFrame`, and `GathererNodeSearchFrame`) with automatic button width calculation (`btn:UpdateSize()`) so localized labels never overflow.
  - Integrated **3D Heads-Up Display (HUD)** directly into the main AddOn.
  - **Ace3** options panel (`AceConfig-3.0` / `AceGUI-3.0`), **`LibDBIcon-1.0`**, **`LibDataBroker-1.1`**, and Blizzard **Addon Compartment** support.
- **Multi-Client & Dynamic Node Support**: Native `C_Map` mapping engine and automatic discovery of new herbs, ores, treasures, fishing schools, gas clouds, and archaeology nodes across **Retail (12.x)**, **Classic Progression**, **Classic Era**, and **WoW Forever (16001)**, including recording herbs and ores on click even without Herbalism or Mining learned.

### Changed
- Rebranded and modernized Norganna's classic *Gatherer* as **Gatherer Reforged** under **GPL-3.0** (upgraded from `GPL-2.0-or-later`).
- Migrated all 18 supported languages (`enUS`, `deDE`, `frFR`, `esES`, `esMX`, `itIT`, `ptBR`, `ptPT`, `ruRU`, `koKR`, `zhCN`, `zhTW`, `csCZ`, `daDK`, `elGR`, `nlNL`, `plPL`, `trTR`) to native **`AceLocale-3.0`** files with 100% translation coverage.
- Modernized node icon resolution using built-in FileDataIDs and item icon fallbacks to prevent missing textures across game flavors.

### Fixed
- Resolved WoW 12.x `<secret string>` taint errors during tooltip and world object scanning.
- Added pre-Cataclysm Classic and *WoW Forever* localized node aliases and canonical `PrimaryNames` across all locales (e.g., German `"Kupfervorkommen"`, `"Zinnvorkommen"`, `"Winterbiss"`, `"Pestblüte"`) so localized clients always display native node names instead of English variant aliases, and prioritized built-in `Gatherer.Icons` over `Gatherer_DropRates` in `GetGatherTexture` so treasure chests and barrels always show their container icons instead of random looted item icons.
- Strict `GameObject-` GUID, spell, and tooltip-type validation in the loot and unskilled-click scanners, plus automatic database cleanup/migration after `GatherItems` loads, preventing mob corpses, quest objects, or stale herb tooltips from ever being recorded on ore veins.
- Fixed modern WoW API compatibility across `C_Map`, `C_AddOns`, `C_Minimap`, `C_ChatInfo`, `BackdropTemplate`, and `StaticPopupDialogs`.
- Fixed 3D HUD combat detection, icon trimming, and indoor/instance facing handling.

### Removed
- Removed discontinued legacy libraries (`Astrolabe`, `DongleStub`, `Babylonian`, `!Swatter`, `SlideBar`) and obsolete XML configuration frames.

---

# Legacy Changelog (Gatherer Upstream)

## [7.3.1] - 2017-09-05
- Final upstream release of Norganna's *Gatherer* (Legion Patch 7.3) prior to **Gatherer Reforged** (`1.0.0`).
