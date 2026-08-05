// SPDX-FileCopyrightText: 2026 IceDBorn
// SPDX-License-Identifier: GPL-3.0-or-later
//
// IceDOS window-borders: a minimal KWin effect that draws an active/inactive
// colored border around normal windows.
//
// Mechanism (from PlasmaZones): a KWin::OutlinedBorderItem scene node parented
// to each window's WindowItem; its color is the active or inactive color
// depending on whether the window is the focused one. A focus change recolors
// the two affected items in place (setOutline); only structural changes (add,
// close, desktop switch, config reload) rebuild the borders.

#pragma once

#include <effect/effect.h>
#include <scene/borderradius.h>

#include <QColor>
#include <QHash>
#include <QList>
#include <QMetaObject>
#include <QPointer>
#include <QSet>
#include <QStringList>

#include <KConfigWatcher>

namespace KWin {
class EffectWindow;
class Item;
class OutlinedBorderItem;
}

namespace WindowBorders {

/// Per-window native border (scene-graph item). `item` is a QPointer because
/// OutlinedBorderItem is parented to the window's WindowItem — Qt parent-child
/// ownership may destroy it before removeWindowBorder() runs.
struct WindowBorder
{
    QPointer<KWin::OutlinedBorderItem> item;
    QMetaObject::Connection geometryConnection;
    QPointer<KWin::Item> clippedContainer;
    KWin::BorderRadius savedContainerRadius;
};

class Effect : public KWin::Effect
{
    Q_OBJECT

public:
    Effect();
    ~Effect() override;

    static bool supported();
    static bool enabledByDefault();

    // Re-asserts each border's clip radius every frame; KWin's
    // WindowItem::updateBorderRadius() can otherwise reset it (e.g. just after a
    // CSD dialog maps), leaving content square behind the rounded outline.
    void prePaintScreen(KWin::ScreenPrePaintData& data) override;

private Q_SLOTS:
    void slotWindowAdded(KWin::EffectWindow* w);
    void slotWindowClosed(KWin::EffectWindow* w);
    void slotWindowActivated(KWin::EffectWindow* w);

private:
    void loadConfig();
    void watchWindow(KWin::EffectWindow* w);

    // Regular = plain top-level app window; Floating = dialog / tool / modal /
    // transient child; Ignored = never. Regular/Floating differ only in keepAbove
    // handling — both are bordered.
    enum class WindowKind { Ignored, Regular, Floating };
    WindowKind classify(KWin::EffectWindow* w) const;
    bool isExcluded(KWin::EffectWindow* w) const;

    void updateWindowBorder(KWin::EffectWindow* w);
    void removeWindowBorder(KWin::EffectWindow* w);
    void clearAllBorders();
    void updateAllBorders();
    void updateBorderColor(KWin::EffectWindow* w);

    // Config (~/.config/icedos-window-bordersrc, group [General]).
    QColor m_activeColor{QStringLiteral("#3daee9")};
    QColor m_inactiveColor{Qt::transparent};
    int m_borderWidth = 2;
    int m_borderRadius = 0;
    QStringList m_excludeClasses;

    QHash<KWin::EffectWindow*, WindowBorder> m_windowBorders;
    // Windows that emitted windowClosed but linger in stackingOrder until
    // windowDeleted; skipped by updateAllBorders so they aren't re-bordered while
    // they animate out.
    QSet<KWin::EffectWindow*> m_closing;

    // The currently-focused window, tracked so a focus change only recolors the
    // previously- and newly-focused windows instead of rebuilding every border.
    // QPointer self-clears if the window is destroyed.
    QPointer<KWin::EffectWindow> m_activeWindow;

    KConfigWatcher::Ptr m_configWatcher;
};

} // namespace WindowBorders
