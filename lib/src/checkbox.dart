import 'checkable.dart';
import 'colors.dart';
import 'control_template.dart';
import 'drawing.dart';
import 'geometry.dart';
import 'path.dart';
import 'properties.dart';
import 'semantics.dart';

/// A control with two states: checked and unchecked.
///
/// The control draws a box with a check mark and the text of the label next
/// to it. The state is a property, so it can be bound: a two-way binding
/// keeps the value of the control and the value of the model equal.
///
/// The template owns the look of the control: it draws the box and the check
/// mark in its own way and reacts to the state of the control.
final class CheckBox extends CheckableControl {
  CheckBox({
    super.isChecked,
    super.text,
    super.fontSize,
    super.color,
    super.onChanged,
  }) : super(
          templateProperty: templateProperty,
          isCheckedProperty: isCheckedProperty,
          textProperty: textProperty,
          fontSizeProperty: fontSizeProperty,
          colorProperty: colorProperty,
        );

  static const templateProperty =
      DuiProperty<CheckBox, ControlTemplate<CheckBox>?>(
    name: 'template',
    defaultValue: null,
    affectsMeasure: true,
    affectsPaint: true,
  );

  /// The state of the box.
  static const isCheckedProperty = DuiProperty<CheckBox, bool>(
    name: 'isChecked',
    defaultValue: false,
    affectsMeasure: true,
    affectsPaint: true,
  );

  /// The text of the label next to the box.
  static const textProperty = DuiProperty<CheckBox, String>(
    name: 'text',
    defaultValue: '',
    affectsMeasure: true,
    affectsPaint: true,
  );

  /// The size of the font of the label.
  static const fontSizeProperty = DuiProperty<CheckBox, double>(
    name: 'fontSize',
    defaultValue: 14,
    affectsMeasure: true,
    affectsPaint: true,
  );

  /// The color of the text of the label.
  static const colorProperty = DuiProperty<CheckBox, Color>(
    name: 'color',
    defaultValue: Colors.black,
    affectsPaint: true,
  );

  /// The radius of the corners of the box.
  static const double boxRadius = 3;

  /// The color of the border of the box.
  static const Color boxBorderColor = Color(0xFF8A8A8A);

  /// The color of the fill of the box.
  static const Color boxFillColor = Color(0xFFFFFFFF);

  /// The color of the check mark.
  static const Color checkMarkColor = Color(0xFF3584E4);

  /// The template of the check box.
  ///
  /// The template owns the look of the control: it draws the box and the
  /// check mark and reacts to the state of the control.
  @override
  ControlTemplate<CheckBox>? get template =>
      super.template as ControlTemplate<CheckBox>?;

  @override
  SemanticsRole get semanticsRole => SemanticsRole.checkBox;

  @override
  void renderMark(DrawingContext context, Rect rect) {
    context.drawRoundedRect(
      rect,
      boxRadius,
      boxRadius,
      const Paint(boxFillColor),
    );
    context.drawRoundedRect(
      rect,
      boxRadius,
      boxRadius,
      Paint(
        isEnabled ? boxBorderColor : CheckableControl.disabledColor,
        strokeWidth: 1,
      ),
    );
    if (!isChecked) return;
    context.drawPath(
      _checkMark(rect),
      Paint(isEnabled ? checkMarkColor : CheckableControl.disabledColor,
          strokeWidth: 2),
    );
  }

  /// The path of the check mark inside the box.
  Path _checkMark(Rect box) {
    return Path()
      ..moveTo(
        Point(box.left + box.width * 0.24, box.top + box.height * 0.52),
      )
      ..lineTo(
        Point(box.left + box.width * 0.44, box.top + box.height * 0.72),
      )
      ..lineTo(
        Point(box.left + box.width * 0.78, box.top + box.height * 0.28),
      );
  }
}
