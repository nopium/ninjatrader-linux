# Bar workspace indicators

Two widgets, because `allowMultiple: false` forbids placing one widget id twice:
one draws workspaces 1-7 on the left, the other draws 8-11 right of the clock
with `ES` / `NQ` / `$` labels.

## Setup

```bash
omarchy plugin clone omarchy.workspaces
# -> ~/.config/omarchy/plugins/<you>.workspaces/
```

Replace that clone's `Workspaces.qml` with `Workspaces.main.qml` from here.

For the second widget, copy the whole cloned directory, then in the copy:

- `manifest.json` — change `id` (e.g. `<you>.workspaces-trading`)
- `Workspaces.qml` — replace with `Workspaces.trading.qml` from here

Both files here use `<you>` as a placeholder; substitute your own username.

Finally place them in `~/.config/omarchy/shell.json` under `bar.layout` —
`centerAnchor` pins one widget to true centre, so items listed after it in
`center` render to its right.

## Gotcha

Widget **code** changes need a full `omarchy restart shell`. Hot-reload and
`omarchy-shell shell rescanPlugins` silently ignore them. `shell.json` layout
changes *do* hot-reload.
