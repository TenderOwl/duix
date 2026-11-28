import 'dart:math' as math;

import 'checkable.dart';
import 'colors.dart';
import 'control_template.dart';
import 'drawing.dart';
import 'events.dart';
import 'focus_decoration.dart';
import 'geometry.dart';
import 'path.dart';
import 'properties.dart';
import 'radio_group.dart';
import 'semantics.dart';
import 'ui_element.dart';

/// A control that belongs to a group and is checked one at a time.
///
/// The button draws a circle with a dot and the text of the label next to
/// it. The group of the button owns the state: checking one button of the
/// group checks it and unchecks the others, so the buttons of a group are
/// never checked together.
///
/// The value of the button tells the group which choice the button stands
/// for, so the group can carry it in a property and bind it to a model.
final class RadioButton<T> extends CheckableControl {
  RadioButton({
    T? value,
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
        ) {
    setValue(valueProperty, value);
  }

  static const templateProperty =
      DuiProperty<RadioButton<dynamic>, ControlTemplate<RadioButton<dynamic>>?>(
    name: 'template',
    defaultValue: null,
    affectsMeasure: true,
    affectsPaint: true,
  );

  /// The state of the button.
  static const isCheckedProperty = DuiProperty<RadioButton<dynamic>, bool>(
    name: 'isChecked',
    defaultValue: false,
    affectsMeasure: true,
    affectsPaint: true,
  );

  /// The value the button stands for.
  ///
  /// The group of the button carries the value of the checked button, so the
  /// value tells the group which choice the button is.
  static const valueProperty = DuiProperty<RadioButton<dynamic>, dynamic>(
    name: 'value',
    defaultValue: null,
  );

  /// The text of the label next to the circle.
  static const textProperty = DuiProperty<RadioButton<dynamic>, String>(
    name: 'text',
    defaultValue: '',
    affectsMeasure: true,
    affectsPaint: true,
  );

  /// The size of the font of the label.
  static const fontSizeProperty = DuiProperty<RadioButton<dynamic>, double>(
    name: 'fontSize',
    defaultValue: 14,
    affectsMeasure: true,
    affectsPaint: true,
  );

  /// The color of the text of the label.
  static const colorProperty = DuiProperty<RadioButton<dynamic>, Color>(
    name: 'color',
    defaultValue: Colors.black,
    affectsPaint: true,
  );

  /// The color of the circle of the button.
  static const Color circleColor = Color(0xFF8A8A8A);

  /// The color of the dot of a checked button.
  static const Color dotColor = Color(0xFF3584E4);

  /// The template of the radio button.
  ///
  /// The template owns the look of the control: it draws the circle and the
  /// dot and reacts to the state of the control.
  @override
  ControlTemplate<RadioButton<T>>? get template =>
      super.template as ControlTemplate<RadioButton<T>>?;

  /// The value the button stands for.
  T? get value => getValue<dynamic>(valueProperty) as T?;
  set value(T? value) => setValue<dynamic>(valueProperty, value);

  /// The group of the button.
  ///
  /// The group is the nearest group of the tree that holds the button.
  RadioGroup<T>? get group {
    UIElement? current = logicalParent;
    while (current != null) {
      if (current is RadioGroup<T>) return current;
      current = current.logicalParent;
    }
    return null;
  }

  /// Checks the button.
  ///
  /// A radio button is never unchecked by a click: the group keeps one button
  /// checked, and it is this button then. The method reports whether the
  /// state of the button changed.
  bool select() {
    if (isChecked) return false;
    isChecked = true;
    return true;
  }

  @override
  void activate() => select();

  @override
  void onCheckedChanged(bool isChecked) {
    final group = this.group;
    if (group == null) return;
    if (isChecked) {
      group.selectValue(value);
    } else {
      group.clearValue(value);
    }
  }

  @override
  bool handleKey(KeyEventArgs args) {
    if (args.primaryShortcutPressed) return false;
    final group = this.group;
    if (args.key == 'space') {
      activate();
      return true;
    }
    if (group == null) return false;
    final step = group.selectionStepFor(args.key);
    if (step == null) return false;
    group.moveSelection(step);
    return true;
  }

  @override
  SemanticsRole get semanticsRole => SemanticsRole.radioButton;

  /// The ring of the focus of a radio button is round, like its mark.
  @override
  FocusRingShape get defaultFocusRingShape => FocusRingShape.capsule;

  @override
  void renderMark(DrawingContext context, Rect rect) {
    final radius = math.min(rect.width, rect.height) / 2;
    final center = Point(rect.left + radius, rect.top + radius);
    context.drawPath(
      _circle(rect, radius),
      Paint(isEnabled ? circleColor : CheckableControl.disabledColor,
          strokeWidth: 1),
    );
    if (!isChecked) return;
    final dotRadius = radius * 0.45;
    context.drawPath(
      _circle(
        Rect.fromLTWH(
          center.x - dotRadius,
          center.y - dotRadius,
          dotRadius * 2,
          dotRadius * 2,
        ),
        dotRadius,
      ),
      Paint(isEnabled ? dotColor : CheckableControl.disabledColor),
    );
  }

  /// The circle of the mark.
  Path _circle(Rect rect, double radius) =>
      Path()..addRoundedRect(rect, radius, radius);
}
