import 'task_list.dart';

List<String> taskListPath(List<FlyTaskList> lists, String id) {
  final byId = {for (final list in lists) list.id: list};
  final seen = <String>{}, names = <String>[];
  String? current = id;
  while (current != null && seen.add(current)) {
    final list = byId[current];
    if (list == null) break;
    names.insert(0, list.name);
    current = list.parentId;
  }
  return names;
}
