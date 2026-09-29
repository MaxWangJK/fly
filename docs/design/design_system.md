# Fly V1 Design System V4

Fly is a quiet, information-dense Windows productivity tool. It prioritizes scanning speed, keyboard flow, and stable spatial memory over decorative UI.

## Foundations

- Primary canvas: `#FAFAFA`
- Primary surface: `#FFFFFF`
- Primary module rail: `#EDEBE8`
- Task sidebar: `#F7F8FA`
- Text: `#202124`
- Border: `#E8E9EC`
- Accent: `#4D6BD8`
- Quadrant accents: red `#C86168`, orange `#C6903E`, blue `#5E7BB8`, green `#5F8D78`
- Type: Microsoft YaHei UI for Chinese, Segoe UI as utility fallback
- Spacing scale: 4, 8, 12, 16, 24, 32
- Radius scale: 4, 6, 9, 12
- Motion: 100, 180, 260 ms; auto-save debounce is 450 ms

## Signature

Selection is identified by a restrained two-pixel “flight path” line. The line appears on the active task or date while the surrounding surface stays flat. Color is functional: blue for selection and action, quadrant colors only for classification.

Task controls, title treatment, completion styling, hover, selection, and drag feedback are implemented by shared task components. Cards, floating action buttons, oversized headings, gradients, and decorative backgrounds are intentionally avoided.

## Density

- Primary module rail: 52 px; icon target: 40 px
- Task sidebar: 236 px
- Navigation item: 38 px
- Standard task row: 44 px
- Calendar and Matrix task row: 25 px
- Page title: 22 px
- Section title: 15 px
- Task title: 14 px
- Metadata: 12 px
