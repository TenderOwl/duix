import 'dart:math' as math;

import 'animation.dart';
import 'checkable.dart';
import 'colors.dart';
import 'control_template.dart';
import 'drawing.dart';
import 'focus_decoration.dart';
import 'geometry.dart';
import 'path.dart';
import 'properties.dart';
import 'semantics.dart';

/// A control with two states that shows them with a thumb that slides.
///
/// The switch draws a track and a thumb. The thumb slides from one end of the
/// track to the other when the state changes, and the color of the track
/// changes with it. The state is a property, so it can be bound: a two-way
/// binding keeps the value of the control and the value of the model equal.
///
/// The template owns the look of the control: it draws the track and the
/// thumb in its own way and reacts to the state of the control.
final class Switch extends CheckableControl {
  Switch({
    super.isChecked,
    super.text,
    super.fontSize,
    super.color,
    super.onChanged,
    Duration animationDuration = defaultAnimationDuration,
  }) : super(
          templateProperty: templateProperty,
          isCheckedProperty: isCheckedProperty,
          textProperty: textProperty,
          fontSizeProperty: fontSizeProperty,
          colorProperty: colorProperty,
        ) {
    _animation = ValueAnimation(
      duration: animationDuration,
      onChanged: _onAnimatedProgress,
    );
    // The switch starts in the state it was given, so the thumb stands at
    // its end from the very first frame.
    final resting = isChecked ? 1.0 : 0.0;
    _animation.jumpTo(resting);
    setValue(progressProperty, resting);
  }

  /// The time the thumb of the switch takes to slide.
  static const Duration defaultAnimationDuration = Duration(milliseconds: 150);

  /// The width of the track of the switch.
  static const double trackWidth = 38;

  /// The height of the track of the switch.
  static const double trackHeight = 20;

  /// The room between the thumb and the edge of the track.
  static const double thumbInset = 3;

  /// The color of the track of a switch that is off.
  static const Color trackOffColor = Color(0xFFD5D5D5);

  /// The color of the track of a switch that is on.
  static const Color trackOnColor = Color(0xFF3584E4);

  /// The color of the border of the track of a switch that is off.
  static const Color trackBorderColor = Color(0xFF8A8A8A);

  /// The color of the thumb.
  static const Color thumbColor = Color(0xFFFFFFFF);

  /// The color of the track of a switch that cannot be used.
  static const Color disabledTrackColor = Color(0xFFE0E0E0);

  /// The color of the thumb of a switch that cannot be used.
  static const Color disabledThumbColor = Color(0xFFBDBDBD);

  static const templateProperty = DuiProperty<Switch, ControlTemplate<Switch>?>(
    name: 'template',
    defaultValue: null,
    affectsMeasure: true,
    affectsPaint: true,
  );

  /// The state of the switch.
  static const isCheckedProperty = DuiProperty<Switch, bool>(
    name: 'isChecked',
    defaultValue: false,
    affectsMeasure: true,
    affectsPaint: true,
  );

  /// The text of the label next to the track.
  static const textProperty = DuiProperty<Switch, String>(
    name: 'text',
    defaultValue: '',
    affectsMeasure: true,
    affectsPaint: true,
  );

  /// The size of the font of the label.
  static const fontSizeProperty = DuiProperty<Switch, double>(
    name: 'fontSize',
    defaultValue: 14,
    affectsMeasure: true,
    affectsPaint: true,
  );

  /// The color of the text of the label.
  static const colorProperty = DuiProperty<Switch, Color>(
    name: 'color',
    defaultValue: Colors.black,
    affectsPaint: true,
  );

  /// The place of the thumb of the switch.
  ///
  /// The value is zero when the switch is off and one when it is on. While
  /// the thumb slides, the value stands between the two.
  static const progressProperty = DuiProperty<Switch, double>(
    name: 'progress',
    defaultValue: 0,
    affectsPaint: true,
  );

  late final ValueAnimation _animation;

  /// The template of the switch.
  ///
  /// The template owns the look of the control: it draws the track and the
  /// thumb and reacts to the state of the control.
  @override
  ControlTemplate<Switch>? get template =>
      super.template as ControlTemplate<Switch>?;

  /// The place of the thumb of the switch.
  ///
  /// The value is zero when the switch is off and one when it is on. While
  /// the thumb slides, the value stands between the two.
  double get progress => getValue<double>(progressProperty);

  /// Whether the thumb of the switch is sliding.
  bool get isAnimating => _animation.isRunning;

  /// The time the thumb of the switch takes to slide.
  Duration get animationDuration => _animation.duration;

  /// The width of the track of the switch.
  @override
  double get markWidth => trackWidth;

  /// The height of the track of the switch.
  @override
  double get markHeight => trackHeight;

  /// The rectangle of the thumb of the switch.
  ///
  /// The thumb slides along the track: it stands at the start of the track
  /// when the switch is off and at its end when the switch is on. In a tree
  /// that runs from right to left the ends of the track change places.
  Rect get thumbRect {
    final track = markRect;
    final travel = isRightToLeft ? 1 - progress : progress;
    final size = math.max(
      0.0,
      math.min(
        track.height - 2 * thumbInset,
        track.width - 2 * thumbInset,
      ),
    );
    final way = math.max(0.0, track.width - size - 2 * thumbInset);
    return Rect.fromLTWH(
      track.left + thumbInset + way * travel,
      track.top + (track.height - size) / 2,
      size,
      size,
    );
  }

  /// The thumb of the switch stands at the start of the track when the switch
  /// is off and at its end when the switch is on.
  @override
  void onCheckedChanged(bool isChecked) {
    _animation.animateTo(isChecked ? 1 : 0);
  }

  void _onAnimatedProgress(double value) {
    if (value == _animation.target) {
      // The thumb came to its end: the value rests in the local layer and the
      // animation lets it be.
      setValue(progressProperty, value);
      clearAnimationValue(progressProperty);
      return;
    }
    setAnimationValue(progressProperty, value);
  }

  @override
  SemanticsRole get semanticsRole => SemanticsRole.toggleSwitch;

  /// The ring of the focus of a switch is a capsule, like its track.
  @override
  FocusRingShape get defaultFocusRingShape => FocusRingShape.capsule;

  @override
  void renderMark(DrawingContext context, Rect rect) {
    final travel = isRightToLeft ? 1 - progress : progress;
    final radius = rect.height / 2;
    final track = Color.lerp(
      isEnabled ? trackOffColor : disabledTrackColor,
      isEnabled ? trackOnColor : disabledTrackColor,
      travel,
    );
    context.drawRoundedRect(rect, radius, radius, Paint(track));

    final border = isEnabled
        ? Color.lerp(trackBorderColor, trackOnColor, travel)
        : CheckableControl.disabledColor;
    context.drawRoundedRect(
        rect, radius, radius, Paint(border, strokeWidth: 1));

    final thumb = thumbRect;
    final size = thumb.width;
    context.drawPath(
      Path()..addRoundedRect(thumb, size / 2, size / 2),
      Paint(
        isEnabled ? thumbColor : disabledThumbColor,
        shadow: const Shadow(
          Color(0x40000000),
          blurRadius: 2,
          offsetY: 1,
        ),
      ),
    );
  }

  @override
  void onUnmounted() {
    // The thumb rests at the end it was going to, so the switch comes back
    // in the state it stands in.
    _animation.stop();
    _settle();
    super.onUnmounted();
  }

  @override
  void onDisposed() {
    _animation.dispose();
    super.onDisposed();
  }

  void _settle() {
    final target = _animation.target;
    setValue(progressProperty, target);
    clearAnimationValue(progressProperty);
  }
}
