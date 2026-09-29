# Order extensions

`OrderExtensionType` has four mutually exclusive states: `none`, `orderDetails`, `financial`, and `notes`. Selecting one summary replaces any previously open order extension.

On wide windows (at least 1620 px), the 420 px extension is docked after Primary Rail, Secondary Sidebar, List, and Detail. Below that breakpoint it overlays the detail area so navigation and the order list remain stable and usable.

## Order details

The extension shows soft-colored item blocks and a compact add action. Factory, product, and quantity are required. Factory and product inputs autocomplete existing definitions and accept Enter-to-create; quantity contains a numeric value and free-form unit. Validation keeps the editor open until all required inputs are valid.

## Notes

Order notes use their own `OrderNote` entity but reuse the customer extension framework, history blocks, search, color treatment, and input behavior. Enter saves; Shift+Enter inserts a line break. The main detail renders only the latest note preview.

