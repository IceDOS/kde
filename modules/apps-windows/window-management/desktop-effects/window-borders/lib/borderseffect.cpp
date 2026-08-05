// SPDX-FileCopyrightText: 2026 IceDBorn
// SPDX-License-Identifier: GPL-3.0-or-later

#include "borderseffect.h"

#include <effect/effecthandler.h>
#include <effect/effectwindow.h>
#include <scene/borderoutline.h>
#include <scene/outlinedborderitem.h>
#include <scene/windowitem.h>

#include <KConfigGroup>
#include <KSharedConfig>

namespace WindowBorders {

// ───────────────────────────── lifecycle ──────────────────────────────────

Effect::Effect()
    : KWin::Effect()
{
    loadConfig();

    auto cfg = KSharedConfig::openConfig(QStringLiteral("icedos-window-bordersrc"));
    m_configWatcher = KConfigWatcher::create(cfg);
    connect(m_configWatcher.get(), &KConfigWatcher::configChanged, this,
            [this](const KConfigGroup&, const QByteArrayList&) {
                loadConfig();
                updateAllBorders();
            });

    if (!KWin::effects) {
        return;
    }

    connect(KWin::effects, &KWin::EffectsHandler::windowAdded, this, &Effect::slotWindowAdded);
    connect(KWin::effects, &KWin::EffectsHandler::windowClosed, this, &Effect::slotWindowClosed);
    connect(KWin::effects, &KWin::EffectsHandler::windowDeleted, this, [this](KWin::EffectWindow* w) {
        m_closing.remove(w);
        removeWindowBorder(w);
        updateAllBorders();
    });
    connect(KWin::effects, &KWin::EffectsHandler::windowActivated, this, &Effect::slotWindowActivated);
    // A virtual-desktop switch changes the visible window set; redraw it.
    connect(KWin::effects, &KWin::EffectsHandler::desktopChanged, this, [this]() { updateAllBorders(); });

    // Watch windows that already exist when the effect loads (login).
    for (KWin::EffectWindow* w : KWin::effects->stackingOrder()) {
        watchWindow(w);
    }

    m_activeWindow = KWin::effects->activeWindow();

    updateAllBorders();
}

Effect::~Effect()
{
    // During compositor teardown KWin::effects can already be null; the
    // compositor reclaims the scene items itself in that case.
    if (KWin::effects) {
        clearAllBorders();
    }
}

bool Effect::supported()
{
    return true;
}

bool Effect::enabledByDefault()
{
    return true;
}

// ───────────────────────────── config ─────────────────────────────────────

void Effect::loadConfig()
{
    KConfigGroup g(KSharedConfig::openConfig(QStringLiteral("icedos-window-bordersrc")), QStringLiteral("General"));
    m_borderWidth = qBound(0, g.readEntry("BorderWidth", 2), 10);
    m_borderRadius = qBound(0, g.readEntry("BorderRadius", 0), 20);
    // Read colors as strings and build QColor ourselves: KConfig's native QColor
    // reader expects an "r,g,b,a" tuple, whereas we want "#rrggbb" and named
    // colors like "transparent". QColor(QString) handles both.
    m_activeColor = QColor(g.readEntry("ActiveColor", QStringLiteral("#3daee9")));
    m_inactiveColor = QColor(g.readEntry("InactiveColor", QStringLiteral("transparent")));
    m_excludeClasses = g.readEntry("ExcludeClasses", QStringList());
}

// ───────────────────────────── scope ──────────────────────────────────────

bool Effect::isExcluded(KWin::EffectWindow* w) const
{
    if (m_excludeClasses.isEmpty()) {
        return false;
    }
    const QString wc = w->windowClass();
    for (const QString& e : m_excludeClasses) {
        if (!e.isEmpty() && wc.contains(e, Qt::CaseInsensitive)) {
            return true;
        }
    }
    return false;
}

Effect::WindowKind Effect::classify(KWin::EffectWindow* w) const
{
    if (!w || !w->isManaged()) {
        // Unmanaged surfaces (override-redirect, plasma-shell layer surfaces) are
        // not real app windows; they would draw stray borders.
        return WindowKind::Ignored;
    }
    // Structural surfaces and ephemeral chrome — never bordered (same rejection
    // set as before): panels, desktop, plasmashell, menus, tooltips,
    // notifications, OSDs, splashes, xdg popups.
    if (w->isSpecialWindow() || w->isDesktop() || w->isDock() || w->isSkipSwitcher()) {
        return WindowKind::Ignored;
    }
    if (w->windowClass().contains(QLatin1String("plasmashell"), Qt::CaseInsensitive)) {
        return WindowKind::Ignored;
    }
    if (w->isSplash() || w->isNotification() || w->isCriticalNotification() || w->isOnScreenDisplay()
        || w->isPopupWindow() || w->isPopupMenu() || w->isDropdownMenu() || w->isMenu() || w->isTooltip()) {
        return WindowKind::Ignored;
    }
    // The user exclude-list applies to every window kind.
    if (isExcluded(w)) {
        return WindowKind::Ignored;
    }

    // Secondary windows that float over a parent — dialogs, tool/utility windows,
    // modals, and transient children. Always bordered, even when keepAbove, since
    // auth dialogs (kwallet/polkit) pin themselves above other windows.
    if (w->isDialog() || w->isUtility() || w->isModal() || w->transientFor()) {
        return WindowKind::Floating;
    }

    // A pinned plain window is skipped as before; only regular windows honor this.
    if (w->keepAbove()) {
        return WindowKind::Ignored;
    }

    // Plain top-level application window — bordered.
    if (w->isNormalWindow()) {
        return WindowKind::Regular;
    }

    return WindowKind::Ignored;
}

// ───────────────────────────── borders ────────────────────────────────────
// Distilled from PlasmaZones kwin-effect/plasmazoneseffect/borders.cpp.

void Effect::removeWindowBorder(KWin::EffectWindow* w)
{
    auto it = m_windowBorders.find(w);
    if (it == m_windowBorders.end()) {
        return;
    }
    WindowBorder& wb = it.value();
    if (wb.clippedContainer) {
        wb.clippedContainer->setBorderRadius(wb.savedContainerRadius);
    }
    // QPointer: item may already be null if Qt parent-child ownership destroyed
    // it. Hide-then-deleteLater avoids a one-frame Z-fight when updateWindowBorder
    // immediately re-allocates a new item under the same parent.
    if (wb.item) {
        wb.item->setVisible(false);
        wb.item->deleteLater();
    }
    QObject::disconnect(wb.geometryConnection);
    m_windowBorders.erase(it);
}

void Effect::clearAllBorders()
{
    while (!m_windowBorders.isEmpty()) {
        removeWindowBorder(m_windowBorders.begin().key());
    }
}

void Effect::updateWindowBorder(KWin::EffectWindow* w)
{
    removeWindowBorder(w);

    const int bw = m_borderWidth;
    if (bw <= 0) {
        return;
    }
    if (!w || w->isMinimized() || w->isFullScreen()) {
        return;
    }
    if (classify(w) == WindowKind::Ignored) {
        return;
    }

    // Active window gets the active color; everything else the inactive color.
    const bool focused = (w == KWin::effects->activeWindow());
    const QColor bc = focused ? m_activeColor : m_inactiveColor;
    if (!bc.isValid() || bc.alpha() == 0) {
        return; // fully-transparent inactive color == "no border when unfocused"
    }

    // Inset by border width so the outline draws inside the frame (the parent
    // WindowItem clips children to the frame).
    const QRectF frame = w->frameGeometry();
    const KWin::RectF innerRect(bw, bw, frame.width() - 2.0 * bw, frame.height() - 2.0 * bw);
    const int br = m_borderRadius;
    const KWin::BorderOutline outline(bw, bc, KWin::BorderRadius(br));

    KWin::WindowItem* windowItem = w->windowItem();
    if (!windowItem) {
        return;
    }

    WindowBorder wb;
    wb.item = new KWin::OutlinedBorderItem(innerRect, outline, windowItem);

    // Round the window content corners to match the outline so squared content
    // doesn't poke past a rounded border. Clip the windowContainer (full frame),
    // not the surface — see PlasmaZones borders.cpp for the SSD-vs-CSD rationale.
    if (bw > 0) {
        KWin::Item* container = windowItem->windowContainer();
        if (container) {
            wb.savedContainerRadius = container->borderRadius();
            container->setBorderRadius(KWin::BorderRadius(br + bw));
            wb.clippedContainer = container;
        }
    }

    // Keep the border in sync when the window resizes or moves.
    wb.geometryConnection =
        connect(w, &KWin::EffectWindow::windowFrameGeometryChanged, this,
                [this, w, bw, br](KWin::EffectWindow* ew, const QRectF& /*oldGeo*/) {
                    auto it = m_windowBorders.find(w);
                    if (it == m_windowBorders.end()) {
                        return;
                    }
                    const QRectF f = ew->frameGeometry();
                    if (it->item) {
                        it->item->setInnerRect(KWin::RectF(bw, bw, f.width() - 2.0 * bw, f.height() - 2.0 * bw));
                    }
                    // KWin's WindowItem::updateBorderRadius() resets the container to
                    // the window's own radius on geometry/state changes; re-assert ours
                    // so CSD-dialog content stays clipped to the rounded outline.
                    if (it->clippedContainer) {
                        it->clippedContainer->setBorderRadius(KWin::BorderRadius(br + bw));
                    }
                });

    m_windowBorders.insert(w, wb);
}

void Effect::updateAllBorders()
{
    clearAllBorders();

    if (m_borderWidth <= 0 || !KWin::effects) {
        return;
    }

    // Border every decoratable, visible window on the current desktop.
    // updateWindowBorder() skips minimized / fullscreen windows, where a border is
    // pointless. Maximized windows ARE bordered — only true fullscreen is bare.
    for (KWin::EffectWindow* w : KWin::effects->stackingOrder()) {
        if (!w || w->isDeleted() || m_closing.contains(w) || !w->isOnCurrentDesktop()) {
            continue;
        }
        if (classify(w) == WindowKind::Ignored) {
            continue;
        }
        updateWindowBorder(w);
    }
}

// Recolor one window's border for a focus change without tearing anything down.
// A transparent color means "no border in that state", so the border is removed
// or created as needed; otherwise the existing item is recolored in place via
// setOutline (the item's innerRect and clip radius are untouched).
void Effect::updateBorderColor(KWin::EffectWindow* w)
{
    // Filter parity with updateAllBorders() and updateWindowBorder(): these
    // windows never carry a border. Remove a stale one rather than skipping, so
    // transitions with no cheap signal to watch (e.g. keepAbove toggled) don't
    // leave a wrongly-colored border behind.
    const bool eligible = w && !w->isDeleted() && !m_closing.contains(w) && w->isOnCurrentDesktop()
        && !w->isMinimized() && !w->isFullScreen() && classify(w) != WindowKind::Ignored;
    if (!eligible) {
        if (w && m_windowBorders.contains(w)) {
            removeWindowBorder(w);
        }
        return;
    }

    const bool focused = (w == KWin::effects->activeWindow());
    const QColor bc = focused ? m_activeColor : m_inactiveColor;
    auto it = m_windowBorders.find(w);
    if (!bc.isValid() || bc.alpha() == 0) {
        // Transparent color: only focused windows carry a border, so drop it if
        // this one lost focus.
        if (it != m_windowBorders.end()) {
            removeWindowBorder(w);
        }
        return;
    }
    if (it != m_windowBorders.end() && it->item) {
        it->item->setOutline(KWin::BorderOutline(m_borderWidth, bc, KWin::BorderRadius(m_borderRadius)));
        return;
    }
    // No border yet (e.g. this window gained focus while the inactive color was
    // transparent, so it never had one) — create it.
    updateWindowBorder(w);
}

// ───────────────────────────── paint ──────────────────────────────────────

void Effect::prePaintScreen(KWin::ScreenPrePaintData& data)
{
    // KWin's WindowItem::updateBorderRadius() can reset our clip radius back to the
    // window's own value after we set it — notably right after a CSD dialog maps,
    // with no signal to react to. Re-assert it every frame; the != guard makes this
    // a no-op once correct, so it schedules no repaint and can't loop.
    if (m_borderWidth > 0) {
        const KWin::BorderRadius target(m_borderRadius + m_borderWidth);
        for (auto it = m_windowBorders.begin(); it != m_windowBorders.end(); ++it) {
            if (it->clippedContainer && it->clippedContainer->borderRadius() != target) {
                it->clippedContainer->setBorderRadius(target);
            }
        }
    }
    KWin::effects->prePaintScreen(data);
}

// ───────────────────────────── slots ──────────────────────────────────────

void Effect::watchWindow(KWin::EffectWindow* w)
{
    if (!w) {
        return;
    }
    // Minimize / fullscreen / desktop-move transitions change whether a window
    // should be bordered; maximize only changes its geometry. Recompute every border
    // on each. `this` as the context auto-disconnects when the window is destroyed,
    // so these need no manual cleanup.
    connect(w, &KWin::EffectWindow::minimizedChanged, this, [this]() { updateAllBorders(); });
    connect(w, &KWin::EffectWindow::windowMaximizedStateChanged, this, [this]() { updateAllBorders(); });
    connect(w, &KWin::EffectWindow::windowFullScreenChanged, this, [this]() { updateAllBorders(); });
    connect(w, &KWin::EffectWindow::windowDesktopsChanged, this, [this]() { updateAllBorders(); });
    // keepAbove toggling changes whether a window is bordered (classify() ignores
    // keep-above windows) but, unlike the transitions above, nothing else rebuilds
    // borders for it — recolor just this window.
    connect(w, &KWin::EffectWindow::windowKeepAboveChanged, this, [this, w]() { updateBorderColor(w); });
}

void Effect::slotWindowAdded(KWin::EffectWindow* w)
{
    watchWindow(w);
    // Border the new window and refresh colors on the rest.
    updateAllBorders();
}

void Effect::slotWindowClosed(KWin::EffectWindow* w)
{
    // The closed window may linger in stackingOrder until windowDeleted; mark it so
    // updateAllBorders skips re-bordering it while it animates out.
    m_closing.insert(w);
    removeWindowBorder(w);
    updateAllBorders();
}

void Effect::slotWindowActivated(KWin::EffectWindow* w)
{
    // Steady-state focus switch: only the previous and newly-focused windows
    // change color. Rebuilding every border on each activation (the former
    // updateAllBorders approach) tore down and re-created every
    // OutlinedBorderItem per focus change — jank on rapid window switching.
    // Recolor the two affected windows in place instead.
    KWin::EffectWindow* prev = m_activeWindow.data();
    m_activeWindow = w;
    if (prev == w) {
        return; // duplicate / re-entrant activation
    }
    if (prev) {
        updateBorderColor(prev);
    }
    if (w) {
        updateBorderColor(w);
    }
}

} // namespace WindowBorders

// ── KWin effect factory ────────────────────────────────────────────────────
namespace KWin {

KWIN_EFFECT_FACTORY_SUPPORTED(WindowBorders::Effect, "metadata.json", return WindowBorders::Effect::supported();)

} // namespace KWin

// MOC include — REQUIRED for the Q_OBJECT generated by KWIN_EFFECT_FACTORY_SUPPORTED.
#include "borderseffect.moc"
