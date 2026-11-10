# AGENTS.md — IceDOS **kde**

> Utilizes the **IceDOS** framework. The full bible — module structure, config flow,
> the `icedos rebuild --build` test loop, `validate.*` helpers, dep loading — lives in
> **core**: <https://github.com/IceDOS/core/blob/main/AGENTS.md> — this file only
> covers what is specific to **kde**.

## Non-negotiable rules (full detail in core)
- Build/test only via the `icedos` CLI — **never `sudo nixos-rebuild`**.
- **Never** `git commit/stash/reset/pull` — the user manages git.
- Every option uses a `validate.*`/`mk*Option` helper; **no untyped options**.
- Option-path segments that hold other options are **kebab-case** (`agent-bridge`); only leaf value keys are camelCase (`remoteLookup`).
- A module's `config.toml` defaults must mirror its `icedos.nix` defaults.
- Format with `icedos nixf .` after editing any `.nix`.
- If a repo or the config root you need isn't checked out locally, **ask the user** for
  its path or permission to `git clone` it — don't guess or clone unprompted.

## Purpose
KDE Plasma configuration for IceDOS, built on `plasma-manager`, under the
`icedos.desktop.kde` namespace.

## Layout (DE repo)
- Modules live under `modules/<group>/…/icedos.nix` (grouped, can nest a level —
  e.g. `colors-themes/{icons,splash-screen,window-decorations}`,
  `appearance-style/wallpaper`).
- `modules/default/icedos.nix` declares the `plasma-manager` flake input and the
  `icedos.desktop.kde` option root. **No root `icedos.nix`** (unlike gnome/hyprland).
- `flake.nix` scans the whole repo: `icedosLib.scanModules { path = ./.; filename = "icedos.nix"; }`.

## Module shape here
Standard IceDOS module. Plasma settings flow through `plasma-manager`'s home-manager
modules. Some Plasma settings can't be set declaratively and are patched in via
priority startup scripts / `kwriteconfig6` (see core memory on panel opacity, system
tray, layout OSD).

## Test a change to this repo
In the config root's `config.toml`, point this repo's `overrideUrl` at your local
checkout (`path:/abs/path/to/kde`), then `icedos rebuild --build` (no activation).

## Notable modules / gotchas
- Tiling/zones (`plasmazones`), `panel`, `colors-themes`, `appearance-style`, `power`, `wattmeter`, `lumen`.
- KDE also ships **in-tree KWin effects/scripts** packaged as KWin plugins — e.g.
  `window-borders` (inline C++, stylix-accent)
  (`lib/qt-6/plugins`, versioned ECM requirement).
- **KWin scripts only load at session start** — you must re-login to test them; a
  `--build` won't show their runtime effect.
- `kde-virtual-session` is the KWin backend for apps' `sunshine-headless`. It runs
  `kwin_wayland --virtual` on a private bus, Wayland-only and SDR. portal-kde needs `kde-authorized`/`remote-desktop`/`""`
  in the permission store or it shows a dialog nobody can answer. That entry must stay in the
  private store, since `""` matches every unsandboxed app. A service override on the KWin bus forces
  that store's `XDG_DATA_HOME`, and the private bus lists override dirs first because the first
  service file wins. `home = "isolated"` gives the session its own `HOME` and wallet. `home = "shared"`
  keeps the real home, and `kwin-wallet-relay.py` forwards the wallet names to the desktop's own
  `kwalletd6` and `ksecretd`, because a second `ksecretd` on the same files loses entries on save.
  Shared KWin still runs from a copy of `kwinrc`, so its virtual output never reaches the real config.
  It has the real `~/.config` in `XDG_CONFIG_DIRS`, so effects read their own rc files there and KWin writes only to the copy.
