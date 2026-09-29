# Container presets

Built-in Fly business presets:

| Preset | Internal dimensions | Default max payload |
| --- | --- | --- |
| 40HQ | 11900 x 2200 x 2690 mm | 28000 kg |
| 20GP | 5800 x 2200 x 2320 mm | 28000 kg |

Maximum payload is copied into the plan and remains user-editable because carrier, road, tare and destination rules differ. The packing engine never hard-codes 28 tonnes.

`doorWidthMm` and `doorHeightMm` are reserved in the preset domain/database. V1 uses the supplied internal dimensions as its packing constraint and shows the required real-world verification warning.
