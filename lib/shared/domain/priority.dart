enum PriorityLevel { low, medium, high }

extension PriorityLevelLabel on PriorityLevel {
  String get label => switch (this) {
    PriorityLevel.high => '高',
    PriorityLevel.medium => '中',
    PriorityLevel.low => '低',
  };
}
