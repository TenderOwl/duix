# Changelog

## Unreleased

- The focus ring of a check box and of a radio button no longer covers the
  control: the ring is drawn around the mark itself, the box with the check
  mark or the circle with the dot. A gap of one pixel stays between the ring
  and the mark, and the text of the label stays outside of the ring.
- The ring of a radio button is round, the ring of a check box is a
  rectangle. The shape that a template asks for still wins.
- A control can tell where its focus ring belongs now: the new hooks
  `Control.focusRingBounds` and `Control.defaultFocusRingShape` let any
  control choose the place and the shape of its own ring.
- A radio button is a control now: `RadioButton` belongs to a `RadioGroup`, and
  the group owns the selection. The value of the checked button lives in the
  property `selectedValue` of the group, so it can be bound to a model: a
  two-way binding keeps the group and the model equal. Only one button of a
  group is checked at a time, and a click on a checked button keeps it
  checked.
- A group of radio buttons is a focus scope, so the keyboard stays inside it.
  The arrows walk over the buttons of the group and move the focus with the
  selection: the vertical arrows in a vertical group, the horizontal arrows in
  a horizontal one, and the sides swap in a right-to-left tree. The buttons of
  a nested group belong to that group.
- The check box and the radio button share one core now: `CheckableControl`
  owns the state, the text of the label, the keyboard, the drawing of the mark
  and the semantics, and the two controls draw only their own mark.
- **Breaking:** the names of the `CheckBox` follow the shared core: `boxSize`
  is `markSize`, `boxRect` is `markRect` and `textRect` is `labelRect`. The
  control is not published yet, so nothing published breaks.
- The semantics tree knows a radio button now: the new role `radioButton`
  carries the state of the button and the name of the label, and the group
  carries the role `group`. The roles stand at the end of the roles, because
  the index of a role crosses the native ABI.
- A check box is a control now: `CheckBox` has two states, draws a box with a
  check mark and the text of the label next to it. The state is a property, so
  it can be bound: a two-way binding keeps the value of the control and the
  value of the model equal. A click and the space bar toggle the box, and the
  box stands at the start of the control, so it moves to the right edge in a
  right-to-left tree.
- The layout of a text is cached in one place now: `CachedTextLayout` reuses
  the layout while the text, the size of the font, the scale, the direction and
  the backend stay the same. `Label`, `TextBox`, `TextArea` and `CheckBox` share
  it instead of keeping a copy each.
- The semantics tree knows a check box: the new role `checkBox` carries the
  state of the box and the name of the label. The role stands at the end of the
  roles, because the index of a role crosses the native ABI.
- A control can edit several lines now: `TextArea` is a field of its own. The text is
  wrapped into the width of the area, the area owns a vertical scroll bar, `Shift+Enter`
  starts a new line, the up and down arrows move the caret between the lines, `Home` and
  `End` work inside a line, and the wheel scrolls the text. The scroll follows the caret
  until the user scrolls the text away from it.
- `TextBox` and `TextArea` share one editing core now. `TextEditor` owns the buffer, the
  commands, the composition, the mouse and the IME, and the two controls only answer the
  questions of the axis of the text and of the scrolling. The headless layout wraps the
  text into words as well, so the wrapping can be checked without the native backend.
- The text of a field is wrapped into the width that the field really shows: the padding
  of the control and the thickness of the scroll bar are subtracted from the available
  width before the layout is made.
- The caret of the native backend stands in the box of the line and not in the box of a
  glyph: the height of the caret is the height of the line, and the vertical scroll of a
  `TextArea` lands on the border of the line. The ABI is unchanged.
- The layout of a tree can run from right to left. `FlowDirection` is an inherited
  property of the elements now: `UIElement.flowDirection` is left-to-right by default,
  a child follows its parent, an element with a direction of its own keeps it, and
  `Window.flowDirection` gives its direction to the content of the window.
- The alignment of an element can be logical: `HorizontalAlignment.start` and
  `HorizontalAlignment.end` follow the direction of the tree, while `left` and
  `right` stay absolute. The horizontal `StackPanel` starts at the right edge and
  the `DockPanel` swaps its left and right sides in a right-to-left tree.
- The text of a `TextBox` starts at the right edge of the field in a right-to-left
  tree, the horizontal scroll of the field is counted from the start of the text, and
  the caret, the mouse and the input area follow it. The thumb of a horizontal
  `ScrollBar` starts at the right edge, the vertical bar of a `ScrollViewer` stands
  on the left and the content of the viewer starts at the right edge.
- `TextLayoutOptions` carries the direction of the text, and `resolveTextAlignment`
  turns the logical alignment of a layout into the absolute one of the backend.
- The native ABI is version 6 now. The options of a text layout carry the direction of
  the paragraph, so the native backend shapes the text with
  `SkParagraph::setTextDirection`. The direction of the paragraph is the base direction
  of the text: it decides where the runs of a line stand, while the runs themselves
  keep their own order, so a Hebrew run is read from right to left in every paragraph.
  The caret, the selection and the mouse hit testing are counted in the coordinates of
  the paragraph, so the field, the caret and the text agree with each other.
- A template does not have to replace the content of a control. A control can offer named
  parts now: `TemplatedControl.registerPart(name, element)` puts a part into the control,
  the template finds it with `control.part(name)` and places it where it belongs, and the
  control draws the content of the part. A part that no template places stays with the
  control, so the content is never lost, and the parts outlive the template that
  placed them.
- `TextBox` has a template and a part with the text now. The template draws the frame of
  the field and places the part, the control keeps the text, the selection, the
  composition and the caret.
- `ScrollViewer` has a template and three parts now: `content` with the scrolled and
  clipped content, `horizontalScrollBar` and `verticalScrollBar`. The template decides
  where the content and the bars sit, the viewer keeps the offset and the values of
  the bars.
- `TemplatePart` is the part of a control that draws its content: it is measured,
  arranged and rendered through the owner of the control.
- A template is not a thing of the button only. `Label`, `Border` and `ScrollBar` have
  their own template property now, so the look of any widget that draws itself can be
  replaced: a template of a label takes over its text, a template of a border presents
  its content through a `ContentPresenter` and a template of a scroll bar draws the
  track and the thumb.
- A text that is exactly as wide as its box does not push its last word onto the next
  line any more.
- A path is a list of commands: `Path` moves the pen, draws straight lines,
  quadratic and cubic curves and closes the contours, and it can add a
  rectangle or a rounded rectangle. `DrawingContext.drawPath(path, paint)`
  draws it, so a widget can draw an icon, a chart or a separator of its own.
- A paint carries more than a color now. `Paint.opacity` is the transparency
  of the shape, `Paint.blendMode` says how the shape is mixed with the pixels
  under it (`srcOver`, `screen`, `multiply`, `plus`, `difference`, `lighten`,
  `darken`, `overlay`) and `Paint.shadow` draws a soft shadow under the shape.
- The paint of a shape crosses the boundary as a struct and the path as a list of
  commands, so a widget can draw a contour with a transparency, a blend mode and a
  shadow.
- Windows UI Automation reads the widgets of a window. The native layer answers
  `WM_GETOBJECT` with a provider of the semantics tree, so the assistive
  technologies of the system see the same tree as the framework: the type of the
  control, its name, its value, its bounds on the screen and its state (enabled,
  focusable, focused, control and content element). A text field answers the value
  pattern, and the bridge reports a moved focus and a changed name or value to the
  system. The example `example/native_accessibility.dart` and the script
  `tool/verify_uia.ps1` show and check the tree.
- Templates work for any control, not only for a button. `TemplatedControl` holds
  the template mechanics: it creates, replaces and releases the persistent
  subtree of the control, exposes `templateRoot` and `hasTemplate` and draws the
  focus ring itself. `ContentControl` inherits it, so a control declares its own
  template property and gets the same behaviour.
- A widget implements its own content through `measureContentCore`,
  `arrangeContentCore`, `renderContentCore` and `hitTestContentCore`. When the
  control has a template, the template owns the layout, the rendering and the
  hit testing, so a subclass cannot accidentally override the template.
- A control without a template property does not support templates: its template
  is always null and setting it throws a `StateError`.
- The paint decides how a shape is drawn: `Paint` carries a `strokeWidth`, zero
  fills the shape and a positive value strokes its outline. `drawRect` and
  `drawRoundedRect` follow the paint, so the separate `strokeWidth` argument of
  `drawRoundedRect` is gone.
- `DrawingContext.drawLine(from, to, paint)` draws a straight line, so a widget
  can draw separators, underlines and borders without a bitmap.
- Images: `ImageFactory` decodes a PNG into a `DrawableImage`, and
  `DrawingContext.drawImage(image, rect, paint)` draws it. The native backend
  decodes the pixels with Skia, so `SdlSkiaHost.imageFactory` returns a factory
  that reads the file bytes of a PNG.
- `ScrollBar` is a control of its own: it draws the track and the thumb, the
  thumb can be dragged, a click on the track scrolls by one page, and the value
  is a property that a scrollable area binds to its offset. It is the base for
  the scroll bars of `ScrollViewer`, and it is ready for a combo box or a list.
- `ScrollViewer` is built on two `ScrollBar` controls now, available as
  `horizontalScrollBar` and `verticalScrollBar`.
- `SelectionModel` is the selection of a list of items: it keeps the selected
  indexes, the current item and the anchor of a range selection, reports every
  change to its listeners and walks through the items with `moveSelection`,
  `selectFirst` and `selectLast`. A list view, a tree view or a combo box can
  bind its state to it.
- `Window.overlay` is the layer of the window that holds an open popup. The
  popup is drawn above the content of the window, it is clipped to the window
  and it takes the clicks that fall outside of it, so a combo box, a menu or a
  tooltip can open above the content. The popup is placed below, above, left,
  right, at the pointer or at the owner area, Escape closes it, and the focus
  goes back to the control that opened it.
- The semantics tree of a window crosses the native ABI: the Dart layer
  publishes the roles, the names, the values, the states and the bounds of the
  accessible elements after every frame, and the native layer keeps them. The
  tree is the base of the platform bridges of the assistive technologies.
- **Breaking:** while a scroll bar thumb is dragged, the pointer capture belongs
  to the scroll bar and not to the viewer. The hit test on a scroll bar returns
  the scroll bar, and clicking a scroll bar does not move the focus: the bar is
  not focusable, the keyboard belongs to the area that scrolls.
- **Breaking:** the native ABI is now version 4: `dui_draw_rect` takes the
  stroke width, `dui_draw_line` and `dui_draw_image` are new and the image
  functions `dui_image_create_from_png`, `dui_image_destroy` and
  `dui_image_get_size` were added. The Dart side refuses a library with another
  ABI version.
- **Breaking:** the focus ring of a templated control is drawn on top of the
  content instead of under it.

## 0.1.0

- First public prototype: a retained-mode tree of controls, layout, real-time
  rendering through SDL3 and Skia, keyboard and mouse input, IME, clipboard
  access, system dialogs and semantics.
- The native library `dui_native` ships inside the package for the supported
  platforms (Windows x64, macOS arm64, Linux x64); users never have to build it
  themselves.
- `dart run duix:setup_native <dir>` copies the library next to the executable
  of a compiled application.
- `runApp(window)` shows the window, runs its event loop until the window is
  closed and releases the native host, so an application no longer needs the
  event loop and the cleanup in its own code.
- `WidgetState` gathers the state of a control into one value: enabled,
  hovered, pressed and focused. The base class keeps the pressed state up to
  date, so a control no longer has to maintain it on its own.
- The layout knows the three sizes of a widget: the minimum size it cannot
  work without, the natural size it would like to have and the size it was
  allocated. An element reports them through `SizeRequest`, and a widget that
  cannot work below a certain size keeps that space.
