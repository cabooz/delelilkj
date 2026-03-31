#!/bin/bash
#═══════════════════════════════════════════════════════════════════════════════
# GET ALL WINDOWS - virtual-desktops plugin compatible
#═══════════════════════════════════════════════════════════════════════════════
# Map windows to vdesks via workspace name (Grid-1 … Grid-9).
# Works correctly on multi-monitor setups: all monitors on the same virtual
# desk share the same "Grid-N" workspace name, so every window is captured
# regardless of which monitor it lives on.
#═══════════════════════════════════════════════════════════════════════════════

hyprctl clients -j | jq '[
    .[]
    | select(.workspace.name | test("^Grid-[1-9]$"))
    | .vdesk = (.workspace.name | ltrimstr("Grid-") | tonumber)
    | {
        vdesk:   .vdesk,
        address: .address,
        title:   .title,
        class:   .class,
        x:       .at[0],
        y:       .at[1],
        width:   .size[0],
        height:  .size[1]
    }
]'
