import 'control_template.dart';
import 'geometry.dart';
import 'properties.dart';
import 'size_request.dart';
import 'text_editor.dart';
import 'text_layout.dart';

/// A control that edits a single line of text.
///
/// The text of the field is a part of the control: the control owns the text
/// and draws it, a template only places the part. The text therefore survives
/// every template.
///
/// The line is not wrapped: a long text is scrolled horizontally, and the
/// offset of the scroll is counted from the start of the text.
final class TextBox extends TextEditor {
  TextBox({super.text, super.fontSize})
      : super(
          textProperty: textProperty,
          fontSizeProperty: fontSizeProperty,
          templateProperty: templateProperty,
        );

  static const templateProperty =
      DuiProperty<TextBox, ControlTemplate<TextBox>?>(
    name: 'template',
    defaultValue: null,
    affectsMeasure: true,
    affectsPaint: true,
  );

  static const textProperty = DuiProperty<TextBox, String>(
    name: 'text',
    defaultValue: '',
    affectsMeasure: true,
    affectsPaint: true,
  );
  static const fontSizeProperty = DuiProperty<TextBox, double>(
    name: 'fontSize',
    defaultValue: 14,
    affectsMeasure: true,
    affectsPaint: true,
  );

  /// Smallest width the control reports so an empty field stays visible.
  static const double _minimumWidth = 80;

  /// Smallest height the control reports for a single line of text.
  static const double _minimumHeight = 30;

  double _horizontalScrollOffset = 0;

  /// The template of the text box.
  ///
  /// The template owns the look of the field: it places the part with the
  /// text and draws the frame around it. The text itself stays with the
  /// control.
  @override
  ControlTemplate<TextBox>? get template =>
      super.template as ControlTemplate<TextBox>?;

  @override
  double get horizontalScrollOffset => _horizontalScrollOffset;

  @override
  double layoutWidthFor(Size availableSize) => double.infinity;

  @override
  void ensureCaretVisible([TextLayout? layout]) {
    final viewport = textPart.bounds.width;
    if (viewport <= 0) {
      _horizontalScrollOffset = 0;
      return;
    }

    final displayText = hasComposition
        ? text.replaceRange(selection.start, selection.end, compositionText)
        : text;
    var targetOffset = caretOffset;
    if (hasComposition) {
      final active = compositionSelection;
      targetOffset = selection.start +
          (active == null ? compositionText.length : active.end);
    }
    final resolved = layout ?? layoutForRender(displayText);
    final textWidth = resolved.width;
    final caret = resolved.caretRect(targetOffset).left;
    // The scroll offset is counted from the start of the text, so the caret
    // is measured from the same edge.
    final caretX = isRightToLeft ? textWidth - caret : caret;
    var nextOffset = _horizontalScrollOffset;
    if (caretX < nextOffset) {
      nextOffset = caretX;
    } else if (caretX > nextOffset + viewport - 1) {
      nextOffset = caretX - viewport + 1;
    }
    final contentWidth = textWidth > caretX ? textWidth : caretX.toDouble();
    final maximumOffset =
        contentWidth > viewport ? contentWidth - viewport + 1 : 0.0;
    _horizontalScrollOffset = nextOffset.clamp(0.0, maximumOffset);
  }

  @override
  SizeRequest measureRequest(Size availableSize) => SizeRequest(
        minimum: const Size(_minimumWidth, _minimumHeight),
        natural: measureCore(availableSize),
      );
}
