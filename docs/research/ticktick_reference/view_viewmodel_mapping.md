# View / ViewModel Mapping

| View family | Observed ViewModel/service focus |
|---|---|
| MainWindow | Application shell, global commands and window lifecycle |
| MainListView / TaskListView | TaskListViewModel, current query, grouping and selection |
| TaskDetailView / detail head and popup | TaskDetailViewModel, task fields and related entities |
| CalendarControl / Month / MultiWeek | CalendarDisplayViewModel and MonthGridViewModel |
| MatrixContainer / QuadrantControl | Quadrant projections and property-changing drag actions |
| Settings components | Preference-specific ViewModels/services |
| Popups, dialogs, menus | Local decision state and command forwarding |
| Drag helpers | Translate pointer gestures into model operations |

The mapping is many-to-one in both directions: a feature ViewModel can support several compositional views, while a complex view can consume multiple focused ViewModels. Views do not own durable task truth.

## Fly translation

Fly replaces WPF ViewModels with Riverpod providers plus focused stateful editors. Repository streams expose durable records, and short-lived providers hold selection, current month, selected date, and theme.
