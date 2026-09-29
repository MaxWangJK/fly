# Packing algorithm

## Single SKU

The reliable calculator evaluates unique allowed orthogonal orientations. For each orientation:

`sections = floor(container length / effective cargo length)`

`rows = floor(container width / effective cargo width)`

`layers = floor(container height / effective cargo height)`

`space capacity = sections * rows * layers`

`weight capacity = floor(max payload / unit weight)`

`maximum load = min(space capacity, weight capacity)`

Effective dimensions include the user clearance on all three axes. Non-stackable cargo is limited to one layer. The chosen orientation maximizes the final load count.

For the built-in WPC package, orientation is deliberately restricted to `2900 x 160 x 120 mm`, matching the real handling rule. In 40HQ this produces 13 rows, 22 layers, 4 sections, 286 packages per section and 1144 total.

Quantity 284 creates one 286-slot section with two explicit empty slots; it never reports or renders 286 loaded packages.

## Multiple SKUs

V1 uses a deterministic regular-slab heuristic. Heavier cargo is ordered first, each SKU chooses its best allowed cross-section, and non-overlapping slabs advance along X. This prioritizes loadability, weight safety and regular blocks over a fragmented mathematical optimum. Every packed instance still has a domain `PackedItem`; the renderer consumes batched `PackedGroup` values.

3D bin packing is NP-hard. A maximal-space/extreme-point engine can be added behind `PackingEngine` later without changing UI or storage.
