# Compact order detail

The main order detail is optimized for first-screen scanning:

1. order number;
2. customer and order status in one responsive row;
3. priority radio choices and Important/Urgent checkbox flags in one logical region;
4. the shared auto-growing tag container;
5. order date and delivery date;
6. compact summaries for order items, financials, and the latest note;
7. file management at the bottom.

The customer name remains a navigation action back to the selected Customer workspace. Priority supplies list sorting/background treatment, while Important/Urgent appear as 11 px red text on the order row; the two signals do not overwrite each other.

The former “生产 / 工厂” area is named “订单详情” and shows no more than three factory/product/quantity summaries. Full editing opens the right extension. Factory-order-status columns remain in the database for migration compatibility but are not read or rendered by this V2 UI.

Orders cannot be created from the Orders workspace. The only creation path is Customer Detail → 新建订单, and repository validation requires an active customer.

