class TagReferenceSummary {
  const TagReferenceSummary({
    required this.customerReferences,
    required this.orderReferences,
    required this.taskReferences,
    required this.categoryLinked,
    this.noteReferences = 0,
  });

  final int customerReferences;
  final int orderReferences;
  final int taskReferences;
  final bool categoryLinked;
  final int noteReferences;

  bool get hasBusinessReferences =>
      customerReferences > 0 || orderReferences > 0;

  bool get hasAnyReferences =>
      hasBusinessReferences || taskReferences > 0 || noteReferences > 0;

  bool get isProtected => categoryLinked;

  bool get isOrphan => !isProtected && !hasAnyReferences;
}
