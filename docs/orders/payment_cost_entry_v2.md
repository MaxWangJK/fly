# Payment and Cost Entry V2

Payment and cost records share one Windows-desktop dialog layout:

- 460 px content width with 24 px horizontal padding.
- Separate 13 px labels and 14 px input text.
- Amount prefix inherited from the order financial currency.
- Empty free-text type field with contextual placeholder examples.
- Date defaults to today and remains editable.
- File area supports click selection and drag-and-drop.

Payment fields are Amount, Type, Date, and File. Cost fields are Amount, Type, Date, and File. Editing retains the existing values; new records do not prefill a payment or cost type.

The financial panel also exposes soft-color quick cards for Deposit and Balance, plus Factory Cost, Inland Cost, and Port Charges. Clicking a quick card opens the same editor with that type selected and the amount field ready; the general Add actions keep the type field empty for free-text entry.
