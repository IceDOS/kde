# SPDX-FileCopyrightText: 2026 IceDBorn
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Single KWin effect plugin (active/inactive window borders). Requires KWin from
# Plasma 6.7+ for the OutlinedBorderItem scene API. The plugin IID embeds KWin's
# exact version, so it is rebuilt against the host KWin on every system rebuild.

cmake_minimum_required(VERSION 3.16)
project(IcedosWindowBorders VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

# ECM version matters: KDECMakeSettings only sets CMAKE_LIBRARY_OUTPUT_DIRECTORY
# (required by kcoreaddons_add_plugin) when ECM_GLOBAL_FIND_VERSION >= 5.38.0, so
# a version MUST be requested here.
find_package(ECM 6.0 REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})
include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)

# Widgets + DBus are in KWin::kwin's link interface but KWinConfig.cmake does not
# find_dependency() them, so we must create those imported targets ourselves.
find_package(Qt6 6.10 REQUIRED COMPONENTS Core Gui Widgets DBus)
find_package(KF6 REQUIRED COMPONENTS Config CoreAddons)
find_package(KWin 6.7 REQUIRED)

list(APPEND CMAKE_AUTOMOC_MACRO_NAMES "KWIN_EFFECT_FACTORY_SUPPORTED")

kcoreaddons_add_plugin(icedos-window-borders
    SOURCES
        borderseffect.cpp
        borderseffect.h
    INSTALL_NAMESPACE "kwin/effects/plugins")

target_link_libraries(icedos-window-borders PRIVATE
    KWin::kwin
    Qt6::Core
    Qt6::Gui
    KF6::ConfigCore
    KF6::CoreAddons)

target_include_directories(icedos-window-borders PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_BINARY_DIR})
