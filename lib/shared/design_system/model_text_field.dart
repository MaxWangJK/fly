import 'package:flutter/material.dart';

extension ModelTextEditing on TextEditingController {
  /// A model echo must not reset the caret, selection or an active IME session.
  /// Callers decide whether an incoming value may replace a local draft.
  void syncTextFromModel(String text) {
    final current = value;
    if (current.text == text ||
        (current.isComposingRangeValid && !current.composing.isCollapsed)) {
      return;
    }
    final selection = current.selection;
    value = current.copyWith(
      text: text,
      selection: selection.isValid
          ? TextSelection(
              baseOffset: selection.baseOffset.clamp(0, text.length),
              extentOffset: selection.extentOffset.clamp(0, text.length),
              affinity: selection.affinity,
              isDirectional: selection.isDirectional,
            )
          : TextSelection.collapsed(offset: text.length),
      composing: TextRange.empty,
    );
  }
}

/// Keeps the editor alive as its model changes. Key by field/record identity,
/// never by the current text or number.
class ModelTextField extends StatefulWidget {
  const ModelTextField({
    required this.value,
    this.onChanged,
    this.onSubmitted,
    this.decoration = const InputDecoration(),
    this.keyboardType,
    this.style,
    this.maxLines = 1,
    super.key,
  });
  final String value;
  final ValueChanged<String>? onChanged, onSubmitted;
  final InputDecoration decoration;
  final TextInputType? keyboardType;
  final TextStyle? style;
  final int? maxLines;

  @override
  State<ModelTextField> createState() => _ModelTextFieldState();
}

class _ModelTextFieldState extends State<ModelTextField> {
  late final controller = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(covariant ModelTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      controller.syncTextFromModel(widget.value);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    onChanged: widget.onChanged,
    onSubmitted: widget.onSubmitted,
    decoration: widget.decoration,
    keyboardType: widget.keyboardType,
    style: widget.style,
    maxLines: widget.maxLines,
  );
}
