# План разработки retained-mode UI framework на Dart

Дата последнего обновления: 2026-11-26

Этот документ — основная точка восстановления контекста после перерыва. Перед продолжением работы сначала прочитать разделы «Текущее состояние», «Ближайшие задачи» и «Протокол продолжения после перерыва».

---

## 1. Цель проекта

Создать кроссплатформенный UI framework на Dart для Windows, macOS и Linux с:

- retained-mode деревом контролов;
- декларативным созданием исходной иерархии;
- постоянной идентичностью контролов;
- property system и bindings;
- routed events;
- measure/arrange layout;
- собственными self-drawn контролами;
- нативным backend на SDL3 и Skia;
- поддержкой HiDPI;
- последующей поддержкой accessibility, виртуализации и нативной интеграции.

Проект не должен превращаться в копию Flutter: не использовать `build()`, виртуальное дерево, reconciliation и пересоздание контролов при каждом обновлении.

---

## 2. Архитектурные принципы

### 2.1. Retained mode

- Контрол создаётся один раз и живёт, пока его явно не удалят из дерева.
- Изменение свойства не пересоздаёт контрол.
- `children.add()` и `children.removeAt()` изменяют существующее дерево.
- Состояние hover, pressed, focus, selection и text cursor принадлежит контролу.
- Обновления выполняются через invalidate, а не через rebuild.

### 2.2. Разделение уровней

```text
Dart application
  └── Application / Window
      └── UIElement / Control / Panel
          ├── properties / bindings
          ├── measure / arrange
          ├── routed events / focus
          └── render via DrawingContext
              └── NativeDrawingContext
                  └── Dart FFI
                      └── C ABI
                          ├── SDL3: окна, ввод, IME
                          └── Skia: CPU rendering и текст
```

### 2.3. Независимость публичного API от backend

- Публичные контролы не должны импортировать SDL3/Skia.
- Контролы используют `DrawingContext` и абстракцию текстовой раскладки.
- FFI-сущности не должны проникать в `UIElement`, `Control` и `Panel`.
- Допускается второй backend без изменения прикладного API.

### 2.4. Координаты

После исправления HiDPI использовать следующие определения:

- **physical pixels** — размер SDL backbuffer и Skia surface;
- **SDL window units** — координаты SDL, зависящие от платформы;
- **logical UI units** — координаты дерева контролов, layout и публичных свойств;
- `displayScale = SDL_GetWindowDisplayScale()`;
- `pixelDensity = SDL_GetWindowPixelDensity()`.

Преобразования:

```text
logical UI = SDL window units * pixelDensity / displayScale
SDL window units = logical UI * displayScale / pixelDensity
```

Skia canvas масштабируется через `displayScale`. Backbuffer создаётся по фактическому `SDL_GetWindowSizeInPixels()`.

---

## 3. Текущее состояние

### 3.1. Уже реализовано

- `Application`, `Window`, `WindowHost`;
- эргономичная точка входа: `runApp(window)` показывает окно, крутит его цикл событий до закрытия и освобождает native-хост; `Application.run` делает то же на своём хосте, а `NativeHost.runWindow` — цикл на уровне хоста;
- единое состояние виджета: `WidgetState` (enabled, hovered, pressed, focused) собирает флаги контрола в одно значение; базовый `Control` владеет press-состоянием (события pointer down/up, отмена при уходе указателя) и сообщает о релизе через `onReleased`, виджет только объявляет `handlesPointerPress`; `SemanticsState` контрола собирается из того же состояния;
- модель размеров GTK: `SizeRequest` (minimum + natural) — элемент сообщает, какого размера он хочет и какого ему нужно; `UIElement` мержит запрос, отдаёт desired = max(natural, minimum) в пределах доступного места, а `arrange` не сжимает элемент ниже минимума, если место есть; доступны `minimumSize`, `naturalSize`, `allocatedSize`; `TextBox` объявляет минимум 80×30 (вместо внутреннего пола на natural);
- `UIElement`, `Control`, `ContentControl`, `Panel`;
- отдельный виджет `ScrollBar`: свой контрол с полосой и бегунком, бегунок перетаскивается, клик по полосе листает на одну страницу, значение — свойство (`minimum`, `maximum`, `value`, `viewportSize`, `thickness`, `orientation`); `ScrollViewer` построен на двух таких контролах (`horizontalScrollBar`, `verticalScrollBar`) и больше не рисует полосы сам;
- модель выделения `SelectionModel`: одиночное и множественное выделение, текущий элемент и якорь диапазона, уведомления об изменениях, переходы клавиатурой (`moveSelection`, `selectFirst`, `selectLast`);
- popup-слой: `PopupLayer` (`lib/src/popup.dart`) и `Window.overlay` — слой окна поверх содержимого со своим layout и clip, перехватывает клики вне всплывающего окна, закрывается по Escape и возвращает фокус владельцу; размещение: снизу, сверху, слева, справа, у курсора, у области владельца;
- мост accessibility: дерево семантики окна уходит в native через `dui_window_set_accessibility_tree` — роли, имена, значения, состояния и границы; native хранит дерево плоским списком, у каждого узла индекс родителя; `SdlSkiaHost.nativeHandle(window)` даёт доступ к native-состоянию окна;
- шаблоны для любого контрола: `TemplatedControl` — базовый класс с механикой шаблона (создание, замена и освобождение persistent-поддерева, `templateRoot`, `hasTemplate`, хук `onTemplateReplacing`); `ContentControl extends TemplatedControl`; собственный контент виджета реализуется через `measureContentCore`/`arrangeContentCore`/`renderContentCore`/`hitTestContentCore`, чтобы шаблон нельзя было случайно перекрыть подкласом; focus ring рисует база (после контента, сверху), а не каждый виджет отдельно; типизированный шаблон живёт в конкретном классе, база хранит `ControlTemplate<dynamic>?`; своё template-свойство есть у `Button`, `Label`, `Border` и `ScrollBar` — у всего набора, который рисует свой вид;
- части шаблона (template parts): контрол отдаёт шаблону именованные части, а шаблон размещает их; содержимое контрола при этом не заменяется. `TemplatePart` (`lib/src/template_part.dart`) — это элемент дерева, который меряется, расставляется и рисуется через владельца (`measurePart`, `arrangePart`, `renderPart`, `hitTestPart`), поэтому рисует содержимое контрол, а шаблон решает только, где часть лежит. `TemplatedControl` держит реестр частей (`registerPart`, `part`, `templateParts`) и сам размещает, меряет и рисует те части, которые шаблон не разместил; части переживают замену шаблона. `TextBox` отдаёт часть `text` (текст, выделение, composition и caret рисует контрол), `ScrollViewer` — части `content`, `horizontalScrollBar` и `verticalScrollBar`;
- `Label`, `TextBox`, `TextArea`, `CheckBox`, `RadioButton`, `RadioGroup`, `Button`, `Border`, `StackPanel`, `DockPanel`, `Grid`;
- переключатели: общее ядро `CheckableControl` (`lib/src/checkable.dart`) держит состояние, текст метки, клавиатуру и семантику, а `CheckBox` и `RadioButton` рисуют только свою метку; группа radio (`RadioGroup`) владеет выбором: значение отмеченной кнопки живёт в свойстве группы (его можно связать с моделью), группа — focus scope, стрелки ходят по кнопкам и ведут за собой фокус; кнопки вложенной группы belongят этой группе;
- флажок: `CheckBox` (`lib/src/checkbox.dart`) — два состояния, галочка и текст метки рядом. Состояние `isChecked` живёт в системе свойств, поэтому двусторонняя связь держит контрол и модель равными; клик и пробел переключают состояние; квадрат с галочкой стоит у начала контрола (левый край в left-to-right, правый в right-to-left), а текст метки — рядом с ним; выключенный контрол рисуется серым;
- focus ring флажков и кнопок radio рисуется вокруг самой метки (квадрата с
  галочкой или кружка с точкой), а не вокруг всего контрола: между кольцом и
  меткой остаётся зазор в один пиксель, текст метки в кольцо не входит, а у
  radio-кнопки кольцо круглое. Базовый `Control` дал для этого хуки
  `focusRingBounds` (где рисуется кольцо) и `defaultFocusRingShape` (какой
  формой); форма из шаблона по-прежнему имеет приоритет;
- раскладка текста кэшируется в одном месте: `CachedTextLayout` (`lib/src/text_layout.dart`) переиспользует раскладку, пока не изменились текст, кегль, масштаб, направление и backend; её используют `Label`, `TextBox`, `TextArea` и `CheckBox`;
- многострочный ввод: общий каркас редактирования вынесен в `TextEditor` (`lib/src/text_editor.dart`) — буфер, команды, composition, мышь, IME, кэш раскладки и отрисовка; `TextBox` и `TextArea` делят его, а не копируют логику. `TextArea` (`lib/src/text_area.dart`) переносит текст по словам в ширину поля, владеет вертикальной полосой прокрутки (часть `verticalScrollBar`), вставляет перевод строки по Shift+Enter, ходит кареткой между строками стрелками вверх и вниз, а Home и End работают по логической строке; прокрутка следует за кареткой, пока пользователь не прокрутил текст сам;
- постоянное дерево и lifecycle mount/unmount;
- `DuiProperty`;
- `ObservableValue`;
- one-way и two-way bindings;
- routed events: direct/bubble/tunnel infrastructure;
- measure/arrange/render;
- базовые invalidate-флаги;
- hit testing;
- focus на уровне одиночного контрола;
- `RecordingDrawingContext` для тестов;
- графика слоя: `Path` (`moveTo`, `lineTo`, `quadTo`, `cubicTo`, `close`, `addRect`, `addRoundedRect`), `DrawingContext.drawPath`, прозрачность `Paint.opacity`, режимы наложения `Paint.blendMode` и тень `Paint.shadow`; native ABI версии 5: paint передаётся структурой `DuiPaint`, путь — списком команд `DuiPathCommand`;
- C ABI с opaque handles;
- Dart FFI loader и typed bindings;
- `SdlSkiaHost`;
- SDL3-окна и события;
- Skia CPU surface и SDL streaming texture;
- цвет фона `Window.background`;
- корректный HiDPI через `SDL_GetWindowDisplayScale()`;
- преобразование координат ввода и layout для Windows/macOS/Linux;
- bootstrap `tools/bootstrap_native.py`;
- закреплённые SDL3 3.4.20 и Skia `chrome/m148`;
- SkParagraph со SkShaper, SkUnicode, HarfBuzz и ICU в нативной сборке;
- нативный пример `example/native_counter.dart`;
- native smoke-пример `example/native_smoke.dart` и команда `--smoke`;
- Paragraph smoke с ASCII и кириллицей, автоматически запускаемый bootstrap;
- отключаемые native diagnostics: scale, logical/physical size, render/present counters;
- отдельные C ABI-тесты и задокументированная однопоточная модель вызовов;
- backend-independent `TextLayout`, `TextLayoutFactory` и `TextLayoutOptions`;
- opaque `DuiTextLayout` и C ABI для create/destroy, measure, draw, hit test, caret и selection;
- Dart FFI bindings для native text layout с UTF-16 offsets и caller-owned output buffers;
- `NativeTextLayoutFactory` поверх SkParagraph и `HeadlessTextLayoutFactory` для unit-тестов;
- `Label` использует кэшированный `TextLayout` для measurement и drawing, освобождает его при замене и unmount;
- Unicode/HiDPI-матрица native text layout с проверками measurement, hit test, caret, selection и масштабов 1.0/1.25/1.5/2.0;
- интерактивная галерея `example/native_text_gallery.dart` с автоматическим smoke-режимом;
- интерактивный пример `example/native_textbox.dart` с тремя полями, Unicode, two-way binding preview, mouse/keyboard/clipboard/IME подсказками и smoke-режимом;
- `TextBox` получает focus по primary pointer down, устанавливает caret через `TextLayout.hitTest()` и выделяет текст перетаскиванием;
- backend-independent pointer capture в `Window` маршрутизирует move/up захваченному контролу, включая координаты за его границами; capture освобождается при primary up, focus loss и unmount;
- `DrawingContext` поддерживает вложенные `pushClipRect`/`popClip`; native backend реализует их через Skia save/clipRect/restore;
- `TextBox` обрезает текст и decoration по content bounds, подсвечивает обычный selection и рисует caret у focused collapsed selection;
- `TextBuffer` и `TextSelection` с UTF-16 offsets, selection anchor/active end, проверкой диапазонов и командами редактирования;
- `TextBox` вставляет text input в caret, заменяет selection и синхронизирует текст с two-way binding;
- SDL text input lifecycle: Start/Stop при focus, TextLayout-based input area/caret, cleanup при unmount/close;
- routed key-down с Shift/Ctrl/Cmd modifiers, команды навигации и редактирования `TextBox`, включая word navigation и selection;
- backend-independent `ClipboardHandler` и SDL clipboard с UTF-8 copy/cut/paste; дополнительный native MIME API копирует наборы форматов, поддерживает binary/empty payloads и сохраняет прежний text API;
- `SDL_EVENT_TEXT_EDITING` проходит через C ABI, Dart FFI и `Window` в focused `TextBox`; composition selection передаётся в UTF-16 offsets;
- `TextBox` хранит composition text/range отдельно от подтверждённого `TextBuffer`, рисует composition через кэшированный `TextLayout` с подчёркиванием и подсветкой активного диапазона;
- промежуточная composition не изменяет `text` и two-way binding; подтверждение через text input заменяет selection и обновляет модель;
- `Button` и `TextBox` рисуют двухпиксельный focus ring внутри своих bounds только при активном focus;
- `Button` активируется по Space/Enter через routed key-down и помечает событие обработанным;
- `KeyEventArgs` содержит physical SDL scancode и layout-dependent logical SDL keycode;
- `SdlSkiaHost.presentWindow()` пропускает render/present для закрытого, невидимого или не имеющего scheduled frame окна;
- `FrameScheduler` объединяет invalidate, отделяет защищённый от рекурсии layout pass от paint и сохраняет invalidate, поступивший во время paint, для следующего кадра;
- C ABI и Dart FFI поддерживают `dui_host_wait_event`/`waitForEvent()` и `dui_host_wake_up`; SDL user event пробуждает очередь при новом scheduled frame;
- SDL event watch синхронно вызывает native→Dart live-resize callback на host thread для `RESIZED`, `PIXEL_SIZE_CHANGED` и live `EXPOSED`; `SdlSkiaHost` обновляет logical size и выполняет render/present внутри модального resize, не дожидаясь возврата главного цикла;
- перед native present сбрасываются SDL renderer viewport и clip rect, чтобы прежние размеры не обрезали увеличенный backbuffer;
- интерактивные примеры используют wait с пределом 16 мс и уступают Dart event loop, поэтому Timer/Future invalidate обрабатываются без постоянного render/present;
- SDL renderer создаётся с включённым VSync;
- diagnostics включают `scheduled`, `layout`, `painted`, `presented` и семплируемый `fps`;
- при `--diagnostics` native host рисует поверх UI полупрозрачный FPS overlay в правом верхнем углу; частота считается по фактическим present за интервалы около 500 мс без дополнительных кадров в idle;
- `example/native_frame_benchmark.dart` измеряет process CPU на Windows через `GetProcessTimes`, idle counters и latency async invalidate→present;
- `UIElement` поддерживает min/max width/height, margin, horizontal/vertical alignment, раздельные `desiredSize`, `arrangedSize` и `bounds`;
- `StackPanel` измеряет детей с бесконечным главным направлением; measure cache учитывает изменение available constraints;
- `DockPanel` поддерживает attached `Dock.left/top/right/bottom`, последовательное уменьшение remaining rect и `lastChildFill` для последнего видимого ребёнка;
- `Grid` поддерживает Auto/Pixel/weighted Star tracks, наблюдаемые row/column definitions, attached row/column и rowSpan/columnSpan, spacing и physical-pixel rounding границ;
- `ScrollViewer` поддерживает viewport/extent, двунаправленные offsets, Auto/Hidden/Visible/Disabled scrollbars, mouse wheel, keyboard scrolling, pointer capture для thumbs и clipping при render/hit test;
- `ObservableCollection<T>` публикует точечные add/insert/remove/replace/move/reset-события, поддерживает отмену подписки и идемпотентный dispose;
- `ItemsControl<T>` создаёт persistent children через `ItemTemplate<T>`, передаёт item в `dataContext`, переиспользует элементы по `ItemKeySelector<T>` и корректно unmount удаляет;
- `VirtualizingStackPanel<T>` материализует только видимый диапазон с buffer, поддерживает estimated extent, измеренную переменную высоту и очистку focus при recycling;
- `example/native_items_control.dart` демонстрирует 100 000 строк и автоматический smoke с прокруткой к середине и концу;
- `BindingSubscription.cancel()` сохраняет последнее синхронизированное значение как локальное только при отсутствии явного local поверх binding; subscription сообщает property/mode/isCancelled;
- `PropertyOwner.dispose()` идемпотентно отменяет bindings, запрещает дальнейшие `bind()`/`setValue()` и интегрирован с `ItemsControl.dispose()`;
- two-way writes подавляют reentrant duplicates и синхронизируются даже без callback notification; `BindingException` сообщает property, operation и cause;
- value layers с приоритетом `default < inherited < style < binding < local < animation`, ручные set/clear API и `PropertyOwner.getValueSource()`;
- one-way local маскирует binding без отписки, а `clearLocalValue()` восстанавливает актуальное binding value; constructor defaults не блокируют style/inherited;
- `UIElement.dataContextProperty` автоматически наследуется по logical tree, обновляет descendants при изменениях и reparenting; local/binding layers сохраняют обычные приоритеты;
- типобезопасные `dataContextAs<T>()` и `requireDataContext<T>()` без строковых paths, reflection и кодогенерации;
- generic `Style<TOwner>` и `DuiSetter<TOwner, T>` применяются через style layer с сохранением local/binding приоритетов;
- `ControlTemplate<Button>` создаёт persistent visual subtree, `ContentPresenter` сохраняет и обновляет исходный content, typed `PropertyBinding`/`MappedBinding` реагируют без rebuild; `focusRingShape` выбирает прямоугольный или капсульный focus ring;
- `Button.isPressedProperty` и `Control.isPointerOverProperty` доступны шаблонам; Window обновляет hover по logical path, template replacement освобождает bindings старого subtree, а input/focus ring сохраняются;
- `Border.colorProperty`/`paddingProperty` поддерживают styles и bindings; `example/native_aqua_button.dart` демонстрирует named Aqua style, persistent template с hover/pressed, капсульную форму, внутреннюю светлую кромку, верхний глянцевый блик и капсульный focus ring;
- `DrawingContext.drawRoundedRect()` поддерживает fill/stroke в recording renderer и native Skia backend через `dui_draw_rounded_rect`;
- публичный backend-independent clipboard: `Window`/`WindowHost.writeClipboardData()`, `hasClipboardData()`, `readClipboardData()` с `Uint8List`, `readClipboardMimeTypes()`, `clearClipboard()`, `ClipboardMimeTypes.plainText/html` и native adapter через `ClipboardHandler`;
- standalone backend-independent `FileDialog(handler)` хранит `title`, `initialDirectory` и typed `filters` в свойствах; `showOpen([Window? parent])` принимает только optional parent. Возвращается один файл или `null` при отмене, native errors становятся `StateError`; совместимый `Window`/`WindowHost.showOpenFileDialog()` сохранён. Windows использует системный `IFileOpenDialog`, Linux — `GtkFileDialog` (GTK 4.10+, пока без GTK parent), macOS — `NSOpenPanel` с parent sheet; возвращаемый UTF-8 path имеет явное native ownership;
- `TextBox` измеряется по реальным метрикам `TextLayout`: desired size = ширина/высота раскладки + content padding (16 по горизонтали, 8 по вертикали), минимальный размер 80×30; добавлено свойство `fontSize` (по умолчанию 14), влияющее на measure и paint;
- измерение `TextBox` клампится к available width и больше не бросает `ArgumentError` на узком контейнере (прежняя оценка `clamp(80, available)` падала при available width меньше 80);
- у `TextBox` раздельные кэши раскладки для measure и render: IME composition не вытесняет раскладку, используемую для измерения, а в steady state создаётся одна native-раскладка;
- native clipboard-тесты помечены тегом `clipboard` (объявлен в `dart_test.yaml`), поэтому их можно исключать через `dart test --exclude-tags clipboard`, когда системный clipboard занят другим процессом;
- legacy `DrawingContext.drawText()` в native backend рисует через SkParagraph shaping: native `dui_draw_text` возвращает логическую ширину нарисованного текста и использует тот же `create_paragraph`, что и `dui_text_layout_create`; шрифт, unicode и font-collection переиспользуются между вызовами, раскладка кэшируется на окне;
- ABI `dui_native` версии 3: `dui_draw_rect` принимает ширину обводки, добавлена `dui_draw_line` (прямая с обводкой), `dui_abi_version()` возвращает 3;
- графика: `Paint` получил `strokeWidth` (0 — заливка, положительное значение — обводка контура), `DrawingContext` получил `drawLine(from, to, paint)`, а `drawRect`/`drawRoundedRect` берут ширину обводки из paint; capsule focus ring рисуется обводкой, прямоугольный — четырьмя залитыми полосами;
- растровое изображение: `ImageFactory` декодирует PNG в `DrawableImage`, `DrawingContext.drawImage(image, rect, paint)` рисует его; native backend читает пиксели через Skia (`SkImages::DeferredFromEncodedData`), `SdlSkiaHost.imageFactory` отдаёт фабрику; добавлен `Image` API в `lib/src/image.dart`;
- исправлен paint-range в `dui_text_layout_draw`: foreground paint задаётся в UTF-16 offsets, а не в UTF-8 байтах;
- `UIElement.dispose()` освобождает элемент и всё его поддерево: отсоединяет от родителя, размонтирует, освобождает потомков и собственные ресурсы, отменяет bindings. Повторный вызов безопасен, а disposed-элемент больше нельзя смонтировать или изменить;
- `UIElement.onDisposed()` — хук для собственных ресурсов контрола; `Label` и `TextBox` освобождают в нём native-раскладки;
- `UIElement.removeChild(child)` — единая точка удаления ребёнка, переопределена в `Panel`, `ContentControl` и `ItemsControl`;
- `Window.dispose()` освобождает дерево контента; `close()` по-прежнему контент не уничтожает, поэтому окно можно переоткрыть;
- `mountTo(null)` идемпотентен и больше не вызывает `onUnmounted()` повторно; монтирование disposed-элемента в окно и добавление его в панель бросают `StateError`;
- `ItemsControl` использует единый флаг disposed из `PropertyOwner` и освобождает контейнеры при dispose;
- native clipboard-тесты помечены тегом `clipboard`, тесты с native-библиотекой — тегом `native` (оба объявлены в `dart_test.yaml`); теги навешиваются на первый импорт файла, как их разбирает package:test;
- CI в `.github/workflows/ci.yml`: job `dart` на Windows/macOS/Linux (pub get, format-check, analyze, `dart test --exclude-tags clipboard,native`) и best-effort job `native` на Windows/Linux (сборка SDL3+Skia из исходников, native-тесты и smoke, `continue-on-error`, запуск по расписанию и вручную);
- backend-independent семантика: `SemanticsRole`, `SemanticsState`, `SemanticsNode` и `SemanticsTree`; дерево строится по требованию из дерева контролов и снимает role, name, value, state, bounds и выделение текста;
- элементы без роли плоско сворачиваются (их дети поднимаются к родителю), а контрол с именем забирает имя своего label-контента, чтобы текст не дублировался;
- `Window.semanticsTree` — снимок семантики дерева контента; фокус и выделение читаются в момент построения, поэтому снимок всегда актуален;
- `Label` → label, `Button` → button (с pressed), `TextBox` → textBox (value, editable, выделение), `ItemsControl` → list, `ContentControl` берёт имя из своего контента;
- native-библиотека ищется сначала в каталоге исполняемого файла (`Platform.resolvedExecutable`), потом по `DUI_NATIVE_LIBRARY` и по абсолютному пути: упакованное приложение кладёт библиотеку рядом с exe;
- install-правила CMake: библиотека уходит в `bin/` (Windows) или `lib/` (Unix), `icudtl.dat` ставится рядом с ней же, `INSTALL_RPATH "$ORIGIN"` на Linux, install name `@rpath` и `@executable_path;@loader_path;@executable_path/../Frameworks` на macOS;
- `tools/package.py`: ставит библиотеку через CMake install-правила, разбирает runtime-зависимости (PE import table / `ldd` / `otool -L`), делит их на системные и private, собирает бандл `build/release/dui_native-<version>-<platform>-<arch>/` с `manifest.json` и sha256 каждого файла;
- архив бандла воспроизводим: фиксированные timestamps и отсортированные записи дают одинаковый sha256 при повторных прогонах;
- `tool/verify_native.dart` — AOT-программа, которая грузит библиотеку из каталога рядом с exe и шейпит Unicode-текст, доказывая, что ICU-данные найдены рядом с библиотекой;
- CI native job запускает `python tools/package.py`, а workflow получил `setup-python` (на ubuntu-раннере нет команды `python`);
- тест `test/native_packaging_test.dart`: порядок поиска библиотеки и раскладка install-дерева;
- автоматизация ScrollViewer: native-тест `test/native_scroll_viewer_test.dart` прогоняет drag полосы прокрутки, клавиатурную прокрутку и клик по треку через публичные `dispatchPointerDown/Move/Up` и `dispatchKeyDown` на реальном native backend;
- native smoke `example/native_scroll_viewer.dart --smoke` проверяет то же: drag до конца и обратно с клампингом, клик по треку, клавиши `down`/`end`/`home`;
- `dart_test.yaml` задаёт `concurrency: 1`: native-тесты создают host, а host в процессе может быть только один, поэтому файлы идут последовательно (тестовые файлы маленькие, suite занимает секунды);
- native-слой сериализует все обращения к SDL process-wide рекурсивным мьютексом: изоляты Dart работают в своих OS-потоках, а SDL не потокобезопасен;
- native-библиотека ищется внутри установленного пакета (`native/bin/<платформа>-<архитектура>/`): путь пакета определяется через `Isolate.resolvePackageUri`, поэтому приложение, запущенное из исходников, находит библиотеку без сборки;
- `NativeBindings.libraryPath` показывает, откуда реально загрузилась библиотека — это первое, что стоит смотреть при ошибке загрузки;
- скомпилированный исполняемый файл не хранит конфигурацию пакетов, поэтому рядом с ним библиотеку копирует исполняемый файл пакета `duix:setup_native`;
- `tools/package.py --dist` собирает папку дистрибуции пакета: исходники, `bin/setup_native.dart` и нативные библиотеки всех платформ из staging-каталога `build/dist/<платформа>-<архитектура>/`; публикация — `dart pub publish --directory ../duix-publish`. Папка лежит вне репозитория, потому что pub прячет всё, что скрыто правилами `.gitignore` репозитория;
- README с quick start: `dart create myapp && cd myapp`, `dart pub add duix`, минимальное приложение, порядок поиска библиотеки, сборка из исходников, публикация и ограничения;
- в процессе разрешён только один native host: SDL имеет одну глобальную очередь событий, поэтому второй host забрал бы события первого; второй host получает явную ошибку вместо тихой поломки;
- видеоподсистема SDL живёт до конца процесса: `SDL_Quit()` при разрушении host рвал подсистему под окном другого изолята, а повторная инициализация SDL после `SDL_Quit` ненадёжна;
- направление раскладки (`FlowDirection`): наследуемое свойство дерева (`UIElement.flowDirection`), логическое выравнивание (`start`/`end`) и зеркалирование раскладки — горизонтальная панель, док, текст в поле, полосы прокрутки и содержимое вьюпорта; направление окна достаётся его содержимому, а собственное значение элемента важнее наследованного;
- направление абзаца в native backend: `DuiTextLayoutOptions` получил поле
  `direction` (0 — left-to-right, 1 — right-to-left), native ставит
  `SkParagraph::setTextDirection`, поэтому порядок прогонов внутри строки
  задаёт направление абзаца, а сами прогоны сохраняют свой порядок;
- 375 Dart-теста, включая file-dialog contract, formatted clipboard snapshots, styles/templates, DataContext inheritance/accessors/reparenting, value precedence/transitions, binding lifecycle/diagnostics, ObservableCollection/ItemsControl/virtualization, ScrollViewer measure/scroll/input/clip, Grid tracks/span/gap/invalidate/HiDPI, DockPanel measure/arrange/invalidate, diagnostics FPS/render-on-demand, synchronous live-resize frame с увеличением physical backbuffer, layout constraints/alignment, infinite text width, clipping/rendering, horizontal scrolling, mouse caret/selection, pointer capture, surrogate pairs, composition, clipboard, recursive dispose, semantics tree, packaging, native ScrollViewer automation, render-on-demand, scheduler counters и направление раскладки (21 тест), многострочный ввод: перенос по словам, вертикальная прокрутка, Shift+Enter и навигация по строкам (15 тестов), флажок: два состояния, связь с моделью, клавиатура, рисование галочки и семантика (16 тестов), группа radio: взаимное исключение кнопок, выбор в свойстве группы, связь с моделью, стрелки, focus scope, вложенные группы и семантика (18 тестов), focus ring вокруг метки флажка и
radio-кнопки: зазор, форма кольца и видимость самого знака (2 теста).

### 3.2. Проверенное поведение

- Нативный пример запускается.
- Заголовок и кнопка видимы.
- Нажатие кнопки обновляет существующий `Label`.
- Идентичность `Label` сохраняется.
- Белый фон окна отображается корректно.
- HiDPI-масштабирование подтверждено на 4K-дисплее.
- `dart analyze` проходит без замечаний.
- Полный `dart test` проходит: все 266 тестов, включая 6 file-dialog contract-тестов, 4 style-теста, 3 control-template-теста, 6 DataContext-тестов, 9 value-precedence-тестов, 13 binding-тестов, 17 ItemsControl/virtualization-тестов, 11 ScrollViewer-тестов, 18 Grid-тестов, 7 DockPanel-тестов, 5 TextBox measurement-тестов, 2 native text-drawing-теста, 12 recursive dispose-тестов, 11 semantics-тестов, native ScrollViewer automation и все clipboard-сценарии.
- Packaging на Windows x64 проверен end-to-end: `cmake --install` кладёт `dui_native.dll` (8 347 648 байт) и `icudtl.dat` (10 468 208 байт) в один каталог install-дерева; DLL тянет только системные Windows DLL (ole32, KERNEL32, USER32, SHELL32, WINMM, ADVAPI32, SETUPAPI, GDI32, OLEAUT32, IMM32, VERSION), private-зависимостей нет.
- Бандл воспроизводим: два подряд прогона `python tools/package.py` дали одинаковый sha256 архива `7553dc6e1a9a450f25cc9ea8a8609d69543d6a1172e087e5f06fdc6f18f6deec`.
- Сквозная проверка бандла проходит: программа, запущенная из другого рабочего каталога, находит библиотеку рядом с exe и шейпит Unicode-текст — «dui_native ABI 2 loaded from the bundle, shaped width 93.4». Негативный контроль: без `icudtl.dat` рядом с библиотекой раскладка не создаётся (`SkParagraph creation failed`), то есть проверка не пустая.
- Классификация зависимостей проверена синтетическими случаями: на Linux private — только библиотеки из дерева сборки проекта (GTK и libstdc++ считаются системными), на macOS private — `@rpath`-зависимости, на Windows — DLL, которых нет в System32.
- Install-правила покрыты тестом с тегом `native`: он запускает `cmake --install` во временный каталог и требует, чтобы библиотека и ICU-файл лежали в одном каталоге.
- ScrollViewer автоматизирован на реальном native backend: drag вертикального ползунка на всю свободную длину трека прокручивает до конца (offset 540 при extent 740 и viewport 200), перетаскивание дальше границ клампится в 0 и в максимум, ползунок следует за offset, клик по треку прокручивает на один viewport, клавиши `down`/`pageup`/`end`/`home` дают 240/40/540/0. Проверено и в native-тесте, и в smoke примера.
- Найдена и устранена опасность параллельных native-тестов: SDL video не потокобезопасен, и два файла с native-окнами в параллельных изолятах (`dart test` запускает файлы параллельно) роняли процесс с `STATUS_STACK_BUFFER_OVERRUN`. Воспроизведено и на двух копиях одного и того же pre-existing файла, то есть проблема не в новом тесте. `dart_test.yaml` теперь задаёт `concurrency: 1`; native-прогон стабильно проходит 36/36 при повторных запусках.
- Потокобезопасность native-слоя закрыта: все SDL-вызовы сериализованы process-wide рекурсивным мьютексом, второй host в процессе отклоняется с явным сообщением, `SDL_Quit()` больше не вызывается. Параллельный прогон native-файлов (`--concurrency=4`) больше не роняет процесс: вместо аварии тесты получают ошибку «Only one native host per process is supported». Три новых теста в `test/native_thread_safety_test.dart` доказывают это изолированно: два изолята одновременно тянут host (один выигрывает, второй получает понятную ошибку, процесс жив), host снова доступен после освобождения, два изолята одновременно шейпят текст.
- Quick start проверен end-to-end на «чужом» приложении с зависимостью на собранную папку дистрибуции: `dart run` находит библиотеку внутри пакета (`Library loaded from: …\publish\native\bin\windows-x64\dui_native.dll`) и рисует окно; `dart compile exe` + `dart run duix:setup_native .` дают собранное приложение, которое грузит библиотеку рядом с exe. Установлено ограничение: в AOT package-конфигурация недоступна (`Isolate.resolvePackageUri` возвращает null), поэтому рядом с exe библиотеку копирует `setup_native`.
- Дерево семантики подтверждено тестами: роли и имена зеркалят дерево UI, элементы без роли сворачиваются, фокус и выделение отражаются в снимке, состояние disabled и границы совпадают с контролом, контрол забирает имя label-контента, `ItemsControl` даёт list с элементами, а disposed-контрол в дерево не попадает.
- Мост Windows UI Automation подтверждён на живой системе: UIA-клиент читает дерево окна (`Window "DUI accessibility"` → `Custom` → `Text`, `Button`, `Edit`), у элементов верные имя, тип управления, границы на экране и состояния (`IsEnabled`, `IsControlElement`, `IsContentElement` — TRUE), фокус отмечен у кнопки, `FrameworkId` — `Dui`.
- Шаблоны есть у всего набора виджетов, который рисует свой вид: `Label`, `Border`, `ScrollBar` и `Button`. Шаблон `Label` заменяет её текст, шаблон `Border` показывает содержимое через `ContentPresenter`, шаблон `ScrollBar` рисует полосу и бегунок. Снимок экрана примера `native_aqua_button` подтвердил бейдж с шаблоном и карточку с шаблоном.
- Части шаблона проверены тестами и снимком экрана: шаблон `TextBox` размещает часть с текстом и текст остаётся на месте, текст не пропадает и когда шаблон часть не разместил, часть переживает замену шаблона и освобождается вместе с контролом; шаблон `ScrollViewer` размещает содержимое и обе полосы, содержимое обрезается по месту части, полосы следуют за смещением вьюпорта.
- Направление абзаца проверено на native backend: в right-to-left абзаце
  первый прогон строки стоит справа, каретка первого символа иврита — на
  правом крае текста, клик по правому краю поля ставит каретку в начало
  строки, а в left-to-right поле тот же клик по левому краю попадает в
  последний символ — иврит внутри прогона всегда читается справа налево.
- Направление раскладки подтверждено и снимком экрана примера `example/native_flow_direction.dart`: заголовок и текст поля стоят у правого края, первый ребёнок горизонтальной панели — справа, вертикальная полоса вьюпорта — слева, горизонтальная полоса начинается у правого края.
- Направление раскладки проверено тестами: направление наследуется по дереву, собственное значение элемента важнее наследованного, направление окна достаётся содержимому, логическое выравнивание `start`/`end` разрешается по направлению, горизонтальная панель и док зеркалятся, текст поля в right-to-left начинается у правого края поля и клик попадает в текст, горизонтальная полоса прокрутки начинается у правого края, вертикальная полоса вьюпорта стоит слева, а содержимое вьюпорта начинается у правого края.
- Исправлен перенос строки на самой границе бокса: текст, ширина которого совпадает с шириной бокса, больше не переносит последнее слово на следующую строку (допуск в один физический пиксель в раскладке Skia). Раньше кнопка показывала «Продолжит», а бейдж — «Badg».
- Графика слоя подтверждена и тестами, и снимком экрана: окно примера `example/native_graphics.dart` рисует кубическую кривую (`drawPath`), белую карточку с мягкой тенью и два прямоугольника, где жёлтый и бирюзовый накладываются в оливковый (`BlendMode.multiply`) с прозрачностью 0.8.
- Recursive dispose подтверждён тестами: поддерево освобождает native-раскладки, disposed-элемент отсоединяется от родителя (список детей пустеет), все потомки получают `isDisposed`, повторный dispose не освобождает ресурсы дважды, фокус снимается, disposed-элемент нельзя вернуть в дерево, `Window.dispose()` освобождает контент, а `close()` оставляет его жить.
- CI-команды проверены локально: `dart format --output=none --set-exit-if-changed lib example test` возвращает 0, `dart analyze` чист, `dart test --exclude-tags clipboard,native` проходит 226 тестов, `dart test --tags native --exclude-tags clipboard` проходит 36 native-тестов. YAML workflow разобран и проверен по структуре; с 2026-11-27 он ещё и отработал на GitHub — job `Dart` зелёный на всех трёх ОС.
- Legacy text drawing подтверждён native-тестом: ширина, возвращённая `dui_draw_text`, совпадает с шириной раскладки `dui_text_layout_create` для того же текста, шрифта и scale; ASCII, кириллица, emoji и RTL-строка рисуются во всех трёх выравниваниях.
- Idle CPU после перевода `drawText` на SkParagraph не вырос: кэш раскладки на окне вернул 1.54% (до кэша было 3.08%), при этом текст теперь shaped.
- `TextBox` измеряется теми же метриками раскладки, что и `Label`: desired width = ширина `Label` + 16, desired height = высота `Label` + 8. Текстовая часть масштабируется с `fontSize` (удвоение `fontSize` удваивает ширину текста), padding остаётся постоянным. Узкий available width клампится вместо падения, изменение текста и remount переизмеряют контрол.
- Native backend подтверждает ту же формулу на реальных SkParagraph-метриках: `TextBox` и `Label` с одинаковым текстом и `fontSize` дают `TextBox.width == Label.width + 16`, а смена текста увеличивает измерение.
- Native library с `IFileOpenDialog` пересобрана, Paragraph smoke проходит. Headless-тесты подтверждают standalone dialog с parent и без него, передачу title/initialDirectory/filters, selected path и `null` при отмене или без backend; пользователь подтвердил parent/ownerless-варианты, фильтры и начальный каталог Windows-примера.
- В formatted clipboard тесте проходят round-trip и восстановление прежнего значения для Unicode plain text, Windows `text/html`/CF_HTML, `application/xhtml+xml`, binary с нулевыми байтами и empty payload. Четыре native clipboard-сценария дополнительно прошли три повторных запуска. CF_HTML формируется с UTF-8 byte offsets, а чтение возвращает fragment без служебного header; остальные MIME-форматы сохраняются. Ручная вставка в сторонние приложения ещё не проверялась.
- Clipboard snapshot/restore покрывает весь набор, перечисляемый MIME API: plain text, CF_HTML, XHTML, binary и empty payload. `clearClipboard()` восстанавливает исходно пустое состояние. Произвольные native-only clipboard formats, не представленные SDL/CF_HTML MIME API, в snapshot не входят.
- Публичный `Window` clipboard API проверен отдельно на headless handler и реальном `SdlSkiaHost`: приложение использует MIME strings и Dart byte lists без FFI/native types. Отсутствие backend возвращает `false`/`null`; native HTML round-trip проходит через тот же `WindowHost` contract.
- Style setters применяются и удаляются через style layer, local/binding маскируют их по общим правилам, несовместимый target type отклоняется. Template factory Button вызывается один раз; content replacement, text и pressed updates сохраняют visual identity. Custom render заменяет default background, keyboard/pointer activation и focus ring продолжают работать.
- Native Aqua smoke на Windows проверяет hover enter/leave, pressed/release, pointer click, Space и сохранение template identity; Skia-вызов rounded rect проходит в native ABI-тесте, а smoke завершается после 3 кадров: scale 2.0, logical 520×320, physical 1040×640. Обновлённый визуальный результат ещё не подтверждён пользователем.
- DataContext рекурсивно наследуется, публикует notifications descendants, восстанавливает актуальное inherited value после очистки local и меняется при detach/reparent. Item context в ItemsControl остаётся local и передаётся вложенным контролам. Typed accessors возвращают совпадение или null, а required accessor выбрасывает понятный `StateError` для absent/wrong type.
- Полная цепочка value layers подтверждена тестами: masked source updates не создают ложных notifications, снятие верхнего слоя восстанавливает effective value, замена binding поверх local публикует корректное previous value. Two-way setter продолжает писать в источник под animation mask; nullable layers различаются по наличию записи, а не по `null`.
- Native items smoke на Windows проходит прокрутку к середине и концу списка из 100 000 строк: после завершения создано 16 контейнеров, extent=2 400 000, отрисованы 3 кадра. Строки примера имеют фиксированную высоту 24; переменная высота проверяется headless-тестом. Ручная проверка примера подтверждена пользователем.
- Cancel/dispose bindings не изменяют последнее effective value, source после отмены не влияет на контрол. Повторная запись того же two-way value и synchronous reentrant notification не создают дополнительных property changes; failed initial read оставляет прежний binding активным.
- Native integration-тест подтверждает, что Dart callback выполняет `beginFrame/present` до возврата из `SDL_SetWindowSize`, получает logical size 240×120 и увеличенный physical backbuffer. Непрерывный drag и maximize двойным щелчком по рамке подтверждены пользователем.
- Margin включается в `desiredSize` и исключается из фактических `bounds`; start/center/end/stretch выравнивание проверено по координатам, а `arrangedSize` сохраняет размер исходного слота.
- Повторный `presentWindow()` без invalidate не увеличивает render/present counters; изменение `Label.text` планирует ровно один следующий кадр. SDL expose/resize могут законно запланировать дополнительный кадр.
- Несколько invalidate до кадра увеличивают `scheduled` и вызывают wake-up только один раз; `layout` и `painted` увеличиваются на каждом обработанном кадре, а пустой `renderFrame()` ничего не рисует.
- Native integration-тест подтверждает `Timer → Label.text → invalidate`: от стабильного baseline добавляется ровно один scheduled/layout/painted/presented.
- Рекурсивный `Window.updateLayout()` во время measure выбрасывает `StateError`, сбрасывает guard через `finally` и не мешает следующему нормальному кадру.
- Два последовательных benchmark-запуска на Windows дали idle process CPU 1.54% и 1.53% за примерно 1 с, без новых кадров после стартовых `scheduled/layout/painted/presented=2/2/2/2`.
- Каждый запуск выполнил 60 async updates ровно за 60 кадров; итоговые counters 62/62/62/62. Медианная invalidate→present latency 16.49 и 16.28 мс, максимум 16.98 и 17.10 мс; средняя latency зависит от фазы таймера и составила 15.48 и 12.05 мс.
- На Windows подтверждены реальные SDL Start/Stop/SetTextInputArea и активное состояние ввода при focus; потеря focus и close останавливают ввод.
- Input area и caret преобразуются из logical UI units в SDL window units; caret вычисляется через `TextLayout`.
- `TextBox` при text input заменяет активное selection, сохраняет направление anchor/extent и обновляет source двустороннего binding.
- Backspace/Delete удаляют выделение или целую surrogate pair; внешнее сокращение текста ограничивает offsets новой длиной.
- Routed Left/Right, Home/End, Shift selection, Ctrl/Cmd word navigation, Select All и Cut/Copy/Paste проходят через `Window.dispatchKeyDown()`; направление selection и two-way binding проверены.
- Left на offset 0 и Right на `text.length` сохраняют caret на границе вместо генерации `-1`/`length + 1`; отдельная регрессия покрывает обычную и word-навигацию, Shift selection и surrogate pair `A😀B`.
- Primary click устанавливает caret через `TextLayout`; drag сохраняет anchor, работает в обоих направлениях и за границами контрола благодаря pointer capture. Клик не оставляет caret внутри surrogate pair и не изменяет binding source.
- `TextBox` использует unbounded single-line layout и автоматический horizontal scroll offset: End и drag за правой границей показывают конец, Home возвращает начало, Left/Right удерживают caret в видимой области. Mouse hit-test и SDL caret получают то же смещение, selection/composition рисуются вместе с прокрученным текстом.
- Текст, selection, composition и caret заключены в Skia clip content bounds; обычный selection рисуется до текста, caret — после него. Focus/collapsed/IME-состояния проверены render-командами.
- Исправлена native-геометрия: `getRectsForRange()` получает UTF-16 offsets без преобразования в UTF-8 bytes, а caret строится по `getGlyphInfoAtUTF16Offset()` или последнему text box для конца строки с учётом направления текста.
- Регрессионный тест на `A😀B` при scale 2.0 проверяет строго возрастающие caret coordinates на offsets 0/1/3/4 и соответствие selection rects диапазонам `0..1`, `1..3` и всего текста. До исправления тест воспроизводил caret `x = 0` после `A`.
- SDL clipboard на Windows выполняет Unicode round-trip, освобождает native string через C ABI и восстанавливает прежнее значение. Bounded retry устранил наблюдавшийся `Couldn't open clipboard` в трёх повторных запусках обоих clipboard-тестов и последующем полном прогоне.
- `DuiEvent` с modifiers, composition range и SDL scancode имеет ABI size 80 байт; SDL byte offsets преобразуются в UTF-16. `KeyEventArgs.logicalKeyCode` получает SDL keycode, `physicalKeyCode` — scancode. OS key modifiers и маппинг SDL key codes покрыты косвенно, без синтеза системного keyboard input.
- Composition видна до commit, не меняет `TextBuffer`/binding, поддерживает CJK/emoji selection range и кириллицу без selection; пустой editing event, focus loss, unmount и editing commands очищают её.
- Матрица проверяет ASCII, кириллицу, emoji, CJK, Arabic, Hebrew, multiline, пустую и очень длинную строки, а также стабильность logical metrics на масштабах 1.0, 1.25, 1.5 и 2.0.
- Пустая строка имеет нулевую ширину и конечные неотрицательные metrics; учтён допустимый glyph overhang tight selection boxes за пределами advance width.
- `Label` на Windows получает реальные SkParagraph metrics, переносит длинный текст по доступной ширине и рисует тот же native layout.
- Цвет не пересоздаёт layout; text, fontSize, alignment, maxWidth, scale и factory вызывают замену с disposal предыдущего layout.
- Native text handles измеряют ASCII, кириллицу и emoji, возвращают UTF-16 hit-test/caret/selection geometry и рисуются в активном SDL/Skia frame.
- Полный `python tools/bootstrap_native.py` успешно пересобирает Skia/SkParagraph и native library.
- Paragraph smoke на Windows измеряет `ASCII, кириллица` через SkParagraph: width 124.945, height 21.
- Native smoke автоматически выполняет 3 event iterations: scale 2.0, logical 320×200, physical 640×400, scheduled=2, layout=2, painted=2, presented=2.
- После устранения повторного resize того же размера native text gallery smoke выполняет 3 event iterations и рисует 1 кадр: scale 2.0, logical 960×800, physical 1920×1600, scheduled=1, layout=1, painted=1, presented=1.
- TextBox smoke через `--textbox --smoke` рисует composition, обычный selection и caret в отдельных кадрах, проверяет `Smoke か😀`, mouse caret и captured drag, затем завершается после 3 кадров: logical 760×590, physical 1520×1180, scheduled=4, layout=6, painted=4, presented=4. Два дополнительных layout pass выполняет централизованный input hit-testing.
- Diagnostics базового native smoke на Windows: scale 2.0, logical 320×200, physical 640×400, scheduled=2, layout=2, painted=2, presented=2.

### 3.3. Основные файлы

```text
lib/dui.dart                         — публичный Dart API с явными exports
lib/native.dart                      — публичный native API
lib/src/application.dart             — Application
lib/src/window.dart                  — Window и native host-контракты
lib/src/clipboard.dart               — ClipboardHandler и стандартные MIME types
lib/src/file_dialog.dart             — standalone FileDialog и backend contract
lib/src/frame_scheduler.dart         — invalidate coalescing, layout/paint passes и counters
lib/src/focus_manager.dart           — FocusManager
lib/src/focus_decoration.dart        — общий focus ring: прямоугольное и капсульное кольцо
lib/src/ui_element.dart              — UIElement, Control и WindowHost lifecycle
lib/src/controls.dart                — compatibility barrel для контролов
lib/src/content_control.dart         — ContentControl и content notifications
lib/src/control_template.dart        — ControlTemplate и ContentPresenter
lib/src/template_part.dart            — TemplatePart: именованная часть контрола, которую размещает шаблон
lib/src/styles.dart                  — типизированные Style и DuiSetter
lib/src/semantics.dart              — SemanticsRole, SemanticsState, SemanticsNode, SemanticsTree
lib/src/button.dart                  — Button и persistent template
lib/src/label.dart                   — Label
lib/src/text_box.dart                — TextBox, editing, scrolling и IME
lib/src/text_editor.dart             — общий каркас редактирования: буфер, команды, composition, мышь и IME
lib/src/text_area.dart                — TextArea: многострочный ввод, перенос по словам и вертикальная прокрутка
lib/src/checkable.dart                — общее ядро флажков: состояние, метка, клавиатура и семантика
lib/src/checkbox.dart                 — CheckBox: два состояния, галочка и текст метки
lib/src/radio_button.dart             — RadioButton: кнопка группы с кружком и точкой
lib/src/radio_group.dart              — RadioGroup: выбор группы, focus scope и стрелки по кнопкам
lib/src/border.dart                  — Border
lib/src/colors.dart                  — Colors
lib/src/panel.dart                   — Panel и ElementChildrenList
lib/src/stack_panel.dart             — StackPanel
lib/src/dock_panel.dart              — Dock, DockPanel и last-child-fill
lib/src/grid.dart                    — GridLength, definitions и Grid layout
lib/src/properties.dart              — свойства и bindings
lib/src/observable.dart              — observable primitives
lib/src/observable_collection.dart   — ObservableCollection и события изменений
lib/src/items_control.dart           — ItemsControl и VirtualizingStackPanel
lib/src/events.dart                  — routed events
lib/src/drawing.dart                 — DrawingContext
lib/src/path.dart                    — Path и команды контура
lib/src/text_buffer.dart              — UTF-16 text/selection model и команды
lib/src/text_layout.dart             — текстовый контракт, cache key и общий кэш раскладки
lib/src/geometry.dart                — FlowDirection, выравнивание и геометрия
lib/src/headless_text_layout.dart    — deterministic headless text layout
lib/src/native/native_bindings.dart  — FFI
lib/src/native/native_text_layout.dart — SkParagraph TextLayout backend
lib/src/native/sdl_skia_host.dart    — SDL/Skia Dart host
native/include/dui_native.h          — C ABI
native/src/dui_native.cpp            — SDL3 + Skia backend
native/src/uia_windows.h            — снимок дерева семантики для моста UI Automation
native/src/uia_windows.cpp          — мост Windows UI Automation: поставщик IRawElementProvider
native/src/file_dialog_macos.mm      — macOS NSOpenPanel и SDL NSWindow parent
native/src/paragraph_smoke.cpp       — SkParagraph smoke-проверка
native/CMakeLists.txt                — нативная сборка; Linux требует pkg-config и GTK 4.10+ (`libgtk-4-dev`)
tools/bootstrap_native.py            — зависимости и сборка
tools/package.py                    — install-правила, разбор зависимостей, воспроизводимый бандл, папка дистрибуции
tool/verify_native.dart             — сквозная проверка бандла: загрузка библиотеки и shaping
tool/verify_uia.ps1                — чтение дерева UI Automation окна
tool/verify_published.dart          — загрузка библиотеки из папки дистрибуции (проверка опубликованного пакета)
bin/setup_native.dart               — копирование нативной библиотеки рядом с exe собранного приложения
README.md                           — quick start, порядок поиска библиотеки, сборка и публикация (английский)
CHANGELOG.md                        — журнал изменений пакета (английский)
LICENSE                             — MIT
example/native_counter.dart          — нативный интерактивный пример
example/native_open_file_dialog.dart — системный Windows/Linux/macOS open-file dialog
example/native_aqua_button.dart      — Aqua style/template, hover/pressed и smoke
example/native_smoke.dart            — native smoke с автоматическим завершением
example/native_text_gallery.dart     — Unicode/HiDPI text gallery и её smoke-режим
example/native_textbox.dart          — интерактивная проверка TextBox и smoke-режим
example/native_textarea.dart         — интерактивная проверка TextArea и smoke-режим
example/native_checkbox.dart         — интерактивная проверка CheckBox и smoke-режим
example/native_radio_button.dart     — интерактивная проверка RadioButton и группы и smoke-режим
example/native_frame_benchmark.dart  — idle CPU и async invalidate latency
example/native_items_control.dart    — список 100 000 элементов и virtualization smoke
example/native_scroll_viewer.dart   — ScrollViewer, прокрутка и smoke
example/native_accessibility.dart   — окно с семантикой для проверки моста UI Automation
example/native_graphics.dart         — пути, тени и режимы наложения
example/native_template_parts.dart   — шаблоны, размещающие части TextBox и ScrollViewer
example/native_flow_direction.dart   — окно с направлением раскладки right-to-left
test/                                — автоматические тесты
test/text_box_measurement_test.dart — измерение TextBox по метрикам раскладки
test/dispose_test.dart              — recursive dispose элементов и поддеревьев
test/semantics_test.dart            — дерево семантики, фокус и выделение
test/path_test.dart                 — контуры пути и paint
test/template_parts_test.dart        — части шаблона у TextBox и ScrollViewer
test/flow_direction_test.dart        — направление раскладки: наследование, зеркалирование, right-to-left
test/text_area_test.dart              — многострочный ввод: перенос по словам, прокрутка и навигация по строкам
test/native_text_area_test.dart       — перенос по словам в SkParagraph и правка многострочного поля
test/checkbox_test.dart               — флажок: состояния, связь с моделью, клавиатура и рисование
test/radio_button_test.dart           — группа radio: выбор, стрелки, focus scope и семантика
test/native_text_direction_test.dart — направление абзаца на native backend
test/native_graphics_test.dart      — путь, тень и наложение на native backend
test/native_packaging_test.dart     — порядок поиска библиотеки и раскладка install-дерева
test/native_scroll_viewer_test.dart — drag полосы прокрутки и клавиатура на native backend
test/native_thread_safety_test.dart — несколько изолят одновременно используют native-слой
dart_test.yaml                       — объявление тегов clipboard и native, concurrency: 1
.github/workflows/ci.yml            — CI: Dart на трёх ОС и best-effort native job
```

### 3.4. Команды

```bash
dart pub get
dart format lib example test
dart analyze
dart test
dart test --exclude-tags clipboard
dart test --exclude-tags clipboard,native
dart test --tags native --exclude-tags clipboard
dart run example/counter.dart
dart run example/native_open_file_dialog.dart --diagnostics
dart run example/native_aqua_button.dart --diagnostics
dart run example/native_aqua_button.dart --smoke --diagnostics
dart run example/native_frame_benchmark.dart
dart run example/native_items_control.dart
dart run example/native_items_control.dart --smoke --diagnostics
dart run example/native_scroll_viewer.dart --smoke --diagnostics
dart run example/native_textarea.dart --smoke --diagnostics
dart run example/native_checkbox.dart --smoke --diagnostics
dart run example/native_radio_button.dart --smoke --diagnostics
dart run example/native_accessibility.dart --seconds=90
dart run example/native_graphics.dart --smoke --diagnostics
powershell -ExecutionPolicy Bypass -File tool/verify_uia.ps1 -ProcessId <pid>
```

Про `--exclude-tags clipboard`: четыре native clipboard-теста работают с реальным
системным clipboard и падают, если буфер удерживает другой процесс. Раньше их
исключали шаблоном `dart test --name '^(?!.*clipboard).*$'`, но Windows-оболочка
съедает символ `^` до запуска Dart, и шаблон деградировал до «совпадает всё» —
исключения не происходило. Теперь используется тег `clipboard`, объявленный в
`dart_test.yaml`.

Нативная проверка и сборка:

```bash
python tools/bootstrap_native.py --check
python tools/bootstrap_native.py
python tools/bootstrap_native.py --run
python tools/bootstrap_native.py --smoke
python tools/bootstrap_native.py --smoke --diagnostics
python tools/bootstrap_native.py --text-gallery
python tools/bootstrap_native.py --text-gallery --smoke --diagnostics
python tools/bootstrap_native.py --textbox
python tools/bootstrap_native.py --textbox --smoke --diagnostics
```

Упаковка и проверка зависимостей:

```bash
python tools/package.py                  # install + проверка зависимостей + бандл + сквозная проверка
python tools/package.py --check-only     # только состав runtime-зависимостей
python tools/package.py --skip-install   # бандл из каталога сборки, без install-правил
python tools/package.py --dist           # папка дистрибуции пакета в build/publish
cmake --install native/build --prefix build/release/install-tree
dart run duix:setup_native .            # копирование библиотеки рядом с exe (для собранных приложений)
```

Бандл собирается в `build/release/dui_native-<version>-<platform>-<arch>/` и
рядом с ним — архив `.zip` (Windows) или `.tar.gz` (Unix).

Если Dart не в `PATH`:

```bash
python tools/bootstrap_native.py --run --dart "<путь-к-dart>"
python tools/bootstrap_native.py --smoke --dart "<путь-к-dart>"
```

---

## 4. Известный технический долг

Приоритет указан в скобках: P0 — критично, P1 — следующий этап, P2 — позже.

1. **P0 (закрыт 2026-11-26):** `TextBox.measureCore()` считал ширину через число символов. Теперь измерение идёт по метрикам `TextLayout`, добавлено свойство `fontSize`, узкий available width клампится вместо `ArgumentError`.
2. **P1 (закрыт 2026-11-26):** legacy `drawText` переведён на SkParagraph shaping: native `dui_draw_text` строит shaped-параграф через общий `create_paragraph`, шрифт/unicode/font-collection переиспользуются между вызовами, а раскладка кэшируется на окне. Остался только headless-раскладка в тестовом рендерере — там shaping по определению отсутствует.
3. **P2:** Clipboard snapshots охватывают форматы SDL/CF_HTML MIME API, но не произвольные native-only formats вне него. Ручная проверка обмена HTML со сторонними приложениями ещё не выполнена.
4. **P2:** SDL wait ограничен 16 мс, чтобы Dart timers получали управление; это не полностью event-driven async integration. Измеренные 1.53–1.54% idle process CPU и медианная latency около 16.3–16.5 мс пока не оправдывают усложнение backend.
5. **P2:** поиск видимого диапазона и расчёт estimated extent в `VirtualizingStackPanel` линейны по числу items; переменная высота может уточнять позицию на последующих layout pass.
6. **P1:** value layers, DataContext inheritance и styles реализованы, но универсальное inherited-property propagation и animation engine ещё отсутствуют; control templates пока поддержаны только у Button.
7. **P1 (закрыт 2026-11-26):** единый recursive dispose реализован — `UIElement.dispose()` освобождает поддерево, `onDisposed()` отдаёт контролам их ресурсы, `removeChild()` унифицирует удаление ребёнка, `Window.dispose()` закрывает дерево окна.
8. **P2 (частично закрыт 2026-11-28):** accessibility — реализована backend-independent модель семантики (`SemanticsTree`, role/name/value/state/bounds, синхронизация focus и selection) и мост Windows UI Automation (`native/src/uia_windows.cpp`: поставщик `IRawElementProvider` поверх дерева семантики). Мост отдаёт дерево и состояния, но не выполняет действия: `SetFocus`, `Invoke` кнопки и запись значения поля требуют обратного вызова из native в Dart. macOS NSAccessibility и Linux AT-SPI не сделаны — они требуют чужих машин.
9. **P2 (закрыт 2026-11-26 на Windows x64):** кроссплатформенный CI добавлен (Dart job на трёх ОС и best-effort native job), packaging runtime dependencies и воспроизводимый release build реализованы: `tools/package.py` разбирает зависимости, проверяет, что private-зависимостей нет, собирает бандл с manifest и sha256 и воспроизводимым архивом, а install-правила CMake кладут `icudtl.dat` рядом с библиотекой. Осталось проверить macOS (universal binary, codesign), arm64 и Linux на реальных дистрибутивах. Native job на macOS не запускается: у hosted-runner нет window server, а сборка Skia требует больше диска и времени, чем даёт раннер.
10. **P2 (закрыт 2026-11-26):** SDL video не потокобезопасен, а native-слой не сериализовал обращения к нему — два изолята с окнами роняли процесс. Теперь все SDL-вызовы идут под process-wide рекурсивным мьютексом, host в процессе может быть только один (второй получает явную ошибку), а `SDL_Quit()` не вызывается. Ограничение «один host на процесс» остаётся осознанным: у SDL одна глобальная очередь событий, и поддержка нескольких host потребовала бы её переделки на стороне Dart.

12. **P1 (закрыт 2026-11-28):** направление абзаца в native backend сделано: `DuiTextLayoutOptions` получил поле `direction`, native ставит `SkParagraph::setTextDirection`, native ABI версии 6. Би-алгоритм unicode отдаёт порядок прогонов, а каретка, выделение и попадание мыши считаются по координатам абзаца.

13. **P1:** перенос по словам в headless-раскладке приблизителен: ширина символа считается как 0.6 от кегля, поэтому тестовая раскладка переносит текст не так, как настоящий backend. На native перенос настоящий (SkParagraph), а headless-раскладка нужна только для тестов и тестового рендерера.
15. **P1:** мост UI Automation ещё не отдаёт галочку и radio-кнопку: у ролей `checkBox` и `radioButton` есть индекс в дереве семантики и флаг состояния, но мост Windows пока отдачает такие узлы как `UIA_CustomControlTypeId` — нужен `TogglePattern` с состоянием и переключением. Слой 1 без native-работ, поэтому работа остаётся в мостах accessibility.
17. **P1:** при переходе с клавиатуры в группу radio фокус встаёт на первую кнопку, а не на отмеченную: менеджер фокуса не знает про группы. В обычных программах фокус встаёт на отмеченную кнопку группы.
16. **P2:** у `CheckBox` два состояния, как и в плане: третье состояние (неопределённое) для «выбрать всё» ещё не сделано, и в дереве семантики для него есть готовый флаг `indeterminate`.
14. **P1:** правки `TextArea` не отменяются: стек отмены (п. 9 §7.1) ещё не сделан, поэтому Ctrl+Z в поле не работает.
11. **P1 (закрыт 2026-11-28):** `TextBox` и `ScrollViewer` шаблоны не поддерживали: шаблон заменял содержимое контрола целиком, а у них содержимое — это текст с выделением и caret либо полосы прокрутки. Теперь у обоих есть модель template parts: контрол отдаёт шаблону именованную часть (`text` у `TextBox`, `content`, `horizontalScrollBar` и `verticalScrollBar` у `ScrollViewer`), а шаблон её размещает; часть, которую шаблон не разместил, остаётся у контрола.

---

## 5. Правила выполнения работ

- Выполнять один небольшой вертикальный шаг за рабочую сессию.
- После каждого шага оставлять проект компилируемым.
- После изменения C ABI обновлять одновременно header, C++, Dart typedef, lookup и вызов.
- После изменения C ABI обязательно пересобирать native library.
- Не добавлять новую функциональность без минимального теста или smoke-примера.
- Не смешивать рефакторинг property system с добавлением новых контролов.
- Не оптимизировать rendering до появления корректного текста и ввода.
- Не добавлять GPU backend на ближайших этапах.
- В конце сессии обновлять разделы «Текущее состояние», «Ближайшие задачи» и «Журнал работ».

---

# Этап 0. Стабилизация и диагностика

Цель: обеспечить быстрый feedback loop перед усложнением текста.

## 0.1. Добавить native smoke-режим

- [x] Добавить флаг `--smoke` или отдельный `example/native_smoke.dart`.
- [x] Открыть окно, нарисовать несколько кадров и автоматически закрыть его.
- [x] Проверить создание и уничтожение host/window без утечек и падений.
- [x] Возвращать ненулевой exit code при native error.
- [x] Не запускать бесконечный event loop в автоматическом smoke-тесте.

Критерий готовности: одна команда запускает native backend и завершается без ручного закрытия окна.

**Проверено пользователем:** `Native smoke passed: 3 frames rendered.`

## 0.2. Добавить диагностические метрики

- [x] Показывать `displayScale`, `pixelDensity`, logical size и physical size.
- [x] Добавить счётчик `renderFrame` и число фактических present.
- [x] Сделать диагностику отключаемой.
- [x] Не печатать сообщения каждый кадр.

Критерий готовности: можно однозначно определить текущие размеры, масштаб и частоту рендеринга.

## 0.3. Добавить базовые ABI-тесты

- [x] Проверить `dui_abi_version()`.
- [x] Проверить создание/уничтожение host.
- [x] Проверить ошибки при нулевых указателях.
- [x] Документировать потоки, на которых разрешено вызывать функции.

Критерий готовности: базовый C ABI проверяется отдельно от UI-контролов.

---

# Этап 1. Нативная текстовая раскладка

Цель: единый источник истины для measurement и drawing текста.

## 1.1. Спроектировать `TextLayout`

Предлагаемый Dart API:

```dart
abstract interface class TextLayout {
  double get width;
  double get height;
  double get baseline;

  void draw(DrawingContext context, Point position);
  TextPosition hitTest(Point position);
  Rect caretRect(int offset);
  List<Rect> selectionRects(int start, int end);
  void dispose();
}
```

Требования:

- [x] `Label` не рассчитывает ширину по числу символов.
- [x] Текстовая раскладка кэшируется.
- [x] Cache invalidation происходит при изменении text, font, fontSize, width и scale.
- [x] `TextLayout` не становится публичной Skia-сущностью.
- [x] Время жизни native handles определено явно.

Зафиксированный контракт:

- `TextLayoutFactory.create()` возвращает объект с одним явным владельцем.
- Владелец вызывает `dispose()` при замене layout и при окончательном уничтожении контрола или cache entry.
- `dispose()` идемпотентен; остальные операции после него выбрасывают `StateError`.
- Native handle скрыт внутри backend-реализации и не входит в публичный контракт.
- `TextPosition.offset`, `caretRect()` и `selectionRects()` используют UTF-16 code unit offsets.
- Cache key — `TextLayoutOptions`: text, fontFamily, fontSize, maxWidth, scale и alignment.

## 1.2. Расширить Skia-сборку

- [x] Включить SkParagraph.
- [x] Включить необходимые HarfBuzz/ICU зависимости.
- [x] Обновить GN args в bootstrap.
- [ ] Проверить Linux fontconfig/Freetype.
- [x] Проверить Windows system font manager.
- [ ] Проверить macOS CoreText.
- [x] Зафиксировать получившиеся linker dependencies в CMake.

Критерий готовности: одинаковый текст строится и измеряется через SkParagraph на трёх ОС. На Windows критерий выполнен. Для Linux и macOS добавлены platform-specific font manager/scanner, но реальные сборка и Paragraph smoke на этих ОС ещё не запускались, поэтому общий критерий готовности не подтверждён.

## 1.3. Добавить native text handles в C ABI

Ориентировочные операции:

```text
text_layout_create
text_layout_destroy
text_layout_measure
text_layout_draw
text_layout_hit_test
text_layout_caret_rect
text_layout_selection_rects
```

Требования:

- [x] Использовать opaque `DuiTextLayout*`.
- [x] Передавать UTF-8 и явную длину.
- [x] Не возвращать указатели на временные C++-строки.
- [x] Возвращать простые структуры с `struct_size`.
- [x] Обрабатывать ошибки без C++ exceptions за ABI boundary.

## 1.4. Перевести `Label` на `TextLayout`

- [x] Получить реальные `width`, `height` и baseline.
- [x] Учитывать доступную ширину в `measureCore()`.
- [ ] Добавить `maxLines`, overflow и wrapping позже отдельными свойствами.
- [x] Не пересоздавать layout, если параметры не изменились.
- [x] Реализовать headless text layout для unit-тестов.

Критерий готовности: measurement совпадает с фактически нарисованным текстом, включая кириллицу и смешанный текст. Выполнено и проверено на Windows; `maxLines` и overflow намеренно оставлены отдельной задачей.

## 1.5. Тестирование текста

- [x] ASCII.
- [x] Кириллица.
- [x] Emoji.
- [x] CJK.
- [x] Arabic/Hebrew.
- [x] Многострочный текст.
- [x] Пустая строка.
- [x] Очень длинная строка.
- [x] Масштабы 1.0, 1.25, 1.5 и 2.0.

Критерий готовности: нет clipping, неправильной ширины и скачков высоты при HiDPI. Автоматические metrics/geometry-проверки и gallery smoke выполнены на Windows. Ручной визуальный контроль clipping на мониторах с разными масштабами ещё не выполнен; Linux и macOS не проверены.

---

# Этап 2. Полноценный TextBox

Цель: базовый однострочный редактор с корректным Unicode/IME поведением.

## 2.1. Модель текста и выделения

- [x] Хранить текст независимо от render layout.
- [x] Ввести selection anchor и active end.
- [x] Определить cursor offset в Unicode code points или UTF-16 offsets и не смешивать модели.
- [x] Добавить команды редактирования вместо обработки клавиш прямо в render logic.
- [x] Проверять диапазоны offsets.

Зафиксировано: `TextSelection.baseOffset` и `extentOffset` — UTF-16 code unit offsets. Backspace/Delete удаляют surrogate pair целиком; полноценная grapheme-cluster навигация пока не реализована.

## 2.2. SDL text input lifecycle

- [x] При получении focus вызвать `SDL_StartTextInput()`.
- [x] Передавать text input area и cursor position.
- [x] При потере focus вызвать `SDL_StopTextInput()`.
- [x] При перемещении/изменении caret обновлять SDL text input area.
- [x] Обрабатывать close/unmount без оставления активного IME.

Проверено на Windows через C ABI и высокоуровневый `TextBox`/`SdlSkiaHost` integration test. Ручная проверка системных IME на Linux/macOS не выполнялась.

## 2.3. Команды редактирования

- [x] Вставка текста.
- [x] Backspace/Delete.
- [x] Left/Right.
- [x] Home/End.
- [x] Ctrl/Cmd+Left/Right.
- [x] Selection с Shift.
- [x] Select All.
- [x] Cut/Copy/Paste.
- [x] Отмена selection при обычном перемещении.

Важно: не формировать вводимый Unicode-текст из key-down событий. Key events нужны для команд, `SDL_EVENT_TEXT_INPUT` — для вставки текста.

Проверено unit/integration-тестами на Windows, включая реальный SDL clipboard. Ручная проверка физической клавиатуры и системных IME не выполнялась; навигация работает по code points и упрощённым word runs, не по grapheme clusters.

## 2.4. IME

- [x] Обрабатывать `SDL_EVENT_TEXT_EDITING`.
- [x] Хранить composition text и composition range.
- [x] Рисовать composition отдельно от подтверждённого текста.
- [x] Не отправлять промежуточный composition как окончательный two-way binding update без явного решения.
- [ ] Проверить русский, китайский/японский ввод и emoji.

Реализация и автоматические события проверены на Windows, включая UTF-16 range для CJK/emoji и ввод кириллицы без composition selection. Последний пункт остаётся открытым для ручной проверки реальных системных IME; автоматические события её не заменяют.

## 2.5. Mouse interaction

- [x] Hit test позиции текста через `TextLayout`.
- [x] Установка caret кликом.
- [x] Selection перетаскиванием.
- [x] Pointer capture во время drag.
- [ ] Двойной клик — выделение слова, если не осложняет этап.

Критерий готовности: можно ввести, выделить, изменить и вставить текст; two-way binding остаётся синхронизированным. Выполнено и проверено unit-тестами и native smoke на Windows. Двойной клик отложен как необязательная часть этапа. Обычные selection/caret и clipping добавлены последующим исправлением отрисовки. Неверные native caret coordinates и UTF-16 selection ranges исправлены, покрыты координатной регрессией и подтверждены ручной проверкой. Граничная навигация также подтверждена вручную; горизонтальная прокрутка пока проверена автоматическими render/mouse/keyboard/native smoke-тестами.

---

# Этап 3. Focus и клавиатурная навигация

## 3.1. FocusManager

- [x] Вынести focus из `Window` в отдельный `FocusManager`.
- [x] Отслеживать focused element и его mount state.
- [x] При unmount focused element корректно очищать или восстанавливать focus.
- [x] Запрещать focus невидимым и disabled контролам.

`FocusManager` проверяет mount state, принадлежность окну, `isFocusable`, а также видимость и доступность всей цепочки родителей. При unmount, disable или hide focus очищается без неявного восстановления; после remount требуется явный `focus()`. Очистка при unmount корректно завершает SDL text input.

## 3.2. Tab traversal

- [x] Построить порядок обхода по logical tree.
- [x] Реализовать Tab и Shift+Tab.
- [x] Добавить `focusable`, `tabIndex` только при необходимости.
- [x] Реализовать focus scope для будущих dialogs/popups.

Обход выполняется в прямом порядке logical tree с wrap-around и пропускает non-focusable, disabled и невидимые ветви. Используется существующий `Control.isFocusable`; `tabIndex` не добавлен за ненадобностью. `UIElement.isFocusScope` ограничивает обход потомками ближайшей области focused control; вложенные scope имеют приоритет. Обработанный routed `keyDown` отменяет автоматический переход, Ctrl/Cmd+Tab его не запускают.

## 3.3. Keyboard activation

- [x] Button активируется Space/Enter.
- [x] Key events имеют modifiers и physical/logical key.
- [x] Обработанное событие не вызывает повторную активацию родителя.

Критерий готовности: пример можно полностью использовать без мыши. Выполнено для текущих примеров: Tab/Shift+Tab выбирают контролы, Space/Enter активируют focused Button, TextBox сохраняет клавиатурное редактирование. Проверено автоматически и native smoke; физическая клавиатура вручную не проверялась.

---

# Этап 4. Frame scheduling и производительность

## 4.1. Убрать постоянный рендеринг

- [x] Рисовать только при `frameScheduled` или необходимости animation tick.
- [x] Не вызывать present, если кадр не изменился.
- [x] Сохранить обработку событий даже без повреждённого кадра.
- [x] Включить SDL VSync.
- [x] Убрать постоянную задержку 8 мс как основной scheduling mechanism.

## 4.2. Централизовать scheduler

- [x] Объединять несколько invalidate в один кадр.
- [x] Отделять layout pass от paint pass.
- [x] Не допускать рекурсивного запуска layout во время layout.
- [x] Добавить diagnostics: scheduled/layout/painted/presented.

## 4.3. Кэширование

- [x] Кэшировать `TextLayout`.
- [x] Кэшировать paths/paints, если профилирование покажет необходимость — замеры не выявили необходимости, новый cache не добавлен.
- [x] Не вводить retained GPU scene graph на CPU backend.
- [x] Добавить damage rectangles только после профилирования — профилирование выполнено, damage rectangles не добавлены.

Критерий готовности достигнут на Windows benchmark: idle process CPU 1.53–1.54%, нулевой прирост кадров в idle, 60 async updates дают 60 кадров с медианной latency около 16.3–16.5 мс. Это локальный замер, а не кроссплатформенная гарантия.

---

# Этап 5. Layout system

## 5.1. Уточнить constraints

- [x] Добавить min/max width/height.
- [x] Добавить margin как attached/layout property.
- [x] Добавить horizontal/vertical alignment.
- [x] Различить desired size, arranged size и actual bounds.
- [x] Проверить поведение при infinite constraints.

`desiredSize` включает margin, `arrangedSize` описывает выделенный слот, а `bounds` — фактический прямоугольник контрола после вычитания margin и выравнивания. Stretch остаётся режимом по умолчанию; min/max проверяются при установке, min может превышать доступный размер, но фактические bounds остаются внутри слота. Measure cache учитывает новые available constraints. `StackPanel` передаёт детям бесконечность по главной оси; headless и native text layouts сохраняют конечные metrics при бесконечной ширине.

## 5.2. DockPanel

- [x] Добавить `Dock` attached property.
- [x] Реализовать последовательное распределение пространства.
- [x] Добавить last-child-fill.

`DockPanel.dockProperty` использует существующий `DuiProperty<UIElement, Dock>`; `getDock()`/`setDock()` работают с любым `UIElement`, а изменение значения инвалидирует measure родителя. Дети последовательно занимают left/top/right/bottom в remaining rect. `lastChildFill` по умолчанию включён и применяется к последнему видимому ребёнку; при исчерпании пространства slots ограничиваются нулём. Margin, alignment, infinite constraints, изменение `Dock`/`lastChildFill` и скрытые дети покрыты координатными тестами.

## 5.3. Grid

- [x] Auto, Pixel и Star tracks.
- [x] Row/column definitions.
- [x] Gap.
- [x] RowSpan/ColumnSpan после базовой версии.
- [x] Тесты на дробные размеры и HiDPI rounding.

Версия использует `GridLength.auto`, `GridLength.pixel()` и `GridLength.star(weight)`, наблюдаемые `RowDefinition`/`ColumnDefinition` и `rowSpacing`/`columnSpacing`. Attached `Grid.row`/`Grid.column` по умолчанию равны 0, а `rowSpan`/`columnSpan` — 1; пустые definitions создают по одному Star track. Auto учитывает максимальный desired size ячейки, Pixel фиксирует размер, Star делит остаток по весам. Spanning-children измеряются по объединённым tracks и промежуточным gaps: дефицит равномерно распределяется между Auto-tracks диапазона, а при бесконечном constraint без Auto — между Star-tracks. После роста Auto конечные Star-доли пересчитываются. Auto-строки повторно измеряются после определения ширины столбцов, а arrange объединяет уже HiDPI-округлённые границы первого и последнего track, включая промежуточные gaps.

## 5.4. ScrollViewer

- [x] Viewport и content extent.
- [x] Mouse wheel.
- [x] Scrollbars.
- [x] Clip при render и hit test.
- [x] Keyboard scrolling после focus scopes.

`ScrollViewer` измеряет content с бесконечным constraint по каждой разрешённой оси и повторно разрешает Auto scrollbars с учётом их перекрёстного влияния на viewport. Поддерживаются `horizontalOffset`/`verticalOffset`, `scrollTo()`, `scrollBy()`, `scrollToStart()`/`scrollToEnd()`, четыре режима `ScrollBarVisibility` и пропорциональные thumbs с минимальным размером. Mouse wheel и клавиши arrows/PageUp/PageDown/Home/End проходят routed events от focused descendants. Scrollbar track выполняет page scrolling, thumb использует pointer capture. Content ограничен viewport и при render, и при hit test.

Критерий готовности этапа 5 выполнен: `example/native_scroll_viewer.dart` собирает типовое окно настроек без абсолютного позиционирования. Корневой `DockPanel` размещает header, footer и заполняющий `ScrollViewer`; каждая секция использует `DockPanel` и двухколоночный Auto/Star `Grid` с Label/TextBox. Пример поддерживает `--smoke --diagnostics`; smoke проверяет регионы layout, wheel, PageDown из focused TextBox и активацию footer Button. Для margin добавлен стандартный `EdgeInsets.only()`.

---

# Этап 6. Коллекции и ItemsControl

## 6.1. ObservableCollection

- [x] Add/remove/insert/move/reset notifications.
- [x] Строгая модель подписки и disposal.
- [x] Не пересоздавать всё дерево при точечном изменении.

`ObservableCollection<T>` реализует `ListBase<T>`, отдельные `add`/`insert`/`remove`/`replace`/`move`/`reset`-события с индексами и неизменяемыми списками элементов, snapshot dispatch listeners, отменяемые подписки и идемпотентный `dispose()`. После disposal мутации и новые подписки запрещены.

## 6.2. ItemsControl

- [x] Items source.
- [x] Item template как factory, не как rebuild существующего контрола.
- [x] Переиспользование контейнеров по ключу при перемещении.
- [x] Корректный unmount/dispose удалённых элементов.

`ItemTemplate<T>` вызывается только для материализуемого item; `dataContext` хранит сам item. Ключи должны быть уникальны. Add/insert/remove/replace не пересоздают unaffected siblings, move/reset сохраняют identity по ключу. Удалённый элемент отсоединяется и unmount, включая очистку focus; смена source отменяет старую подписку.

## 6.3. VirtualizingStackPanel

- [x] Создавать только видимые элементы плюс небольшой buffer.
- [x] Поддерживать estimated extent.
- [x] Обрабатывать переменную высоту элементов.
- [x] Проверять focus и selection при recycling.

Виртуализация использует `verticalOffset`/`viewportHeight` непосредственного родителя `ScrollViewer`; создаются видимые элементы и buffer, measured heights уточняют estimated extent. Повторная прокрутка сохраняет overlapping keyed elements, recycling очищает focus и не переносит selection state в новый контейнер. Поиск offset и extent пока линейны по числу items; сложных иерархических контейнеров и pooling отдельных контролов нет.

Критерий готовности выполнен: native smoke прокручивает список из 100 000 простых элементов к середине и концу, в конечном viewport создано 16 контейнеров вместо 100 000, затем отрисованы 3 кадра. Unit-тест проверяет extent 2 400 000 и менее 50 контейнеров.

---

# Этап 7. Property system, стили и шаблоны

## 7.1. Жизненный цикл bindings

- [x] Определить поведение `cancel()`: отсоединение, сохранение последнего значения или возврат к local value.
- [x] Отменять bindings при dispose.
- [x] Предотвращать повторное уведомление при двустороннем обновлении.
- [x] Добавить binding diagnostics и понятные ошибки.

`cancel()` отписывает listener и сохраняет последнее синхронизированное значение в local value только если над binding нет явного local; повторный cancel безопасен. Замена binding отменяет прежний, а ошибка initial read нового источника не разрушает прежнюю привязку. `PropertyOwner.dispose()` отменяет все bindings и запрещает последующие `bind()`/`setValue()`, но оставляет чтение сохранённых значений доступным. `ItemsControl.dispose()` вызывает базовый dispose.

Two-way write подавляет reentrant source callback, затем выполняет одну синхронизацию и одно property notification; это работает и для `CallbackBinding`, который не уведомляет из write. `BindingSubscription` предоставляет `property`, `mode`, `isCancelled` и диагностический `toString()`. `BindingException` содержит property, operation (`Initial read`/`Read`/`Write`/subscription) и исходную cause.

## 7.2. Приоритеты значений

```text
default < inherited < style < binding < local < animation
```

Реализованы `DuiValueSource`, `getValueSource()`, отдельные `setInheritedValue()`/`setStyleValue()`/`setAnimationValue()` и соответствующие clear API. Nullable values различаются по наличию записи в слое. Уведомления публикуются только при изменении effective value; скрытые изменения источника не создают ложных property changes.

One-way local маскирует binding, но не отменяет его; `clearLocalValue()` восстанавливает актуальное binding value. Новый `bind()` удаляет прежний явный local, поэтому становится effective value. `cancel()` сохраняет последнее binding value как local только при отсутствии явного local поверх него. Two-way setter продолжает писать в источник даже под animation mask. Присваивание default без активного binding не создаёт явный local, поэтому constructor defaults контролов не блокируют style/inherited.

На этом шаге реализованы ручные value layers, а не универсальное automatic inherited-property propagation, styles/control templates или animation engine. Automatic propagation для `DataContext` добавлено отдельно в этапе 7.3.

## 7.3. DataContext

- [x] Наследование по logical tree.
- [x] Типобезопасные accessors.
- [x] Строковые paths, `dart:mirrors` и кодогенерация не используются.

`UIElement.dataContextProperty` использует общие value layers. При attach/detach и изменении effective context предка inherited layer рекурсивно обновляется у descendants; local, style, binding и animation продолжают действовать по общим приоритетам. `effectiveDataContext` сохранён как compatibility alias.

`dataContextAs<T>()` возвращает типизированное значение или null, `requireDataContext<T>()` возвращает значение либо выбрасывает `StateError`. `ItemsControl` задаёт item как local context корня шаблона, поэтому item перекрывает ancestor context и наследуется вложенными контролами.

## 7.4. Styles и templates

- [x] Named style или type style.
- [x] Setter-ы свойств.
- [x] Control template как persistent subtree factory.
- [x] Template bindings без потери идентичности после смены обычных свойств.

`Style<TOwner>` содержит типизированные `DuiSetter<TOwner, T>` и необязательное имя, применяется через `UIElement.styleProperty`. Setters записываются в style layer; local/binding/animation сохраняют приоритет. При замене style общие свойства обновляются без промежуточного clear, отсутствующие в новом style setters удаляются. Несовместимый owner type отклоняется.

`ControlTemplate<Button>` создаёт subtree один раз; `ContentPresenter` переносит текущий content в шаблон и следит за его заменой. `PropertyBinding` и `MappedBinding` связывают элементы шаблона с typed properties, включая `Button.isPressedProperty`, без строковых paths. Обычные property/content changes не вызывают factory повторно. При замене template старое subtree отсоединяется и его property bindings освобождаются; content сохраняет identity и возвращается под Button.

Шаблоны распространены на любой контрол: механика живёт в `TemplatedControl`, а `ContentControl` — её подкласс. Контрол без template-свойства шаблон не поддерживает (`template` всегда null, установка бросает `StateError`). Тип шаблона остаётся типизированным на конкретном контроле (`ControlTemplate<Button>`), база хранит `ControlTemplate<dynamic>?` и делает явный downcast в конкретном классе. Собственный контент виджета вынесен в `measureContentCore`/`arrangeContentCore`/`renderContentCore`/`hitTestContentCore`: при наличии шаблона база мержит, раскладывает, рисует и hit-тестит поддерево шаблона, а иначе — собственный контент. Focus ring рисует база (после контента, сверху), поэтому виджету не нужно рисовать его самому.

Критерий готовности выполнен: custom Border заменяет default Button background, pointer/keyboard activation и focus ring сохраняются. Шаблоны работают не только для Button: template задаётся любому контролу через его собственное template-свойство.

---

# Этап 8. Production readiness

## 8.1. Accessibility

- [x] Добавить semantics к дереву: role, name, value, state, bounds.
- [x] Windows UI Automation.
- [ ] macOS NSAccessibility.
- [ ] Linux AT-SPI.
- [x] Синхронизировать focus и selection.

Семантика backend-independent: `SemanticsTree` строится по требованию из дерева
контролов и снимает role, name, value, state, bounds и выделение текста. Фокус и
выделение читаются в момент построения, поэтому снимок всегда актуален. Элементы
без роли сворачиваются, контрол забирает имя label-контента.

Мост Windows UI Automation реализован в native-слое: окно отдаёт корень фрагмента
(`IRawElementProviderFragmentRoot`), а тот — дерево виджетов как элементы
`IRawElementProviderSimple` с типом управления, именем, значением, границами на
экране и состоянием. Остались macOS NSAccessibility и Linux AT-SPI: их нельзя
собрать и проверить на этой машине.

## 8.2. Нативная интеграция

- [ ] Clipboard с форматами.
  - [x] Универсальный MIME C ABI/Dart FFI: multi-format write, has/read, binary и empty payloads.
  - [x] Windows `text/html` через CF_HTML: UTF-8 offsets, fragment read/write и совместимость с остальными MIME-форматами.
  - [x] Высокоуровневый backend-independent formatted clipboard API через `Window`/`WindowHost`, `ClipboardHandler` и MIME-константы.
  - [x] Перечисление MIME-форматов, очистка clipboard и полный snapshot/restore в integration cleanup.
  - [ ] Ручная проверка HTML в сторонних приложениях.
- [ ] File dialogs.
  - [x] Standalone `FileDialog.showOpen([parent])` с настройками в свойствах title/initialDirectory/filters и `null` при отмене; compatibility API через `Window` сохранён.
  - [x] Windows `IFileOpenDialog` с родительским HWND либо без owner, UTF-8 path и явным освобождением native string.
  - [x] Headless contract-тесты и `example/native_open_file_dialog.dart`.
  - [x] Typed filters (`txt`/`*.txt` и `*` для всех файлов) и initial directory через Windows `SetFileTypes`/`SetFolder`.
  - [x] Пользователь подтвердил parent/ownerless и filters/initialDirectory на Windows.
  - [x] Linux `GtkFileDialog`: title, initial directory, filters и ownerless fallback; SDL X11/Wayland handles не преобразуются в `GtkWindow*`.
  - [x] macOS `NSOpenPanel`: title, initial directory, объединённые UTType filters, `*` для всех файлов и sheet для SDL `NSWindow`.
  - [ ] Собрать и вручную проверить Linux `GtkFileDialog` на X11/Wayland и macOS `NSOpenPanel`. Собственные самодельные диалоги не использовать.
- [ ] Native menus.
- [ ] Drag-and-drop.
- [ ] Notifications/tray по необходимости.

## 8.3. Packaging

- [x] Разбор runtime-зависимостей `dui_native`: PE import table на Windows, `ldd` на
  Linux, `otool -L` на macOS; зависимость считается private, если её не providing
  система — она обязана лежать рядом с библиотекой.
- [x] Windows: runtime DLL проверены на x64 (11 зависимостей, все системные).
  Архитектура arm64 ещё не собрана.
- [ ] macOS: dylib rpath задан (`@executable_path;@loader_path;@executable_path/../Frameworks`,
  install name `@rpath`), но universal binary и codesign/notarization не сделаны.
- [ ] Linux: rpath `$ORIGIN` задан, зависимости классифицируются по `ldd`, но сборка
  и проверка на реальном дистрибутиве не выполнялись.
- [x] Воспроизводимый release build: `tools/package.py` собирает бандл с
  `manifest.json` и sha256, архив с фиксированными timestamps даёт одинаковый
  sha256 при повторных прогонах.
- [x] Install-правила CMake: библиотека в `bin/` (Windows) или `lib/` (Unix),
  `icudtl.dat` рядом с библиотекой только на Windows (на Unix Skia вшивает данные
  ICU в библиотеку), относительный rpath.
- [ ] Проверка зависимостей на чистой машине — не выполнена, есть только
  автоматическая проверка состава импортов.

## 8.4. CI и тестирование

- [x] Dart analyze/test на Windows, macOS и Linux.
- [x] Native build на всех ОС (Windows, Linux, macOS arm64) — библиотеки
  выгружаются артефактами и собраны в опубликованный пакет.
- [x] Smoke window test (Windows и Linux; на macOS runner нет window server).
- [ ] Layout golden tests.
- [ ] Text golden tests при разных displayScale.
- [ ] Ввод и focus integration tests.
- [ ] Проверка native memory ownership.

---

## 6. Матрица ручного тестирования

Для каждого крупного этапа проверять:

| Область | Проверки |
|---|---|
| Windows | 100%, 125%, 150%, 200%, два монитора с разным scale |
| macOS | Retina/non-Retina, перемещение окна между дисплеями |
| Linux | X11 и Wayland, fractional scaling |
| Text | ASCII, кириллица, CJK, emoji, RTL |
| Input | mouse, wheel, keyboard, IME, clipboard |
| Lifecycle | remove focused element, close window, reopen, dispose |
| Performance | idle CPU, resize, long list, continuous text input |

---

## 7. Ближайшие задачи

Порядок ближайших рабочих сессий:

Пункты 1, 2, 4, 6, 7, 8, 9, 10, 11, 13 требуют macOS/Linux, сторонних приложений
или живого IME и выполняются пользователем; пункт 3 доступен для кодовой
работы на текущей машине.

1. **Ручная проверка этапа 8.2:** на macOS собрать Objective‑C++ backend и проверить `NSOpenPanel` в parent/ownerless-режимах, title/initialDirectory/filters и Unicode paths; на Linux аналогично проверить GTK 4.10+ на X11/Wayland (parent пока ownerless).
2. **Ручная проверка clipboard:** проверить вставку CF_HTML в Word, браузер и другие сторонние приложения.
3. **Этап 8.1, мосты:** модель семантики готова; мост Windows UI Automation сделан и проверен на этой машине (дерево, свойства, состояния, события фокуса). Остались macOS NSAccessibility и Linux AT-SPI — они требуют чужих машин. Открытый вопрос моста: действия (`SetFocus`, `Invoke` кнопки, запись значения поля) требуют обратного вызова из native в Dart.
4. **Ручная проверка ScrollViewer:** автоматическая часть закрыта полностью — `example/native_scroll_viewer.dart --smoke` проходит на Windows (wheel, drag ползунка, клик по треку, клавиатура, offsets, bounds, 3 кадра, scale 2.0); остаётся только визуальная проверка clipping и resize при разных display scales.
5. **Автоматизация ScrollViewer (закрыт 2026-11-26):** thumb dragging, клик по треку и клавиатурная прокрутка закрыты в native-тесте `test/native_scroll_viewer_test.dart` и в smoke-режиме примера — через публичные `dispatchPointerDown/Move/Up` и `dispatchKeyDown`.
6. **Незавершённая часть этапа 1.2 (закрыт 2026-11-27):** сборка и Paragraph smoke проверены на Linux (FontConfig/Freetype) и macOS (CoreText) — CI собирает библиотеку и запускает `dui_paragraph_smoke` на обоих runner'ах, шаг падал бы при ошибке. Живая проверка текста на этих платформах остаётся в пунктах 7 и 8.
7. **Ручная визуальная проверка:** открыть text gallery и TextBox на мониторах с разными масштабами, проверить clipping, selection и caret; отдельно посмотреть FPS-overlay в `--diagnostics` — после перевода на SkParagraph текст в нём стал shaped, baseline сдвинут на `y + font_size`, как и раньше.
8. **Ручная проверка этапа 2.4:** русский, китайский/японский ввод и emoji через реальные системные IME.
9. **Ручная проверка lifecycle:** dispose поддерева, повторное открытие окна после `close()`, поведение `Window.dispose()`.
10. **Этап 8.3, остаток — нужны другие машины:** macOS x64 (universal binary x64+arm64) и codesign/notarization, проверка dylib rpath в собранном приложении; Linux arm64 — сборка на arm64-машине и проверка rpath `$ORIGIN` вместе с зависимостями; Windows arm64 — сборка и проверка, что arm64-библиотека тоже ставится install-правилами. macOS arm64 и Linux x64 собраны через CI (2026-11-27) и лежат в пакете.
11. **Этап 8.3, чистая машина:** развернуть бандл из `build/release/` на машине без Skia, SDL и ICU. Сейчас состав импортов DLL проверяется автоматически, но запуск на «голой» системе не выполнялся.
12. **Потокобезопасность native-слоя (закрыт 2026-11-26):** SDL-вызовы сериализованы process-wide мьютексом, host в процессе может быть только один, `SDL_Quit()` не вызывается; поведение закреплено тремя native-тестами с двумя изолятами. Дальше по этой теме можно думать только про несколько host — для этого нужна переделка глобальной очереди событий SDL.
13. **Публикация пакета на pub.dev (закрыт 2026-11-27):** пакет `duix` 0.1.0 опубликован — https://pub.dev/packages/duix. Внутри: лицензия MIT с файлом `LICENSE`, поля `homepage`/`repository`, description и topics, сборки нативной библиотеки для Windows x64, macOS arm64 и Linux x64, разложенные в `build/dist/<платформа>-<архитектура>/`, и дистрибуция `python tools/package.py --dist` в `../duix-publish`. Осталось: macOS x64, Linux arm64 и Windows arm64, codesign/notarization для macOS и публикация следующих версий.

Кодовая работа: слой 0 закрыт, идёт слой 1 — простые элементы ввода.
`TextArea` (п. 20) закрыт 2026-11-28: многострочный ввод с переносом по
словам, вертикальной прокруткой и Shift+Enter. `CheckBox` (п. 12) закрыт
2026-11-28: флажок с двумя состояниями, галочкой и текстом метки. `RadioButton`
с группой radio (п. 13) закрыт 2026-11-28: кнопки группы, выбор в свойстве
группы, стрелки и focus scope. Дальше — `Switch` с анимацией (п. 14) и остальные
элементы слоя 1. Полный список виджетов и подсистем — в §7.1.
Focus ring флажков и radio-кнопок теперь рисуется вокруг самой метки, а не
вокруг всего контрола (2026-11-28).
Пункт 7 «Направление раскладки» закрыт полностью: часть A (направление в
дереве, зеркалирование раскладки, логическое выравнивание, right-to-left
текст в поле и прокрутка) и часть B (направление абзаца в native backend,
native ABI версии 6).

GPU backend по-прежнему не входит в ближайшие этапы.

### 7.1. Список виджетов к реализации

Сейчас в пакете: `Label`, `TextBox`, `TextArea`, `CheckBox`, `RadioButton`, `RadioGroup`, `Button`, `Border`, `ContentPresenter`,
`ContentControl`, `TemplatedControl`, `TemplatePart`, `ItemsControl`
(+ `VirtualizingStackPanel`), `ScrollBar`, `ScrollViewer`, `PopupLayer`,
`SelectionModel`, `Path`, `StackPanel`, `DockPanel`, `Grid`. Для настоящего
UI-кита этого мало, но порядок работ определяется не списком виджетов, а
подсистемами, без которых их нельзя построить.

**Слой 0 — подсистемы (блокируют всё остальное):**

1. **Графика.** Сейчас `DrawingContext` умеет только заливку прямоугольника,
   скруглённого прямоугольника, текст и clip. Нужны: контур и обводка
   (`drawPath`, `drawLine`), прозрачность и блендинг, тени, растровое
   изображение (`drawImage` — нужна native-декодировка PNG и загрузка
   текстуры в Skia). Без этого нет ни иконок, ни картинок, ни разделителей,
   ни рамок ползунков. **Часть A закрыта (2026-11-27):** обводка (`Paint.strokeWidth`)
   и прямые линии (`drawLine`), native ABI версии 3. **Часть B закрыта (2026-11-27):**
   растровое изображение (`drawImage`) с native-декодировкой PNG, native ABI версии 4.
   **Часть C закрыта (2026-11-28):** контур (`Path` и `drawPath`), прозрачность (`Paint.opacity`), режимы наложения (`Paint.blendMode`) и тень (`Paint.shadow`), native ABI версии 5.
2. **Popup-слой.** Всплывающие окна нужны ComboBox, меню, Tooltip и
   контекстному меню: отдельный слой поверх содержимого окна со своим
   layout, своим clip и перехватом кликов, плюс позиционирование у курсора
   или у элемента. **Готово (2026-11-27):** `PopupLayer` и `Window.overlay`.
   Всплывающее окно живёт внутри окна; настоящее окно ОС — отдельная работа.
3. **Шаблоны для любого контрола.** ~~Сейчас `ControlTemplate` поддержан только
   для `Button` (`ControlTemplate<Button>`).~~ **Готово (2026-11-27):** механика
   шаблона живёт в `TemplatedControl`, `ContentControl` её наследует, шаблон
   задаётся любому контролу через его собственное свойство.
   **Доделано (2026-11-28):** своё template-свойство есть не только у кнопки:
   `Label.templateProperty`, `Border.templateProperty` и `ScrollBar.templateProperty` —
   шаблон есть у каждого виджета, который рисует свой вид.
   **Доделано (2026-11-28):** `TextBox` и `ScrollViewer` тоже шаблонизированы, но по
   модели template parts: контрол отдаёт шаблону именованную часть (`text` у `TextBox`,
   `content`, `horizontalScrollBar` и `verticalScrollBar` у `ScrollViewer`), а шаблон её
   размещает. Содержимое контрола при этом не заменяется.
4. **Отдельный `ScrollBar`.** Полосы прокрутки встроены в `ScrollViewer`;
   как самостоятельный виджет он нужен и пользователям, и как основа для
   ComboBox и ListView. **Готово (2026-11-27):** `ScrollBar` — отдельный
   контрол, `ScrollViewer` построен на двух таких контролах.
5. **Модель выделения** (`SelectionModel`): выделенные элементы, множественное
   выделение, клавиатурная навигация, перенос фокуса и выделения. Это
   подсистема, а не виджет: на ней стоят ListView, TreeView, ComboBox.
   **Готово (2026-11-27):** `SelectionModel` с одиночным и множественным
   выделением, якорем диапазона и переходами клавиатурой.
6. **Мосты accessibility**: UI Automation, NSAccessibility, AT-SPI.
7. **Направление раскладки** (`FlowDirection`): left-to-right и right-to-left.
   **Часть A закрыта (2026-11-28):** направление — наследуемое свойство
   дерева (`UIElement.flowDirection`, значение по умолчанию —
   left-to-right), логическое выравнивание `start`/`end` (`HorizontalAlignment`)
   и зеркалирование раскладки: горизонтальная панель, док, текст поля,
   горизонтальная полоса прокрутки, вертикальная полоса вьюпорта и
   содержимое вьюпорта. Направление окна достаётся его содержимому, а
   собственное значение элемента важнее наследованного.
   **Часть B закрыта (2026-11-28):** направление абзаца в native backend —
   `DuiTextLayoutOptions.direction` и `SkParagraph::setTextDirection`, native
   ABI версии 6. Направление абзаца — базовое направление текста: оно
   решает, где стоят прогоны строки, а сами прогоны сохраняют свой
   порядок (иврит читается справа налево и в left-to-right абзаце).
8. **Команды и горячие клавиши** (`Command`): действие с `canExecute` и
   `execute`, чтобы кнопка, пункт меню и сочетание клавиш вели себя одинаково,
   и реестр сочетаний, который разбирается с конфликтами. Без этого меню
   приложения и диалоги придётся писать вручную.
9. **Стек отмены** (`UndoStack`): отмена и повтор правок (Ctrl+Z /
   Ctrl+Shift+Z). Нужен `TextBox`, `TextArea` и `RichText`: без него правку
   текста нельзя откатить.
10. **Форма указателя** (`Cursor`): I-beam в поле текста, стрелки изменения
    размера у `Splitter`, рука над ссылкой. Сейчас курсор всегда один и тот же,
    поэтому интерфейс не показывает, где нажатие имеет смысл.
11. **Drag & drop**: перенос данных между элементами. События есть в
    native-части (этап 8.2), модели источника, цели и формата переносимых
    данных в дереве ещё нет.

**Слой 1 — простые элементы ввода** (по одной сессии, native-работ нет):

12. `CheckBox` — два состояния, галочка. **Готово (2026-11-28):** состояние `isChecked` в системе свойств (двусторонняя связь с моделью), переключение кликом и пробелом, галочка и текст метки рядом, квадрат у начала контрола, выключенное состояние серым, своя роль в дереве семантики, focus ring
    вокруг квадрата с зазором в один пиксель.
13. `RadioButton` + группа radio — нужен контейнер с focus scope и общей
    группой. **Готово (2026-11-28):** `RadioGroup` — контейнер с focus
    scope, который владеет выбором группы: значение отмеченной кнопки
    живёт в свойстве группы и связывается с моделью; кнопки группы не
    отмечаются вместе, стрелки ходят по кнопкам и ведут за собой фокус,
    вложенная группа владеет своими кнопками, круглое focus ring вокруг
    кружка с зазором в один пиксель.
14. `Switch` / `ToggleButton` — переключатель с анимацией.
15. `Slider` — drag ползунка плюс клавиатура, тот же жест, что у полосы
    прокрутки.
16. `ProgressBar` — детерминированный и неопределённый.
17. `Separator` — разделитель, требует `drawLine`.
18. `Spacer` — пустое пространство в контейнере, почти бесплатно.
19. `Image` / `Icon` — требует слой 0 (растровая графика).
20. `TextArea` — многострочный ввод. **Готово (2026-11-28):** перенос по
    словам в ширину поля, вертикальная прокрутка с полосой, Shift+Enter,
    переход каретки между строками стрелками, Home и End по строке, IME по
    нескольким строкам. Общий каркас редактирования вынесен в `TextEditor`,
    его делят `TextBox` и `TextArea`.
21. `Hyperlink` — метка-ссылка: клик, hover и focus, подчёркивание.
22. `GroupBox` — контейнер с заголовком вокруг содержимого.

**Слой 2 — списки и выбор:**

23. `ListView` / `ListBox` — на базе `ItemsControl` с моделью выделения.
24. `ComboBox` — нужен слой 0 (popup-слой и отдельный `ScrollBar`).
25. `Menu`, `PopupMenu`, `ContextMenu` — нужен popup-слой.
26. `TreeView` — рекурсивный `ItemsControl` с раскрытием узлов.
27. `TabControl` с заголовками — переключение содержимого плюс свой layout
    заголовков.
28. `DataGrid` — таблица с колонками, сортировкой и выделением; самая тяжёлая
    часть слоя, делается последней.

**Слой 3 — компоновка:**

29. `WrapPanel` — перенос строк.
30. `Canvas` — абсолютное позиционирование.
31. `UniformGrid` — равные ячейки.
32. `Splitter` — перетаскиваемая граница между областями.
33. `Expander` — раскрываемая область.
34. `RenderTransform` — масштаб, поворот и перенос элемента. Требует поддержки
    трансформации в native-рисовании, а не только в layout.

**Слой 4 — текст и ввод данных:**

35. `RichText` с `TextSpan` — жирный, курсив, цвет, ссылки; требует расширения
    text layout (SkParagraph умеет spans, текущий API принимает строку).
36. `SelectableLabel` — метка с выделением и копированием.
37. `PasswordBox` — маскированный ввод.
38. `SearchField` — поле поиска с кнопкой очистки.
39. `NumberField` — числовой ввод со стрелками.
40. `DatePicker` и `TimePicker` — календарь и время во всплывающем окне.
41. `ColorPicker` — выбор цвета во всплывающем окне.
42. `SaveFileDialog` — открытие файла уже есть, сохранение — нет.
43. `AutoCompleteBox` — поле с подсказками: popup-окно со списком совпадений.

**Слой 5 — оформление и окна:**

44. `Tooltip` — всплывающая подсказка с задержкой.
45. `Card` / `Surface` — скруглённый контейнер с тенью.
46. `Badge`, `Chip` — мелкие метки.
47. `Dialog` и `MessageBox` — модальный диалог поверх окна: блокирует ввод под
    собой, возвращает результат, закрывается по Escape. Это не то же самое,
    что дочернее окно ОС: диалог живёт внутри окна.
48. `MenuBar` — меню приложения с горячими клавишами (п. 8).
49. `StatusBar` — строка состояния внизу окна.
50. `Toast` / `Notification` — короткое всплывающее уведомление в углу окна.
51. Дочерние окна приложения — пока в процессе одно окно.

**Рекомендуемый порядок:** слой 0 по частям (сначала шаблоны для любого
контрола и графика, потом popup-слой), затем слой 1 целиком — он даёт
работоспособный набор элементов ввода без новой подсистемы, — затем слой 2
(списки), затем 3 и 4. Слой 5 косметический. Самыми дорогими являются
`DataGrid` (слой 2) и `AutoCompleteBox` (слой 4), их стоит делать последними;
многострочный ввод (`TextArea`) полезнее остальных элементов слоя 1, потому
что без него не собрать ни одну форму.

**Что не нужно делать сейчас:** GPU backend, собственный CSS-движок вместо
`Style`/`DuiSetter`, анимации как отдельная подсистема (текущий
`value_precedence` уже различает слои local/binding/animation), собственный
диалект разметки вместо compositional API.

---

## 8. Протокол продолжения после перерыва

В начале новой сессии:

1. Прочитать `plan.md`.
2. Проверить последние записи журнала.
3. Выполнить:

   ```bash
   dart analyze
   dart test --exclude-tags clipboard
   python tools/bootstrap_native.py --check
   python tools/package.py --check-only
   ```

   `dart test --exclude-tags clipboard` — надёжный gate: четыре native
   clipboard-теста работают с реальным системным clipboard и падают, если буфер
   удерживает другой процесс. Полный `dart test` тоже проходит, когда clipboard
   свободен.

   `dart_test.yaml` задаёт `concurrency: 1`: native-тесты создают host, а host
   в процессе может быть только один (у SDL одна глобальная очередь событий),
   поэтому тестовые файлы идут последовательно. Флаг `--concurrency` в
   командной строке переопределяет это значение — вернуть параллельный прогон
   можно, но native-тесты тогда конфликтуют за host.

   `python tools/package.py --check-only` — проверка состава runtime-зависимостей
   библиотеки; она же ставит библиотеку через install-правила CMake.

4. Если менялся C++ или C ABI — пересобрать native:

   ```bash
   python tools/bootstrap_native.py
   ```

5. Выбрать только один пункт из «Ближайшие задачи».
6. Перед изменениями записать кратко, какой критерий готовности должен быть достигнут.

В конце сессии:

1. Запустить доступные проверки.
2. Отметить завершённые checkbox-ы.
3. Записать неработающее или непроверенное явно.
4. Обновить «Ближайшие задачи».
5. Добавить запись в журнал: что сделано, что проверено, что следующее.
6. Не оставлять следующий шаг только в переписке — перенести его в этот файл.

---

## 9. Журнал работ

### 2026-11-28 — слой 1: focus ring флажка и radio-кнопки

Сделано:

- Focus ring у `CheckBox` и `RadioButton` больше не перекрывает сам виджет:
  кольцо рисуется вокруг метки (квадрата с галочкой или кружка с точкой),
  между кольцом и меткой остаётся зазор в один пиксель, а текст метки в
  кольцо не входит.
- У `RadioButton` кольцо круглое (`FocusRingShape.capsule`), у `CheckBox` —
  прямоугольное. Форма, заданная шаблоном, по-прежнему имеет приоритет.
- В каркас добавлены общие хуки `Control.focusRingBounds` (где рисуется
  кольцо) и `Control.defaultFocusRingShape` (какой формой), поэтому любой
  контрол может указать своё кольцо; база рисует кольцо по этим хукам.
- Метка переключателей отодвинута от края контрола на 3 пикселя
  (`CheckableControl.focusRingPadding`), а высота контрола резервирует
  место под кольцо, поэтому галочка и точка видны целиком.

Проверено:

- `dart analyze` — без замечаний; `dart format` применён.
- `dart test --exclude-tags clipboard,native` — 375/375;
  `dart test --tags native --exclude-tags clipboard` — 55/55.
- Новые тесты в `test/checkbox_test.dart` и `test/radio_button_test.dart`:
  кольцо стоит вокруг метки и не закрывает её, у radio-кнопки кольцо
  круглое.
- Смоуки `example/native_checkbox.dart --smoke` и
  `example/native_radio_button.dart --smoke` проходят.
- Снимки экрана показывают флажок и radio-кнопку в фокусе: кольцо обводит
  знак, зазор виден, текст метки вне кольца.

Дальше: слой 1 — `Switch` с анимацией (п. 14) и остальные простые элементы
ввода. Публикация пакета 0.2.0 должна нести native ABI версии 6.

### 2026-11-28 — слой 1, пункт 13: переключатель и группа radio

Сделано:

- Добавлен `RadioButton` (`lib/src/radio_button.dart`): кнопка группы, которая
  рисует кружок с точкой и текст метки. Значение кнопки (`value`) говорит
  группе, какой выбор кнопка означает.
- Добавлена группа `RadioGroup` (`lib/src/radio_group.dart`): контейнер с focus
  scope, который владеет выбором. Значение отмеченной кнопки живёт в свойстве
  группы (`selectedValue`), поэтому его можно связать с модельом; отмеченная
  кнопка одна, клик по отмеченной кнопке не снимает отметку, а кнопки
  вложенной группы belongят этой группе.
- Группа — focus scope: клавиатура не уходит из неё, пока Tab не выйдет из
  группы. Стрелки ходят по кнопкам группы и ведут за собой фокус: в
  вертикальной группе это вертикальные стрелки, в горизонтальной —
  горизонтальные, а в дереве справа налево стороны меняются местами.
- Общее ядро флажков вынесено в `CheckableControl`
  (`lib/src/checkable.dart`): состояние, текст метки, кегль, цвет, клавиатура,
  рисование метки и семантика. `CheckBox` и `RadioButton` делят его и рисуют
  только свою метку — квадрат с галочкой и кружок с точкой.
- В дереве семантики появилась роль `radioButton` (и роль группы `group` у
  контейнера). Роль стоит в конце перечисления, потому что индекс роли
  пересекает native ABI: числа уже существующих ролей не изменились.
- Имена CheckBox приведены к общему ядру: `boxSize` стал `markSize`,
  `boxRect` — `markRect`, `textRect` — `labelRect`. Контрол не опубликован
  ещё, поэтому ломать API не пришлось.

Проверено:

- `dart analyze` — без замечаний; `dart format` применён.
- `dart test --exclude-tags clipboard,native` — 373/373;
  `dart test --tags native --exclude-tags clipboard` — 55/55.
- Новый `test/radio_button_test.dart` (18 тестов): кнопки группы, клик по
  кнопке и по отмеченной кнопке, значение группы следует за кнопкой и ведёт
  за собой кнопку, обработчик изменения, связь с моделью, стрелки в вертикальной
  и горизонтальной группе, пробел, focus scope группы, вложенная группа,
  семантика группы и кнопок, кнопка без группы, рисование кружка и точки,
  положение кружка в дереве справа налево.
- Смоук примера `example/native_radio_button.dart --smoke` проходит: клик
  отмечает кнопку и группа отдаёт значение в модель, стрелка переносит
  выбор.
- Снимок экрана примера показывает группу с отмеченной кнопкой и отключённую
  группу.

Дальше: слой 1 — `Switch` с анимацией (п. 14) и остальные простые элементы
ввода. Публикация пакета 0.2.0 должна нести native ABI версии 6.

### 2026-11-28 — слой 1, пункт 12: флажок (`CheckBox`)

Сделано:

- Добавлен `CheckBox` (`lib/src/checkbox.dart`): контрол с двумя состояниями.
  Состояние живёт в системе свойств (`isChecked`), поэтому двусторонняя
  связь держит контрол и модель равными; клик и пробел переключают его, а
  обработчик `onChanged` сообщает о новом состоянии.
- Контрол рисует квадрат с галочкой и текст метки рядом с ним. Квадрат стоит
  у начала контрола: левый край в left-to-right, правый в right-to-left, — и
  текст метки встаёт рядом с квадратом, а не с краем окна. Выключенный
  контрол рисуется серым.
- У контрола есть свой шаблон (`template`), поэтому вид флажка можно заменить
  целиком, как у остальных контролов с собственным видом.
- В дереве семантики появилась роль `checkBox` с состоянием `checked` и
  именем из текста метки. Роль стоит в конце перечисления, потому что индекс
  роли пересекает native ABI: числа уже существующих ролей не изменились.
- Раскладка текста кэшируется в одном месте: `CachedTextLayout` в
  `lib/src/text_layout.dart`. Раньше кэш раскладки жил внутри `Label` и
  внутри `TextEditor` — две копии; теперь `Label`, `TextBox`, `TextArea` и
  `CheckBox` делят один.

Проверено:

- `dart analyze` — без замечаний; `dart format` применён.
- `dart test --exclude-tags clipboard,native` — 355/355;
  `dart test --tags native --exclude-tags clipboard` — 55/55.
- Новый `test/checkbox_test.dart` (16 тестов): клик по квадрату и по тексту
  метки, повторный клик, пробел, Enter не переключает, обработчик изменения,
  двусторонняя связь с моделью, выключенный контрол, измерение, положение
  квадрата и текста в обеих направлениях раскладки, рисование галочки и
  серого выключенного состояния, семантика, состояние нажатия.
- Смоук примера `example/native_checkbox.dart --smoke` проходит: клик
  переключает флажок, пробел переключает его обратно, двусторонняя связь
  переносит состояние в модель.
- Снимок экрана примера показывает отмеченный и неотмеченные флажки рядом с
  текстом метки.

Дальше: слой 1 — `RadioButton` с группой radio (п. 13) и остальные простые
элементы ввода. Публикация пакета 0.2.0 должна нести native ABI версии 6.

### 2026-11-28 — слой 1, пункт 20: многострочный ввод (`TextArea`)

Сделано:

- Общий каркас редактирования вынесен в `TextEditor`
  (`lib/src/text_editor.dart`): буфер, команды, composition, мышь, IME, кэш
  раскладки, попадание мыши и отрисовка. `TextBox` и `TextArea` — два
  наследника, а не две копии логики: иначе правки в одном поле расходились бы
  с другим.
- `TextArea` (`lib/src/text_area.dart`): текст переносится по словам в ширину
  поля, у поля есть вертикальная полоса прокрутки (часть
  `verticalScrollBar`), Shift+Enter вставляет перевод строки, стрелки вверх и
  вниз ходят кареткой по строкам, Home и End работают по логической строке,
  колесо мыши прокручивает текст.
- Прокрутка следует за кареткой, пока пользователь не прокрутил текст сам;
  после ручной прокрутки движение каретки снова включает следование.
- Headless-раскладка (`lib/src/headless_text_layout.dart`) переносит текст по
  словам и считает геометрию каретки, выделения и попадания мыши по визуальным
  строкам, поэтому перенос проверяется без native-бэкенда.
- Ширина раскладки при измерении совпадает с шириной, которую показывает поле:
  отступы поля и толщина полосы вычитаются из доступной ширины. До этого текст
  при измерении раскладывался по полной ширине поля, а рисовался уже в более
  узкой, поэтому перенос отличался от отрисовки.
- Каретка native-бэкенда стоит в рамке строки, а не в рамке глифа: рамка
  каретки считается по метрикам строки (`getLineMetricsAt`), поэтому высота
  каретки равна высоте строки, а вертикальная прокрутка `TextArea` попадает на
  границу строки. ABI не менялся, библиотека пересобрана.

Проверено:

- `dart analyze` — без замечаний; `dart format` применён.
- `dart test --exclude-tags clipboard,native` — 339/339;
  `dart test --tags native --exclude-tags clipboard` — 55/55.
- Новый `test/text_area_test.dart` (15 тестов): перенос по словам, рост поля
  вниз, Shift+Enter, клик по строке, появление и скрытие полосы, стрелки между
  строками, Home и End, колесо, ограничение прокрутки, следование за кареткой и
  ручная прокрутка, отрисовка строк, части поля.
- Новый `test/native_text_area_test.dart`: native-абзац переносит текст по
  ширине, каретка переноса стоит на своей строке, поле в native-окне переносит
  текст, Shift+Enter и переходы между строками, полоса прокрутки и следование за
  кареткой.
- Смоук примера `example/native_textarea.dart --smoke` проходит; снимок экрана
  показывает перенос по словам и вертикальную полосу прокрутки.

Дальше: слой 1 — `CheckBox` и остальные простые элементы ввода. Публикация
пакета 0.2.0 должна нести native ABI версии 6.

### 2026-11-28 — слой 0, пункт 7: направление абзаца в native backend

Сделано:

- `DuiTextLayoutOptions` получил поле `direction`: 0 — left-to-right, 1 —
  right-to-left. Native ABI версии 6, библиотека пересобрана.
- Native ставит направление абзаца через `SkParagraph::setTextDirection`, и
  направление абзаца стало базовым направлением текста: би-алгоритм
  unicode решает, где стоят прогоны строки, а сами прогоны сохраняют
  свой порядок.
- Dart передаёт направление раскладки в native: направление элемента
  доходит до абзаца, поэтому текст поля и текст метки раскладываются в
  том же направлении, в котором стоит дерево.
- Каретка, выделение и попадание мыши считаются по координатам абзаца, а
  геометрия поля (привязка текста к правому краю, смещение прокрутки от
  начала строки) осталась частью A — теперь она совпадает с настоящим
  порядком символов.
- Попадание мыши между двумя каретками surrogate pair выбирает ближайшую
  каретку, а не половину между ними: в right-to-left тексте каретки пары
  стоят в обратном порядке.
- Инструменты проверки пакета (`tool/verify_native.dart`,
  `tool/verify_published.dart`) ждут ABI версии 6.

Проверено:

- `dart analyze` — без замечаний; `dart format` применён.
- `dart test --exclude-tags clipboard,native` — 324/324;
  `dart test --tags native --exclude-tags clipboard` — 51/51.
- Новый `test/native_text_direction_test.dart`: в right-to-left абзаце
  первый прогон строки стоит справа, каретка первого символа иврита — на
  правом крае текста, клик по правому краю поля ставит каретку в начало
  строки, а в left-to-right поле клик по левому краю попадает в последний
  символ.
- `test/native_contract_test.dart` проверяет размер структуры опций
  раскладки в Dart (72 байта) — он совпадает с C-структурой.
- Смоуки примеров проходят: `native_smoke`, `native_textbox`,
  `native_graphics`, `native_aqua_button`, `native_template_parts`,
  `native_flow_direction`.
- Снимок экрана примера `example/native_flow_direction.dart` показывает
  иврит в поле: текст стоит у правого края и читается справа налево.

Дальше: слой 1 — простые элементы ввода, начиная с `TextArea` и
`CheckBox`. Публикация пакета 0.2.0 должна нести native ABI версии 6.

### 2026-11-28 — слой 0: направление раскладки (часть A)

Сделано:

- Добавлено направление раскладки: `FlowDirection` в `geometry.dart` и наследуемое свойство `UIElement.flowDirection`. Значение по умолчанию — left-to-right; направление наследуется по дереву, собственное значение элемента важнее наследованного, а направление окна достаётся его содержимому и overlay.
- `PropertyOwner.setLocalValue` пишет локальное значение даже когда оно равно значению по умолчанию: без этого потомок right-to-left дерева не мог оставить себе left-to-right.
- Логическое выравнивание: в `HorizontalAlignment` добавлены `start` и `end`, они разрешаются по направлению элемента. Абсолютные `left` и `right` не зеркалятся.
- Зеркалирование раскладки: горизонтальная `StackPanel` ставит первого ребёнка у правого края, `DockPanel` меняет местами `Dock.left` и `Dock.right`.
- Текст: `TextLayoutOptions` получил поле направления, `resolveTextAlignment` переводит логическое выравнивание в абсолютное для native (0 — left, 1 — center, 2 — right), поэтому ABI не менялся. Headless-раскладка теперь тоже уважает выравнивание и рисует текст по направлению.
- `TextBox` в right-to-left: текст начинается у правого края поля, горизонтальное смещение считается от начала строки, каретка остаётся видимой, попадание мыши и область ввода считаются от нового края.
- `ScrollBar` и `ScrollViewer` в right-to-left: горизонтальная полоса начинается у правого края, бегунок и клик по треку зеркалятся, вертикальная полоса вьюпорта стоит слева, содержимое начинается у правого края, колесо мыши и стрелки двигают содержимое физически.

Проверено:

- `dart analyze` — без замечаний; `dart format` применён.
- `dart test --exclude-tags clipboard,native` — 323/323; `dart test --tags native --exclude-tags clipboard` — 47/47.
- `test/flow_direction_test.dart` — 21 тест: наследование, локальное переопределение, отсоединение, окно, логическое и абсолютное выравнивание, зеркалирование панели и дока, разрешение выравнивания текста, ключ кэша опций и right-to-left поведение поля, полосы прокрутки и вьюпорта.
- Пример `example/native_flow_direction.dart` и его smoke-режим: окно с направлением right-to-left, smoke проверяет зеркалирование панели, положение вертикальной полосы и начало содержимого вьюпорта.
- Снимок экрана примера подтверждает результат: заголовок и текст поля у правого края, кнопки идут справа налево, вертикальная полоса слева, горизонтальная полоса начинается у правого края.
- Найдена и исправлена ошибка native-пути: раскладка без ограничения ширины не должна получать выравнивание, иначе абзац уезжает за правый край и каретка не находится. Теперь при бесконечной ширине выравнивание не передаётся в native, как и в headless-раскладке.

Дальше: часть B пункта 7 — направление абзаца в native backend (`SkParagraph::setTextDirection`). Это меняет структуру `DuiTextLayoutOptions`, то есть native ABI становится версии 6, и библиотеку нужно пересобрать; следующая публикация пакета (0.2.0) и так должна нести ABI 5 или 6.

### 2026-11-28 — список необходимых виджетов и подсистем

Сделано:

- Дополнен §7.1 «Список виджетов к реализации». В слое 0 добавлены
  подсистемы, которых нет в коде и без которых не собрать слои 1–5:
  направление раскладки (left-to-right и right-to-left), команды и горячие
  клавиши, стек отмены правок, форма указателя и drag & drop.
- В слое 1 добавлены `TextArea` (многострочный ввод — сейчас `TextBox`
  однострочный), `Hyperlink` и `GroupBox`; в слое 2 — `DataGrid`; в слое 3 —
  `RenderTransform`; в слое 4 — `AutoCompleteBox`; в слое 5 — `Dialog` и
  `MessageBox`, `MenuBar`, `StatusBar`, `Toast`/`Notification`.
- Пункты перенумерованы (7–51), слои и рекомендуемый порядок работ сохранены.
  У пункта про мосты accessibility убрана ссылка на прежний номер.
- В §7 «Ближайшие задачи» добавлена строка о следующей кодовой сессии.

Проверено:

- Список сверен с кодом: многострочного ввода, отмены правок, направления
  раскладки, формы указателя, команд и горячих клавиш, диалогов, меню
  приложения, таблицы, тостов и трансформаций в пакете нет — поиск по
  `lib/` и `native/src/` даёт только pointer capture, файловый диалог и
  модификатор `primaryShortcutPressed`.
- Новых пунктов нет среди уже реализованных виджетов: список «Сейчас в
  пакете» не изменился.

Дальше: следующая кодовая сессия — слой 1, начиная с `TextArea` и
`CheckBox`.

### 2026-11-28 — слой 0: шаблоны, которые не заменяют содержимое

Сделано:

- Добавлен `TemplatePart` (`lib/src/template_part.dart`): именованная часть
  контрола, которую размещает шаблон. Часть меряется, расставляется и рисуется
  через владельца (`measurePart`, `arrangePart`, `renderPart`, `hitTestPart`),
  поэтому содержимое рисует контрол, а шаблон решает только, где часть лежит.
- `TemplatedControl` получил реестр частей (`registerPart`, `part`,
  `templateParts`) и правило: часть, которую шаблон не разместил, остаётся у
  контрола — он сам её меряет, расставляет в своей области и рисует. Части
  переживают замену шаблона: перед освобождением старого дерева они
  отсоединяются от него, а без шаблона возвращаются контролу.
- `TextBox` стал `TemplatedControl` с частью `text`: текст, выделение,
  composition и caret рисует контрол, а рамку поля рисует шаблон. Геометрия
  текста (content rect, hit test, IME area) считается от границ части, а не от
  границ контрола.
- `ScrollViewer` получил своё template-свойство и три части: `content`
  (обрезанное и смещённое содержимое), `horizontalScrollBar` и
  `verticalScrollBar`. Вьюпорт в шаблоне — это границы части с содержимым,
  полосы следуют за смещением, а видимость полос считается по вьюпорту.
- Инвалидация контрола распространяется на его части: содержимое изменилось —
  части перемеряются и перерасставляются, иначе виджет видел бы устаревший
  размер содержимого.
- Смещение прокрутки обрезается по фактическому вьюпорту, а не по оценке
  фазы измерения: шаблон может мерять часть со свободным пространством, и
  оценка вьюпорта тогда неверна.

Проверено:

- `dart analyze` — No issues found; `dart format` — 0 изменений.
- `dart test --exclude-tags clipboard,native` — 302/302; `dart test --tags native
  --exclude-tags clipboard` — 47/47.
- `test/template_parts_test.dart` (12 тестов): часть с текстом у `TextBox`,
  текст в шаблоне и без части в шаблоне, переживание замены шаблона, возврат
  текста при снятии шаблона, освобождение части вместе с контролом, части
  `ScrollViewer`, обрезка содержимого по месту части и полосы, следующие за
  смещением.
- Смоук и снимок экрана примера `example/native_template_parts.dart`: поле в
  рамке из шаблона с текстом внутри и прокручиваемая область с полосами,
  размещёнными шаблоном.

Ограничение: части размещает только шаблон — если шаблон их не упоминает,
контрол рисует их сам, в своей области. Части нельзя пока сделать
необязательными поимённо (часть всегда рисуется, если шаблон её не скрыл).

Дальше: публикация 0.2.0 с native ABI 5.

### 2026-11-28 — слой 0, пункт 3: шаблоны для всего набора виджетов

Сделано:

- `Label` стал `TemplatedControl`: у него есть `Label.templateProperty`
  (`ControlTemplate<Label>?`), своя отрисовка переехала в
  `measureContentCore`/`renderContentCore`, а шаблон заменяет текст метки.
- `Border` и `ScrollBar` получили свои типизированные template-свойства
  (`Border.templateProperty`, `ScrollBar.templateProperty`): рамка и полоса
  прокрутки теперь темизируются.
- Исправлен перенос строки на границе бокса: раскладка Skia получает на один
  физический пиксель больше места, поэтому текст ровно по ширине бокса не
  переносит последнее слово. Раньше кнопка показывала «Продолжит», а бейдж —
  «Badg».

Проверено:

- `dart analyze` — No issues found; `dart format` — 0 изменений.
- `dart test --exclude-tags clipboard,native` — 290/290; `dart test --tags native
  --exclude-tags clipboard` — 47/47.
- `test/templated_control_test.dart` (12 тестов): шаблон у метки, у рамки и у
  полосы; шаблон заменяет текст метки; текст возвращается при снятии шаблона;
  рамка показывает содержимое через `ContentPresenter`; полоса рисуется по
  шаблону.
- `test/native_text_matrix_test.dart`: текст ровно по ширине бокса остаётся на
  одной строке.
- Снимок экрана примера `native_aqua_button`: бейдж с шаблоном и карточка с
  шаблоном.

Ограничение закрыто следующей записью журнала: для `TextBox` и `ScrollViewer` сделана
модель template parts, их шаблоны не заменяют содержимое.

Дальше: слой 0 закрыт; публикация 0.2.0 с native ABI 5.

### 2026-11-28 — слой 0, пункт 1c: контуры, прозрачность, наложение и тени

Сделано:

- Добавлен `Path` (`lib/src/path.dart`): список команд контура — `moveTo`, `lineTo`,
  `quadTo`, `cubicTo`, `close`, плюс `addRect` и `addRoundedRect`; у пути есть
  границы, которые учитывают и control-точки кривых.
- `DrawingContext` получил `drawPath(path, paint)`, `RecordingDrawingContext`
  записывает `DrawPathCommand`.
- `Paint` (`lib/src/geometry.dart`) получил прозрачность (`opacity`), режим
  наложения (`blendMode`: srcOver, screen, multiply, plus, difference, lighten,
  darken, overlay) и тень (`shadow`: цвет, размытие, смещение).
- Native C ABI переведён на версию 5: paint передаётся структурой `DuiPaint`
  (цвет, обводка, прозрачность, режим наложения, тень), путь — списком команд
  `DuiPathCommand`; добавлена `dui_draw_path`, а `dui_draw_rect`,
  `dui_draw_rounded_rect`, `dui_draw_line` и `dui_draw_image` принимают paint.
- В Skia paint собирается из структуры: прозрачность умножается на альфу цвета,
  режим наложения — `SkBlendMode`, тень — силуэт фигуры с `SkMaskFilter`
  (размытие) и смещением; тень всегда заливается, даже если фигура обведена.
- Dart FFI: `DuiPaintStruct`, `DuiPathCommandStruct`, новые typedef'ы и
  `NativeBindings.drawPath`; проверка ABI поднята до 5.

Проверено:

- `dart analyze` — No issues found; `dart format` — 0 изменений.
- `dart test --exclude-tags clipboard,native` — 285/285; `dart test --tags native
  --exclude-tags clipboard` — 46/46 (добавлено 2 теста графики).
- Новый `test/path_test.dart` (8 тестов): команды пути, пустые пути, прямоугольник,
  скруглённый прямоугольник с обрезкой радиусов, границы с control-точками,
  свойства paint и запись пути в headless-рендерере.
- Новый `test/native_graphics_test.dart` (2 теста): путь с тенью и наложением
  рисуется в кадр, пустой путь не ломает кадр.
- `example/native_graphics.dart` — окно с кривой, карточкой с тенью и двумя
  прямоугольниками; снимок экрана подтвердил кривую, мягкую тень и оливковую
  зону наложения (multiply) с прозрачностью 0.8.

Дальше: слой 0 закрыт. Следующий этап по плану — публикация 0.2.0 с новым native
ABI (5) и пересборка бинарников для pub.dev.

### 2026-11-28 — слой 0, пункт 6b: мост Windows UI Automation

Сделано:

- Мост к UI Automation живёт в native-слое (`native/src/uia_windows.h`,
  `native/src/uia_windows.cpp`): окно перехватывает `WM_GETOBJECT` и отдаёт корень
  фрагмента (`IRawElementProviderFragmentRoot`), а тот — дерево виджетов как элементы
  `IRawElementProviderSimple`.
- Снимок дерева неизменяем и разделяется через `shared_ptr` под мьютексом: клиенты
  UI Automation зовут поставщика из своих потоков. Провайдеры узлов кэшируются в
  мосте, поэтому один и тот же элемент всегда отдаёт тот же объект.
- Свойства элемента: тип управления, имя, значение, границы на экране, `IsEnabled`,
  `IsKeyboardFocusable`, `HasKeyboardFocus`, `IsControlElement`, `IsContentElement`,
  `IsOffscreen`, `FrameworkId` (`Dui`). Текстовое поле отдаёт паттерн `Value`.
- События: перенос фокуса (`UiaRaiseAutomationEvent`) и изменение имени или значения
  (`UiaRaiseAutomationPropertyChangedEvent`) — мост сравнивает снимки соседних кадров.
- Границы считаются от начала клиентской области окна (`ClientToScreen`), поэтому
  они совпадают с координатами контролов на экране.
- Пример `example/native_accessibility.dart` (окно с `Label`, `Button` и `TextBox`) и
  скрипт `tool/verify_uia.ps1`, который читает дерево окна через UI Automation.

Проверено:

- `dart analyze` — No issues found; `dart format` — 0 изменений.
- `dart test --exclude-tags clipboard,native` и `dart test --tags native --exclude-tags
  clipboard` — без падений.
- `dart run example/native_smoke.dart --smoke` и `dart run
  example/native_textbox.dart --smoke` проходят после пересборки библиотеки.
- UIA-клиент (PowerShell + `UIAutomationClient`) видит дерево: `Window "DUI
  accessibility"` → `Custom` → `Text "Accessibility bridge"`, `Button "Press me"`,
  `Edit ""`; имена, типы управления и границы верны, у всех элементов `IsEnabled`,
  `IsControlElement` и `IsContentElement` — TRUE, фокус отмечен у кнопки.

Найденная ошибка: булевы свойства заполнялись значением `TRUE` (1), тогда как VARIANT
ждёт `VARIANT_TRUE` (-1), поэтому все состояния приходили как `False`.

Ограничение шага: мост отдаёт дерево и состояния, но не выполняет действия — `SetFocus`,
`Invoke` кнопки и запись значения поля требуют обратного вызова из native в Dart.

Дальше: слой 0, пункт 1c — `drawPath`, прозрачность и блендинг, тени.

### 2026-11-27 — слой 0, пункт 6 (мост дерева семантики)

Сделано:

- Дерево семантики окна пересекает C ABI: `dui_window_set_accessibility_tree` принимает плоский список узлов (`DuiAccessibleNode`: роль, индекс родителя, флаги состояния, границы, имя, значение), строки копируются. Ответные функции: `dui_window_get_accessibility_node_count`, `..._node_info`, `..._node_name`, `..._node_value`.
- Dart-слой публикует дерево после каждого кадра (`lib/src/native/accessibility.dart`): узлы идут в порядке обхода, у каждого — индекс родителя, состояние пакуется в битовые флаги.
- `SdlSkiaHost.nativeHandle(window)` открывает native-состояние окна (нужно для проверки моста и для будущих мостов платформ).

Проверено:

- `dart analyze` — No issues found; `dart format` — 0 изменений.
- `dart test --exclude-tags clipboard,native` — 277/277; `dart test --tags native --exclude-tags clipboard` — 44/44 (было 41, добавлено 3 теста моста).
- `test/native_accessibility_test.dart`: кнопка публикуется одним узлом с ролью `button`, именем и границами; дерево из нескольких узлов хранит индексы родителей; флаги состояния следуют за контролами.

Дальше: сам мост к assistive technology — Windows UI Automation (поставщик `IRawElementProvider` поверх хранимого дерева); macOS NSAccessibility и Linux AT-SPI требуют чужих машин для проверки.

### 2026-11-27 — слой 0, пункт 2: popup-слой

Сделано:

- Добавлен `PopupLayer` (`lib/src/popup.dart`): слой, который лежит поверх содержимого окна, со своим layout и своим clip. Он мержит и раскладывает содержимое всплывающего окна, рисует его последним и перехватывает клики вне окна — содержимое под окном не реагирует на них.
- Размещение окна: `PopupPlacement` (`below`, `above`, `right`, `left`, `atPointer`, `atOwner`). Если окно не помещается снизу, оно открывается сверху.
- Окно забирает фокус на себя, `Escape` его закрывает, а фокус возвращается контролу, который окно открыл.
- `Window` получил `overlay`: слой смонтирован вместе с окном, разложен на весь размер окна, отрисован после содержимого, а hit-test окна проверяет слой раньше содержимого. Закрытый слой невидим и не участвует в hit-test.

Проверено:

- `dart analyze` — No issues found; `dart format` — 0 изменений.
- `dart test --exclude-tags clipboard,native` — 277/277; `dart test --tags native --exclude-tags clipboard` — 41/41.
- Новый `test/popup_test.dart` (8 тестов): размещение, переворот при нехватке места снизу, порядок отрисовки, перехват клика вне окна, клик внутри окна, Escape и возврат фокуса, закрытый слой не забирает клики.
- `example/native_smoke.dart --smoke` открывает popup в настоящем окне.

Ограничение шага: всплывающее окно живёт внутри окна, поэтому оно не может выходить за его границы. Настоящее окно ОС (отдельный popup SDL) — отдельная работа, если она понадобится.

Дальше: слой 0, пункт 6 — мосты accessibility, начнём с Windows UI Automation.

### 2026-11-27 — слой 0, пункт 5: модель выделения `SelectionModel`

Сделано:

- Добавлена `SelectionModel` (`lib/src/selection_model.dart`): одиночное и множественное выделение (`SelectionMode.single` / `SelectionMode.multiple`), выбранные индексы, текущий элемент (`selectedIndex`), якорь диапазона (`anchorIndex`), счётчик элементов (`count`).
- Операции: `select`, `toggle`, `extendTo` (диапазон от якоря), `selectAll`, `clear`, `moveSelection(delta, {extend})`, `selectFirst`, `selectLast`. Индекс вне списка отклоняется через `RangeError`.
- Модель сообщает об изменениях: `addSelectionChangedListener` получает модель, добавленные и удалённые индексы.
- Когда элементы исчезают (`count` уменьшается), выделение обрезается, а текущий элемент переходит на последний оставшийся выбранным.

Проверено:

- `dart analyze` — No issues found; `dart format` — 0 изменений.
- `dart test --exclude-tags clipboard,native` — 269/269; `dart test --tags native --exclude-tags clipboard` — 41/41.
- Новый `test/selection_model_test.dart` (9 тестов): одиночное и множественное выделение, уведомления, диапазон от якоря, переходы клавиатурой, расширенный переход, обрезка при уменьшении списка, выделение всего списка и очистка, отказ для индекса вне списка.

Дальше: слой 0, пункт 2 — popup-слой (всплывающие окна).

### 2026-11-27 — слой 0, пункт 4: отдельный виджет `ScrollBar`

Сделано:

- Добавлен виджет `ScrollBar` (`lib/src/scroll_bar.dart`): свой контрол с полосой и бегунком. Свойства: `orientation`, `minimum`, `maximum`, `value`, `viewportSize`, `thickness`; производные: `isScrollable`, `trackLength`, `extent`, `thumbRect`. Бегунок перетаскивается указателем, клик по полосе листает на одну страницу, значение всегда внутри диапазона. Виджет наследует `TemplatedControl`, поэтому его вид можно заменить шаблоном.
- `ScrollBarVisibility` переехал в `lib/src/scroll_bar.dart` (экспорт из `package:duix/dui.dart` не изменился).
- `ScrollViewer` переписан на двух дочерних `ScrollBar`: полосы больше не рисуются вручную, а `horizontalScrollBar` и `verticalScrollBar` доступны как публичные свойства. Просмотрщик синхронизирует с полосами диапазон, значение и размер видимой области и слушает их значения, чтобы прокрутка следовала за перетаскиванием.
- Поведение изменилось намеренно: захват указателя при перетаскивании бегунка принадлежит полосе, а не просмотрщику; hit-test полосы возвращает полосу; клик по полосе не забирает фокус (полоса не фокусируема, клавиатура принадлежит прокручиваемой области).

Проверено:

- `dart analyze` — No issues found; `dart format` — 0 изменений.
- `dart test --exclude-tags clipboard,native` — 260/260; `dart test --tags native --exclude-tags clipboard` — 41/41.
- Новый `test/scroll_bar_test.dart` (7 тестов): пропорции бегунка, полоса без диапазона, перетаскивание, клик по полосе, ограничение значения, отрисовка полосы и бегунка, горизонтальная ориентация.
- `test/scroll_viewer_test.dart` и `test/native_scroll_viewer_test.dart` обновлены под новое владение указателем и hit-test; размеры бегунков и значения прокрутки не изменились.

Дальше: слой 0, пункт 5 — модель выделения `SelectionModel`.

### 2026-11-27 — слой 0, пункт 1 (часть B): растровое изображение

Сделано:

- Добавлен backend-независимый API картинок (`lib/src/image.dart`): `DrawableImage` (размер, `isDisposed`, `dispose`) и `ImageFactory` (`decodePng`). Образец взят с текстовой раскладки: ресурсы принадлежат реализации, публичный слой не знает про native.
- `DrawingContext` получил `drawImage(image, rect, paint)`; `RecordingDrawingContext` записывает `DrawImageCommand`, поэтому картинку видно в тестах без backend'а.
- Native backend (`lib/src/native/native_image.dart`): `NativeImageFactory` декодирует PNG через Skia, `NativeImage` держит native handle и освобождает его в `dispose`. `SdlSkiaHost.imageFactory` отдаёт фабрику.
- Native C ABI переведён на версию 4: `dui_image_create_from_png`, `dui_image_destroy`, `dui_image_get_size` (со структурой `DuiImageSize`) и `dui_draw_image`. PNG-сигнатура проверяется при декодировании, пиксели читаются через `SkImages::DeferredFromEncodedData`, картинка рисуется через `SkCanvas::drawImageRect` с линейной фильтрацией; нулевая ширина или высота означает натуральный размер.
- Dart FFI: `DuiImageOpaque`, `DuiImageSizeStruct`, typedef'ы и обёртки `imageCreateFromPng`/`imageGetSize`/`imageDestroy`/`drawImage` в `NativeBindings`; проверка ABI поднята до 4.

Проверено:

- `dart analyze` — No issues found; `dart format` — 0 изменений.
- `dart test --exclude-tags clipboard,native` — 253/253; `dart test --tags native --exclude-tags clipboard` — 41/41 (было 38, добавлено 3 теста картинок).
- `test/native_image_test.dart`: PNG 4×3 декодируется с правильным размером, мусорные байты отклоняются, картинка рисуется в кадр и показывается окном.
- `example/native_smoke.dart --smoke` проходит.

Замечание: виджет `Image`/`Icon` не входил в этот шаг — он относится к слою 1 и строится на готовой подсистеме.

Дальше: слой 0, пункт 4 — отдельный виджет `ScrollBar`; затем пункт 5 (`SelectionModel`).

### 2026-11-27 — слой 0, пункт 1 (часть A): обводка и линии

Сделано:

- `Paint` (`lib/src/geometry.dart`) получил `strokeWidth`: ноль — заливка фигуры, положительное значение — обводка контура. Добавлен `Paint.isStroke`.
- `DrawingContext` (`lib/src/drawing.dart`) получил `drawLine(from, to, paint)`. `drawRect` и `drawRoundedRect` берут ширину обводки из paint, отдельный параметр `strokeWidth` у `drawRoundedRect` убран.
- Capsule focus ring рисуется обводкой скруглённого прямоугольника, прямоугольный — четырьмя залитыми полосами (как раньше).
- `RecordingDrawingContext` записывает линии (`DrawLineCommand`), а `DrawRoundedRectCommand.strokeWidth` читается из paint.
- Native C ABI переведён на версию 3: `dui_draw_rect` принимает ширину обводки, добавлена `dui_draw_line(x1, y1, x2, y2, rgba, stroke_width)`. В Skia обводка включается через `SkPaint::kStroke_Style`, линия нулевой ширины рисуется hairline-ом.
- Dart FFI: новые typedef'ы `_DrawLineNative`/`_DrawLineDart`, `dui_draw_rect` получил седьмой аргумент, проверка ABI поднята до 3. Поправлены `tool/verify_native.dart` и `tool/verify_published.dart`.
- В примере `native_smoke` добавлены `_Rule` (линия) и `_Outline` (обводка скруглённого прямоугольника) — примитивы проверяются через настоящий native-путь.

Проверено:

- `dart analyze` — No issues found; `dart format --output=none --set-exit-if-changed lib bin example test tool` — 0 изменений.
- `dart test --exclude-tags clipboard,native` — 252/252; `dart test --tags native --exclude-tags clipboard` — 38/38 (native-библиотека пересобрана: `cmake --build native/build --config Release`).
- `example/native_smoke.dart --smoke` — линия и обводка рисуются в настоящем окне.

Замечание: изменение ABI ломает совместимость со старой native-библиотекой: Dart отказывается открывать библиотеку с другой версией ABI, поэтому библиотеку из пакета нужно пересобрать и перевыложить вместе с новой версией пакета.

Дальше: пункт 1 слоя 0 — растровое изображение (`drawImage`) с native-декодировкой PNG; после него — контуры (`drawPath`), прозрачность и тени.

### 2026-11-27 — слой 0, пункт 3: шаблоны для любого контрола

Сделано:

- Добавлен `TemplatedControl` (`lib/src/templated_control.dart`): базовый класс с механикой шаблона. Он хранит template-свойство (`DuiProperty<dynamic, ControlTemplate<dynamic>?>?`), создаёт persistent-поддерево при установке шаблона, освобождает старое при замене, отдаёт `templateRoot` и `hasTemplate`, поддерживает хук `onTemplateReplacing` и рисует focus ring сам — после контента, сверху, формой из `template?.focusRingShape`.
- `ContentControl` теперь наследует `TemplatedControl` и умеет отдавать и забирать свой контент: при замене шаблона контрол забирает контент обратно через `onTemplateReplacing`, чтобы новый шаблон показал его снова через `ContentPresenter`.
- Собственный контент виджета вынесен из `measureCore`/`arrangeCore`/`renderCore`/`hitTestCore` в `measureContentCore`/`arrangeContentCore`/`renderContentCore`/`hitTestContentCore`. База ветвится сама: при наличии шаблона она мержит, раскладывает, рисует и hit-тестит поддерево шаблона, иначе — собственный контент. Точки расширения `UIElement` для не-шаблонных виджетов (`Label`, `TextBox`, `Grid`, `StackPanel`, `DockPanel`, `ItemsControl`) не изменились.
- `Button` больше не держит собственную механику шаблона: она целиком в базе. `Button.templateProperty` (`ControlTemplate<Button>`) остался публичным и типизированным, getter `template` сужен до `ControlTemplate<Button>?` через явный downcast базового значения.
- `Border`, `ScrollViewer` и `_AquaSurface` из примера переведены на `*ContentCore`-хуки; `ScrollViewer` больше не рисует focus ring сам — это делает база.
- Экспорты: `lib/src/templated_control.dart` добавлен в `package:duix/dui.dart`.
- Добавлен `test/templated_control_test.dart` (7 тестов): шаблон на не-Button контроле, шаблон владеет measure/arrange, контент возвращается при снятии шаблона, замена шаблона освобождает старое поддерево и сохраняет контент, поддерево освобождается вместе с контролом, база рисует focus ring сама, контрол без template-свойства не поддерживает шаблоны.

Проверено:

- `dart analyze` — No issues found; `dart format --output=none --set-exit-if-changed lib bin example test tool` — 0 изменений.
- `dart test --exclude-tags clipboard,native` — 251/251 (было 244, добавлено 7).
- `dart test --tags native --exclude-tags clipboard` — 38/38.
- Смоуки: `example/native_aqua_button.dart --smoke` (шаблон, capsule focus ring, hover/pressed), `example/native_smoke.dart --smoke`, `example/native_textbox.dart --smoke`, `example/counter.dart` — проходят.

Замечание: порядок отрисовки focus ring изменился — теперь кольцо рисуется поверх контента, а не под ним. Внешний вид не-шаблонного `Button` и `ScrollViewer` не изменился, кроме порядка слоёв.

Ограничение шага: шаблон по-прежнему подписывается на отдельные typed-свойства, а не на `WidgetState` целиком — для этого нужны derived-свойства в системе свойств (отдельный шаг). Контрол без собственного template-свойства шаблон не поддерживает: `template` всегда null, установка бросает `StateError`.

Дальше: пункт 1 слоя 0 — графика: контур и обводка (`drawLine`, `drawPath`), прозрачность и блендинг, тени; затем растровое изображение с native-декодировкой PNG.

### 2026-11-27 — сборка библиотек macOS и Linux через CI

Сделано:

- Native job в CI расширен: в матрицу добавлен `macos-15` (образ `macos-14` выведен из образа GitHub — job отменялся до старта), а macOS runner делает только сборку, упаковку и выгрузку артефактов: window server у раннера нет, поэтому тесты с окнами и смоуки там пропускаются.
- Каждая native-сборка выкладывает артефакты (`actions/upload-artifact@v4`, путь `build/dist/`) — библиотеку каждой платформы можно забрать и сложить в общий релизный бандл.
- Политика `concurrency` уточнена: push отменяет предыдущий прогон (быстрый фидбек), а ручной и плановый прогоны не отменяются — иначе получаса сборка Skia прерывалась бы очередным пушем.
- Исправлен Linux- образ: SDL3 требует `libxss-dev` (XSCRNSAVER), которого не было в списке пакетов, из-за чего Linux-сборка падала на конфигурации SDL. Добавлен полный набор зависимостей SDL3 для Linux (X11, XKB, DRM, GBM, ALSA, PulseAudio, udev, EGL/GL).
- ICU-файл оказался нужен только на Windows: Skia на Unix вшивает данные ICU в библиотеку, поэтому `icudtl.dat` на Linux и macOS не существует. Убрана его проверка из `tools/bootstrap_native.py` и `native/CMakeLists.txt` (устанавливается только для Windows), а в `tools/package.py` файл стал необязательным вне Windows.
- Тест live-resize переписан так, чтобы ждать resize-событие: на Windows оно приходит внутри вызова, на Linux приходит позже, когда оконная система его доставит. Если событие не доставляется вовсе (оконного менеджера нет), тест пропускается, а не падает.
- Шаги упаковки, сборки дистрибуции и выгрузки артефактов в CI теперь выполняются всегда (`if: always()`), чтобы упавший тест не выбрасывал уже собранную библиотеку.
- Linux-библиотека весила 205 МБ: статическая линковка Skia оставляет в ней таблицу символов. Упаковщик теперь снимает символы (`strip --strip-unneeded` на Linux, `strip -x` на macOS), библиотека Windows собирается без них.
- Тест «async Dart invalidation» ждал сигнала таймера по числу итераций: на платформе без оконного менеджера ожидание события возвращается сразу, и цикл успевал завершиться раньше таймера. Теперь цикл ждёт реального времени.

Проверено:

- Первый Linux-прогон упал на конфигурации SDL3: «Couldn't find dependency package for XSCRNSAVER» — причина найдена по логу job, список зависимостей исправлен.
- macOS job отменялся, не начавшись: образ `macos-14` больше не публикуется, актуальный — `macos-15-arm64`.
- Прогон `45913881229`: Windows и macOS собраны и выгрузили артефакты (macOS-библиотека собрана с первого раза, Objective-C++-ветка диалога скомпилировалась без ошибок), Linux собрал библиотеку, но упал на одном тесте (resize-событие без оконного менеджера).
- Прогон `45916008409`: тест live-resize на Linux прошёл, но упал тест с таймером; артефакты при этом выгружены — шаги упаковки больше не блокируются упавшим тестом. Скачаны библиотеки трёх платформ: Windows 8 МБ, macOS 22 МБ, Linux 196 МБ (до снятия символов).
- Прогон `45920251125`: все job'ы зелёные, включая native на Linux. Артефакты после снятия символов: Windows 8,1 МБ, macOS 18,8 МБ, Linux 21,4 МБ.
- Политика `concurrency` в CI исправлена: имя события добавлено в группу, поэтому push больше не отменяет ручной прогон с получасовой сборкой Skia.

Готово:

- Дистрибуция собрана из артефактов CI: `windows-x64` (библиотека и `icudtl.dat`), `macos-arm64`, `linux-x64` — 61 МБ, из них сжатый архив около 25 МБ.
- Windows-библиотека из пакета проверена локально: `tool/verify_published.dart` грузит её из папки дистрибуции и measures text (ширина 93,4).
- `dart pub publish --dry-run --directory ../duix-publish` — 0 ошибок, 0 предупреждений.

Опубликовано:

- `dart pub publish -f --directory ../duix-publish` — «Successfully uploaded https://pub.dev/packages/duix version 0.1.0»; API pub.dev отдаёт `latest: 0.1.0`, дата публикации 2026-11-27T07:59:02Z. Архив 26 МБ, внутри библиотеки трёх платформ.

### 2026-11-27 — эргономичная точка входа: `runApp`

Сделано:

- Бойлерплейт из quick start (`while (host.isOpen(window)) { waitForEvent; presentWindow; await Future.delayed(Duration.zero); }` плюс `shutdown` и `dispose`) убран из публичного API: цикл событий переехал внутрь хоста.
- `NativeHost` получил метод `runWindow(window)`: показать окно, крутить цикл (доставка событий, отрисовка запланированных кадров, уступка Dart-событийному циклу) и вернуться, когда окно закрыто.
- `SdlSkiaHost.runWindow` — реализация цикла; `Application.run(window)` теперь блокирует до закрытия окна, а `Application.shutdown(window)` закрывает его.
- Добавлена функция `runApp(window)` в `package:duix/native.dart`: создаёт хост, показывает окно, крутит цикл и освобождает хост — приложение пишется в одну строку.
- Переписаны все примеры (aqua button, open file dialog, items control, scroll viewer, text gallery, textbox, smoke, frame benchmark, counter) и quick start в README.
- Добавлены тесты: `test/application_test.dart` (headless, три сценария `Application`) и `test/native_event_loop_test.dart` (native, цикл заканчивается с окном и рисует кадры).

Проверено:

- `dart analyze` — No issues found; `dart format` — 0 изменений.
- `dart test --exclude-tags clipboard,native` — 229/229; `dart test --tags native --exclude-tags clipboard` — 38/38.
- Все smoke-примеры проходят: native smoke (1 кадр, presented=1), aqua button, items control (16 контейнеров), scroll viewer, text gallery, textbox; headless-пример counter печатает те же значения.
- `example/native_frame_benchmark.dart`: idle 1015,6 мс при CPU 1,54 %, 60 асинхронных обновлений, latency avg 10,4 мс, fps 62,4.

Дальше: публикация следующей версии пакета с новым API; остальные платформы (macOS x64, Linux arm64, Windows arm64) и codesign/notarization для macOS.

### 2026-11-27 — единое состояние виджета `WidgetState`

Сделано:

- Добавлен `WidgetState` (`lib/src/widget_state.dart`): одно значение с флагами `enabled`, `hovered`, `pressed`, `focused`, с `copyWith`, сравнением и `toString`. Экспортируется из `package:duix/dui.dart`.
- Базовый `Control` владеет press-состоянием: свойство `isPressedProperty` переехало из `Button` в `Control`, база подписалась на `pointerDown`/`pointerUp` и ведёт pressed-состояние сама. Виджет объявляет `handlesPointerPress` (по умолчанию false, у `Button` — true) и получает релиз через `onReleased(args)`.
- Уход указателя от контрола отменяет нажатие (`updatePointerOver(false)`), как GTK снимает active-состояние при leave-notify. Релиз вне контрола больше не активирует кнопку.
- `Control.state` собирает состояние целиком; `SemanticsState` контрола и кнопки собираются из него же — это единый источник для будущих native-мостов accessibility (UIA/NSAccessibility/AT-SPI, §7 п. 3).
- `Button` больше не ведёт pressed-состояние сам: активация переехала в `onReleased`, `focus()` остался в обработчике pointer down.
- Добавлен `test/widget_state_test.dart` (7 тестов): начальное состояние, hover, press/release, отмена нажатия при уходе указателя, disabled-контрол, фокус и связь с `SemanticsState`.

Проверено:

- `dart analyze` — No issues found; `dart format` — 0 изменений.
- `dart test --exclude-tags clipboard,native` — 236/236; `dart test --tags native --exclude-tags clipboard` — 38/38.
- `example/native_aqua_button.dart --smoke` проходит: шаблон по-прежнему переключает normal/hover/pressed по typed-свойствам.

Ограничение шага: `WidgetState` — производное значение, а не bindable-свойство, поэтому шаблон по-прежнему подписывается на отдельные свойства (`Control.isPressedProperty`, `Control.isPointerOverProperty`). Чтобы шаблон подписывался на состояние целиком, нужны derived-свойства в системе свойств — это отдельный шаг.

Дальше: `natural size` (minimum/natural/allocated) в layout — вторая недостающая часть модели GTK; затем native-мосты accessibility, которые публикуют `WidgetState`.

### 2026-11-27 — модель размеров GTK: minimum, natural, allocated

Сделано:

- Добавлен `SizeRequest` (`lib/src/size_request.dart`): пара `minimum` и `natural` — как `gtk_widget_get_preferred_width` в GTK. Экспортируется из `package:duix/dui.dart`.
- `UIElement.measureRequest(availableSize)` — новый примитив: по умолчанию отдаёт natural из `measureCore` и нулевой minimum, поэтому поведение существующих виджетов не меняется; виджет, которому нужен минимум, переопределяет метод.
- `UIElement.measure` считает natural и minimum отдельно (оба ограничены доступным местом), отдаёт desired = max(natural, minimum) и запоминает `_naturalSize`/`_minimumSize`.
- `UIElement.arrange` не сжимает элемент ниже минимума, если слот это позволяет; если места меньше минимума, элемент сжимается и не выходит за границы — «элемент никогда не переполняет контейнер» остаётся правилом duix.
- Новое API: `UIElement.minimumSize`, `naturalSize`, `allocatedSize` (размер, который дал родитель).
- `TextBox` переведён на модель: `_minimumWidth`/`_minimumHeight` (80×30) стали minimum-размером запроса, а не полом на natural; поведение не изменилось — и в тесте «clamps to the available width instead of overflowing it», и в остальных.
- Добавлен `test/size_request_test.dart` (8 тестов): элемент без минимума, минимум важнее меньшего natural, сжатие при нехватке места, резерв места родителем, allocated-размер, растянутый элемент, минимум TextBox, TextBox в узком окне.

Проверено:

- `dart analyze` — No issues found; `dart format` — 0 изменений.
- `dart test --exclude-tags clipboard,native` — 244/244; `dart test --tags native --exclude-tags clipboard` — 38/38.
- Примеры: native smoke (1 кадр, presented=1), TextBox smoke, headless counter, frame benchmark (idle 1005,6 мс при CPU 1,55 %, 60 обновлений, fps 63,0) — те же значения, что до шага.

Отличие от GTK: GTK считает natural размер независимо от доступного места, duix мержит в доступном месте (модель WPF). Поэтому natural в duix — «размер при текущих ограничениях», а minimum — «размер, который элемент резервирует». Следующий шаг по теме — отдельный natural размер, не зависящий от места, и производные свойства в системе свойств, чтобы шаблон подписывался на состояние и на размер целиком.

Дальше: native-мосты accessibility, которые публикуют `WidgetState` и размеры; затем отдельный natural-размер, не зависящий от места.

### 2026-11-27 — репозиторий на GitHub и публикация пакета

Сделано:

- Установлен GitHub CLI 2.106.0 (winget), выполнен вход через device flow в аккаунт `amka`; пользователь — admin организации `TenderOwl`.
- Создан публичный репозиторий `TenderOwl/duix` (описание совпадает с описанием пакета), вся история проекта запушена в ветку `main`, локальная ветка теперь отслеживает `origin/main`.
- В `pubspec.yaml` добавлены поля `homepage` и `repository` — `https://github.com/TenderOwl/duix`.
- Первый push был отклонён: OAuth-токен без scope `workflow` не позволяет создать `.github/workflows/ci.yml`. Scope добавлен через `gh auth refresh -s workflow` (повторный device flow), после чего push прошёл, и workflow `ci.yml` появился в репозитории.

Проверено:

- `dart pub publish --dry-run --directory ../duix-publish` — 0 ошибок и 0 предупреждений, сжатый архив 8 МБ, README, CHANGELOG и LICENSE внутри.
- `gh repo view TenderOwl/duix` показывает репозиторий с README пакета; `ci.yml` присутствует в репозитории.
- CI впервые запустился на GitHub и прошёл: оба пуша дали `success`, job `Dart` зелёный на `windows-latest`, `ubuntu-latest` и `macos-latest` (53–56 с). Job `Native` остался skipped — он запускается только по расписанию и вручную.

Дальше: пункт 3 «Этап 8.1, мосты accessibility». Публикацию на pub.dev можно запускать командой `dart pub publish --directory ../duix-publish` — но лучше после сборки библиотек под macOS и Linux, иначе пакет уедет с одной платформой.

### 2026-11-26 — английская документация и лицензия MIT

Сделано:

- `README.md` и `CHANGELOG.md` переведены на английский: пользовательская документация пакета должна быть на языке публикации. Внутренний рабочий документ `plan.md` остаётся на русском.
- Добавлен `LICENSE` с лицензией MIT (copyright 2026 Andrey Maksimov) — pub.dev требует файл лицензии, без него публикация не проходит.

Проверено:

- `dart pub publish --dry-run --directory ../duix-publish`: ошибок нет, пакет содержит README (4 КБ), CHANGELOG и LICENSE, сжатый архив 8 МБ. Осталась одна рекомендация — поля `homepage`/`repository` в pubspec: их нельзя заполнить без созданного remote.
- `dart analyze` — No issues found; `dart format lib bin example test` — 0 изменений.
- `dart test --exclude-tags clipboard,native` — 226/226; `dart test --tags native --exclude-tags clipboard` — 36/36.

Дальше: пункт 3 «Этап 8.1, мосты accessibility»; перед публикацией — создать remote и вписать `repository` в pubspec.

### 2026-11-26 — quick start и дистрибуция пакета

Сделано:

- Написан `README.md` с quick start для потребителей: `dart create myapp && cd myapp`, `dart pub add duix`, минимальное приложение с окном и кнопкой, порядок поиска нативной библиотеки, сборка из исходников для разработчиков пакета, таблица поддерживаемых платформ, публикация и ограничения. Добавлен `CHANGELOG.md`.
- Нативная библиотека теперь ищется **внутри установленного пакета** (`native/bin/<платформа>-<архитектура>/`). Путь пакета определяется через `Isolate.resolvePackageUri`, поэтому приложение, запущенное из исходников (`dart run`), находит библиотеку без сборки и без ручного копирования.
- `NativeBindings.openAsync()` и `NativeBindings.packageDirectory()` добавлены в API; `SdlSkiaHost.initialize()` использует async-путь. Ключ платформы считается через `Abi.current()` и совпадает с ключом, который раскладывает скрипт упаковки.
- `NativeBindings.libraryPath` показывает, откуда реально загрузилась библиотека.
- Новый исполняемый файл пакета `bin/setup_native.dart` (`dart run duix:setup_native <dir>`): копирует библиотеку и `icudtl.dat` из установленного пакета в папку приложения. Нужен для собранных приложений: скомпилированный исполняемый файл не хранит конфигурацию пакетов, и `Isolate.resolvePackageUri` в AOT возвращает null.
- `tools/package.py --dist` раскладывает собранную библиотеку в staging-каталог `build/dist/<платформа>-<архитектура>/` и собирает папку пакета `../duix-publish/` — исходники, `bin/setup_native.dart`, примеры, README, CHANGELOG, `pubspec.yaml` без `publish_to: none` и нативные библиотеки всех платформ, что нашлись в staging. Пишется `dist-manifest.json` с sha256 каждого файла и размером; недостающие платформы перечисляются предупреждением. Папка публикации лежит вне репозитория: pub прячет всё, что скрыто правилами `.gitignore` репозитория, а `build/` в ignore есть.
- Имя пакета на pub.dev проверено: `dui` уже занят чужой Flutter-библиотекой (dribbahq), свободно имя `duix` — quick start использует его.

Проверено:

- `dart analyze` — No issues found; `dart format lib bin example test` — 0 изменений.
- `dart test --exclude-tags clipboard,native` — 226/226 (плюс тесты packaging и поиска библиотеки в пакете), `dart test --tags native --exclude-tags clipboard` — 36/36.
- Сквозная проверка на «чужом» приложении с зависимостью на собранную папку дистрибуции: `dart run bin/main.dart` загрузил библиотеку изнутри пакета (`…\publish\native\bin\windows-x64\dui_native.dll`) и отрисовал 3 кадра.
- Собранное приложение: `dart compile exe bin/main.dart -o consumer.exe` + `dart run duix:setup_native .` → exe загрузил библиотеку рядом с собой и отрисовал 3 кадра.
- `python tools/package.py --dist` собрал дистрибуцию (19 125 046 байт) с библиотекой Windows x64 и ICU.
- `dart pub publish --dry-run --directory ../duix-publish` проходит по содержимому: README и CHANGELOG внутри, сжатый архив 8 МБ. Остаются ровно два пункта: файл `LICENSE` (обязателен) и поля `homepage`/`repository` в pubspec (рекомендация) — оба требуют решения владельца пакета.

Не проверено:

- Публикация на pub.dev не выполнялась: нужны аккаунт, `LICENSE` (файл ещё не выбран) и сборки библиотеки для macOS и Linux.
- Собранные приложения на macOS и Linux не проверялись: `setup_native` и порядок поиска библиотеки там не тестировались.

Дальше: пункт 3 «Этап 8.1, мосты accessibility», а также публикация пакета после выбора лицензии и сборки остальных платформ.

### 2026-11-26 — потокобезопасность native-слоя

Сделано:

- В `native/src/dui_native.cpp` введён process-wide рекурсивный мьютекс `sdl_mutex()` и класс `SdlScope`. Все экспортированные функции, работающие с SDL или с общим состоянием, берут этот мьютекс: clipboard (включая глобальную карту `clipboard_formats`), host (create/destroy/set callback/next event/wait event/wake up), window (create/destroy/size/metrics/background/text input/begin frame/clip/present), drawing (rect, rounded rect, text) и все text layout функции. Мьютекс рекурсивный, потому что live-resize event watch вызывает Dart, а тот возвращается в native.
- `SDL_Quit()` больше не вызывается: видеоподсистема живёт до конца процесса. Раньше разрушение host в одном изоляте рвал подсистему под окном другого, а повторный `SDL_Init` после `SDL_Quit` ненадёжен.
- В процессе разрешён только один native host. SDL имеет одну глобальную очередь событий, поэтому второй host забрал бы события первого; теперь второй `dui_host_create` возвращает ошибку «Only one native host per process is supported: SDL has a single global event queue…», а Dart превращает её в `StateError('Could not create SDL host: …')`.
- `SdlSkiaHost.initialize()` получил документацию этого правила: один host на процесс, host владеет любым числом окон.
- Новый `test/native_thread_safety_test.dart` (тег `native`): два изолята одновременно создают host (один выигрывает, второй получает явную ошибку, процесс не падает), host снова доступен после освобождения, два изолята одновременно шейпят текст через общий font collection.
- Попутно найден и закрыт баг гигиены native-тестов: три clipboard-теста создавали raw host, а в `finally` сначала восстанавливали clipboard и только потом уничтожали host. Когда восстановление падало («Couldn't open clipboard», буфер держит другой процесс), host не освобождался и ломал все следующие тесты. Теперь host уничтожается первым, а в тесте с публичным clipboard API dispose обёрнут во вложенный `finally`.

Проверено:

- `dart analyze` — No issues found; `dart format lib example test` — 0 изменений.
- `dart test --exclude-tags clipboard,native` — 224/224; `dart test --tags native --exclude-tags clipboard` — 36/36, три подряд запуска стабильны. Полный `dart test` — 261 проходят, падают только clipboard-тесты (environmental).
- Решающая проверка: `dart test --tags native --exclude-tags clipboard --concurrency=4` (параллельные файлы). До правки этот прогон ронял процесс с `STATUS_STACK_BUFFER_OVERRUN`; теперь процесс живёт, а конкурирующий host получает явную ошибку вместо аварии.
- Native библиотека пересобрана (`cmake --build` и полный `python tools/bootstrap_native.py`): Paragraph smoke проходит (width 124.945, height 21).
- Все native smokes проходят: smoke, textbox, items control (16 контейнеров, extent 2 400 000), scroll viewer, aqua button.
- Idle CPU не изменился: 1.55% (один прогон показал 4.63% — это шум загруженной машины, тот же процесс, что держит системный clipboard).
- Бандл пересобран под новую библиотеку: runtime-зависимости по-прежнему 11 и все системные, сквозная проверка «dui_native ABI 2 loaded from the bundle, shaped width 93.4», новый sha256 архива `b65e90e78fc82dbb096cbffc7eb8ba2f16fc3cb688ae7f45bf97b11fea86e8e7`.

Ограничение, которое остаётся осознанным: в процессе может быть только один native host. Поддержка нескольких host потребовала бы переделки глобальной очереди событий SDL на стороне Dart.

Дальше: пункт 3 «Этап 8.1, мосты accessibility» доступен на текущей машине.

### 2026-11-26 — автоматизация ScrollViewer

Сделано:

- Новый `test/native_scroll_viewer_test.dart` (тег `native`) прогоняет ScrollViewer на реальном native backend: drag вертикального ползунка, клавиатурную прокрутку и клик по треку через публичные `window.dispatchPointerDown/Move/Up` и `window.dispatchKeyDown`.
- Smoke-режим `example/native_scroll_viewer.dart` дополнен теми же проверками: drag до конца и обратно с клампингом на границах, клик по треку, клавиши `down`/`end`/`home` после `scrollViewer.focus()`.
- Найдена опасность, которую добавлял новый тестовый файл: **два файла с native-окнами, идущие в параллельных изолятах, роняют процесс** (`STATUS_STACK_BUFFER_OVERRUN`, `GetAndValidateCurrentThreadStackBounds failed`). Причина — SDL video не потокобезопасен, а `dart test` запускает файлы параллельно. Опасность не в новом тесте: она воспроизведена на двух копиях pre-existing `native_abi_test.dart` и проявляется даже без `host.dispose()` (то есть `SDL_Quit` не причина).
- `dart_test.yaml` теперь задаёт `concurrency: 1`: тестовые файлы выполняются последовательно. Раньше это держалось случайно — native-окна создавал только один файл.

Проверено:

- `dart analyze` — No issues found; `dart format lib example test` — 0 изменений.
- `dart test --exclude-tags clipboard,native` — 224/224; `dart test --tags native --exclude-tags clipboard` — 33/33, два подряд запуска стабильны.
- Полный `dart test` — 257 проходят, падают только 4 известных clipboard-теста («Couldn't open clipboard»: системный буфер удерживает другой процесс — это environmental, не регресс).
- Реальная геометрия ScrollViewer на native backend: viewport 308×200, extent 308×740, максимальный offset 540; drag на всю свободную длину трека даёт 540, дальше — клампинг в 540 и в 0; клик по треку даёт 200 (viewport), `down` → 240, `pageup` → 40, `end` → 540, `home` → 0.
- Native smokes (`native_smoke`, `native_scroll_viewer`) проходят; idle CPU не менялся.

Не проверено:

- Визуальная часть ScrollViewer (clipping, resize при разных display scales) — по-прежнему ручная проверка пользователем.
- Потокобезопасность native-слоя для приложений с несколькими изолятами не исправлена: в тестах это закрыто `concurrency: 1`, сам `dui_native` по-прежнему не сериализует SDL-вызовы (пункт 10 в §4 и пункт 12 в §7).

Дальше: пункт 3 «Этап 8.1, мосты accessibility» и пункт 12 «Потокобезопасность native-слоя» доступны на текущей машине.

### 2026-11-26 — этап 8.3, Packaging

Сделано:

- `native/CMakeLists.txt` получил install-правила: библиотека уходит в `bin/` (Windows) или `lib/` (Unix), `icudtl.dat` кладётся рядом с ней же. Путь к ICU-файлу нормализуется через `file(TO_CMAKE_PATH)`: Windows-путь с обратными слэшами CMake при установке читал как escape-последовательность и установка падала с `Invalid character escape '\U'`. Путь переопределяется через `SKIA_ICU_DATA`; если файла нет, install-правило пропускается с предупреждением, а не с ошибкой.
- rpath задан явно: `$ORIGIN` на Linux (библиотека и её приватные зависимости лежат рядом), `@executable_path;@loader_path;@executable_path/../Frameworks` и install name `@rpath` на macOS.
- Новый `tools/package.py`: ставит библиотеку через install-правила CMake, разбирает runtime-зависимости (свой PE-парсер import table на Windows, `ldd` на Linux, `otool -L` на macOS), делит их на системные и private, собирает бандл `build/release/dui_native-<version>-<platform>-<arch>/` с `manifest.json` и sha256 каждого файла и пишет воспроизводимый архив (фиксированные timestamps, отсортированные записи).
- Классификация зависимостей переписана на resolved paths: на Linux private — только библиотеки из дерева сборки проекта, на macOS private — `@rpath`-зависимости, на Windows — DLL, которых нет в System32. Прежняя версия считала private любую Linux-зависимость, не начинающуюся с `libc.so`/`libm.so`, и сломала бы упаковку на Linux (GTK, libstdc++).
- `package.py` умеет `--check-only` (только состав зависимостей) и `--skip-install` (бандл из каталога сборки). Префикс install передаётся относительным путём, чтобы в сгенерированный скрипт не попали обратные слэши.
- Новый `tool/verify_native.dart` — AOT-программа, которая грузит библиотеку из каталога рядом с exe и шейпит Unicode-текст. Это доказывает, что ICU-данные найдены рядом с библиотекой: без `icudtl.dat` раскладка не создаётся (`SkParagraph creation failed`).
- Поиск native-библиотеки в Dart начинается с каталога исполняемого файла (`Platform.resolvedExecutable`), дальше `DUI_NATIVE_LIBRARY` и абсолютный путь: упакованное приложение кладёт библиотеку рядом с exe.
- Новый `test/native_packaging_test.dart`: первый кандидат поиска — библиотека рядом с exe; тест с тегом `native` запускает `cmake --install` во временный каталог и требует, чтобы библиотека и ICU-файл лежали в одном каталоге.
- CI native job получил шаг `python tools/package.py` и `actions/setup-python`: на ubuntu-раннере нет команды `python`, а без неё и существующий `python tools/bootstrap_native.py` упал бы.

Проверено:

- `dart analyze` — No issues found; `dart format lib example test` — 0 изменений.
- `dart test` — 260/260; `dart test --exclude-tags clipboard,native` — 224/224; `dart test --tags native --exclude-tags clipboard` — 32/32.
- `cmake --install native/build --prefix build/release/install-tree` — установлены `dui_native.dll` (8 347 648 байт) и `icudtl.dat` (10 468 208 байт) в одном каталоге.
- `python tools/package.py` — 11 runtime-зависимостей, все системные; бандл и архив собраны; сквозная проверка из другого CWD: «dui_native ABI 2 loaded from the bundle, shaped width 93.4».
- Воспроизводимость: два подряд прогона дали одинаковый sha256 архива `7553dc6e1a9a450f25cc9ea8a8609d69543d6a1172e087e5f06fdc6f18f6deec`.
- Негативный контроль: без `icudtl.dat` рядом с библиотекой verify-программа падает с `SkParagraph creation failed`, то есть проверка бандла не пустая.
- Классификация зависимостей проверена синтетическими случаями для Linux, macOS и Windows.
- Native smokes (smoke, textbox) проходят; idle CPU не менялся (1.54%).

Не проверено:

- macOS и Linux: сборка, rpath в реальном приложении, universal binary, codesign. Разбор зависимостей для этих ОС написан, но на живых системах не запускался.
- Windows arm64: библиотека не собиралась.
- Запуск бандла на чистой машине без Skia/SDL/ICU не выполнялся — проверен только состав импортов DLL.

Дальше: пункт 10 «Этап 8.3, остаток — нужны другие машины» и пункт 11 «Этап 8.3, чистая машина» в §7.

### 2026-11-26 — этап 8.1, backend-independent семантика

Сделано:

- Добавлен `lib/src/semantics.dart`: `SemanticsRole`, `SemanticsState`, `SemanticsNode` и `SemanticsTree`. Узел снимает role, name, value, state, bounds и диапазон выделения текста; `SemanticsNode.element` держит ссылку на контрол, чтобы платформенный мост мог сопоставить native-объект с элементом.
- `SemanticsTree` строится по требованию: `SemanticsTree.fromElement(element)` и `Window.semanticsTree`. Фокус и выделение читаются в момент построения, поэтому снимок всегда актуален и не требует подписки на изменения.
- Элементы без роли (`SemanticsRole.none`) плоско сворачиваются — их дети поднимаются к родителю, дерево остаётся компактным. Контрол с непустым именем забирает имя своего label-контента, поэтому текст кнопки не дублируется в дереве.
- `UIElement` получил хуки `semanticsRole`, `semanticsName`, `semanticsValue`, `semanticsState` и `semanticsSelection`; `Control` по умолчанию отдаёт `focused` и `disabled`.
- Роли контролов: `Label` → label, `Button` → button (с `pressed`), `TextBox` → textBox (value, editable, выделение), `ItemsControl` → list, `ContentControl` берёт имя из контента.

Проверено:

- `dart analyze` — без замечаний; `dart format` — без изменений.
- `dart test` — 258/258; `dart test --exclude-tags clipboard,native` — 223/223; `dart test --tags native --exclude-tags clipboard` — 31/31.
- Новый `test/semantics_test.dart` (11 тестов): роли и имена зеркалят дерево UI, элементы без роли сворачиваются, фокус отражается и переносится при смене, выделение и его схлопывание видны в узле, disabled и границы совпадают с контролом, контрол забирает имя label-контента, `ItemsControl` даёт list с элементами, disposed-контрол в дерево не попадает.
- Native-смоуки (textbox, items control) проходят.

Не проверено:

- Платформенные мосты (UI Automation, NSAccessibility, AT-SPI) не реализованы — им нужен native-слой и проверка на macOS/Linux.
- Снимок семантики не проверялся в живом accessibility-инструменте (NVDA, VoiceOver, Orca) — до мостов это невозможно.

Следующий шаг:

- Windows UI Automation поверх готовой `SemanticsTree`: мост в native-слое плюс проверка на этой машине.

### 2026-11-26 — этап 8.4, CI на трёх ОС

Сделано:

- Добавлен `.github/workflows/ci.yml`. Job `dart` работает на Windows, macOS и Linux: `dart pub get`, `dart format --output=none --set-exit-if-changed lib example test`, `dart analyze`, `dart test --exclude-tags clipboard,native`. Триггеры: push в `main`, pull request, ручной запуск и еженедельное расписание.
- Job `native` собирает SDL3 и Skia из исходников через `tools/bootstrap_native.py`, затем гоняет native-тесты и smoke. Он помечен `continue-on-error`, запускается только вручную или по расписанию и работает на Windows и Ubuntu: сборка Skia требует больше диска и времени, чем даёт hosted-runner, а у macOS-runner нет window server, поэтому оконные проверки там невозможны.
- Введён тег `native` для тестов, которым нужна собранная библиотека (`native_abi_test.dart`, `native_text_matrix_test.dart`); тег объявлен в `dart_test.yaml` вместе с `clipboard`.
- Оказалось, что package:test читает аннотации уровня файла с **library directive**, а не с `main()` и не с импорта: `@Tags(['native'])` на `main()` молча не применялся, и `--tags native` не находил ни одного теста. Теги навешены на `library;`, после чего `--tags native` находит 35 тестов, а `--exclude-tags clipboard,native` — 212.

Проверено:

- `dart format --output=none --set-exit-if-changed lib example test` — код 0; `dart analyze` — без замечаний.
- `dart test --exclude-tags clipboard,native` — 212/212; `dart test --tags native --exclude-tags clipboard` — 31/31; полный `dart test` — 247/247.
- YAML workflow разобран парсером и проверен по структуре: два job, матрицы и триггеры на месте.

Не проверено:

- Сам GitHub Actions прогон выполнить отсюда нельзя: native job не проверен на раннере, включая MSVC-окружение для `clang-cl`, дисковое место под Skia и работу `xvfb-run` на Ubuntu.
- macOS native job не включён: у hosted-runner нет window server, а Skia-сборка на нём не проверена.
- Первая native-сборка в CI будет долгой — нужен прогрев кэша `.native-deps`.

Следующий шаг:

- Прогнать workflow вручную (`workflow_dispatch`) и довести native job до зелёного состояния; затем этап 8.1 semantics или этап 8.3 packaging.

### 2026-11-26 — P1, recursive dispose по дереву контролов

Сделано:

- `UIElement.dispose()` освобождает элемент и всё поддерево: отсоединяет от родителя, размонтирует, освобождает потомков, отменяет bindings и вызывает `onDisposed()`. Повторный вызов безопасен.
- `UIElement.onDisposed()` — хук для собственных ресурсов; `Label` и `TextBox` освобождают в нём native-раскладки (в том числе если контрол никогда не монтировался).
- `UIElement.removeChild(child)` — единая точка удаления ребёнка; переопределена в `Panel`, `ContentControl` и `ItemsControl`, поэтому родитель всегда знает, как убрать своего ребёнка.
- `Window.dispose()` освобождает дерево контента. `close()` контент не уничтожает — окно можно переоткрыть.
- `UIElement.isDisposed` теперь учитывает и начало dispose; дублирующий флаг в `ItemsControl` удалён, единый источник состояния — `PropertyOwner`.
- `mountTo(null)` стал идемпотентным: `onUnmounted()` больше не вызывается повторно. Монтирование disposed-элемента в окно и добавление его в панель бросают `StateError`.

Исправлено по ходу:

- `Panel.removeChild` не мог использовать `ListBase.remove` — он присваивает `null` в слот, а список элементов non-nullable; удаление идёт через `removeAt`.
- `ItemsControl.dispose()` освобождал контейнеры, но не их элементы: элементы теперь dispose-ятся до удаления контейнеров.

Проверено:

- `dart analyze` — без замечаний; `dart format` — без изменений.
- `dart test` — 247/247; `dart test --exclude-tags clipboard` — 243/243.
- Новый `test/dispose_test.dart` (12 тестов): освобождение native-раскладок поддерева, отсоединение от родителя, dispose всех потомков, идемпотентность, снятие фокуса, запрет вернуть disposed-элемент в дерево, запрет мутаций, `Window.dispose()`, сохранение контента при `close()`, отсоединение контента `ContentControl`, освобождение контейнеров `ItemsControl`.
- Native-смоуки (smoke, textbox, aqua button, items control) проходят.

Не проверено:

- macOS/Linux не затрагивались.
- Ручная проверка lifecycle (dispose поддерева в живом окне, переоткрытие окна после `close()`) не проводилась.

Следующий шаг:

- Этап 8.4 CI: `.github/workflows` с analyze/test и native build на трёх ОС; затем этап 8.1 semantics.

### 2026-11-26 — P1, legacy `drawText` на SkParagraph

Сделано:

- Native `dui_draw_text` больше не использует `SkCanvas::drawSimpleText`: текст строится как SkParagraph-параграф через общий хелпер `create_paragraph`, который теперь используют и `dui_text_layout_create`, и legacy-путь. Shaping, fallback-шрифты и Unicode работают на обоих путях.
- Вынесен общий `create_paragraph(...)`; шрифт-менеджер, `SkUnicode` и `FontCollection` стали статическими синглами — раньше `SkFontMgr_New_DirectWrite()` создавался на каждый вызов, что недопустимо для пути, вызываемого каждый кадр.
- На окне добавлен кэш legacy-текста: раскладка переиспользуется, пока не изменились текст, размер шрифта и scale; цвет применяется через `updateForegroundPaint` на каждом draw.
- Якорные точки legacy-API сохранены: start — левая кромка, center — середина, end — правая кромка; baseline по-прежнему на `y + font_size`. Текст не переносится.
- Исправлен paint-range в `dui_text_layout_draw`: foreground paint задавался в UTF-8 байтах вместо UTF-16 offsets, из-за чего диапазон не покрывал весь не-ASCII текст.
- ABI `dui_native` поднят до версии 2: `dui_draw_text` возвращает `int32_t` и получает out-параметр `out_width`; обновлены header, C++, Dart typedef, lookup и вызов. Native library пересобрана.

Проверено:

- `dart analyze` — без замечаний; `dart format` — без изменений.
- `dart test` — 235/235; `dart test --exclude-tags clipboard` — 231/231.
- Native-тест «text drawing uses the same shaped metrics as the text layout»: ширина, возвращённая `dui_draw_text`, совпадает с измерением `dui_text_layout_create` для того же текста, шрифта и scale — legacy-путь теперь даёт те же метрики, что и layout-путь.
- Native-тест «text drawing accepts Unicode and every alignment»: ASCII, кириллица, emoji и RTL-строка рисуются во всех трёх выравниваниях.
- `example/native_frame_benchmark.dart`: idle CPU 1.54% — на уровне зафиксированных 1.53–1.54%. Без кэша раскладки было 3.08%, то есть shaped-текст на каждом кадре стоил ~16 мс CPU за секунду.
- Native-смоуки (smoke, textbox, aqua button, items control, scroll viewer) проходят.

Не проверено:

- Визуально shaped-текст legacy-API (FPS-overlay в `--diagnostics`) не подтверждён пользователем.
- macOS/Linux сборка и поведение не проверялись: там `SkFontMgr_New_CoreText`/`FontConfig` и другой fallback-путь.
- Headless-раскладка по-прежнему рисует через `context.drawText` без shaping — это детерминированный тестовый рендерер, shaping в нём не предусмотрен.

Следующий шаг:

- P1 recursive `dispose()` по дереву контролов; затем этап 8.4 CI.

### 2026-11-26 — P0, реальное измерение TextBox

Сделано:

- `TextBox.measureCore()` больше не оценивает ширину по числу символов: desired size считается по метрикам `TextLayout` (ширина/высота раскладки + content padding 16/8, минимум 80×30).
- Добавлено свойство `TextBox.fontSize` (по умолчанию 14) с `affectsMeasure`/`affectsPaint`; оно же используется при раскладке текста, поэтому measure и render считаются по одним метрикам.
- Измерение клампится к available width. Прежняя формула `clamp(80, available)` бросала `ArgumentError`, если контейнер был уже 80 px — это воспроизведено и закрыто.
- Раздельные кэши раскладки для measure и render: IME composition не вытесняет раскладку измерения, а в steady state держится одна native-раскладка.
- `onMounted`/`onUnmounted` переизмеряют контрол, чтобы смена backend (headless → native) и remount не оставляли устаревший размер.
- Четыре native clipboard-теста помечены тегом `clipboard`, тег объявлен в `dart_test.yaml`.

Проверено:

- `dart analyze` — без замечаний; `dart format` — без изменений.
- `dart test` — 233/233; `dart test --exclude-tags clipboard` — 229/229.
- Новый `test/text_box_measurement_test.dart` (5 тестов): ширина `TextBox` = ширина `Label` + 16 и высота = высота `Label` + 8; масштабирование с `fontSize`; клампинг к узкому available width; переизмерение при смене текста; корректность после remount.
- Native-тест `TextBox measures with native text metrics` подтверждает ту же формулу на SkParagraph-метриках и рост измерения при смене текста.
- `example/native_scroll_viewer.dart --smoke --diagnostics` проходит на Windows (scale 2.0, logical 640×420, physical 1280×840, 3 кадра) — автоматическая часть ручной проверки ScrollViewer закрыта.

Обнаружено и исправлено в документации:

- Windows-оболочка съедает `^` до запуска Dart, поэтому команда `dart test --name '^(?!.*clipboard).*$'` из «Команды» деградировала до «совпадает всё» и не исключала clipboard-тесты. Заменена на tag-based `--exclude-tags clipboard`.
- Пункт долга «legacy `drawText`, используемый `TextBox`» устарел: `TextBox` уже рисует через `layout.draw()` и SkParagraph; без shaping остались только публичный `DrawingContext.drawText()`, FPS-overlay диагностики и headless-раскладка. Пункт переформулирован как P1.
- В списке файлов не было `example/native_scroll_viewer.dart` — добавлен.

Не проверено:

- Визуальная проверка нового измерения в native-примерах (TextBox и три поля в `example/native_textbox.dart`) не проводилась — нужен взгляд пользователя.
- macOS/Linux и внешние IME не затрагивались.

Следующий шаг:

- P1: перевести `DrawingContext.drawText()` и native `dui_draw_text` на SkParagraph shaping либо убрать API; затем recursive `dispose()` по дереву контролов.

### 2026-11-26 — этап 8.2, macOS NSOpenPanel

Сделано:

- Добавлен Objective‑C++ backend `native/src/file_dialog_macos.mm`; CMake на Apple включает OBJCXX/ARC и линкует AppKit и weak-linked UniformTypeIdentifiers.
- `NSOpenPanel` настроен для одного файла с title и initial directory. Возврат `SDL_strdup` сохраняет существующий ownership contract.
- При parent используется настоящий SDL `NSWindow` и `beginSheetModalForWindow`; ownerless использует `runModal`. Асинхронный sheet адаптирован к синхронному ABI через текущий `CFRunLoop`.
- Typed filters преобразуются в `UTType` на macOS 11+, с fallback на `allowedFileTypes` для более ранних версий. `*`/`*.*` снимает ограничение.

Проверено:

- Windows native build и Paragraph smoke — успешно, `dart analyze` — без замечаний, полный `dart test` — 227/227.

Не проверено / ограничения:

- macOS-компиляция и реальный dialog не проверялись на Windows-машине. AppKit объединяет extensions всех named filters в один набор `allowedContentTypes`; отдельного переключателя именованных фильтров пока нет.

Следующий шаг:

- На macOS собрать проект и вручную проверить parent/ownerless, выбор/отмену, filters/initialDirectory и Unicode path через `example/native_open_file_dialog.dart`.

### 2026-11-26 — этап 8.2, Linux GtkFileDialog

Сделано:

- Linux native build подключает GTK 4.10+ через `pkg-config`; для сборки нужны `pkg-config` и `libgtk-4-dev`.
- `dui_window_open_file_dialog()` использует системный `GtkFileDialog`: title, initial directory и `GListStore` из `GtkFileFilter`; `*.*` нормализуется в GTK pattern `*`.
- Асинхронный `open`/`open_finish` адаптирован к существующему синхронному C ABI через локальный `GMainLoop`. Cancel/Close возвращает `null`, остальные ошибки включают GTK message. Native path по-прежнему выделяется через `SDL_malloc`.
- SDL X11/Wayland handles не выдаются за `GtkWindow*`; при переданном parent Linux пока использует безопасный ownerless fallback. Dart API и Windows backend не изменялись.

Проверено:

- Windows native build и Paragraph smoke — успешно, `dart analyze` — без замечаний, полный `dart test` — 227/227.
- Официальная документация GTK подтверждает async contract, ownership filters/result и коды `GTK_DIALOG_ERROR_DISMISSED`/`CANCELLED`.

Не проверено / ограничения:

- Linux-компиляция, связывание с GTK и реальный диалог на X11/Wayland не проверялись на Windows-машине. GTK parent/modality для SDL window отсутствует.

Следующий шаг:

- На Linux установить `pkg-config`/`libgtk-4-dev`, собрать native library и вручную проверить `example/native_open_file_dialog.dart`; затем macOS `NSOpenPanel`.

### 2026-11-26 — этап 8.2, настройки FileDialog в свойствах

Сделано:

- `title`, `initialDirectory` и `filters` перенесены из аргументов `showOpen()` в mutable properties экземпляра `FileDialog`.
- `showOpen([Window? parent])` теперь принимает только optional positional parent. Backend contract и legacy `Window` API сохраняют передачу настроек.
- Пример настраивает один reusable dialog через cascade и использует `try`/`on Exception` вокруг `showOpen(parent)` для обоих режимов.

Проверено:

- Пользователь подтвердил предыдущие filters/initialDirectory на Windows.
- `dart analyze` — без замечаний; полный `dart test` — 227/227. Native code в этом шаге не менялся.

Следующий шаг:

- Linux `GtkFileDialog` для того же property-based standalone API.

### 2026-11-26 — этап 8.2, filters и initialDirectory

Сделано:

- `FileDialog.showOpen()` и compatibility API получили `initialDirectory` и typed `FileDialogFilter(name, extensions)`. Поддерживаются `txt`/`.txt`, составные фильтры и `*` для всех файлов.
- C ABI передаёт UTF-8 initial directory и массив filter specs. Windows использует `SHCreateItemFromParsingName` + `IFileDialog.SetFolder` и `SetFileTypes` с patterns `*.txt;*.md`.
- Пример задаёт каталог проекта и фильтры `txt/md`/«Все файлы» в parent и ownerless-режимах. Добавлен headless forwarding-тест.

Проверено:

- Пользователь подтвердил предыдущий ownerless-вариант.
- Native library пересобрана, Paragraph smoke успешен; `dart analyze` — без замечаний; полный `dart test` — 227/227.

Не проверено / ограничения:

- Визуальное применение новых фильтров и стартового каталога ещё не проверено. Linux `GtkFileDialog` и macOS `NSOpenPanel` остаются отдельными срезами.

Следующий шаг:

- Ручная проверка filters/initialDirectory, затем Linux `GtkFileDialog`.

### 2026-11-26 — этап 8.2, standalone FileDialog с optional parent

Сделано:

- `FileDialog` стал самостоятельным объектом, связанным с `FileDialogHandler`; `showOpen()` принимает optional `parent` и `title`. Прежний `Window.showOpenFileDialog()` оставлен для совместимости.
- Windows C ABI допускает `NULL` window и передаёт `NULL` owner в `IFileOpenDialog`; parent, если задан, по-прежнему преобразуется в HWND.
- Пример переведён на standalone `FileDialog(host)` и содержит отдельные кнопки для parent/ownerless-диалогов. Добавлены headless-тесты обоих contracts.

Проверено:

- Пользователь подтвердил работу предыдущего Windows-примера с родительским окном.
- Native library пересобрана, Paragraph smoke успешен; `dart analyze` — без замечаний; полный `dart test` — 226/226.

Не проверено / ограничения:

- Реальный ownerless-вариант после изменения API не запускался; Unicode path и native error behavior по-прежнему требуют ручной проверки.

Следующий шаг:

- Проверить ownerless-диалог вручную, затем добавить filters/initial directory.

### 2026-11-26 — этап 8.2, Windows system open-file dialog

Сделано:

- Добавлены backend-independent `FileDialogHandler` и `Window`/`WindowHost.showOpenFileDialog({String? title})` для выбора одного файла. Без backend и при отмене возвращается `null`; native errors преобразуются в `StateError`.
- C ABI и Dart FFI получили open-file call и явное освобождение возвращаемого UTF-8 path. Windows backend использует системный `IFileOpenDialog` с owner HWND и `FOS_FILEMUSTEXIST | FOS_PATHMUSTEXIST`.
- Добавлены три headless contract-теста и `example/native_open_file_dialog.dart` для ручной проверки выбора и отмены.

Проверено:

- Native library пересобрана с готовыми SDL/Skia dependencies; Paragraph smoke — успешно.
- `dart analyze` — без замечаний; полный `dart test` — 224/224.
- `git diff --check` — без ошибок, только LF→CRLF warnings.

Не проверено / ограничения:

- Реальный системный диалог не запускался, поэтому выбор, отмена, Unicode path и owner behavior требуют ручной проверки. Filters и initial directory отсутствуют. Linux `GtkFileDialog` и macOS `NSOpenPanel` не реализованы в этом Windows-срезе.
- Полный bootstrap повторно запускал GN и остановился из-за отсутствующего `ProgramFiles(x86)` в среде; изменённая native library затем успешно настроена и собрана напрямую с уже готовыми зависимостями.

Следующий шаг:

- Ручная проверка примера, затем filters/initial directory отдельным небольшим срезом.

### 2026-11-26 — этап 8.2, clipboard MIME enumeration и snapshot cleanup

Сделано:

- В C ABI, Dart FFI, `WindowHost`, `Window` и `ClipboardHandler` добавлены `readClipboardMimeTypes()` и `clearClipboard()` с native реализациями и bounded retry очистки.
- Native enumeration объединяет SDL MIME list и Windows CF_HTML с дедупликацией; C ABI ownership покрывает массив и отдельные strings.
- Все clipboard integration-тесты сохраняют полный доступный MIME snapshot и восстанавливают его в `finally`; пустой snapshot восстанавливается через clear вместо записи пустого текста.
- Добавлена регрессия snapshot/restore для plain text, HTML, XHTML, binary, empty payload и исходно пустого состояния.

Проверено:

- Native library пересобрана; `dart analyze` — без замечаний.
- Четыре native clipboard-сценария прошли трижды; полный `dart test` — 221/221.
- `git diff --check` — без ошибок, только LF→CRLF warnings.

Не проверено / ограничения:

- Snapshot включает форматы, перечисляемые SDL/CF_HTML MIME API; произвольные native-only formats вне этого API не сохраняются. Ручная проверка HTML в сторонних приложениях не выполнялась.

Следующий шаг:

- Первый open-file dialog vertical slice.

### 2026-11-26 — этап 8.2, backend-independent formatted clipboard API

Сделано:

- Добавлены `ClipboardMimeTypes.plainText/html` и методы `writeClipboardData`, `hasClipboardData`, `readClipboardData` в `Window` и `WindowHost`; binary data представлены `Uint8List`, без FFI-типов в публичном `dui.dart`.
- `ClipboardHandler` вынесен в `src/clipboard.dart`; `SdlSkiaHost` делегирует formatted calls существующему native bindings API. Без handler сохраняется безопасное `false`/`null` поведение.
- Добавлены headless contract tests и native integration через публичный `Window` API. Native clipboard integration оставлен в одном файле, чтобы параллельные test suites не конкурировали за системный clipboard.

Проверено:

- `dart analyze` — без замечаний; полный `dart test` — 220/220.
- Headless round-trip проверяет HTML, binary с нулевыми байтами, empty payload и missing format; native integration проверяет Unicode plain text и CF_HTML через `WindowHost`.
- `git diff --check` — без ошибок, только LF→CRLF warnings.

Следующий шаг:

- Сохранение и восстановление полного прежнего MIME-набора в clipboard integration cleanup; ручная проверка HTML в сторонних приложениях остаётся открытой.

### 2026-11-26 — этап 8.2, Windows CF_HTML

Сделано:

- `text/html` на Windows исключён из SDL text MIME mapping и обрабатывается через registered `HTML Format`/`CF_HTML` с `OpenClipboard` bounded retry.
- Запись формирует CF_HTML header с UTF-8 byte offsets и fragment markers; чтение возвращает fragment по markers либо numeric offsets, без служебного header. HTML-only write поддержан без передачи пустого MIME-списка в SDL.
- Остальные MIME-форматы по-прежнему записываются через SDL и сохраняются при добавлении CF_HTML. Integration-тест расширен настоящим `text/html` round-trip с кириллицей и emoji наряду с XHTML, binary и empty payload.

Проверено:

- Оба clipboard-теста прошли трижды подряд; полный `dart test` — 217/217.
- Native library пересобрана, `dart analyze` — без замечаний, `git diff --check` — без ошибок, только LF→CRLF warnings.

Не проверено / ограничения:

- Ручная вставка HTML в Word, браузер и другие сторонние приложения не выполнялась. Linux/macOS в этом шаге не запускались; CF_HTML изолирован Windows guards.

Следующий шаг:

- Backend-independent formatted clipboard API и сохранение полного прежнего MIME-набора в integration cleanup.

### 2026-11-26 — этап 8.2, стабилизация Windows clipboard

Сделано:

- Native text и formatted writes используют bounded retry на Windows: до 12 попыток с паузой 25 мс (максимум около 275 мс ожидания сверх внутренних retry SDL). На остальных ОС остаётся одна попытка.
- `dui_clipboard_get_data` различает missing format и существующий empty payload: для последнего возвращает освобождаемый SDL buffer нулевой логической длины вместо `NULL`.

Проверено:

- Оба clipboard integration-теста трижды подряд прошли, включая восстановление прежнего plain text и empty custom payload.
- Полный `dart test` — все 217 тестов проходят, включая оба Windows clipboard-сценария. Ранее воспроизводимый `Couldn't open clipboard` в этих прогонах не возник.
- Native library пересобрана; `git diff --check` — без ошибок, только известные LF→CRLF warnings.

Следующий шаг:

- Windows CF_HTML и backend-independent formatted clipboard API; сохранение полного прежнего MIME-набора в integration cleanup.

### 2026-11-26 — этап 8.2, универсальный MIME clipboard

Сделано:

- В C ABI/C++ добавлены `dui_clipboard_set_data`, `has_data`, `get_data`, `free_data`. SDL delayed-rendering callback читает native-owned копии MIME payloads; cleanup освобождает их при замене clipboard.
- В Dart FFI добавлены `writeClipboardData`, `hasClipboardData`, `readClipboardData`; бинарные buffers передаются с explicit lengths, поэтому поддерживаются нулевые байты и empty payloads. Прежний text API не изменён.
- Добавлен native integration-тест для одновременных `text/plain`, `application/xhtml+xml`, custom binary и custom empty форматов.

Проверено:

- `dart analyze` — без замечаний; `dui_native.dll` пересобрана без warnings.
- Все round-trip assertions нового теста проходят, включая совместимость formatted write с прежним `readClipboardText()`.
- `dart test --name '^(?!.*clipboard).*$'` — все 214 тестов проходят.

Не проверено / ограничения:

- Новый тест дважды завершился известной ошибкой `Couldn't open clipboard` только при восстановлении прежнего системного значения; старый text clipboard тест воспроизвёл ту же ошибку. Сами операции formatted round-trip до cleanup успешны.
- SDL Windows обрабатывает любой `text/*` как `CF_UNICODETEXT`: попытка round-trip `text/html` вернула plain text. CF_HTML требует platform-specific реализации; тест использует `application/xhtml+xml`, не выдавая его за системный HTML clipboard.
- Integration-тест восстанавливает только прежний plain text, не весь прежний MIME-набор. Linux/macOS не запускались.

Следующий шаг:

- Стабилизировать Windows clipboard cleanup, затем добавить CF_HTML и backend-independent formatted API.

### 2026-11-26 — пример Aqua Button

Сделано:

- Добавлен `example/native_aqua_button.dart`: named `Style<Button>` назначает persistent Aqua template с белым content label и сохранением focus ring. После визуальной проверки прямоугольная поверхность заменена капсулой со скруглёнными краями, внутренней светлой кромкой и верхним полупрозрачным глянцевым бликом.
- `Control.isPointerOver` переведён на typed `DuiProperty`; Window обновляет hover для logical path hit-tested element и очищает его при выходе, смене content и закрытии окна.
- `Border.color` и `Border.padding` переведены на `DuiProperty`, поэтому поверхность шаблона поддерживает bindings.
- Комбинированный binding примера переключает normal/hover/pressed colors без пересоздания template subtree. Поддержаны `--diagnostics` и автоматический `--smoke`.
- В `DrawingContext`, recording renderer, FFI bindings, C ABI и Skia backend добавлен `drawRoundedRect`/`dui_draw_rounded_rect` с fill/stroke; native ABI-тест вызывает его в активном кадре, recording-тест проверяет геометрию, Paint и strokeWidth.
- `ControlTemplate.focusRingShape` позволяет шаблону выбрать `rectangle` или `capsule`; Aqua использует капсульный контур вместо прежнего прямоугольного, default-рендеринг остальных контролов не изменён. Тест проверяет геометрию capsule ring и отсутствие прямоугольных полос.

Проверено:

- `dart format` и `dart analyze` — без замечаний.
- `cmake --build native/build --parallel` — `dui_native.dll` успешно пересобрана.
- `dart run example/native_aqua_button.dart --smoke --diagnostics` — успешно: hover, pressed, pointer click, Space и template identity проверены, 3 кадра; scale 2.0, logical 520×320, physical 1040×640.
- `dart test --name '^(?!.*clipboard).*$'` — все 214 тестов проходят.
- `git diff --check` — без ошибок; только известные предупреждения LF→CRLF.

Не проверено:

- Интерактивный визуальный результат пока не подтверждён пользователем; smoke проверяет состояния и native render/present автоматически.

Следующий шаг:

- Ручная проверка Aqua-примера; затем этап 8.1 — semantics и accessibility.

### 2026-11-26 — этап 7.4, styles и control templates

Сделано:

- Добавлены generic `Style<TOwner>` с необязательным именем и `DuiSetter<TOwner, T>`. `UIElement.styleProperty` применяет setters через style layer, обновляет общие свойства при смене style и очищает удалённые setters. Несовместимые target types отклоняются.
- Добавлены `PropertyBinding` и `MappedBinding` для typed property/template bindings без строковых paths и reflection.
- `Button.isPressed` переведён на `DuiProperty`; добавлены `Button.templateProperty`, `ControlTemplate<Button>` и доступный для проверок persistent `templateRoot`.
- `ContentPresenter` переносит исходный content в visual subtree и синхронизирует последующие replacements. Обычные property/content changes не пересоздают template root.
- Custom template полностью заменяет default Button visuals, но pointer/keyboard activation и focus ring сохраняются. При замене template старое subtree отсоединяется и его bindings освобождаются; content не dispose и сохраняет identity.
- Добавлены 4 теста `test/styles_test.dart` и 3 теста `test/control_template_test.dart`. C ABI и native C++ не изменялись.

Проверено:

- `dart format` и `dart analyze` — без замечаний.
- Целевой прогон styles/templates/Button keyboard/focus/DataContext/value precedence — все 35 тестов проходят.
- `dart test --name '^(?!.*clipboard).*$'` — все 212 тестов проходят.
- `git diff --check` — без ошибок; только известные предупреждения LF→CRLF.

Ограничение:

- Control templates реализованы для Button, как требовал критерий этапа; универсальная поддержка остальных контролов и общий recursive dispose остаются отдельными задачами.

Следующий шаг:

- Этап 8.1 — semantics для дерева контролов и accessibility.

### 2026-11-26 — этап 7.3, DataContext

Сделано:

- `DataContext` переведён на `UIElement.dataContextProperty` и общие value layers. Effective context автоматически наследуется по logical tree и рекурсивно обновляется при изменении предка.
- Attach/detach/reparent синхронизируют inherited layer. Local context маскирует ancestor updates до `clearLocalValue()`, bound parent context распространяется по тем же правилам.
- Добавлены `dataContextAs<T>()` и `requireDataContext<T>()`; строковые paths, reflection и кодогенерация не используются. `effectiveDataContext` сохранён как compatibility alias.
- `ItemsControl` продолжает задавать item как local context корня шаблона; вложенные контролы теперь автоматически наследуют item.
- Добавлены 6 тестов `test/data_context_test.dart`: recursive inheritance/notifications, local mask, binding propagation, detach/reparent, typed accessors и item context. C ABI и native C++ не изменялись.

Проверено:

- `dart format` и `dart analyze` — без замечаний.
- `dart test test/data_context_test.dart test/items_control_test.dart test/value_precedence_test.dart` — все 26 тестов проходят.
- `dart test --name '^(?!.*clipboard).*$'` — все 205 тестов проходят.
- `git diff --check` — без ошибок; только известное предупреждение LF→CRLF.

Следующий шаг:

- Этап 7.4 — styles и persistent control templates.

### 2026-11-26 — этап 7.2, приоритеты значений

Сделано:

- Реализована цепочка `default < inherited < style < binding < local < animation` с `DuiValueSource`, `getValueSource()` и отдельными set/clear API для inherited, style, local и animation слоёв.
- One-way local маскирует binding без отмены подписки; очистка local восстанавливает актуальное binding value. Новый binding заменяет прежний явный local, а cancel сохраняет binding value как local только при отсутствии явного local поверх него.
- Two-way setter продолжает писать в источник под animation mask. Nullable values различаются по наличию записи в слое; constructor defaults не создают блокирующий local.
- Property notifications публикуются только при изменении effective value. Замена binding поверх local сохраняет корректное previous value.
- Добавлены 9 тестов `test/value_precedence_test.dart`: вся цепочка, masked bindings, animation notifications, замена/отмена binding, nullable, two-way под animation и constructor defaults. C ABI и native C++ не изменялись.

Проверено:

- `dart format` и `dart analyze` — без замечаний.
- `dart test test/value_precedence_test.dart test/bindings_test.dart` — все 22 теста проходят.
- `dart test --name '^(?!.*clipboard).*$'` — все 199 тестов проходят.
- `git diff --check` — без ошибок; только известное предупреждение LF→CRLF.

Следующий шаг:

- Этап 7.3 — наследование `DataContext` по logical tree и типобезопасные accessors.

### 2026-11-26 — этап 7.1, жизненный цикл bindings

Сделано:

- Зафиксировано поведение `BindingSubscription.cancel()`: listener отключается, последнее синхронизированное значение сохраняется как local, повторная отмена безопасна.
- `BindingSubscription` предоставляет property, mode, isCancelled и диагностический `toString()`.
- Добавлен идемпотентный `PropertyOwner.dispose()` с сохранением значений и запретом дальнейших `bind()`/`setValue()`; `ItemsControl.dispose()` теперь также освобождает property subscriptions.
- Two-way writes подавляют reentrant callbacks, не записывают неизменившееся значение, публикуют одно property change и синхронизируются даже если `CallbackBinding.write()` сам не уведомляет listeners.
- Добавлен `BindingException` с property, operation и cause. Initial read нового binding выполняется до отмены прежнего, поэтому ошибка не разрушает рабочую привязку. Read-only source отклоняется для two-way до attach.
- Добавлены 9 binding-тестов и 1 интеграционный тест dispose в ItemsControl. C ABI и native C++ не изменялись.

Проверено:

- `dart analyze` — без замечаний.
- `dart test --name '^(?!.*clipboard).*$'` — 190 тестов проходят, включая 13 binding-тестов и 17 ItemsControl/virtualization-тестов.
- `git diff --check` — без ошибок.

Следующий шаг:

- Этап 7.2: зафиксировать приоритеты значений и добавить их без изменения cancel/dispose semantics.

### 2026-11-26 — этап 6, коллекции и виртуализация

Сделано:

- Добавлены `ObservableCollection<T>`, `CollectionChangedEvent<T>`, `CollectionChangeAction` и `CollectionSubscription`: точечные add/insert/remove/replace/move/reset, snapshot listeners, cancellation и строгий dispose.
- Добавлены `ItemsControl<T>`, `ItemTemplate<T>`, `ItemKeySelector<T>` и `VirtualizingStackPanel<T>` с публичными exports. Поддерживаются persistent keyed identity, `dataContext`, lifecycle удаляемых элементов и смена источника.
- Виртуализация использует viewport непосредственного `ScrollViewer`, видимый диапазон с buffer, estimated extent и измеренные переменные высоты. Повторный layout и move сохраняют подходящие существующие элементы; recycling очищает focus и не переносит selection в новый контейнер.
- Добавлены 16 тестов: события/подписки/dispose коллекции, точечные изменения без пересоздания siblings, keyed move/reset, focus/unmount, смена source, 100 000 элементов, прокрутка к середине/концу, bounds, variable heights и recycling.
- Добавлен `example/native_items_control.dart`: 100 000 строк фиксированной высоты 24, интерактивный `ScrollViewer`, `--smoke --diagnostics`, проверки начала/середины/конца и 3 автоматических кадра.
- C ABI и native C++ не изменялись.

Проверено:

- `dart analyze` — без замечаний.
- `dart test --name '^(?!.*clipboard).*$'` — 180 тестов проходят; два известных Windows clipboard-сценария исключены.
- `dart run example/native_items_control.dart --smoke --diagnostics` — успешно, конечный viewport содержит 16 контейнеров, extent=2 400 000, 3 кадра.
- Предупреждение `SkIcuLoader` о копии `icudtl.dat` рядом с Dart executable остаётся известным и не влияет на результат; native backend использует копию рядом с `dui_native.dll`.
- Пользователь вручную проверил интерактивный пример и подтвердил корректную работу.

Не проверено:

- Поведение на Linux/macOS и на нескольких display scales.
- Для переменной высоты estimate уточняется по мере измерения; offset может требовать последующего layout pass, поэтому native smoke намеренно использует фиксированную высоту строк.

Следующий шаг на момент записи:

- Этап 7.1 — строгий lifecycle bindings; впоследствии выполнен.

### 2026-11-26 — этап 5.4, ScrollViewer

Сделано:

- Добавлены `ScrollViewer` и `ScrollBarVisibility { disabled, hidden, auto, visible }`. Content измеряется с бесконечным constraint по разрешённым осям; viewport, extent, offsets и видимость Auto scrollbars пересчитываются с учётом перекрёстного влияния полос.
- Реализованы программная прокрутка, mouse wheel с scroll chaining, клавиши arrows/PageUp/PageDown/Home/End через bubbling от focused descendants, page click по track и thumb dragging с pointer capture.
- Исправлено падение при перетаскивании thumb перед началом track: вычисленный drag offset ограничивается нулём до вызова validating `scrollTo()`. Регрессионный сценарий проверяет обе оси на нижней и верхней границах.
- Исправлено отсутствие визуальной прокрутки во вложенном примере: `UIElement.invalidateArrange()` теперь инвалидирует родительскую цепочку, поэтому закэшированный DockPanel повторно вызывает arrange детей. Регрессионный тест подтверждает не только offset, но и фактические content bounds.
- Render помещает content в viewport clip, hit test отклоняет content вне viewport и направляет scrollbar input в `ScrollViewer`. Изменение offsets инвалидирует arrange и публикует property notifications.
- В routed events добавлен `mouseWheel`; SDL `SDL_EVENT_MOUSE_WHEEL` передаёт позицию и обе delta через существующий `DuiEvent` без изменения его layout. Native key mapping дополнен arrows и PageUp/PageDown.
- Добавлены `example/native_scroll_viewer.dart` с типовым окном настроек и 11 тестов `test/scroll_viewer_test.dart`: viewport/extent, visibility modes, offsets, wheel, keyboard, clipping, hit testing, thumb drag, track click и shrink.
- Пример расширен до критерия готовности этапа 5: корневой DockPanel с header/footer, ScrollViewer как fill, секции на DockPanel и Auto/Star Grid, действия обновляют bound status. Абсолютное позиционирование не используется; добавлен `EdgeInsets.only()`.

Проверено:

- `dart format` и `dart analyze` — без замечаний.
- Все 11 ScrollViewer-тестов проходят. Общий прогон с исключением двух clipboard-сценариев — все 164 теста проходят.
- Native library успешно пересобрана через CMake/Ninja/Clang; SkParagraph smoke проходит.
- `dart run example/native_scroll_viewer.dart --smoke --diagnostics` — успешно, 3 кадра; проверены DockPanel regions, двунаправленный wheel, PageDown из TextBox, footer Button и соответствие фактических content bounds текущим offsets.
- `git diff --check` — успешно, только известные LF→CRLF warnings.

Не проверено / ограничение:

- Реальные SDL wheel и ручное перетаскивание thumbs ещё не подтверждены пользователем; native smoke использует Dart dispatch и проверяет реальное native render/present. Известный Windows clipboard-сбой не исправлялся.

Следующий шаг:

- Ручная проверка ScrollViewer; затем стабилизация Windows clipboard согласно порядку ближайших задач.

### 2026-11-26 — этап 5.3, RowSpan и ColumnSpan

Сделано:

- Добавлены attached `Grid.rowSpanProperty` и `Grid.columnSpanProperty` со статическими getters/setters. Значения по умолчанию равны 1; значения меньше 1, выход начальной ячейки или всего диапазона за definitions отклоняются.
- Spanning-children измеряются отдельно от одиночных по объединённым tracks и промежуточным gaps. Дефицит равномерно распределяется между Auto-tracks диапазона; при бесконечном constraint без Auto используются Star-tracks. После роста Auto конечные Star-доли пересчитываются.
- Arrange объединяет уже HiDPI-округлённые границы первого и последнего track, включая промежуточные gaps. Повторный measure сохраняет wrapping и учёт объединённой ширины столбцов.
- Добавлены 8 тестов `test/grid_test.dart`: ColumnSpan/RowSpan с gaps, рост Auto и invalidation, перерасчёт Star, бесконечные Star constraints, HiDPI 1.25 и validation.

Проверено:

- `dart format` и `dart analyze` — без замечаний.
- Все 18 Grid-тестов проходят. Общий прогон с исключением двух clipboard-сценариев — все 153 теста проходят.
- `git diff --check` — успешно, только известные LF→CRLF warnings.

Не проверено / ограничение:

- Распределение дефицита между tracks остаётся упрощённым. Отдельный визуальный пример не добавлялся; C++ и native ABI не менялись.

Следующий шаг:

- Стабилизация Windows clipboard согласно порядку ближайших задач, затем ScrollViewer.

### 2026-11-26 — этап 5.3, базовый Grid

Сделано:

- Добавлены `GridLength` (`Auto`, validated `Pixel`, weighted `Star`), `RowDefinition`, `ColumnDefinition` и наблюдаемые definition lists. Изменение длины или состава definitions инвалидирует measure Grid.
- `Grid` получил attached `row`/`column`, `rowSpacing`/`columnSpacing`, render/hit-testing детей и exports. Пустые definitions создают одну Star-строку и столбец; отрицательные индексы и выход за definitions отклоняются.
- Auto и Pixel измеряются до Star; при конечном размере Star делит остаток по весам, при бесконечном — измеряется по содержимому. Строки измеряются с фактически разрешёнными ширинами столбцов, включая повторный measure для wrapping.
- Arrange пересчитывает Star под фактический rect и округляет начала/концы tracks к физическим пикселям через `displayScale`, избегая накопления дробных ошибок и щелей.
- Добавлены 10 тестов `test/grid_test.dart`: defaults, Auto/Pixel/Star, weights/gaps, infinite constraints, wrapping measure, definition/attached invalidation, invisible children, HiDPI 1.25 и invalid arguments.

Проверено:

- `dart format` и `dart analyze` — без замечаний.
- Все 10 Grid-тестов проходят. Общий прогон с исключением двух clipboard-сценариев — все 145 тестов проходят.
- `git diff --check` — успешно, только известные LF→CRLF warnings.

Не проверено / ограничение:

- RowSpan/ColumnSpan не реализованы и остаются открытым пунктом этапа 5.3. Отдельный визуальный пример не добавлялся; C++ и native ABI не менялись.

Следующий шаг:

- Grid RowSpan/ColumnSpan после стабилизации Windows clipboard согласно порядку ближайших задач, затем ScrollViewer.

### 2026-11-26 — этап 5.2, DockPanel

Сделано:

- Добавлены `Dock { left, top, right, bottom }` и `DockPanel` с attached `dockProperty`, статическими `getDock()`/`setDock()` и `lastChildFill = true` по умолчанию. Изменения attached property и `lastChildFill` инвалидируют measure.
- Measure последовательно передаёт remaining constraints, учитывает невидимые дети и возвращает конечный desired size при бесконечной поперечной оси. Arrange распределяет left/top/right/bottom и отдаёт оставшийся rect последнему видимому ребёнку при включённом fill.
- Размеры docked slots включают margin; существующие alignment и min/max применяются внутри slot. Oversized children не создают отрицательное remaining space.
- Добавлены render/hit-testing детей, exports в `dui.dart` и compatibility barrel. Создано 7 координатных тестов `test/dock_panel_test.dart`.

Проверено:

- `dart format` и `dart analyze` — без замечаний.
- Все 7 DockPanel-тестов проходят. Общий прогон с исключением двух clipboard-сценариев — все 135 тестов проходят.

Не проверено / ограничение:

- Отдельный визуальный пример не добавлялся; поведение проверено measure/arrange координатами. C++ и native ABI не менялись, native smoke для этого Dart-only шага не запускался.

Следующий шаг:

- Стабилизация Windows clipboard, затем этап 5.3 (Grid).

### 2026-11-26 — FPS overlay для diagnostics

Сделано:

- При `diagnosticsEnabled` (`--diagnostics` во всех native-примерах) `SdlSkiaHost` рисует поверх дерева контролов полупрозрачную плашку `N.N FPS` в правом верхнем углу. До первого измерения отображается `0.0 FPS`.
- FPS вычисляется по монотонному `Stopwatch` и числу фактических present за интервалы не менее 500 мс. Таймер и принудительные invalidate не добавлены: в idle overlay не создаёт дополнительные кадры и сохраняет последнее измеренное значение до следующего present.
- `NativeWindowDiagnostics` получил nullable `framesPerSecond` и включает FPS в строковое представление.
- Добавлена integration-регрессия: отсутствие invalidate не увеличивает present и не обновляет FPS, а отложенный реальный кадр даёт положительное измерение.

Проверено:

- `dart format` и `dart analyze` — без замечаний.
- Целевые diagnostics contract/FPS-тесты проходят. Общий прогон с исключением двух clipboard-сценариев — все 128 тестов проходят.
- `dart run example/native_smoke.dart --diagnostics` — успешно, 3 event iterations и 1 кадр, counters 1/1/1/1.
- Пользователь вручную подтвердил отображение и работу FPS overlay.

Не проверено / ограничение:

- Значение обновляется только на кадрах, поэтому после прекращения рендеринга остаётся последний семпл, а не принудительно сбрасывается в ноль.
- Общий `python tools/bootstrap_native.py --smoke --diagnostics` остановлен на GN из-за отсутствующей переменной окружения `ProgramFiles(x86)`; C++ не менялся, тот же smoke успешно запущен напрямую через Dart.

Следующий шаг:

- Этап 5.2 (DockPanel) после подтверждения diagnostics; этап завершён следующей записью.

### 2026-11-26 — синхронный render во время live resize

Сделано:

- Причина чёрного окна при перетаскивании: модальный resize Windows не возвращает управление обычному Dart event loop до отпускания мыши. Добавлен SDL event watch, который обрабатывает `SDL_EVENT_WINDOW_RESIZED` и live `SDL_EVENT_WINDOW_EXPOSED` непосредственно во время изменения размера.
- C ABI получил `DuiLiveResizeCallback`, `dui_host_set_live_resize_callback()` и `dui_window_set_size()`. Callback вызывается только на host thread, защищён от рекурсии, а обычное queued resize-событие сохраняется.
- `SdlSkiaHost` регистрирует `NativeCallable.isolateLocal`, обновляет logical size и немедленно выполняет render/present. Ошибки Dart перехватываются внутри callback и повторно выбрасываются при возврате в `pumpEvents`, `waitForEvent` или `presentWindow`; native callable корректно закрывается при dispose.
- При maximize обнаружены ещё две причины чёрной области: `RESIZED` может прийти до фактического изменения backbuffer, а сохранённый SDL renderer viewport/clip способен обрезать новый кадр. Event watch дополнительно обрабатывает `SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED`; logical size для pixel-size/expose берётся через `SDL_GetWindowSize`, а viewport и clip rect сбрасываются перед каждым present.
- `Window.resize()` игнорирует неизменённый размер, поэтому последующее queued событие не создаёт лишний кадр.
- Исправлено несоответствие const в объявлении `dui_window_text_input_active`, из-за которого обновлённая DLL не экспортировала этот существующий символ.
- Интеграционный тест расширен: синхронный Dart callback выполняет `beginFrame/present` до возврата из native `SDL_SetWindowSize`, получает logical size 240×120 и подтверждает увеличение physical backbuffer.

Проверено:

- Native library пересобрана через существующий CMake/Ninja build; `python tools/bootstrap_native.py --check` с явно добавленными tool paths проходит.
- `dart format` и `dart analyze` — без замечаний.
- Целевой `live resize callback`-тест проходит. `dart test --name '^(?!.*clipboard).*$'` — все 128 тестов проходят, включая расширенный resize-тест.
- Два полных `dart test` до первоначального исправления maximize дошли до 128 успешных тестов и остановились только на известном Windows clipboard `Couldn't open clipboard`; ошибка воспроизвелась дважды и оставлена открытой.
- Базовый native smoke — успешно, 3 event iterations. Text gallery smoke — успешно, 3 iterations и 1 кадр; TextBox smoke — успешно, 3 кадра, counters 4/6/4/4.
- Пользователь подтвердил корректный непрерывный resize перетаскиванием границы и maximize двойным щелчком по рамке: вся раскрытая область сразу заполняется UI без чёрных полос.

Не проверено / ограничение:

- Callback работает только на host thread по зафиксированному ABI threading contract; Linux/macOS не запускались.

Следующий шаг:

- Стабилизация Windows clipboard, после этого этап 5.2.

### 2026-11-26 — этап 5.1, layout constraints и alignment

Сделано:

- В `UIElement` добавлены `minWidth`/`maxWidth`, `minHeight`/`maxHeight`, `margin`, `horizontalAlignment` и `verticalAlignment`; значения проверяются, изменения constraints/margin вызывают invalidate measure, а alignment — invalidate arrange.
- Разделены `desiredSize` (включая margin), `arrangedSize` (выделенный слот) и `bounds` (фактический прямоугольник после margin и выравнивания). Поддержаны left/top, center, right/bottom и stretch; stretch остаётся поведением по умолчанию.
- Measure cache теперь зависит от `availableSize`; нарушения диапазонов, NaN и бесконечный arrange rect отклоняются. Минимальный desired size может превышать доступный размер, но arrange ограничивает фактические bounds слотом.
- `StackPanel` передаёт бесконечность по главной оси при measure. `Label` при drawing использует layout для фактической ширины bounds.
- Для `Point`, `Rect` и `EdgeInsets` добавлены value equality/hashCode. Добавлено 11 тестов `test/layout_constraints_test.dart` на constraints, margin, alignment, cache invalidation и infinite text width.
- Подтверждено, что существующий native backend уже принимает `maxWidth = double.infinity`; C ABI/C++ не менялись.

Проверено:

- `dart format` и `dart analyze` — без замечаний.
- Полный `dart test` — все 128 тестов проходят, включая native infinite-width layout.
- `git diff --check` — успешно.

Не проверено / ограничение:

- `python tools/bootstrap_native.py --check` остановлен: в `PATH` отсутствуют `cmake` и `ninja`. Native-код не менялся, существующая native library использована полным тестовым набором.
- Новых визуальных smoke-примеров для constraints не добавлено; поведение проверено координатными unit/integration-тестами. Linux/macOS и ручной визуальный контроль не выполнялись.

Следующий шаг:

- Этап 5.2: DockPanel, attached `Dock` и last-child-fill.

### 2026-11-25 — переименование TextBlock в Label

Сделано:

- Readonly-текстовый контрол полностью переименован из `TextBlock` в `Label`, чтобы явно отличать его от редактируемого `TextBox`.
- `lib/src/text_block.dart` переименован в `lib/src/label.dart`, тест — в `test/label_layout_test.dart`; exports, bindings, примеры и все тесты используют `Label`.
- Compatibility alias специально не сохранён: публичный API содержит только однозначное имя `Label`.
- Текущие разделы плана обновлены; прежние записи журнала сохранены как историческая терминология соответствующих этапов.

Проверено:

- Поиск по Dart-коду не находит `TextBlock` или `text_block`.
- `dart format`, `dart analyze` — без замечаний.
- Полный `dart test` — все 117 тестов проходят.

Следующий шаг:

- Этап 5.1: min/max constraints, margin, alignment и infinite constraints native text layout.

### 2026-11-25 — этап 4.3, профилирование и кэширование

Сделано:

- Добавлен `example/native_frame_benchmark.dart`: после 1 с idle выполняет 60 периодических async updates, измеряет invalidate→present latency и counters. На Windows process CPU читается через `GetProcessTimes`; на других ОС CPU сообщается как unsupported.
- Подтверждено существующее кэширование `TextLayout` в `TextBlock` и `TextBox`: полный `TextLayoutOptions`, identity factory, повторное использование и disposal при замене/unmount уже реализованы и покрыты тестами.
- По результатам замеров не добавлены paths/paints cache, damage rectangles или retained GPU scene graph. C ABI/C++ и scheduler не менялись.

Проверено:

- `dart format example/native_frame_benchmark.dart` и `dart analyze` — без замечаний.
- Полный `dart test` — все 117 тестов проходят, включая clipboard.
- Первый benchmark: idle wall 1013.5 мс, process CPU 15.6 мс (1.54%); counters 2/2/2/2. Выполнено 60 updates за 60 кадров; latency average 15.48 мс, median 16.49 мс, max 16.98 мс. Итоговые counters 62/62/62/62; общий process CPU 7.70%.
- Повторный benchmark: idle wall 1018.4 мс, process CPU 15.6 мс (1.53%); те же counters. Latency average 12.05 мс, median 16.28 мс, max 17.10 мс; общий process CPU 7.71%.
- `git diff --check` — успешно.

Ограничения:

- CPU измерен только для benchmark-процесса на Windows, без системного профилирования и энергопотребления. Физический ввод, Linux и macOS не проверялись; async latency не равна измеренной задержке аппаратного ввода.
- Предел wait 16 мс остаётся сознательным компромиссом для Dart timers; дальнейшая event-driven интеграция отложена как P2.

Следующий шаг:

- Этап 5.1: min/max constraints, margin, alignment и infinite constraints native text layout.

### 2026-11-25 — этап 4.2, централизованный scheduler

Сделано:

- Добавлен `lib/src/frame_scheduler.dart`: повторные invalidate объединяются, scheduled counter и wake-up callback срабатывают один раз на ожидающий кадр. `tryBeginFrame()` снимает запрос до layout/paint, поэтому invalidate во время paint сохраняется для следующего кадра.
- `Window.updateLayout()` централизует measure/arrange для rendering и pointer hit-testing; guard запрещает рекурсивный layout и восстанавливается через `finally`. `renderFrame()` отдельно выполняет layout и paint passes и ничего не делает без scheduled frame.
- Добавлены counters `scheduledFrameCount`, `layoutPassCount`, `paintPassCount`; `NativeWindowDiagnostics` выводит `scheduled/layout/painted/presented`, сохраняя `renderFrameCount` как alias painted.
- Добавлены C ABI `dui_host_wake_up`, SDL user event через `SDL_PushEvent()`, Dart typedef/lookup/bindings и `SdlSkiaHost` frame request handler с отсоединением при close.
- `waitForEvent()` по умолчанию ограничен 16 мс, чтобы вернуть управление Dart timers; он не ждёт, если кадр уже запланирован. Интерактивные примеры дополнительно уступают event loop через `await Future.delayed(Duration.zero)` без периодического render.
- Добавлены 3 scheduler unit-теста и native async integration-тест `Timer → invalidate → один кадр`; null wake-up проверен в ABI-тесте. Исправлено сохранение прежнего headless pointer hit-testing для невидимого окна.

Проверено:

- `dart format` и `dart analyze` — без замечаний.
- Native library пересобрана после изменения C ABI/C++; Paragraph smoke `width=124.945, height=21`.
- Полный `dart test` — все 117 тестов проходят, включая Windows clipboard и async scheduler.
- Базовый native smoke — успешно: 3 event iterations, 2 кадра; scheduled=2, layout=2, painted=2, presented=2.
- Text gallery smoke — успешно: 3 event iterations, 2 кадра; scheduled=2, layout=2, painted=2, presented=2.
- TextBox native smoke — успешно: 3 кадра; scheduled=4, layout=6, painted=4, presented=4. Дополнительные layout passes принадлежат pointer hit-testing.

Не проверено / ограничение:

- Ручной idle CPU/input latency, физический ввод, Linux и macOS не проверялись.
- Ограниченный 16 мс wait обслуживает Dart timers, но не является полностью event-driven async integration; оценить необходимость дальнейшей оптимизации при профилировании 4.3.

Следующий шаг:

- Этап 4.3: профилирование и кэширование только по результатам измерений.

### 2026-11-25 — этап 4.1, render on demand

Сделано:

- `SdlSkiaHost.presentWindow()` пропускает render/present для закрытого, невидимого и не имеющего scheduled frame окна. После invalidate выполняется один новый кадр; SDL expose/resize по-прежнему могут запланировать кадр.
- Добавлены C ABI `dui_host_wait_event`, общий C++ `translate_event()` для poll/wait и блокирующий `SDL_WaitEventTimeout()` с `timeout_ms == -1`.
- Dart FFI получил typedef, lookup, `NativeBindings.hostWaitEvent`, `waitEvent()` и общий `_decodeEvent()`; `SdlSkiaHost.waitForEvent()` диспетчеризует полученное событие.
- Интерактивные циклы counter, text gallery и TextBox ждут SDL-событие вместо polling с задержкой 8 мс. SDL renderer включает VSync через `SDL_SetRenderVSync(renderer, 1)` и отклоняет создание окна при ошибке.
- Добавлены ABI-проверка `hostWaitEvent()` с null и integration-тест counters: 1/1 после show и повторных unchanged present, затем 2/2 после изменения текста и снова 2/2 без invalidate.
- Smoke-сообщения базового примера и gallery разделяют event iterations и фактически rendered frames.

Проверено:

- `dart format` и `dart analyze` — без замечаний.
- Native library пересобрана после изменения C ABI/C++; Paragraph smoke `width=124.945, height=21`.
- Полный `dart test` — все 113 тестов проходят, включая новый render-on-demand и Windows clipboard.
- Базовый native smoke — успешно: 3 event iterations, 2 кадра; scale 2.0, logical 320×200, physical 640×400, renderFrame=2, present=2.
- TextBox native smoke — успешно: 3 кадра; logical 760×590, physical 1520×1180, renderFrame=4, present=4.
- Text gallery native smoke — успешно: 3 event iterations, 2 кадра; logical 960×800, physical 1920×1600, renderFrame=2, present=2.

Не проверено / ограничение:

- Ручной замер idle CPU, физический ввод, Linux и macOS не проверялись.
- Блокирующий wait реагирует на SDL events, но программный Dart invalidate из async callback сам по себе SDL event queue не пробуждает; wake-up остаётся частью scheduler-модели 4.2.

Следующий шаг:

- Этап 4.2: централизованный scheduler и wake-up для программных invalidate.

### 2026-11-25 — этап 3.3, keyboard activation

Сделано:

- `Button` обрабатывает routed Space/Enter, вызывает click handlers один раз на событие и устанавливает `handled`; вложенный parent Button не активируется повторно. Disabled Button и Ctrl/Cmd-модифицированные комбинации игнорируются.
- `KeyEventArgs` и `Window.dispatchKeyDown()` получили `physicalKeyCode` и `logicalKeyCode`; программные вызовы без кодов сохраняют прежнюю совместимость через значение 0.
- В `DuiEvent` добавлен `scan_code`: C++ передаёт SDL scancode, Dart FFI читает его в `NativeEvent.scanCode`, а `SdlSkiaHost` передаёт оба кода в key event. `key_code` остаётся layout-dependent logical key.
- SDL Space и Enter отображаются в имена `space`/`enter`; размер `DuiEvent` увеличен с 72 до 80 байт с учётом выравнивания.
- Добавлены 4 теста `test/button_keyboard_test.dart`; `example/native_smoke.dart` теперь проверяет Enter и Space у реального native Button.

Проверено:

- `dart format` и `dart analyze` — без замечаний.
- Native library пересобрана после изменения C ABI; `sizeOf<DuiEventStruct>() == 80`.
- Полный `dart test` после пересборки — все 112 тестов проходят, включая clipboard.
- Базовый native smoke — успешно: Button активирован по Enter и Space, 3 кадра, 4 renderFrame и 4 present при scale 2.0.
- TextBox native smoke — успешно: 3 кадра, 4 renderFrame и 4 present; Paragraph smoke `width=124.945, height=21`.

Не проверено:

- Физическая клавиатура и реальные SDL key events вручную, Linux и macOS; key identity и активация проверены программной dispatch-последовательностью.

Следующий шаг:

- Этап 4: render on demand.

### 2026-11-25 — видимое focus-состояние контролов

Сделано:

- Добавлен общий `drawFocusRing()` в `lib/src/focus_decoration.dart`: четыре rectangle-команды рисуют двухпиксельную рамку внутри bounds без расширения layout и clipping наружу.
- `Button` и `TextBox` рисуют рамку только при `isFocused`; существующие pressed background, caret, selection и composition сохранены.
- Добавлены 2 теста `test/focus_rendering_test.dart` на появление/исчезновение рамки, точную геометрию Button и совместимость с caret/disable у TextBox.
- C ABI и C++ не изменялись.

Проверено:

- `dart format` и `dart analyze` — без замечаний.
- Полный `dart test` — все 108 тестов проходят, включая clipboard.
- Полный bootstrap с `--textbox --smoke --diagnostics` — успешно: Paragraph smoke `width=124.945, height=21`; TextBox smoke 3 кадра, 4 renderFrame и 4 present при scale 2.0.

Не проверено:

- Ручной визуальный контроль контраста и рамки на физической клавиатуре, Linux и macOS.

Следующий шаг:

- Этап 3.3: keyboard activation и physical/logical key.

### 2026-11-25 — этап 3.2, Tab traversal

Сделано:

- `FocusManager.moveFocus()` обходит logical tree в прямом порядке с wrap-around; без focused control Tab выбирает первый, Shift+Tab — последний доступный контрол.
- Non-focusable, disabled и невидимые контролы и ветви пропускаются. Используется существующий `Control.isFocusable`; `tabIndex` не добавлен.
- `UIElement.isFocusScope` ограничивает обход ближайшей областью focused control; поддержаны вложенные scope.
- `Window.dispatchKeyDown()` сначала маршрутизирует событие, затем запускает Tab traversal только для необработанного Tab без Ctrl/Cmd. SDL `SDLK_TAB` отображается в `tab`.
- Добавлены 7 тестов `test/focus_traversal_test.dart`; native TextBox smoke проверяет прямой, обратный и циклический переход между тремя полями.
- C ABI и C++ не изменялись.

Проверено:

- `dart format lib example/native_textbox.dart test/focus_traversal_test.dart` и `dart analyze` — без замечаний.
- Первый полный `dart test` завершился известным сбоем Windows clipboard cleanup; отдельный clipboard-тест и повторный полный прогон прошли — все 106 тестов.
- Полный bootstrap с `--textbox --smoke --diagnostics` — успешно: Paragraph smoke `width=124.945, height=21`; TextBox smoke 3 кадра, 4 renderFrame и 4 present при scale 2.0.

Не проверено:

- Физическая клавиатура вручную, Linux и macOS; native smoke использует программную key dispatch-последовательность.

Следующий шаг:

- Этап 3.3: keyboard activation и physical/logical key.

### 2026-11-25 — этап 3.1, FocusManager

Сделано:

- Focus вынесен из `Window` в `FocusManager` без изменения публичного API фокусировки контролов.
- Проверяются mount state, принадлежность окну, `isFocusable`, видимость и доступность контрола и всех его родителей.
- Unmount, disable и hide очищают focus; неявного восстановления после remount/show/enable нет, требуется явный `focus()`.
- Очистка focus при unmount выполняется до `onUnmounted()` и однократно завершает SDL text input.
- Добавлены 5 тестов `test/focus_manager_test.dart` на переключение focus, ограничения и lifecycle.

Проверено:

- `dart format lib test/focus_manager_test.dart` и `dart analyze` — без замечаний.
- Полный `dart test` — все 99 тестов проходят, включая clipboard и существующие text input lifecycle/integration tests.
- Полный bootstrap с `--textbox --smoke --diagnostics` — успешно: Paragraph smoke `width=124.945, height=21`; TextBox smoke 3 кадра, 4 renderFrame и 4 present при scale 2.0.

Не проверено:

- Ручная клавиатурная навигация и поведение на Linux/macOS; этот шаг проверен автоматическими тестами и native smoke на Windows.

Следующий шаг:

- Этап 3.2: Tab traversal по logical tree.

### 2026-11-25 — clipping и видимые selection/caret в TextBox

Сделано:

- `DrawingContext` получил `pushClipRect()`/`popClip()`; добавлены recording-команды и реализация в `NativeDrawingContext`.
- В C ABI/C++/Dart FFI добавлены `dui_window_push_clip_rect` и `dui_window_pop_clip` с проверками active frame и аргументов; native backend использует Skia save/clipRect/restore.
- `TextBox` ограничивает текст и decorations content clip с padding. Обычный selection рисуется через `TextLayout.selectionRects()` до текста.
- Focused `TextBox` с collapsed selection рисует caret через `TextLayout.caretRect()` после текста; при IME composition обычный caret не дублируется. Clip восстанавливается через `finally`.
- Добавлены 5 тестов `test/text_box_rendering_test.dart` и native ABI-проверки null/active clip. Smoke отдельно рисует composition, обычный selection и caret, сохраняя 3 кадра.
- Подсказка `example/native_textbox.dart` обновлена.

Проверено:

- `dart format lib example test` и `dart analyze` — без замечаний.
- Native library пересобрана после C ABI/C++ изменений; новые clip ABI и render-тесты проходят.
- Полный `dart test` — 88 из 89 тестов проходят. Clipboard round-trip успешен, но восстановление пустого прежнего значения падает с `Couldn't open clipboard`; отдельный запуск и дополнительные retry cleanup не помогли, retry-изменение откачено.
- Полный bootstrap с `--textbox --smoke --diagnostics` — успешно: Paragraph smoke `width=124.945, height=21`; TextBox smoke 3 кадра, 4 renderFrame и 4 present при scale 2.0.

Не проверено:

- Ручной визуальный контроль clipping/selection/caret и Linux/macOS. Caret пока статический, без blink timer.

Следующий шаг:

- Отдельно стабилизировать восстановление пустого Windows clipboard, затем перейти к этапу 3.

### 2026-11-25 — этап 2.5, mouse interaction

Сделано:

- Добавлены bubble `UIElement.pointerMove`, `Window.dispatchPointerMove()` и маршрутизация SDL `DUI_EVENT_POINTER_MOVE`; SDL mouse buttons преобразуются в `PointerButton`.
- `Window` поддерживает backend-independent pointer capture/release: move/up направляются захваченному контролу даже за его границами; primary up автоматически освобождает capture.
- Primary click в `TextBox` получает UTF-16 offset через `TextLayout.hitTest()`, устанавливает caret и начинает selection drag с сохранением anchor. Hit test не оставляет caret внутри surrogate pair.
- Pointer capture освобождается при primary up, focus loss и unmount; клик очищает composition без изменения подтверждённого текста.
- Добавлены 8 тестов `test/text_mouse_interaction_test.dart`; TextBox smoke теперь проверяет native hit test, captured drag за пределами поля и установку caret кликом.
- C ABI и C++ не изменялись.

Проверено:

- `dart format lib example test` — изменений после форматирования нет; `dart analyze` — без замечаний.
- `dart test` — все 84 теста проходят, включая clipboard ABI-тест.
- Полный bootstrap с `--textbox --smoke --diagnostics` — успешно: Paragraph smoke `width=124.945, height=21`; TextBox smoke 3 кадра, 4 renderFrame и 4 present при scale 2.0.

Не реализовано / не проверено:

- Двойной клик для выделения слова отложен как необязательная часть этапа.
- Обычные visual selection/caret и clipping длинного текста остаются открытыми дефектами.
- Физическая мышь в интерактивном примере вручную, Linux и macOS не проверялись; native smoke использует программную dispatch-последовательность.

Следующий шаг:

- Исправить clipping текста и добавить видимые обычные selection/caret в `TextBox`.

### 2026-11-25 — этап 2.4, IME composition

Сделано:

- `SDL_EVENT_TEXT_EDITING` добавлен в C ABI, Dart FFI и SDL host; composition start/length преобразуются из UTF-8 byte offsets в UTF-16, `DuiEvent` увеличен до 72 байт.
- Добавлены `TextEditingEventArgs`, bubble-событие `UIElement.textEditing` и маршрутизация через `Window.dispatchTextEditing()` в focused control.
- `TextBox` хранит composition text/range отдельно от подтверждённого `TextBuffer`; composition рисуется через кэшированный `TextLayout` с подчёркиванием и подсветкой активного range.
- До подтверждения `text`, `TextBuffer` и two-way binding не изменяются; commit через text input использует обычную вставку/замену selection. Пустой editing event, focus loss, unmount и распознанные editing commands очищают composition.
- Добавлены `test/text_composition_test.dart` с пятью тестами и composition-кадр в TextBox smoke; обновлён ABI layout test.

Проверено:

- `dart format lib example test` и `dart analyze` — без замечаний.
- `dart test` — все 76 тестов проходят, включая ранее нестабильный clipboard ABI-тест.
- Native library пересобрана после изменения C ABI.
- Полный bootstrap с `--textbox --smoke --diagnostics` — успешно: Paragraph smoke `width=124.945, height=21`; TextBox smoke рисует 3 кадра, подтверждает `Smoke か😀`, 4 renderFrame и 4 present при scale 2.0.

Не работает / не проверено:

- Реальные системные IME для русского, китайского/японского ввода и emoji вручную не проверялись; Linux и macOS не проверялись.
- Длинный текст по-прежнему может рисоваться за границами `TextBox`; обычные visual selection/caret пока не видны.
- Ранее наблюдавшийся сбой восстановления пустого Windows clipboard в последнем полном запуске не воспроизвёлся; отдельная стабилизация cleanup не выполнялась.

Следующий шаг:

- Этап 2.5: mouse selection и caret positioning через `TextLayout`.

### 2026-11-25 — пример для проверки TextBox

Сделано:

- Добавлен `example/native_textbox.dart`: bound editor с live preview, Unicode и пустое поле, подсказки клавиатурных и clipboard-команд.
- `TextBox` получает focus по pointer down, поэтому кликом можно переключаться между полями; caret positioning по тексту не добавлялся.
- В bootstrap добавлены `--textbox` и совместимый `--smoke`; smoke проверяет Select All, ввод, Home, Shift+Right и two-way binding.
- Добавлен unit-тест focus по клику.

Проверено:

- `dart analyze` — без замечаний.
- TextBox smoke напрямую и через `python tools/bootstrap_native.py --textbox --smoke --diagnostics` — успешно, 3 кадра, 4 renderFrame и 4 present.
- `python -m unittest test/bootstrap_native_test.py -v` — 2 теста проходят.
- Полный `dart test` — 70 из 71 тестов проходят; новый pointer-focus тест успешен.

Не работает / не проверено:

- Clipboard ABI-тест завершается ошибкой `Couldn't open clipboard` при восстановлении пустого прежнего значения после успешного round-trip; требуется отдельная стабилизация очистки/восстановления Windows clipboard.
- Ручной ввод с физической клавиатуры, clipboard через реальные shortcuts, IME и Linux/macOS.

Следующий шаг:

- Этап 2.4: IME composition; отдельно стабилизировать clipboard cleanup test.

### 2026-11-25 — этап 2.3, клавиатурные команды и clipboard

Сделано:

- `KeyEventArgs` и `Window.dispatchKeyDown()` передают Shift/Ctrl/Cmd; native `DuiEvent` получил modifiers, а SDL host маппит editing key codes в команды.
- `TextBuffer` поддерживает Left/Right, Home/End, Shift selection и Ctrl/Cmd word navigation без разрыва surrogate pairs; обычные стрелки сворачивают selection к краю.
- `TextBox` обрабатывает Backspace/Delete, Select All и Copy/Cut/Paste через routed key-down; Unicode-ввод остаётся на `SDL_EVENT_TEXT_INPUT`.
- Добавлен backend-independent `ClipboardHandler`; `SdlSkiaHost` назначает и очищает его вместе с text input lifecycle.
- В C ABI/C++/Dart FFI добавлены clipboard set/get/free; SDL-строка всегда освобождается, пустой clipboard не удаляет selection.
- Добавлены `test/text_editing_commands_test.dart` и реальный Unicode clipboard ABI-тест с восстановлением прежнего значения.

Проверено:

- `dart analyze` — без замечаний.
- `dart test` — все 70 тестов проходят.
- Native library пересобрана после C ABI изменений; `sizeOf<DuiEventStruct>() == 64`.
- Полный bootstrap, Paragraph smoke (`width=124.945, height=21`) и native smoke — успешно, 3 кадра, 4 renderFrame и 4 present.
- `git diff --check` — ошибок нет; предупреждения Git относятся только к будущей нормализации LF в CRLF.

Не проверено:

- Физическая клавиатура и системные IME вручную; OS key events не синтезировались. Word navigation не является grapheme-cluster/полным Unicode word-break алгоритмом.
- Linux и macOS.

Следующий шаг:

- Этап 2.4: IME composition и `SDL_EVENT_TEXT_EDITING`.

### 2026-11-25 — этап 2.2, SDL text input lifecycle

Сделано:

- В C ABI и Dart FFI добавлены Start/Stop, запрос активного состояния и SetTextInputArea.
- C++ вызывает `SDL_StartTextInput`, `SDL_StopTextInput`, `SDL_TextInputActive` и `SDL_SetTextInputArea`.
- Input area и cursor преобразуются из logical UI units в SDL window units через displayScale/pixelDensity.
- Добавлен backend-independent `TextInputHandler`; `WindowHost` маршрутизирует lifecycle без SDL/Skia типов в контролах.
- `TextBox` запускает ввод при focus, останавливает при потере focus/unmount и обновляет area/caret через `TextLayout` при layout, текстовых и selection изменениях.
- `SdlSkiaHost` закрывает UI и останавливает ввод до уничтожения native window; C++ destroy дополнительно останавливает активный text input.
- Добавлены fake-host lifecycle тесты, null ABI checks и реальные SDL integration tests.

Проверено:

- `dart analyze` — без замечаний.
- `dart test` — все 60 тестов проходят, включая 7 новых lifecycle/ABI проверок.
- Native library пересобрана после изменения C ABI.
- Полный bootstrap, Paragraph smoke и native smoke с diagnostics — успешно, 3 кадра.
- Windows: реальное SDL text input активируется при focus, деактивируется при смене focus и закрытии.

Не проверено:

- Ручная работа системных IME; composition events относятся к этапу 2.4.
- Linux и macOS.

Следующий шаг:

- Этап 2.3: клавиатурные команды редактирования и selection.

### 2026-11-25 — этап 2.1, модель текста и selection

Сделано:

- Добавлены независимые от rendering `TextBuffer` и `TextSelection` с `baseOffset`/`extentOffset` в UTF-16 code units.
- Реализованы вставка и замена selection, Backspace/Delete, move caret с расширением selection и Select All.
- Backspace/Delete не разрывают surrogate pair emoji; offsets проверяются, обратные explicit range отклоняются.
- Внешнее изменение текста ограничивает оба selection offsets новой длиной.
- `TextBox` использует `TextBuffer` через свойство `buffer` для text input, синхронизирует two-way binding и предоставляет команды редактирования вне render logic.
- Модель и файл названы по аналогии с GTK TextBuffer: `text_buffer.dart`; прежние имена `TextEditingController` и `editingController` удалены.
- Исправлено shadowing параметра `text` в callback buffer, которое препятствовало записи результата редактирования в binding.
- C ABI и C++ не изменялись.

Проверено:

- `dart analyze` — без замечаний.
- `dart test` — все 53 теста проходят, включая 12 новых тестов модели, Unicode deletion, диапазонов, routed input и binding integration.

Не реализовано в этом шаге:

- Клавиатурные key bindings, SDL text input lifecycle, IME, clipboard, mouse interaction и отрисовка caret/selection.
- Grapheme-cluster навигация: offsets и удаление работают на уровне UTF-16 code units/code points.

Следующий шаг:

- Этап 2.2: SDL text input lifecycle и обновление text input area.

### 2026-11-25 — этап 1.5, Unicode/HiDPI-матрица и text gallery

Сделано:

- Добавлены 10 native text layout тестов для ASCII, кириллицы, emoji, CJK, Arabic, Hebrew, multiline, пустой и очень длинной строки, а также масштабов 1.0, 1.25, 1.5 и 2.0.
- Проверяются конечные metrics, ограничение ширины, hit test, caret, selection и стабильность logical metrics между масштабами с допуском 0.51.
- Исправлена ширина пустой строки: вместо отрицательного sentinel `SkParagraph::getLongestLine()` теперь возвращается 0.
- В selection-проверках учтён небольшой glyph overhang tight boxes за advance width; ограничение ширины самого layout не ослаблено.
- Добавлены интерактивная `example/native_text_gallery.dart` и её автоматический трёхкадровый smoke-режим.
- В bootstrap добавлены команды `--text-gallery` и `--text-gallery --smoke`; прежние `--run` и `--smoke` сохранены.
- C ABI не изменялся; native library пересобрана после исправления C++ measurement.

Проверено:

- `dart analyze` — без замечаний.
- `dart test` — все 41 теста проходят.
- `python -m unittest test/bootstrap_native_test.py -v` — 2 теста проходят.
- Полный bootstrap с Paragraph smoke и `--text-gallery --smoke --diagnostics` — успешно: gallery рисует 3 кадра, displayScale 2.0, logical 960×800, physical 1920×1600, 4 renderFrame и 4 present.
- Исходный `native_smoke.dart` с собранной библиотекой — успешно, 3 кадра.

Не проверено:

- Ручной визуальный контроль clipping на мониторах с разными масштабами; автоматические metrics/geometry-тесты и smoke его не заменяют.
- Linux и macOS.

Следующий шаг:

- Этап 2: TextBox input/IME/selection/clipboard; отдельной задачей остаётся кроссплатформенная проверка этапа 1.2.

### 2026-11-25 — этап 1.4, TextBlock через TextLayout

Сделано:

- Добавлены `NativeTextLayoutFactory`/`NativeTextLayout` поверх C ABI и SkParagraph с идемпотентным disposal и проверками операций после dispose.
- Добавлены deterministic `HeadlessTextLayoutFactory`/`HeadlessTextLayout` для unit-тестов, включая measurement, hit test, caret и selection geometry.
- `WindowHost` предоставляет `TextLayoutFactory` и display scale; `SdlSkiaHost` подключает native factory к `Window`.
- `TextBlock` использует единый `TextLayout` для measurement и drawing, передаёт цвет только при paint и освобождает layout при замене или unmount.
- Cache key включает text, fontSize, maxWidth, scale, alignment и identity factory; неизменённые параметры и color не пересоздают layout.
- Исправлено обновление binding внутри `StackPanel`: `invalidateMeasure()` теперь распространяется вверх по retained-дереву.
- C ABI и C++ на этом этапе не изменялись.

Проверено:

- `dart analyze` — без замечаний.
- `dart test` — 31 тест проходит, включая cache reuse/invalidation, disposal, headless geometry, native TextBlock measurement/wrapping/drawing и обновление binding.
- `python -m unittest test/bootstrap_native_test.py -v` — 2 теста проходят.
- Paragraph smoke — успешно; native smoke с diagnostics и SkParagraph TextBlock — успешно, 4 renderFrame и 4 present.

Следующий шаг:

- Этап 1.5: расширить матрицу текстовых тестов и проверить разные displayScale.

### 2026-11-25 — этап 1.3, native text handles

Сделано:

- В C ABI добавлены opaque `DuiTextLayout` и операции create/destroy, measure, draw, hit test, caret rect и selection rects.
- Входной `DuiTextLayoutOptions` принимает UTF-8 text/font family с явными byte lengths; результаты возвращаются через caller-owned structs с `struct_size`.
- Selection rects используют двухфазный протокол count/fill без возврата указателей на временные C++-данные.
- Все новые C ABI entry points перехватывают C++ exceptions; ошибки доступны через `dui_last_error_message()`.
- Добавлены проверка UTF-8 и преобразование UTF-16 offsets в UTF-8 для caret/selection; hit test учитывает актуальное UTF-16 поведение SkParagraph editing API.
- Добавлены Dart FFI structs, typedefs, lookups и вызовы, включая scale-aware measurement/drawing.
- `TextBlock` намеренно не изменялся; его перевод относится к этапу 1.4.

Проверено:

- Полный bootstrap и пересборка `dui_native.dll` — успешно.
- `dart analyze` — без замечаний.
- `dart test` — 27 тестов проходят, включая ASCII, кириллицу, emoji, UTF-16 offsets, measurement, hit test, caret, selection и drawing в активный frame.
- `python -m unittest test/bootstrap_native_test.py -v` — 2 теста проходят.
- Paragraph smoke — успешно; native smoke с diagnostics — успешно, 4 renderFrame и 4 present.

Примечание:

- При запуске через `dart.exe` Skia сначала выводит предупреждение об отсутствии `icudtl.dat` рядом с executable, затем использует копию рядом с `dui_native.dll`; текстовые тесты проходят. Не изменять Dart SDK ради подавления этого предупреждения.

Следующий шаг:

- Этап 1.4: реализовать backend `TextLayout` поверх native handles и перевести `TextBlock` на него.

### 2026-11-25 — этап 1.2, SkParagraph и зависимости

Сделано:

- В GN args включены SkParagraph, SkShaper, SkUnicode, HarfBuzz и ICU.
- `build_skia()` всегда синхронизирует зависимости, применяет GN args и собирает `skia skparagraph`, не завершаясь преждевременно при наличии старой `skia.lib`.
- В CMake и bootstrap зафиксированы библиотеки `skia`, `skparagraph`, `skshaper`, `skunicode_core`, `skunicode_icu`, `harfbuzz` и `icu`.
- `icudtl.dat` копируется в `native/build/bin` после сборки.
- Добавлен автоматически запускаемый `dui_paragraph_smoke`: создаёт Paragraph для `ASCII, кириллица`, выполняет `layout(240)` и проверяет положительные width/height.
- Добавлены Windows DirectWrite, macOS CoreText и Linux FontConfig/FreeType font manager/scanner.

Проверено:

- Полный `python tools/bootstrap_native.py` в настроенном native окружении — успешно, включая Skia/SkParagraph и `dui_native.dll`.
- `dui_paragraph_smoke` на Windows — `SkParagraph smoke passed: width=124.945, height=21`.
- `dart analyze` — без замечаний.
- `dart test` — 24 теста проходят.
- `python -m unittest test/bootstrap_native_test.py -v` — 2 теста проходят.
- Native smoke с diagnostics — успешно: scale 2.0, logical 320×200, physical 640×400, 4 renderFrame и 4 present.

Не проверено:

- Реальные сборка и Paragraph smoke на Linux и macOS; общий кроссплатформенный критерий этапа 1.2 пока не подтверждён.

Следующий шаг:

- Этап 1.3: добавить opaque native text handles в C ABI.

### 2026-11-25 — этап 1.1, контракт TextLayout

Сделано:

- Добавлен публичный backend-independent `TextLayout` с measurement, draw, hit test, caret и selection geometry.
- Добавлены `TextLayoutFactory`, `TextPosition` и immutable `TextLayoutOptions`.
- Зафиксированы UTF-16 offsets, единоличное владение layout, идемпотентный `dispose()` и запрет операций после disposal.
- Полный cache key включает text, fontFamily, fontSize, maxWidth, scale и alignment.
- Skia, FFI и native handles не входят в публичный текстовый контракт.
- `TextBlock` и C ABI намеренно не изменялись; реализация отложена к этапам 1.3–1.4.

Проверено:

- `dart analyze` — без замечаний.
- `dart test` — 24 теста проходят, включая равенство и изменение всех компонентов cache key.

Следующий шаг:

- Этап 1.2: включить SkParagraph и необходимые зависимости в bootstrap.

### 2026-11-25 — этап 0.3, базовые C ABI-тесты

Сделано:

- Добавлен `test/native_abi_test.dart`, не использующий UI-контролы.
- Проверяются ABI version, повторные create/destroy host, null event/frame/metrics arguments и безопасный null destroy.
- В `dui_native.h` задокументированы однопоточная модель host/window и thread-local lifetime `last_error`.
- Исправлен `dui_window_begin_frame(nullptr)`: теперь устанавливается понятное `last_error`.
- Native library пересобрана после C++ изменения.

Проверено:

- `dart analyze` — без замечаний.
- `dart test` — 21 тест проходит.
- `python -m unittest test/bootstrap_native_test.py -v` — 2 теста проходят.
- Native smoke с diagnostics — успешно, 4 renderFrame и 4 present.

Следующий шаг:

- Этап 1.1: спроектировать `TextLayout` и ownership native handles.

### 2026-11-25 — этап 0.2, диагностические метрики

Сделано:

- В C ABI добавлены `DuiWindowMetrics` и `dui_window_get_metrics()` с `struct_size` и проверкой аргументов.
- Добавлены Dart FFI struct, typed binding, lookup и вызов метрик.
- `NativeWindowDiagnostics` показывает displayScale, pixelDensity, logical/physical size, renderFrame и present.
- Диагностика отключена по умолчанию и включается через `--diagnostics`; снимок печатается один раз, не каждый кадр.
- Обновлены native counter, smoke и bootstrap.
- Импорты приведены к актуальному имени пакета `duix`, package config обновлён после переноса.
- Добавлены тесты ABI layout и текстового представления диагностики.

Проверено:

- Native library пересобрана после изменения C ABI.
- `dart analyze` — без замечаний.
- `dart test` — 16 тестов проходят.
- `python tools/bootstrap_native.py --smoke --diagnostics` — успешно.
- Windows: displayScale 2.0, pixelDensity 1.0, logical 320×200, physical 640×400, renderFrame 4, present 4.

Следующий шаг:

- Этап 0.3: базовые ABI-тесты и документация потоковой модели.

### 2026-11-25 — исправление сборки после перемещения проекта

Сделано:

- Удалён устаревший `native/build` с абсолютными путями прежнего расположения.
- `bootstrap_native.py` теперь проверяет `CMAKE_CACHEFILE_DIR` и `CMAKE_HOME_DIRECTORY` перед настройкой SDL и native library.
- Build-каталог автоматически очищается только при несовпадении сохранённых и текущих путей.
- Добавлены Python unit-тесты для актуального и перемещённого CMake build-каталога.

Проверено:

- `python -m unittest test/bootstrap_native_test.py -v` — 2 теста проходят.
- Старый `native/build/CMakeCache.txt` удалён.
- Полная пересборка в текущем shell не запускалась: инструменты сборки не находятся в `PATH`.

Следующий шаг:

- Повторить `python tools/bootstrap_native.py --smoke` в настроенном native окружении.

### 2026-11-25 — этап 0.1, native smoke-режим

Сделано:

- Добавлен `example/native_smoke.dart`: создаёт host и окно, обрабатывает события, рисует 3 кадра и автоматически закрывает окно.
- Добавлена команда `python tools/bootstrap_native.py --smoke`.
- Освобождение window/host выполняется в `finally`; необработанные native errors завершают процесс с ненулевым кодом.
- C ABI и C++ не изменялись.

Проверено:

- Синтаксис `tools/bootstrap_native.py` — корректен.
- `python tools/bootstrap_native.py --help` — опция `--smoke` доступна.

Не проверено:

- `dart analyze` и `dart test`: Dart SDK не найден в текущем окружении.
- Реальный native smoke: CMake и Ninja не найдены, нативная библиотека не собрана.

Следующий шаг:

- Запустить `python tools/bootstrap_native.py --smoke` в настроенном окружении, затем перейти к этапу 0.2.

### 2026-11-25 — базовый framework и native backend

Сделано:

- Создан retained-mode Dart package.
- Добавлены свойства, bindings, routed events, layout и базовые контролы.
- Добавлены C ABI, Dart FFI, SDL3 и Skia CPU backend.
- Добавлен bootstrap нативных зависимостей.
- Исправлен чёрный фон через `Window.background`.
- Исправлен HiDPI: используется `SDL_GetWindowDisplayScale()`, а не pixel/window ratio.
- Преобразуются размеры окна и pointer coordinates в logical UI units.
- Нативный пример подтверждён пользователем как работающий.

Проверено:

- `dart analyze` — без замечаний.
- `dart test` — 14 тестов проходят.
- Нативный пример запускается и обновляет текст.
- HiDPI на 4K-дисплее работает корректно.

Следующий шаг:

- Этап 0.1: native smoke-режим, затем native text measurement.
