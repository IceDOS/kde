# SPDX-License-Identifier: GPL-3.0-or-later
#
# Inline build of the IceDOS window-borders KWin effect plugin.
#
# Built against the host's kdePackages.kwin (the running KWin), so the plugin's
# IID matches and KWin loads it. ECM's default plugin dir (lib/qt-6/plugins) is
# exactly where this-nixpkgs KWin scans its own effects — no path override.

{
  lib,
  stdenv,
  cmake,
  pkg-config,
  kdePackages,
}:

stdenv.mkDerivation {
  pname = "icedos-window-borders";
  version = "1.0.0";

  src = ./.;

  nativeBuildInputs = [
    cmake
    pkg-config
    kdePackages.extra-cmake-modules
  ];

  buildInputs = [
    kdePackages.qtbase # same set as kwin → single qtbase, no Qt mismatch
    kdePackages.kwin # private effect/scene headers + libkwin (IID-locked)
    kdePackages.kconfig # KF6::ConfigCore — reads icedos-window-bordersrc
    kdePackages.kcoreaddons # KF6::CoreAddons — kcoreaddons_add_plugin
  ];

  # Plugin-only output (no executables in $out/bin) → nothing for wrapQtAppsHook.
  dontWrapQtApps = true;

  cmakeFlags = [ "-DCMAKE_BUILD_TYPE=Release" ];

  meta = {
    description = "Minimal KWin effect: active/inactive window borders";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
  };
}
