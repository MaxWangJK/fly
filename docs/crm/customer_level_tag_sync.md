# Customer Level and Tag Synchronization

Customer levels remain dynamic `CustomerCategory` records, while their linked tags are normal, removable customer tags.

- Selecting a level adds its linked tag.
- Replacing a level removes the previous linked tag and adds the new one.
- Removing the currently selected level tag clears `Customer.categoryId`.
- Removing every level tag is valid and never deletes or hides the customer.
- Sidebar level entries are shortcuts for the linked tag filter; they do not match `categoryId` independently.
- All Customers, Today, Next 7 Days, and Inbox depend on their own projections, not on customer level.

This keeps the existing schema while preventing `categoryId` and visible tags from becoming permanently inconsistent.

The high-frequency Customer Detail grid now uses a compact Customs Information entry in place of Customer Source. It shows only the first line with ellipsis and opens a spacious multiline editor for consignee, address, phone, email, and declaration notes. Customer Source remains available at the bottom of the collapsed Basic Information section.
