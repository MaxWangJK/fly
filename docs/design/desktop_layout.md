# Desktop Layout

## Expanded

```text
232 sidebar | flexible workspace | 372 selected-task detail
```

This mode preserves navigation, collection context and editing simultaneously.

## Medium

A 72-pixel labeled navigation rail replaces the sidebar. Detail opens as an addressable task page, protecting primary workspace width.

## Compact

Bottom navigation replaces side navigation. Task detail is a full page. Calendar and Matrix retain their semantics; Matrix becomes vertically stacked below 700 pixels.

## Resizing rules

- Width decisions come from shared breakpoints.
- Workspace content uses `Expanded`, `LayoutBuilder` and constrained grids.
- Calendar derives cell aspect ratio from available size.
- Long titles ellipsize.
- Detail is removed before the primary content becomes unusable.
