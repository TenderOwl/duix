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
- интерактивный пример `example/native_textbox.dart` с тремя полями, Unicode, two-way binding preview, mouse/keyboard/clipboard/IME подсказками и smoke-режимом;
- `TextBox` получает focus по primary pointer down, устанавливает caret через `TextLayout.hitTest()` и выделяет текст перетаскиванием;
- backend-independent pointer capture в `Window` маршрутизирует move/up захваченному контролу, включая координаты за его границами; capture освобождается при primary up, focus loss и unmount;
- `DrawingContext` поддерживает вложенные `pushClipRect`/`popClip`; native backend реализует их через Skia save/clipRect/restore;
- `TextBox` обрезает текст и decoration по content bounds, подсвечивает обычный selection и рисует caret у focused collapsed selection;
- `TextBuffer` и `TextSelection` с UTF-16 offsets, selection anchor/active end, проверкой диапазонов и командами редактирования;
- `TextBox` вставляет text input в caret, заменяет selection и синхронизирует текст с two-way binding;
- SDL text input lifecycle: Start/Stop при focus, TextLayout-based input area/caret, cleanup при unmount/close;
- routed key-down с Shift/Ctrl/Cmd modifiers, команды навигации и редактирования `TextBox`, включая word navigation и selection;
- backend-independent `ClipboardHandler` и SDL clipboard с UTF-8 copy/cut/paste;
- `SDL_EVENT_TEXT_EDITING` проходит через C ABI, Dart FFI и `Window` в focused `TextBox`; composition selection передаётся в UTF-16 offsets;
- `TextBox` хранит composition text/range отдельно от подтверждённого `TextBuffer`, рисует composition через кэшированный `TextLayout` с подчёркиванием и подсветкой активного диапазона;
- промежуточная composition не изменяет `text` и two-way binding; подтверждение через text input заменяет selection и обновляет модель;
- 94 Dart-теста, включая clipping/rendering, horizontal scrolling, mouse caret/selection, pointer capture, surrogate pairs, composition и clipboard.

### 3.2. Проверенное поведение

- Нативный пример запускается.
- Заголовок и кнопка видимы.
- Нажатие кнопки обновляет существующий `TextBlock`.
- Идентичность `TextBlock` сохраняется.
- Белый фон окна отображается корректно.
- HiDPI-масштабирование подтверждено на 4K-дисплее.
- `dart analyze` проходит без замечаний.
- Все 94 Dart-теста проходят, включая render/clipping, native clip ABI и восстановление прежнего Windows clipboard.
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
- SDL clipboard на Windows выполняет Unicode round-trip, освобождает native string через C ABI и в последнем полном прогоне успешно восстанавливает прежнее значение; ранее наблюдавшаяся нестабильность `Couldn't open clipboard` требует наблюдения на повторных запусках.
- `DuiEvent` с modifiers и composition range имеет ABI size 72 байта; SDL byte offsets преобразуются в UTF-16. OS key modifiers и маппинг SDL key codes покрыты косвенно, без синтеза системного keyboard input.
- Composition видна до commit, не меняет `TextBuffer`/binding, поддерживает CJK/emoji selection range и кириллицу без selection; пустой editing event, focus loss, unmount и editing commands очищают её.
- Матрица проверяет ASCII, кириллицу, emoji, CJK, Arabic, Hebrew, multiline, пустую и очень длинную строки, а также стабильность logical metrics на масштабах 1.0, 1.25, 1.5 и 2.0.
- Пустая строка имеет нулевую ширину и конечные неотрицательные metrics; учтён допустимый glyph overhang tight selection boxes за пределами advance width.
- `TextBlock` на Windows получает реальные SkParagraph metrics, переносит длинный текст по доступной ширине и рисует тот же native layout.
- Цвет не пересоздаёт layout; text, fontSize, alignment, maxWidth, scale и factory вызывают замену с disposal предыдущего layout.
- Native text handles измеряют ASCII, кириллицу и emoji, возвращают UTF-16 hit-test/caret/selection geometry и рисуются в активном SDL/Skia frame.
- Полный `python tools/bootstrap_native.py` успешно пересобирает Skia/SkParagraph и native library.
- Paragraph smoke на Windows измеряет `ASCII, кириллица` через SkParagraph: width 124.945, height 21.
- Native smoke автоматически завершается после 3 smoke-кадров.
- Native text gallery smoke успешно рисует 3 кадра: scale 2.0, logical 960×800, physical 1920×1600, 4 renderFrame и 4 present.
- TextBox smoke через `--textbox --smoke` рисует composition, обычный selection и caret в отдельных кадрах, проверяет `Smoke か😀`, mouse caret и captured drag, затем завершается после 3 кадров: logical 760×590, physical 1520×1180, 4 renderFrame и 4 present.
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
lib/src/text_buffer.dart              — UTF-16 text/selection model и команды
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
example/native_textbox.dart          — интерактивная проверка TextBox и smoke-режим
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
python tools/bootstrap_native.py --textbox
python tools/bootstrap_native.py --textbox --smoke --diagnostics
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
4. **P1:** Windows clipboard cleanup нестабилен при восстановлении пустого прежнего значения: SDL `Couldn't open clipboard`; round-trip и запись самого значения при этом успешны.
5. **P1:** нативный пример рисует кадр каждые 8 мс независимо от invalidate.
6. **P1:** нет keyboard focus traversal и focus scopes.
7. **P1:** нет `Grid`, `ScrollViewer`, alignment и min/max constraints.
8. **P1:** binding lifecycle и отмена подписок требуют более строгой модели владения.
9. **P1:** нет единого механизма `dispose()` для контролов и ресурсов.
10. **P2:** нет styles/templates, `ItemsControl`, виртуализации и accessibility.
11. **P2:** нет packaging runtime dependencies и кроссплатформенной CI.

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

1. **Стабилизация Windows clipboard:** устранить сбой восстановления пустого прежнего значения в native ABI-тесте.
2. **Этап 3:** focus traversal.
3. **Незавершённая часть этапа 1.2:** проверить сборку и Paragraph smoke на Linux (FontConfig/Freetype) и macOS (CoreText).
4. **Ручная визуальная проверка:** открыть text gallery и TextBox на мониторах с разными масштабами, проверить clipping, selection и caret; автоматический smoke этого не заменяет.
5. **Ручная проверка этапа 2.4:** русский, китайский/японский ввод и emoji через реальные системные IME.
6. **Этап 4:** render on demand.

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
