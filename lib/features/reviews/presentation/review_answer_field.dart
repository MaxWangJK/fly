import 'package:flutter/material.dart';

/// An answer reads like a note until the user chooses to edit it.
class ReviewAnswerField extends StatefulWidget {
  const ReviewAnswerField({
    required this.field,
    required this.label,
    required this.controller,
    required this.onChanged,
    required this.doneLabel,
    required this.editLabel,
    this.summary = false,
    super.key,
  });

  final String field, label, doneLabel, editLabel;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool summary;

  @override
  State<ReviewAnswerField> createState() => _ReviewAnswerFieldState();
}

class _ReviewAnswerFieldState extends State<ReviewAnswerField> {
  final focus = FocusNode();
  bool editing = false;

  @override
  void initState() {
    super.initState();
    focus.addListener(_focusChanged);
    widget.controller.addListener(_answerChanged);
  }

  void _focusChanged() {
    if (mounted) setState(() => editing = focus.hasFocus);
  }

  void _answerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant ReviewAnswerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, widget.controller)) return;
    oldWidget.controller.removeListener(_answerChanged);
    widget.controller.addListener(_answerChanged);
  }

  void _edit() {
    setState(() => editing = true);
    focus.requestFocus();
  }

  void _finish() {
    focus.unfocus();
    setState(() => editing = false);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_answerChanged);
    focus.removeListener(_focusChanged);
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasAnswer = widget.controller.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: editing || !hasAnswer
          ? TextField(
              key: ValueKey('review-${widget.field}'),
              controller: widget.controller,
              focusNode: focus,
              minLines: widget.summary ? 4 : 2,
              maxLines: null,
              maxLength: 20000,
              keyboardType: TextInputType.multiline,
              onTapOutside: (_) => focus.unfocus(),
              onEditingComplete: _finish,
              decoration: InputDecoration(
                labelText: widget.label,
                counterText: '',
                isDense: true,
                suffixIcon: editing && hasAnswer
                    ? IconButton(
                        key: ValueKey('review-done-${widget.field}'),
                        tooltip: widget.doneLabel,
                        onPressed: _finish,
                        icon: const Icon(Icons.check_rounded),
                      )
                    : null,
              ),
              onChanged: widget.onChanged,
            )
          : Semantics(
              button: true,
              label: '${widget.editLabel} ${widget.label}',
              child: InkWell(
                key: ValueKey('review-answer-${widget.field}'),
                borderRadius: BorderRadius.circular(8),
                onTap: _edit,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 56),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          widget.label,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.controller.text,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(height: 1.55),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
