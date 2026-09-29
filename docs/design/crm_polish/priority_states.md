# Priority States

Customer and Order share `PriorityLevel`, `PrioritySelector`, and `PriorityColorTokens`.

| Priority | Selector | Row base | Selected row |
| --- | --- | --- | --- |
| High | soft red, red text | very light red | slightly stronger light red plus border |
| Medium | soft amber, amber text | very light amber | slightly stronger light amber plus border |
| Low | neutral | transparent | Fly neutral selected surface plus border |

Priority owns the row background. Status remains a small colored label. Important and urgent remain small indicators and never replace the priority field. Selected state is expressed through a stronger overlay and subtle border, so it does not erase priority.
