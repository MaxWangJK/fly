# Customer custom fields

Custom fields use two normalized Drift entities:

- `customer_custom_field_definitions` stores global name, type, sort order, timestamps, and soft-deletion state;
- `customer_custom_field_values` stores one value for one customer and one definition.

Supported V2 types are text, number, and date. Definitions are global: once “年采购量” is created, the field appears in every customer’s expanded Basic Information section. Values remain customer-specific.

`+ 添加字段` opens a compact name/type editor. Enter creates the definition and exposes its value editor immediately. Deleting a definition first counts affected customer values and presents that count in the confirmation. Confirmation soft-deletes the definition and its values; cancellation performs no write.

Dynamic fields intentionally do not modify the `customers` table and do not introduce formula, relation, or rollup behavior.

