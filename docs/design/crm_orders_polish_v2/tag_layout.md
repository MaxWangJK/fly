# Tag layout

## Customer list filter

The customer list measures each filter pill against the current list width. It lays out `全部`, visible tags, and `更多 ›` in at most two rows with a 5 px gap. If all tags do not fit, the algorithm reserves space for `更多 ›` and moves the remaining tags into its popover.

The layout is width-driven rather than count-driven. A small Windows font-metric reserve is included in measurement so the rendered row cannot overflow by a few pixels.

The popover always receives the complete tag collection and the current selected-id set. Selected tags remain checked after opening or closing the popover, and filtering remains AND-based.

## Detail tag container

Customer and order details use the same `FlyTagContainer` component. It has no visible “标签” heading, uses a subtle outline, wraps naturally, and grows vertically with its contents. Clicking a chip removes its link; clicking the empty surface opens the selector with search, selection, Enter-to-create, and removal support.

