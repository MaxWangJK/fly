# Localization

Fly defaults to Simplified Chinese (`zh_CN`) and supports English (`en`) from the sidebar language switcher.

UI text is resolved through `FlyLocalizations` and `context.l10n`. Navigation, Completed/Trash actions, dialogs, detail fields, task menus, empty states, Calendar, Matrix, dates, weekday labels, counts, and errors use localization keys or locale-aware helper methods.

Adding a language requires:

1. Add its locale to `supportedLocales`.
2. Add a complete resource map.
3. Add locale-aware month, weekday, and date helpers.
4. Add the language to the sidebar switcher.
5. Run `flutter analyze` and `flutter test`.
