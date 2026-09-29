# Responsive Customer Detail

At 420 logical pixels or wider, high-frequency customer fields use two columns. Below 420 they become one column without horizontal overflow.

The primary rail, customer sidebar, and customer list keep their established widths. The extension panel uses 400 pixels within the requested 340–440 range:

- at window widths of 1580 or more, it is docked to the far right;
- at narrower expanded-desktop widths, it slides/fades over the right edge of Customer Detail;
- the customer list is never compressed to make room for it.

Only one `DetailExtensionType` can be active: `none`, `notes`, or `followUps`. Switching customers preserves the active type while changing its content. Close and Escape dismiss the extension.
