# План разработки retained-mode UI framework на Dart

Дата последнего обновления: 2026-11-25

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
- `UIElement`, `Control`, `ContentControl`, `Panel`;
- `TextBlock`, `TextBox`, `Button`, `Border`, `StackPanel`;
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
- `TextBlock` использует кэшированный `TextLayout` для measurement и drawing, освобождает его при замене и unmount;
- Unicode/HiDPI-матрица native text layout с проверками measurement, hit test, caret, selection и масштабов 1.0/1.25/1.5/2.0;
- интерактивная галерея `example/native_text_gallery.dart` с автоматическим smoke-режимом;
- 41 Dart-тест.

### 3.2. Проверенное поведение

- Нативный пример запускается.
- Заголовок и кнопка видимы.
- Нажатие кнопки обновляет существующий `TextBlock`.
- Идентичность `TextBlock` сохраняется.
- Белый фон окна отображается корректно.
- HiDPI-масштабирование подтверждено на 4K-дисплее.
- `dart analyze` проходит без замечаний.
- Все 41 Dart-теста проходят, включая C ABI, TextLayout cache/ownership, native text geometry, Unicode/HiDPI-матрицу и TextBlock integration.
- Матрица проверяет ASCII, кириллицу, emoji, CJK, Arabic, Hebrew, multiline, пустую и очень длинную строки, а также стабильность logical metrics на масштабах 1.0, 1.25, 1.5 и 2.0.
- Пустая строка имеет нулевую ширину и конечные неотрицательные metrics; учтён допустимый glyph overhang tight selection boxes за пределами advance width.
- `TextBlock` на Windows получает реальные SkParagraph metrics, переносит длинный текст по доступной ширине и рисует тот же native layout.
- Цвет не пересоздаёт layout; text, fontSize, alignment, maxWidth, scale и factory вызывают замену с disposal предыдущего layout.
- Native text handles измеряют ASCII, кириллицу и emoji, возвращают UTF-16 hit-test/caret/selection geometry и рисуются в активном SDL/Skia frame.
- Полный `python tools/bootstrap_native.py` успешно пересобирает Skia/SkParagraph и native library.
- Paragraph smoke на Windows измеряет `ASCII, кириллица` через SkParagraph: width 124.945, height 21.
- Native smoke автоматически завершается после 3 smoke-кадров.
- Native text gallery smoke успешно рисует 3 кадра: scale 2.0, logical 960×800, physical 1920×1600, 4 renderFrame и 4 present.
- Diagnostics подтверждены на Windows: scale 2.0, logical 320×200, physical 640×400, 4 renderFrame и 4 present.

### 3.3. Основные файлы

```text
lib/dui.dart                         — публичный Dart API
lib/native.dart                      — публичный native API
lib/src/ui_element.dart              — база дерева, layout, события
lib/src/controls.dart                — базовые контролы
lib/src/panel.dart                   — Panel и StackPanel
lib/src/properties.dart              — свойства и bindings
lib/src/observable.dart              — observable primitives
lib/src/events.dart                  — routed events
lib/src/window.dart                  — Application и Window
lib/src/drawing.dart                 — DrawingContext
lib/src/text_layout.dart             — текстовый контракт и cache key
lib/src/headless_text_layout.dart    — deterministic headless text layout
lib/src/native/native_bindings.dart  — FFI
lib/src/native/native_text_layout.dart — SkParagraph TextLayout backend
lib/src/native/sdl_skia_host.dart    — SDL/Skia Dart host
native/include/dui_native.h          — C ABI
native/src/dui_native.cpp            — SDL3 + Skia backend
native/src/paragraph_smoke.cpp       — SkParagraph smoke-проверка
native/CMakeLists.txt                — нативная сборка
tools/bootstrap_native.py            — зависимости и сборка
example/native_counter.dart          — нативный интерактивный пример
example/native_smoke.dart            — native smoke с автоматическим завершением
example/native_text_gallery.dart     — Unicode/HiDPI text gallery и её smoke-режим
test/                                — автоматические тесты
```

### 3.4. Команды

```bash
dart pub get
dart format lib example test
dart analyze
dart test
dart run example/counter.dart
```

Нативная проверка и сборка:

```bash
python tools/bootstrap_native.py --check
python tools/bootstrap_native.py
python tools/bootstrap_native.py --run
python tools/bootstrap_native.py --smoke
python tools/bootstrap_native.py --smoke --diagnostics
python tools/bootstrap_native.py --text-gallery
python tools/bootstrap_native.py --text-gallery --smoke --diagnostics
```

Если Dart не в `PATH`:

```bash
python tools/bootstrap_native.py --run --dart "<путь-к-dart>"
python tools/bootstrap_native.py --smoke --dart "<путь-к-dart>"
```

---

## 4. Известный технический долг

Приоритет указан в скобках: P0 — критично, P1 — следующий этап, P2 — позже.

1. **P0:** `TextBox.measureCore()` всё ещё приблизительно считает ширину через число символов.
2. **P0:** legacy `drawText`, используемый `TextBox`, рисует через `drawSimpleText` без SkParagraph.
3. **P1:** native text layout пока принимает только конечную положительную `maxWidth`; infinite constraints остаются задачей layout system.
4. **P0:** `TextBox` не запускает SDL text input при focus.
5. **P0:** нет IME composition, selection, clipboard и нормальной клавиатурной навигации.
6. **P1:** нативный пример рисует кадр каждые 8 мс независимо от invalidate.
7. **P1:** нет keyboard focus traversal и focus scopes.
8. **P1:** нет `Grid`, `ScrollViewer`, alignment и min/max constraints.
9. **P1:** binding lifecycle и отмена подписок требуют более строгой модели владения.
10. **P1:** нет единого механизма `dispose()` для контролов и ресурсов.
11. **P2:** нет styles/templates, `ItemsControl`, виртуализации и accessibility.
12. **P2:** нет packaging runtime dependencies и кроссплатформенной CI.

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

- [x] `TextBlock` не рассчитывает ширину по числу символов.
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

## 1.4. Перевести `TextBlock` на `TextLayout`

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

- [ ] Хранить текст независимо от render layout.
- [ ] Ввести selection anchor и active end.
- [ ] Определить cursor offset в Unicode code points или UTF-16 offsets и не смешивать модели.
- [ ] Добавить команды редактирования вместо обработки клавиш прямо в render logic.
- [ ] Проверять диапазоны offsets.

## 2.2. SDL text input lifecycle

- [ ] При получении focus вызвать `SDL_StartTextInput()`.
- [ ] Передавать text input area и cursor position.
- [ ] При потере focus вызвать `SDL_StopTextInput()`.
- [ ] При перемещении/изменении caret обновлять SDL text input area.
- [ ] Обрабатывать close/unmount без оставления активного IME.

## 2.3. Команды редактирования

- [ ] Вставка текста.
- [ ] Backspace/Delete.
- [ ] Left/Right.
- [ ] Home/End.
- [ ] Ctrl/Cmd+Left/Right.
- [ ] Selection с Shift.
- [ ] Select All.
- [ ] Cut/Copy/Paste.
- [ ] Отмена selection при обычном перемещении.

Важно: не формировать вводимый Unicode-текст из key-down событий. Key events нужны для команд, `SDL_EVENT_TEXT_INPUT` — для вставки текста.

## 2.4. IME

- [ ] Обрабатывать `SDL_EVENT_TEXT_EDITING`.
- [ ] Хранить composition text и composition range.
- [ ] Рисовать composition отдельно от подтверждённого текста.
- [ ] Не отправлять промежуточный composition как окончательный two-way binding update без явного решения.
- [ ] Проверить русский, китайский/японский ввод и emoji.

## 2.5. Mouse interaction

- [ ] Hit test позиции текста через `TextLayout`.
- [ ] Установка caret кликом.
- [ ] Selection перетаскиванием.
- [ ] Pointer capture во время drag.
- [ ] Двойной клик — выделение слова, если не осложняет этап.

Критерий готовности: можно ввести, выделить, изменить и вставить текст; two-way binding остаётся синхронизированным.

---

# Этап 3. Focus и клавиатурная навигация

## 3.1. FocusManager

- [ ] Вынести focus из `Window` в отдельный `FocusManager`.
- [ ] Отслеживать focused element и его mount state.
- [ ] При unmount focused element корректно очищать или восстанавливать focus.
- [ ] Запрещать focus невидимым и disabled контролам.

## 3.2. Tab traversal

- [ ] Построить порядок обхода по logical tree.
- [ ] Реализовать Tab и Shift+Tab.
- [ ] Добавить `focusable`, `tabIndex` только при необходимости.
- [ ] Реализовать focus scope для будущих dialogs/popups.

## 3.3. Keyboard activation

- [ ] Button активируется Space/Enter.
- [ ] Key events имеют modifiers и physical/logical key.
- [ ] Обработанное событие не вызывает повторную активацию родителя.

Критерий готовности: пример можно полностью использовать без мыши.

---

# Этап 4. Frame scheduling и производительность

## 4.1. Убрать постоянный рендеринг

- [ ] Рисовать только при `frameScheduled` или необходимости animation tick.
- [ ] Не вызывать present, если кадр не изменился.
- [ ] Сохранить обработку событий даже без повреждённого кадра.
- [ ] Включить SDL VSync.
- [ ] Убрать постоянную задержку 8 мс как основной scheduling mechanism.

## 4.2. Централизовать scheduler

- [ ] Объединять несколько invalidate в один кадр.
- [ ] Отделять layout pass от paint pass.
- [ ] Не допускать рекурсивного запуска layout во время layout.
- [ ] Добавить diagnostics: scheduled/layout/painted/presented.

## 4.3. Кэширование

- [ ] Кэшировать `TextLayout`.
- [ ] Кэшировать paths/paints, если профилирование покажет необходимость.
- [ ] Не вводить retained GPU scene graph на CPU backend.
- [ ] Добавить damage rectangles только после профилирования.

Критерий готовности: неподвижное окно почти не использует CPU, ввод остаётся отзывчивым.

---

# Этап 5. Layout system

## 5.1. Уточнить constraints

- [ ] Добавить min/max width/height.
- [ ] Добавить margin как attached/layout property.
- [ ] Добавить horizontal/vertical alignment.
- [ ] Различить desired size, arranged size и actual bounds.
- [ ] Проверить поведение при infinite constraints.

## 5.2. DockPanel

- [ ] Добавить `Dock` attached property.
- [ ] Реализовать последовательное распределение пространства.
- [ ] Добавить last-child-fill.

## 5.3. Grid

- [ ] Auto, Pixel и Star tracks.
- [ ] Row/column definitions.
- [ ] Gap.
- [ ] RowSpan/ColumnSpan после базовой версии.
- [ ] Тесты на дробные размеры и HiDPI rounding.

## 5.4. ScrollViewer

- [ ] Viewport и content extent.
- [ ] Mouse wheel.
- [ ] Scrollbars.
- [ ] Clip при render и hit test.
- [ ] Keyboard scrolling после focus scopes.

Критерий готовности: можно собрать типовое окно настроек без абсолютного позиционирования.

---

# Этап 6. Коллекции и ItemsControl

## 6.1. ObservableCollection

- [ ] Add/remove/insert/move/reset notifications.
- [ ] Строгая модель подписки и disposal.
- [ ] Не пересоздавать всё дерево при точечном изменении.

## 6.2. ItemsControl

- [ ] Items source.
- [ ] Item template как factory, не как rebuild существующего контрола.
- [ ] Переиспользование контейнеров по ключу при перемещении.
- [ ] Корректный unmount/dispose удалённых элементов.

## 6.3. VirtualizingStackPanel

- [ ] Создавать только видимые элементы плюс небольшой buffer.
- [ ] Поддерживать estimated extent.
- [ ] Обрабатывать переменную высоту элементов.
- [ ] Проверять focus и selection при recycling.

Критерий готовности: список из 100 000 простых элементов прокручивается без создания 100 000 контролов.

---

# Этап 7. Property system, стили и шаблоны

## 7.1. Жизненный цикл bindings

- [ ] Определить поведение `cancel()`: отсоединение, сохранение последнего значения или возврат к local value.
- [ ] Отменять bindings при dispose.
- [ ] Предотвращать повторное уведомление при двустороннем обновлении.
- [ ] Добавить binding diagnostics и понятные ошибки.

## 7.2. Приоритеты значений

```text
default < inherited < style < binding < local < animation
```

Точный порядок зафиксировать отдельно перед реализацией.

## 7.3. DataContext

- [ ] Наследование по logical tree.
- [ ] Типобезопасные accessors.
- [ ] Строковые paths только через кодогенерацию, без `dart:mirrors`.

## 7.4. Styles и templates

- [ ] Named style или type style.
- [ ] Setter-ы свойств.
- [ ] Control template как persistent subtree factory.
- [ ] Template bindings без потери идентичности после смены обычных свойств.

Критерий готовности: внешний вид Button меняется шаблоном без изменения его input/focus поведения.

---

# Этап 8. Production readiness

## 8.1. Accessibility

- [ ] Добавить semantics к дереву: role, name, value, state, bounds.
- [ ] Windows UI Automation.
- [ ] macOS NSAccessibility.
- [ ] Linux AT-SPI.
- [ ] Синхронизировать focus и selection.

## 8.2. Нативная интеграция

- [ ] Clipboard с форматами.
- [ ] File dialogs.
- [ ] Native menus.
- [ ] Drag-and-drop.
- [ ] Notifications/tray по необходимости.

## 8.3. Packaging

- [ ] Проверить зависимости `dui_native` на чистой машине.
- [ ] Windows: runtime DLL и архитектуры x64/arm64.
- [ ] macOS: dylib rpath, universal binary, codesign/notarization.
- [ ] Linux: rpath `$ORIGIN`, dependencies и supported distros.
- [ ] Добавить reproducible release build.

## 8.4. CI и тестирование

- [ ] Dart analyze/test на Windows, macOS и Linux.
- [ ] Native build на всех ОС.
- [ ] Smoke window test.
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

1. **Этап 2:** TextBox input/IME/selection/clipboard.
2. **Незавершённая часть этапа 1.2:** проверить сборку и Paragraph smoke на Linux (FontConfig/Freetype) и macOS (CoreText).
3. **Ручная визуальная проверка этапа 1.5:** открыть text gallery на мониторах с разными масштабами и проверить clipping; автоматический smoke этого не заменяет.
4. **Этап 3:** focus traversal.
5. **Этап 4:** render on demand.

Не начинать GPU, styles или virtualization до завершения этапов 1–4.

---

## 8. Протокол продолжения после перерыва

В начале новой сессии:

1. Прочитать `plan.md`.
2. Проверить последние записи журнала.
3. Выполнить:

   ```bash
   dart analyze
   dart test
   python tools/bootstrap_native.py --check
   ```

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
