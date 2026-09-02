import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "<you>.workspaces-trading"

  // Workspace labels; anything unlisted just shows its number. These are the
  // NinjaTrader homes -- see ~/.config/hypr/ninjatrader.lua, which routes
  // windows to them.
  readonly property var labels: ({ 8: "ES", 9: "NQ", 10: "0", 11: "$" })

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  function workspaceIds() {
    // The NinjaTrader half of the bar: 8-11, always shown. Workspaces 1-7
    // live in the <you>.workspaces widget on the left. 11 has no SUPER+key
    // binding, so clicking its indicator is the only way to reach it.
    var ids = []
    for (var i = 8; i <= 11; i++) ids.push(i)
    return ids
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceIds()

      WidgetButton {
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData

        bar: root.bar
        // A labelled workspace keeps its label even when focused -- losing "NQ" on
        // the workspace you are standing on defeats the point. `active` supplies
        // the focus cue instead, so no information is lost.
        text: root.labels[modelData] !== undefined ? root.labels[modelData] : (focused ? "\uDB85\uDCFB" : String(modelData))
        active: focused
        opacity: occupied || focused ? 1 : 0.5
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : Style.space(20)
        fixedHeight: root.barSize
        onPressed: function() { root.focusWorkspace(modelData) }
      }
    }
  }
}
