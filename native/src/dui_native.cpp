#include "dui_native.h"

#include "uia_windows.h"

#include <SDL3/SDL.h>

#if defined(_WIN32)
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <shobjidl.h>
#elif defined(__linux__)
#include <gtk/gtk.h>
#endif

#include "include/core/SkBlurTypes.h"
#include "include/core/SkCanvas.h"
#include "include/core/SkColor.h"
#include "include/core/SkData.h"
#include "include/core/SkFont.h"
#include "include/core/SkImage.h"
#include "include/core/SkFontMgr.h"
#include "include/core/SkFontStyle.h"
#include "include/core/SkImageInfo.h"
#include "include/core/SkMaskFilter.h"
#include "include/core/SkPaint.h"
#include "include/core/SkPathBuilder.h"
#include "include/core/SkPixmap.h"
#include "include/core/SkRRect.h"
#include "include/core/SkSurface.h"
#include "include/core/SkTypeface.h"
#include "modules/skparagraph/include/FontCollection.h"
#include "modules/skparagraph/include/Paragraph.h"
#include "modules/skparagraph/include/ParagraphBuilder.h"
#include "modules/skparagraph/include/ParagraphStyle.h"
#include "modules/skparagraph/include/TextStyle.h"
#include "modules/skunicode/include/SkUnicode_icu.h"

#if defined(_WIN32)
#include "include/ports/SkTypeface_win.h"
#elif defined(__APPLE__)
#include "include/ports/SkFontMgr_mac_ct.h"
#else
#include "include/ports/SkFontMgr_fontconfig.h"
#include "include/ports/SkFontScanner_FreeType.h"
#endif

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <limits>
#include <memory>
#include <mutex>
#include <new>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

struct DuiTextLayout {
  std::string text;
  std::unique_ptr<skia::textlayout::Paragraph> paragraph;
  double scale = 1.0;
  uint32_t utf16_length = 0;
};

// Cached paragraph for the legacy text drawing path. The path is used for
// overlays and simple labels that are redrawn every frame, so the shaped
// paragraph is reused while the text, font size, scale and alignment stay
// the same. The foreground paint is applied on every draw.
struct DuiLegacyText {
  std::string text;
  double font_size = 0.0;
  double scale = 0.0;
  std::unique_ptr<skia::textlayout::Paragraph> paragraph;
};

// A decoded bitmap. The pixels stay in the CPU memory of Skia, so the image
// can be drawn on every surface of the backend.
struct DuiImage {
  sk_sp<SkImage> image;
};

// One node of the semantics tree of a window. The strings are owned by the
// window, so a platform bridge can read them without a copy.
struct DuiAccessibleNodeData {
  int32_t role = 0;
  int32_t parent = -1;
  uint32_t flags = 0;
  double left = 0.0;
  double top = 0.0;
  double width = 0.0;
  double height = 0.0;
  std::string name;
  std::string value;
};

struct DuiWindow {
  explicit DuiWindow(DuiHost* owner) : host(owner) {}

  DuiHost* host = nullptr;
  SDL_Window* window = nullptr;
  SDL_Renderer* renderer = nullptr;
  SDL_Texture* texture = nullptr;
  sk_sp<SkSurface> surface;
  int pixel_width = 0;
  int pixel_height = 0;
  uint32_t background_rgba = 0xFFFFFFFF;
  bool frame_active = false;
  DuiLegacyText legacy_text;
  // The semantics tree of the window, published by the Dart layer.
  std::vector<DuiAccessibleNodeData> accessible_nodes;
};

struct DuiHost {
  std::vector<std::unique_ptr<DuiWindow>> windows;
  std::string text_storage;
  SDL_ThreadID thread_id = 0;
  DuiLiveResizeCallback live_resize_callback = nullptr;
  void* live_resize_user_data = nullptr;
  bool live_resize_active = false;
};

#if defined(__APPLE__)
char* dui_macos_open_file_dialog(
    SDL_Window* window,
    const char* title_utf8,
    const char* initial_directory_utf8,
    const DuiFileDialogFilter* filters,
    size_t filter_count,
    std::string* error);
#endif

namespace {

thread_local std::string last_error;
std::unordered_map<std::string, std::vector<uint8_t>> clipboard_formats;

#if defined(__linux__)
struct GtkOpenDialogResult {
  GMainLoop* loop = nullptr;
  GFile* file = nullptr;
  GError* error = nullptr;
};

void gtk_open_dialog_ready(
    GObject* source_object,
    GAsyncResult* async_result,
    gpointer user_data) {
  auto* result = static_cast<GtkOpenDialogResult*>(user_data);
  result->file = gtk_file_dialog_open_finish(
      GTK_FILE_DIALOG(source_object), async_result, &result->error);
  g_main_loop_quit(result->loop);
}
#endif

const void* SDLCALL clipboard_data_callback(
    void*,
    const char* mime_type,
    size_t* size) {
  const auto found = clipboard_formats.find(mime_type);
  if (found == clipboard_formats.end()) {
    *size = 0;
    return nullptr;
  }
  *size = found->second.size();
  return found->second.data();
}

void SDLCALL clipboard_cleanup_callback(void*) {
  clipboard_formats.clear();
}

template <typename Write>
bool retry_clipboard_write(Write&& write) {
#if defined(_WIN32)
  constexpr int max_attempts = 12;
#else
  constexpr int max_attempts = 1;
#endif
  for (int attempt = 0; attempt < max_attempts; ++attempt) {
    if (write()) return true;
    if (attempt + 1 < max_attempts) SDL_Delay(25);
  }
  return false;
}

void clear_error() { last_error.clear(); }

void set_error(const char* message) { last_error = message; }

void set_sdl_error() { last_error = SDL_GetError(); }

// SDL owns a single global event queue and a single video subsystem, and it
// is not thread safe. The Dart runtime can run several isolates, each with its
// own host, so every call that touches SDL is serialized with a process wide
// recursive mutex. The mutex is recursive because the live resize event watch
// calls back into Dart, which calls back into the native layer.
std::recursive_mutex& sdl_mutex() {
  static std::recursive_mutex mutex;
  return mutex;
}

class SdlScope {
 public:
  SdlScope() { sdl_mutex().lock(); }
  ~SdlScope() { sdl_mutex().unlock(); }

  SdlScope(const SdlScope&) = delete;
  SdlScope& operator=(const SdlScope&) = delete;
};

// The video subsystem stays initialized for the lifetime of the process.
// Quitting it while another isolate still owns a window would tear the
// subsystem down under it, and initializing it again afterwards is not
// reliable, so the process cleans SDL up when it exits.
bool ensure_sdl_initialized() {
  static bool initialized = false;
  if (initialized) return true;
  if (!SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS)) {
    set_sdl_error();
    return false;
  }
  initialized = true;
  return true;
}

// Only one host may exist per process: SDL has one global event queue, so two
// hosts in two isolates would steal the events of each other. A window is
// created through the host, so a single host still serves many windows.
int& live_host_count() {
  static int count = 0;
  return count;
}

bool is_html_mime(const char* mime_type) {
  return mime_type && std::strcmp(mime_type, "text/html") == 0;
}

#if defined(_WIN32)
UINT html_clipboard_format() {
  static const UINT format = RegisterClipboardFormatA("HTML Format");
  return format;
}

bool open_clipboard_for_html() {
  return retry_clipboard_write([] { return OpenClipboard(nullptr) != 0; });
}

std::string make_cf_html(const std::vector<uint8_t>& fragment) {
  constexpr char prefix[] = "<html>\r\n<body>\r\n<!--StartFragment-->";
  constexpr char suffix[] = "<!--EndFragment-->\r\n</body>\r\n</html>\r\n";
  constexpr char format[] =
      "Version:0.9\r\n"
      "StartHTML:%010llu\r\n"
      "EndHTML:%010llu\r\n"
      "StartFragment:%010llu\r\n"
      "EndFragment:%010llu\r\n";
  const int header_size =
      std::snprintf(nullptr, 0, format, 0ULL, 0ULL, 0ULL, 0ULL);
  const unsigned long long start_html = static_cast<unsigned>(header_size);
  const unsigned long long start_fragment = start_html + sizeof(prefix) - 1;
  const unsigned long long end_fragment = start_fragment + fragment.size();
  const unsigned long long end_html = end_fragment + sizeof(suffix) - 1;
  char header[256];
  std::snprintf(
      header,
      sizeof(header),
      format,
      start_html,
      end_html,
      start_fragment,
      end_fragment);
  std::string result(header, static_cast<size_t>(header_size));
  result.append(prefix, sizeof(prefix) - 1);
  if (!fragment.empty()) {
    result.append(reinterpret_cast<const char*>(fragment.data()), fragment.size());
  }
  result.append(suffix, sizeof(suffix) - 1);
  return result;
}

bool clear_clipboard_for_html() {
  if (!open_clipboard_for_html()) {
    set_error("Couldn't open clipboard to write HTML data.");
    return false;
  }
  const bool cleared = EmptyClipboard() != 0;
  CloseClipboard();
  if (!cleared) set_error("Couldn't clear clipboard for HTML data.");
  return cleared;
}

bool write_html_clipboard(const std::vector<uint8_t>& fragment) {
  const UINT format = html_clipboard_format();
  const std::string html = make_cf_html(fragment);
  if (!format || !open_clipboard_for_html()) {
    set_error("Couldn't open clipboard to write HTML data.");
    return false;
  }
  HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, html.size() + 1);
  if (!memory) {
    CloseClipboard();
    set_error("Couldn't allocate clipboard HTML data.");
    return false;
  }
  void* destination = GlobalLock(memory);
  if (!destination) {
    GlobalFree(memory);
    CloseClipboard();
    set_error("Couldn't lock clipboard HTML data.");
    return false;
  }
  std::memcpy(destination, html.data(), html.size());
  static_cast<char*>(destination)[html.size()] = '\0';
  GlobalUnlock(memory);
  if (!SetClipboardData(format, memory)) {
    GlobalFree(memory);
    CloseClipboard();
    set_error("Couldn't publish clipboard HTML data.");
    return false;
  }
  CloseClipboard();
  return true;
}

bool read_cf_html_offset(
    const std::string& html,
    const char* name,
    size_t* offset) {
  size_t current = html.find(name);
  if (current == std::string::npos) return false;
  current += std::strlen(name);
  while (current < html.size() && html[current] == ' ') ++current;
  if (current == html.size() || html[current] < '0' || html[current] > '9') {
    return false;
  }
  size_t value = 0;
  while (current < html.size() && html[current] >= '0' && html[current] <= '9') {
    const size_t digit = static_cast<size_t>(html[current] - '0');
    if (value > (std::numeric_limits<size_t>::max() - digit) / 10) return false;
    value = value * 10 + digit;
    ++current;
  }
  *offset = value;
  return true;
}

bool read_html_clipboard(std::vector<uint8_t>* fragment) {
  const UINT format = html_clipboard_format();
  if (!format || !open_clipboard_for_html()) {
    set_error("Couldn't open clipboard to read HTML data.");
    return false;
  }
  HGLOBAL memory = static_cast<HGLOBAL>(GetClipboardData(format));
  if (!memory) {
    CloseClipboard();
    set_error("Clipboard HTML data is unavailable.");
    return false;
  }
  const char* source = static_cast<const char*>(GlobalLock(memory));
  if (!source) {
    CloseClipboard();
    set_error("Couldn't lock clipboard HTML data.");
    return false;
  }
  const size_t allocated_size = GlobalSize(memory);
  const void* terminator = std::memchr(source, '\0', allocated_size);
  const size_t size = terminator
                          ? static_cast<const char*>(terminator) - source
                          : allocated_size;
  const std::string html(source, size);
  GlobalUnlock(memory);
  CloseClipboard();

  constexpr char start_marker[] = "<!--StartFragment-->";
  constexpr char end_marker[] = "<!--EndFragment-->";
  const size_t marked_start = html.find(start_marker);
  const size_t marked_end = html.find(end_marker);
  size_t start = 0;
  size_t end = html.size();
  if (marked_start != std::string::npos && marked_end != std::string::npos) {
    start = marked_start + sizeof(start_marker) - 1;
    end = marked_end;
  } else if (!read_cf_html_offset(html, "StartFragment:", &start) ||
             !read_cf_html_offset(html, "EndFragment:", &end)) {
    start = 0;
    end = html.size();
  }
  if (start > end || end > html.size()) {
    set_error("Clipboard HTML fragment offsets are invalid.");
    return false;
  }
  fragment->assign(html.begin() + start, html.begin() + end);
  return true;
}
#endif

bool decode_utf8(
    const std::string& text,
    size_t offset,
    uint32_t* code_point,
    size_t* next) {
  if (offset >= text.size()) return false;
  const auto* bytes = reinterpret_cast<const unsigned char*>(text.data());
  const unsigned char first = bytes[offset];
  size_t length = 0;
  uint32_t value = 0;
  uint32_t minimum = 0;
  if (first < 0x80) {
    length = 1;
    value = first;
  } else if (first >= 0xC2 && first <= 0xDF) {
    length = 2;
    value = first & 0x1F;
    minimum = 0x80;
  } else if (first >= 0xE0 && first <= 0xEF) {
    length = 3;
    value = first & 0x0F;
    minimum = 0x800;
  } else if (first >= 0xF0 && first <= 0xF4) {
    length = 4;
    value = first & 0x07;
    minimum = 0x10000;
  } else {
    return false;
  }
  if (offset + length > text.size()) return false;
  for (size_t index = 1; index < length; ++index) {
    const unsigned char continuation = bytes[offset + index];
    if ((continuation & 0xC0) != 0x80) return false;
    value = (value << 6) | (continuation & 0x3F);
  }
  if (value < minimum || value > 0x10FFFF ||
      (value >= 0xD800 && value <= 0xDFFF)) {
    return false;
  }
  *code_point = value;
  *next = offset + length;
  return true;
}

uint32_t utf8_prefix_utf16_length(const char* text, int32_t byte_count) {
  if (!text || byte_count <= 0) return 0;
  const std::string value(text);
  const size_t limit = std::min(value.size(), static_cast<size_t>(byte_count));
  size_t current = 0;
  uint32_t result = 0;
  while (current < limit) {
    uint32_t code_point = 0;
    size_t next = 0;
    if (!decode_utf8(value, current, &code_point, &next) || next > limit) break;
    result += code_point > 0xFFFF ? 2 : 1;
    current = next;
  }
  return result;
}

// Length of the whole string in UTF-16 code units, the unit used by the
// SkParagraph paint and editing APIs.
uint32_t utf16_length_of(const std::string& text) {
  size_t current = 0;
  uint64_t result = 0;
  while (current < text.size()) {
    uint32_t code_point = 0;
    size_t next = 0;
    if (!decode_utf8(text, current, &code_point, &next)) return 0;
    result += code_point > 0xFFFF ? 2 : 1;
    current = next;
  }
  return static_cast<uint32_t>(result);
}

bool utf16_to_utf8_offset(
    const DuiTextLayout& layout,
    uint32_t requested,
    size_t* byte_offset) {
  if (requested > layout.utf16_length) return false;
  size_t current = 0;
  uint32_t utf16_offset = 0;
  while (current < layout.text.size()) {
    if (utf16_offset == requested) {
      *byte_offset = current;
      return true;
    }
    uint32_t code_point = 0;
    size_t next = 0;
    if (!decode_utf8(layout.text, current, &code_point, &next)) return false;
    const uint32_t units = code_point > 0xFFFF ? 2 : 1;
    if (units == 2 && requested == utf16_offset + 1) return false;
    utf16_offset += units;
    current = next;
  }
  if (utf16_offset != requested) return false;
  *byte_offset = current;
  return true;
}

sk_sp<SkFontMgr> create_font_manager() {
#if defined(_WIN32)
  return SkFontMgr_New_DirectWrite();
#elif defined(__APPLE__)
  return SkFontMgr_New_CoreText(nullptr);
#else
  return SkFontMgr_New_FontConfig(nullptr, SkFontScanner_Make_FreeType());
#endif
}

// The font manager, the unicode implementation and the font collection are
// shared between all text operations. Creating them per call is expensive on
// Windows, and the legacy text drawing path runs on every rendered frame.
sk_sp<SkFontMgr> shared_font_manager() {
  static const sk_sp<SkFontMgr> manager = create_font_manager();
  return manager;
}

sk_sp<SkUnicode> shared_unicode() {
  static const sk_sp<SkUnicode> unicode = SkUnicodes::ICU::Make();
  return unicode;
}

sk_sp<skia::textlayout::FontCollection> shared_font_collection() {
  static const sk_sp<skia::textlayout::FontCollection> collection = [] {
    auto fonts = sk_make_sp<skia::textlayout::FontCollection>();
    fonts->setDefaultFontManager(shared_font_manager());
    return fonts;
  }();
  return collection;
}

// Builds a shaped SkParagraph. The paragraph is laid out with [max_width] in
// physical pixels; [font_size] is expected in physical pixels as well. The
// direction is 0 for left to right and 1 for right to left: it decides the
// order of the runs inside a line and the side the text starts from.
std::unique_ptr<skia::textlayout::Paragraph> create_paragraph(
    const char* text,
    size_t text_length,
    const char* font_family,
    size_t font_family_length,
    SkScalar font_size,
    int32_t alignment,
    int32_t direction,
    SkScalar max_width) {
  auto unicode = shared_unicode();
  auto fonts = shared_font_collection();
  if (!unicode || !fonts->getFallbackManager()) return nullptr;

  skia::textlayout::TextStyle text_style;
  text_style.setFontSize(font_size);
  if (font_family_length != 0) {
    text_style.setFontFamilies(
        {SkString(font_family, font_family_length)});
  }
  skia::textlayout::ParagraphStyle paragraph_style;
  paragraph_style.setTextStyle(text_style);
  switch (alignment) {
    case 1:
      paragraph_style.setTextAlign(skia::textlayout::TextAlign::kCenter);
      break;
    case 2:
      paragraph_style.setTextAlign(skia::textlayout::TextAlign::kRight);
      break;
    default:
      paragraph_style.setTextAlign(skia::textlayout::TextAlign::kLeft);
      break;
  }
  paragraph_style.setTextDirection(
      direction == 1 ? skia::textlayout::TextDirection::kRtl
                     : skia::textlayout::TextDirection::kLtr);

  auto builder = skia::textlayout::ParagraphBuilder::make(
      paragraph_style,
      fonts,
      unicode);
  if (!builder) return nullptr;
  builder->addText(text, text_length);
  auto paragraph = builder->Build();
  if (!paragraph) return nullptr;
  // The paragraph is laid out with a hair more room than it gets. The width
  // of a line and the width of the box are the same number, so a text that is
  // exactly as wide as its box would push its last word onto the next line.
  paragraph->layout(max_width + 1.0f);
  return paragraph;
}

void write_rect(DuiRect* output, const SkRect& input, double scale) {
  std::memset(output, 0, sizeof(*output));
  output->struct_size = sizeof(*output);
  output->left = input.left() / scale;
  output->top = input.top() / scale;
  output->width = input.width() / scale;
  output->height = input.height() / scale;
}

double window_pixel_density(SDL_Window* window) {
  const float value = window ? SDL_GetWindowPixelDensity(window) : 1.0f;
  return value > 0 ? value : 1.0;
}

double window_display_scale(SDL_Window* window) {
  const float value = window ? SDL_GetWindowDisplayScale(window) : 1.0f;
  return value > 0 ? value : 1.0;
}

double window_units_to_content(SDL_Window* window, double value) {
  return value * window_pixel_density(window) / window_display_scale(window);
}

double content_to_window_units(SDL_Window* window, double value) {
  return value * window_display_scale(window) / window_pixel_density(window);
}

bool SDLCALL live_resize_event_watch(void* user_data, SDL_Event* event) {
  auto* host = static_cast<DuiHost*>(user_data);
  if (!host || !event || !host->live_resize_callback ||
      host->live_resize_active ||
      SDL_GetCurrentThreadID() != host->thread_id) {
    return true;
  }

  const bool resized = event->type == SDL_EVENT_WINDOW_RESIZED;
  const bool pixel_size_changed =
      event->type == SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED;
  const bool live_expose = event->type == SDL_EVENT_WINDOW_EXPOSED &&
                           event->window.data1 == 1;
  if (!resized && !pixel_size_changed && !live_expose) return true;

  auto* window = SDL_GetWindowFromID(event->window.windowID);
  if (!window) return true;
  int width = event->window.data1;
  int height = event->window.data2;
  if ((pixel_size_changed || live_expose) &&
      !SDL_GetWindowSize(window, &width, &height)) {
    return true;
  }
  if (width <= 0 || height <= 0) return true;

  host->live_resize_active = true;
  host->live_resize_callback(
      host->live_resize_user_data,
      event->window.windowID,
      window_units_to_content(window, width),
      window_units_to_content(window, height));
  host->live_resize_active = false;
  return true;
}

bool ensure_surface(DuiWindow* window) {
  int width = 0;
  int height = 0;
  if (!SDL_GetWindowSizeInPixels(window->window, &width, &height)) {
    set_sdl_error();
    return false;
  }
  if (width <= 0 || height <= 0) {
    set_error("The window has an empty pixel surface.");
    return false;
  }
  if (window->surface && window->pixel_width == width &&
      window->pixel_height == height) {
    return true;
  }

  window->frame_active = false;
  window->surface.reset();
  if (window->texture) {
    SDL_DestroyTexture(window->texture);
    window->texture = nullptr;
  }

  window->texture = SDL_CreateTexture(
      window->renderer,
      SDL_PIXELFORMAT_ARGB8888,
      SDL_TEXTUREACCESS_STREAMING,
      width,
      height);
  if (!window->texture) {
    set_sdl_error();
    return false;
  }

  const auto info = SkImageInfo::Make(
      width,
      height,
      kBGRA_8888_SkColorType,
      kPremul_SkAlphaType);
  window->surface = SkSurfaces::Raster(
      info,
      static_cast<size_t>(width) * 4,
      nullptr);
  if (!window->surface) {
    set_error("Skia could not allocate a raster surface.");
    return false;
  }

  window->pixel_width = width;
  window->pixel_height = height;
  return true;
}

#if defined(_WIN32)
// The window handle of the platform, used by the accessibility bridge.
void* platform_window_handle(SDL_Window* window) {
  const SDL_PropertiesID properties = SDL_GetWindowProperties(window);
  return SDL_GetPointerProperty(properties, SDL_PROP_WINDOW_WIN32_HWND_POINTER, nullptr);
}
#endif

// The state of the accessibility bridge of the window.
DuiUiaSnapshot accessibility_snapshot(DuiWindow* window) {
  DuiUiaSnapshot snapshot;
  snapshot.nodes.reserve(window->accessible_nodes.size());
  for (const DuiAccessibleNodeData& node : window->accessible_nodes) {
    DuiUiaNode value;
    value.role = node.role;
    value.parent = node.parent;
    value.flags = node.flags;
    value.left = node.left;
    value.top = node.top;
    value.width = node.width;
    value.height = node.height;
    value.name = node.name;
    value.value = node.value;
    snapshot.nodes.push_back(std::move(value));
  }
  if (window->window) {
#if defined(_WIN32)
    void* handle = platform_window_handle(window->window);
    snapshot.hwnd = handle;
    if (handle != nullptr) {
      // The bounds of the nodes are relative to the client area of the
      // window, so the origin of the client area is needed.
      POINT origin{0, 0};
      ClientToScreen(static_cast<HWND>(handle), &origin);
      snapshot.window_x = origin.x;
      snapshot.window_y = origin.y;
    }
#endif
    const char* title = SDL_GetWindowTitle(window->window);
    if (title) snapshot.title = title;
    snapshot.scale = SDL_GetWindowDisplayScale(window->window);
    int width = 0;
    int height = 0;
    SDL_GetWindowSizeInPixels(window->window, &width, &height);
    snapshot.window_width = width;
    snapshot.window_height = height;
  }
  return snapshot;
}

void destroy_window_resources(DuiWindow* window) {
  window->surface.reset();
  if (window->window && SDL_TextInputActive(window->window)) {
    SDL_StopTextInput(window->window);
  }
#if defined(_WIN32)
  if (window->window) {
    dui_windows_remove_uia(platform_window_handle(window->window));
  }
#endif
  if (window->texture) SDL_DestroyTexture(window->texture);
  if (window->renderer) SDL_DestroyRenderer(window->renderer);
  if (window->window) SDL_DestroyWindow(window->window);
  window->texture = nullptr;
  window->renderer = nullptr;
  window->window = nullptr;
}

}  // namespace

uint32_t dui_abi_version(void) { return 6; }

const char* dui_last_error_message(void) { return last_error.c_str(); }

int32_t dui_clipboard_set_text(const char* text_utf8) {
SdlScope lock;
  clear_error();
  if (!text_utf8) {
    set_error("Clipboard text must not be null.");
    return 0;
  }
  if (!retry_clipboard_write(
          [&] { return SDL_SetClipboardText(text_utf8); })) {
    set_sdl_error();
    return 0;
  }
  return 1;
}

char* dui_clipboard_get_text(void) {
  SdlScope lock;
  clear_error();
  if (!SDL_HasClipboardText()) return nullptr;
  char* text = SDL_GetClipboardText();
  if (!text) set_sdl_error();
  return text;
}

void dui_clipboard_free_text(char* text) { SDL_free(text); }

int32_t dui_clipboard_set_data(
    const char* const* mime_types,
    const uint8_t* const* data,
    const size_t* sizes,
    size_t count) {
    SdlScope lock;
  clear_error();
  if (!mime_types || !data || !sizes || count == 0) {
    set_error("Formatted clipboard requires at least one data entry.");
    return 0;
  }
  try {
    std::unordered_map<std::string, std::vector<uint8_t>> replacement;
    std::vector<const char*> mime_type_names;
    mime_type_names.reserve(count);
    for (size_t index = 0; index < count; ++index) {
      const char* mime_type = mime_types[index];
      if (!mime_type || !*mime_type || (sizes[index] > 0 && !data[index])) {
        set_error("Invalid formatted clipboard entry.");
        return 0;
      }
      std::vector<uint8_t> bytes;
      if (sizes[index] > 0) {
        bytes.assign(data[index], data[index] + sizes[index]);
      }
      replacement.emplace(mime_type, std::move(bytes));
#if defined(_WIN32)
      if (is_html_mime(mime_type)) continue;
#endif
      mime_type_names.push_back(mime_type);
    }
    clipboard_formats = std::move(replacement);
    if (!mime_type_names.empty()) {
      if (!retry_clipboard_write([&] {
            return SDL_SetClipboardData(
                clipboard_data_callback,
                clipboard_cleanup_callback,
                nullptr,
                mime_type_names.data(),
                mime_type_names.size());
          })) {
        clipboard_formats.clear();
        set_sdl_error();
        return 0;
      }
    }
#if defined(_WIN32)
    else if (!clear_clipboard_for_html()) {
      clipboard_formats.clear();
      return 0;
    }
    const auto html = clipboard_formats.find("text/html");
    if (html != clipboard_formats.end() && !write_html_clipboard(html->second)) {
      clipboard_formats.clear();
      return 0;
    }
#endif
    return 1;
  } catch (const std::exception& error) {
    clipboard_formats.clear();
    set_error(error.what());
    return 0;
  }
}

int32_t dui_clipboard_has_data(const char* mime_type) {
SdlScope lock;
  clear_error();
  if (!mime_type || !*mime_type) {
    set_error("Clipboard MIME type must not be empty.");
    return 0;
  }
#if defined(_WIN32)
  if (is_html_mime(mime_type)) {
    const UINT format = html_clipboard_format();
    return format && IsClipboardFormatAvailable(format) ? 1 : 0;
  }
#endif
  return SDL_HasClipboardData(mime_type) ? 1 : 0;
}

void* dui_clipboard_get_data(const char* mime_type, size_t* out_size) {
  SdlScope lock;
  clear_error();
  if (!mime_type || !*mime_type || !out_size) {
    set_error("Invalid formatted clipboard read arguments.");
    return nullptr;
  }
  *out_size = 0;
#if defined(_WIN32)
  if (is_html_mime(mime_type)) {
    const UINT format = html_clipboard_format();
    if (!format || !IsClipboardFormatAvailable(format)) return nullptr;
    try {
      std::vector<uint8_t> fragment;
      if (!read_html_clipboard(&fragment)) return nullptr;
      *out_size = fragment.size();
      void* result = SDL_malloc(fragment.empty() ? 1 : fragment.size());
      if (!result) {
        *out_size = 0;
        set_error("Couldn't allocate clipboard HTML result.");
        return nullptr;
      }
      if (!fragment.empty()) std::memcpy(result, fragment.data(), fragment.size());
      return result;
    } catch (const std::exception& error) {
      set_error(error.what());
      return nullptr;
    }
  }
#endif
  if (!SDL_HasClipboardData(mime_type)) return nullptr;
  SDL_ClearError();
  void* data = SDL_GetClipboardData(mime_type, out_size);
  if (!data && *out_size == 0 && !SDL_GetError()[0]) {
    /* SDL represents a present empty payload as NULL; preserve the distinction
     * between an empty format and a missing format at the C ABI boundary. */
    data = SDL_malloc(1);
  }
  if (!data) set_sdl_error();
  return data;
}

void dui_clipboard_free_data(void* data) { SDL_free(data); }

int32_t dui_clipboard_clear(void) {
SdlScope lock;
  clear_error();
  if (!retry_clipboard_write([] { return SDL_ClearClipboardData(); })) {
    set_sdl_error();
    return 0;
  }
  clipboard_formats.clear();
  return 1;
}

char** dui_clipboard_get_mime_types(size_t* out_count) {
  SdlScope lock;
  clear_error();
  if (!out_count) {
    set_error("Clipboard MIME type count must not be null.");
    return nullptr;
  }
  *out_count = 0;
  size_t sdl_count = 0;
  SDL_ClearError();
  char** sdl_types = SDL_GetClipboardMimeTypes(&sdl_count);
  if (!sdl_types && SDL_GetError()[0]) {
    set_sdl_error();
    return nullptr;
  }
  std::unique_ptr<void, void (*)(void*)> sdl_owner(sdl_types, &SDL_free);
  try {
    std::vector<std::string> names;
    for (size_t index = 0; index < sdl_count; ++index) {
      if (sdl_types[index] &&
          std::find(names.begin(), names.end(), sdl_types[index]) == names.end()) {
        names.emplace_back(sdl_types[index]);
      }
    }
#if defined(_WIN32)
    const UINT html_format = html_clipboard_format();
    if (html_format && IsClipboardFormatAvailable(html_format) &&
        std::find(names.begin(), names.end(), "text/html") == names.end()) {
      names.emplace_back("text/html");
    }
#endif
    char** result = static_cast<char**>(
        SDL_calloc(names.size() + 1, sizeof(char*)));
    if (!result) {
      set_error("Couldn't allocate clipboard MIME type list.");
      return nullptr;
    }
    for (size_t index = 0; index < names.size(); ++index) {
      const size_t size = names[index].size() + 1;
      result[index] = static_cast<char*>(SDL_malloc(size));
      if (!result[index]) {
        dui_clipboard_free_mime_types(result, index);
        set_error("Couldn't allocate clipboard MIME type.");
        return nullptr;
      }
      std::memcpy(result[index], names[index].c_str(), size);
    }
    *out_count = names.size();
    return result;
  } catch (const std::exception& error) {
    set_error(error.what());
    return nullptr;
  }
}

void dui_clipboard_free_mime_types(char** mime_types, size_t count) {
  if (!mime_types) return;
  for (size_t index = 0; index < count; ++index) SDL_free(mime_types[index]);
  SDL_free(mime_types);
}

DuiHost* dui_host_create(void) {
  SdlScope lock;
  clear_error();
  try {
    if (!ensure_sdl_initialized()) {
      return nullptr;
    }
    if (live_host_count() > 0) {
      set_error(
          "Only one native host per process is supported: SDL has a single "
          "global event queue, so a second host would steal the events of "
          "the first one.");
      return nullptr;
    }
    auto host = std::make_unique<DuiHost>();
    host->thread_id = SDL_GetCurrentThreadID();
    if (!SDL_AddEventWatch(live_resize_event_watch, host.get())) {
      set_sdl_error();
      return nullptr;
    }
    live_host_count() = 1;
    return host.release();
  } catch (const std::exception& error) {
    set_error(error.what());
    return nullptr;
  } catch (...) {
    set_error("Unknown native host creation error.");
    return nullptr;
  }
}

void dui_host_destroy(DuiHost* host) {
  if (!host) return;
  SdlScope lock;
  SDL_RemoveEventWatch(live_resize_event_watch, host);
  for (auto& window : host->windows) destroy_window_resources(window.get());
  host->windows.clear();
  delete host;
  if (live_host_count() > 0) live_host_count() = 0;
}

int32_t dui_host_set_live_resize_callback(
    DuiHost* host,
    DuiLiveResizeCallback callback,
    void* user_data) {
    SdlScope lock;
  clear_error();
  if (!host) {
    set_error("Invalid host.");
    return 0;
  }
  host->live_resize_callback = callback;
  host->live_resize_user_data = callback ? user_data : nullptr;
  return 1;
}

static int32_t translate_event(
    DuiHost* host, DuiEvent* out_event, const SDL_Event& source) {

  out_event->window_id = 0;
  switch (source.type) {
    case SDL_EVENT_QUIT:
      out_event->type = DUI_EVENT_QUIT;
      break;
    case SDL_EVENT_WINDOW_CLOSE_REQUESTED:
      out_event->type = DUI_EVENT_CLOSE;
      out_event->window_id = source.window.windowID;
      break;
    case SDL_EVENT_WINDOW_RESIZED: {
      out_event->type = DUI_EVENT_RESIZE;
      out_event->window_id = source.window.windowID;
      auto* event_window = SDL_GetWindowFromID(source.window.windowID);
      out_event->width =
          window_units_to_content(event_window, source.window.data1);
      out_event->height =
          window_units_to_content(event_window, source.window.data2);
      break;
    }
    case SDL_EVENT_MOUSE_BUTTON_DOWN:
    case SDL_EVENT_MOUSE_BUTTON_UP: {
      out_event->type = source.type == SDL_EVENT_MOUSE_BUTTON_DOWN
                            ? DUI_EVENT_POINTER_DOWN
                            : DUI_EVENT_POINTER_UP;
      out_event->window_id = source.button.windowID;
      auto* event_window = SDL_GetWindowFromID(source.button.windowID);
      out_event->x = window_units_to_content(event_window, source.button.x);
      out_event->y = window_units_to_content(event_window, source.button.y);
      out_event->key_code = source.button.button;
      break;
    }
    case SDL_EVENT_MOUSE_MOTION: {
      out_event->type = DUI_EVENT_POINTER_MOVE;
      out_event->window_id = source.motion.windowID;
      auto* event_window = SDL_GetWindowFromID(source.motion.windowID);
      out_event->x = window_units_to_content(event_window, source.motion.x);
      out_event->y = window_units_to_content(event_window, source.motion.y);
      break;
    }
    case SDL_EVENT_MOUSE_WHEEL: {
      out_event->type = DUI_EVENT_MOUSE_WHEEL;
      out_event->window_id = source.wheel.windowID;
      auto* event_window = SDL_GetWindowFromID(source.wheel.windowID);
      out_event->x = window_units_to_content(event_window, source.wheel.mouse_x);
      out_event->y = window_units_to_content(event_window, source.wheel.mouse_y);
      const float direction =
          source.wheel.direction == SDL_MOUSEWHEEL_FLIPPED ? -1.0F : 1.0F;
      out_event->width = source.wheel.x * direction;
      out_event->height = source.wheel.y * direction;
      break;
    }
    case SDL_EVENT_TEXT_INPUT:
      out_event->type = DUI_EVENT_TEXT_INPUT;
      out_event->window_id = source.text.windowID;
      host->text_storage = source.text.text ? source.text.text : "";
      out_event->text_utf8 = host->text_storage.c_str();
      break;
    case SDL_EVENT_TEXT_EDITING:
      out_event->type = DUI_EVENT_TEXT_EDITING;
      out_event->window_id = source.edit.windowID;
      host->text_storage = source.edit.text ? source.edit.text : "";
      out_event->text_utf8 = host->text_storage.c_str();
      if (source.edit.start >= 0 && source.edit.length >= 0) {
        out_event->composition_start = static_cast<int32_t>(
            utf8_prefix_utf16_length(source.edit.text, source.edit.start));
        out_event->composition_length = static_cast<int32_t>(
            utf8_prefix_utf16_length(
                source.edit.text, source.edit.start + source.edit.length) -
            out_event->composition_start);
      } else {
        out_event->composition_start = -1;
        out_event->composition_length = -1;
      }
      break;
    case SDL_EVENT_KEY_DOWN:
      out_event->type = DUI_EVENT_KEY_DOWN;
      out_event->window_id = source.key.windowID;
      out_event->key_code = static_cast<int32_t>(source.key.key);
      out_event->scan_code = static_cast<int32_t>(source.key.scancode);
      out_event->modifiers = static_cast<uint16_t>(source.key.mod);
      break;
    default:
      out_event->type = DUI_EVENT_NONE;
      break;
  }
  return 1;
}

int32_t dui_host_next_event(DuiHost* host, DuiEvent* out_event) {
SdlScope lock;
  clear_error();
  if (!host || !out_event) {
    set_error("Invalid event arguments.");
    return -1;
  }
  std::memset(out_event, 0, sizeof(*out_event));
  out_event->struct_size = sizeof(*out_event);
  SDL_Event source;
  if (!SDL_PollEvent(&source)) return 0;
  return translate_event(host, out_event, source);
}

int32_t dui_host_wait_event(
    DuiHost* host, DuiEvent* out_event, int32_t timeout_ms) {
    SdlScope lock;
  clear_error();
  if (!host || !out_event || timeout_ms < -1) {
    set_error("Invalid event arguments.");
    return -1;
  }
  std::memset(out_event, 0, sizeof(*out_event));
  out_event->struct_size = sizeof(*out_event);
  SDL_Event source;
  if (!SDL_WaitEventTimeout(&source, timeout_ms)) {
    if (timeout_ms >= 0) return 0;
    set_sdl_error();
    return -1;
  }
  return translate_event(host, out_event, source);
}

int32_t dui_host_wake_up(DuiHost* host) {
SdlScope lock;
  clear_error();
  if (!host) {
    set_error("Invalid host.");
    return 0;
  }
  SDL_Event event;
  std::memset(&event, 0, sizeof(event));
  event.type = SDL_EVENT_USER;
  if (!SDL_PushEvent(&event)) {
    set_sdl_error();
    return 0;
  }
  return 1;
}

DuiWindow* dui_window_create(
    DuiHost* host,
    const char* title_utf8,
    int32_t width,
    int32_t height) {
    SdlScope lock;
  clear_error();
  if (!host || width <= 0 || height <= 0) {
    set_error("Invalid window creation arguments.");
    return nullptr;
  }
  try {
    auto window = std::make_unique<DuiWindow>(host);
    window->window = SDL_CreateWindow(
        title_utf8 ? title_utf8 : "DUI",
        width,
        height,
        SDL_WINDOW_RESIZABLE | SDL_WINDOW_HIGH_PIXEL_DENSITY);
    if (!window->window) {
      set_sdl_error();
      return nullptr;
    }
    SDL_SetWindowSize(
        window->window,
        static_cast<int>(std::lround(
            content_to_window_units(window->window, width))),
        static_cast<int>(std::lround(
            content_to_window_units(window->window, height))));
    window->renderer = SDL_CreateRenderer(window->window, nullptr);
    if (!window->renderer) {
      destroy_window_resources(window.get());
      set_sdl_error();
      return nullptr;
    }
    if (!SDL_SetRenderVSync(window->renderer, 1)) {
      destroy_window_resources(window.get());
      set_sdl_error();
      return nullptr;
    }

#if defined(_WIN32)
    dui_windows_install_uia(platform_window_handle(window->window));
#endif

    DuiWindow* result = window.get();
    host->windows.push_back(std::move(window));
    return result;
  } catch (const std::exception& error) {
    set_error(error.what());
    return nullptr;
  } catch (...) {
    set_error("Unknown native window creation error.");
    return nullptr;
  }
}

void dui_window_destroy(DuiHost* host, DuiWindow* window) {
SdlScope lock;
  if (!host || !window) return;
  const auto found = std::find_if(
      host->windows.begin(),
      host->windows.end(),
      [window](const auto& item) { return item.get() == window; });
  if (found == host->windows.end()) return;
  destroy_window_resources(window);
  host->windows.erase(found);
}

int32_t dui_window_set_size(
    DuiWindow* window,
    int32_t logical_width,
    int32_t logical_height) {
    SdlScope lock;
  clear_error();
  if (!window || !window->window || logical_width <= 0 || logical_height <= 0) {
    set_error("Invalid window size arguments.");
    return 0;
  }
  if (!SDL_SetWindowSize(
          window->window,
          static_cast<int>(std::lround(
              content_to_window_units(window->window, logical_width))),
          static_cast<int>(std::lround(
              content_to_window_units(window->window, logical_height))))) {
    set_sdl_error();
    return 0;
  }
  return 1;
}

uint64_t dui_window_get_id(const DuiWindow* window) {
  SdlScope lock;
  return window && window->window ? SDL_GetWindowID(window->window) : 0;
}

char* dui_window_open_file_dialog(
    DuiWindow* window,
    const char* title_utf8,
    const char* initial_directory_utf8,
    const DuiFileDialogFilter* filters,
    size_t filter_count) {
  clear_error();
#if defined(_WIN32)
  if ((filter_count > 0 && !filters) ||
      filter_count > std::numeric_limits<UINT>::max()) {
    set_error("Invalid open-file dialog filters.");
    return nullptr;
  }
  auto widen = [](const char* value, std::wstring* output) {
    const int size = MultiByteToWideChar(
        CP_UTF8, MB_ERR_INVALID_CHARS, value, -1, nullptr, 0);
    if (size <= 0) return false;
    output->assign(static_cast<size_t>(size), L'\0');
    return MultiByteToWideChar(
               CP_UTF8, MB_ERR_INVALID_CHARS, value, -1, output->data(), size) >
           0;
  };
  HRESULT initialized = CoInitializeEx(
      nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
  const bool uninitialize = SUCCEEDED(initialized);
  if (FAILED(initialized) && initialized != RPC_E_CHANGED_MODE) {
    set_error("Couldn't initialize COM for the open-file dialog.");
    return nullptr;
  }
  IFileOpenDialog* dialog = nullptr;
  HRESULT result = CoCreateInstance(
      CLSID_FileOpenDialog,
      nullptr,
      CLSCTX_INPROC_SERVER,
      IID_PPV_ARGS(&dialog));
  if (FAILED(result)) {
    if (uninitialize) CoUninitialize();
    set_error("Couldn't create the system open-file dialog.");
    return nullptr;
  }
  auto finish = [&] {
    dialog->Release();
    if (uninitialize) CoUninitialize();
  };
  if (title_utf8 && *title_utf8) {
    std::wstring title;
    if (!widen(title_utf8, &title) || FAILED(dialog->SetTitle(title.c_str()))) {
      finish();
      set_error("Couldn't set the open-file dialog title.");
      return nullptr;
    }
  }
  if (initial_directory_utf8 && *initial_directory_utf8) {
    std::wstring directory;
    if (!widen(initial_directory_utf8, &directory)) {
      finish();
      set_error("Invalid UTF-8 in the initial directory.");
      return nullptr;
    }
    IShellItem* folder = nullptr;
    result = SHCreateItemFromParsingName(
        directory.c_str(), nullptr, IID_PPV_ARGS(&folder));
    if (FAILED(result)) {
      finish();
      set_error("Couldn't resolve the initial directory.");
      return nullptr;
    }
    result = dialog->SetFolder(folder);
    folder->Release();
    if (FAILED(result)) {
      finish();
      set_error("Couldn't set the initial directory.");
      return nullptr;
    }
  }
  if (filter_count > 0) {
    std::vector<std::wstring> strings;
    strings.reserve(filter_count * 2);
    for (size_t index = 0; index < filter_count; ++index) {
      const auto& filter = filters[index];
      if (!filter.name_utf8 || !filter.spec_utf8) {
        finish();
        set_error("Invalid UTF-8 in the open-file dialog filters.");
        return nullptr;
      }
      std::wstring name;
      std::wstring spec;
      if (!widen(filter.name_utf8, &name) ||
          !widen(filter.spec_utf8, &spec)) {
        finish();
        set_error("Invalid UTF-8 in the open-file dialog filters.");
        return nullptr;
      }
      strings.push_back(std::move(name));
      strings.push_back(std::move(spec));
    }
    std::vector<COMDLG_FILTERSPEC> specs;
    specs.reserve(filter_count);
    for (size_t index = 0; index < filter_count; ++index) {
      specs.push_back(COMDLG_FILTERSPEC{
          strings[index * 2].c_str(), strings[index * 2 + 1].c_str()});
    }
    result = dialog->SetFileTypes(
        static_cast<UINT>(filter_count), specs.data());
    if (FAILED(result)) {
      finish();
      set_error("Couldn't set the open-file dialog filters.");
      return nullptr;
    }
  }
  DWORD options = 0;
  if (SUCCEEDED(dialog->GetOptions(&options))) {
    dialog->SetOptions(options | FOS_FILEMUSTEXIST | FOS_PATHMUSTEXIST);
  }
  HWND owner = nullptr;
  if (window && window->window) {
    owner = static_cast<HWND>(SDL_GetPointerProperty(
        SDL_GetWindowProperties(window->window),
        SDL_PROP_WINDOW_WIN32_HWND_POINTER,
        nullptr));
  }
  result = dialog->Show(owner);
  if (result == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
    finish();
    return nullptr;
  }
  if (FAILED(result)) {
    finish();
    set_error("The system open-file dialog failed.");
    return nullptr;
  }
  IShellItem* item = nullptr;
  result = dialog->GetResult(&item);
  if (FAILED(result)) {
    finish();
    set_error("Couldn't read the selected file.");
    return nullptr;
  }
  PWSTR path = nullptr;
  result = item->GetDisplayName(SIGDN_FILESYSPATH, &path);
  item->Release();
  if (FAILED(result)) {
    finish();
    set_error("Couldn't read the selected file path.");
    return nullptr;
  }
  const int size = WideCharToMultiByte(
      CP_UTF8, 0, path, -1, nullptr, 0, nullptr, nullptr);
  char* utf8 = size > 0 ? static_cast<char*>(SDL_malloc(size)) : nullptr;
  if (utf8) {
    WideCharToMultiByte(CP_UTF8, 0, path, -1, utf8, size, nullptr, nullptr);
  }
  CoTaskMemFree(path);
  finish();
  if (!utf8) set_error("Couldn't allocate the selected file path.");
  return utf8;
#elif defined(__linux__)
  (void)window;  // SDL's X11/Wayland handles are not GtkWindow instances.
  if (filter_count > 0 && !filters) {
    set_error("Invalid open-file dialog filters.");
    return nullptr;
  }
  static bool gtk_initialized = false;
  if (!gtk_initialized) {
    if (!gtk_init_check()) {
      set_error("Couldn't initialize GTK for the open-file dialog.");
      return nullptr;
    }
    gtk_initialized = true;
  }

  GtkFileDialog* dialog = gtk_file_dialog_new();
  if (!dialog) {
    set_error("Couldn't create the system open-file dialog.");
    return nullptr;
  }
  if (title_utf8 && *title_utf8) {
    gtk_file_dialog_set_title(dialog, title_utf8);
  }
  if (initial_directory_utf8 && *initial_directory_utf8) {
    GFile* folder = g_file_new_for_path(initial_directory_utf8);
    gtk_file_dialog_set_initial_folder(dialog, folder);
    g_object_unref(folder);
  }
  if (filter_count > 0) {
    GListStore* store = g_list_store_new(GTK_TYPE_FILE_FILTER);
    for (size_t index = 0; index < filter_count; ++index) {
      const auto& filter = filters[index];
      if (!filter.name_utf8 || !filter.spec_utf8) {
        g_object_unref(store);
        g_object_unref(dialog);
        set_error("Invalid UTF-8 in the open-file dialog filters.");
        return nullptr;
      }
      GtkFileFilter* file_filter = gtk_file_filter_new();
      gtk_file_filter_set_name(file_filter, filter.name_utf8);
      gchar** patterns = g_strsplit(filter.spec_utf8, ";", -1);
      bool has_pattern = false;
      for (gchar** pattern = patterns; *pattern; ++pattern) {
        g_strstrip(*pattern);
        if (!**pattern) continue;
        gtk_file_filter_add_pattern(
            file_filter, g_str_equal(*pattern, "*.*") ? "*" : *pattern);
        has_pattern = true;
      }
      g_strfreev(patterns);
      if (!has_pattern) {
        g_object_unref(file_filter);
        g_object_unref(store);
        g_object_unref(dialog);
        set_error("An open-file dialog filter has no patterns.");
        return nullptr;
      }
      g_list_store_append(store, file_filter);
      g_object_unref(file_filter);
    }
    gtk_file_dialog_set_filters(dialog, G_LIST_MODEL(store));
    g_object_unref(store);
  }

  GtkOpenDialogResult result = {};
  result.loop = g_main_loop_new(nullptr, FALSE);
  gtk_file_dialog_open(
      dialog, nullptr, nullptr, gtk_open_dialog_ready, &result);
  g_main_loop_run(result.loop);
  g_main_loop_unref(result.loop);
  g_object_unref(dialog);

  if (result.error) {
    const bool dismissed = g_error_matches(
                               result.error,
                               GTK_DIALOG_ERROR,
                               GTK_DIALOG_ERROR_DISMISSED) ||
                           g_error_matches(
                               result.error,
                               GTK_DIALOG_ERROR,
                               GTK_DIALOG_ERROR_CANCELLED) ||
                           g_error_matches(
                               result.error, G_IO_ERROR, G_IO_ERROR_CANCELLED);
    if (!dismissed) {
      set_error(
          (std::string("The system open-file dialog failed: ") +
           result.error->message)
              .c_str());
    }
    g_error_free(result.error);
    return nullptr;
  }
  if (!result.file) {
    set_error("Couldn't read the selected file.");
    return nullptr;
  }
  gchar* path = g_file_get_path(result.file);
  g_object_unref(result.file);
  if (!path) {
    set_error("The selected file has no local filesystem path.");
    return nullptr;
  }
  const size_t size = std::strlen(path) + 1;
  char* utf8 = static_cast<char*>(SDL_malloc(size));
  if (utf8) {
    std::memcpy(utf8, path, size);
  } else {
    set_error("Couldn't allocate the selected file path.");
  }
  g_free(path);
  return utf8;
#elif defined(__APPLE__)
  return dui_macos_open_file_dialog(
      window ? window->window : nullptr,
      title_utf8,
      initial_directory_utf8,
      filters,
      filter_count,
      &last_error);
#else
  set_error("The system open-file dialog is not implemented on this platform.");
  return nullptr;
#endif
}

void dui_file_dialog_free_path(char* path) { SDL_free(path); }

double dui_window_get_content_scale(const DuiWindow* window) {
  SdlScope lock;
  return window ? window_display_scale(window->window) : 1.0;
}

int32_t dui_window_get_metrics(
    const DuiWindow* window,
    DuiWindowMetrics* out_metrics) {
    SdlScope lock;
  clear_error();
  if (!window || !window->window || !out_metrics) {
    set_error("Invalid window metrics arguments.");
    return 0;
  }

  int width = 0;
  int height = 0;
  if (!SDL_GetWindowSizeInPixels(window->window, &width, &height)) {
    set_sdl_error();
    return 0;
  }
  std::memset(out_metrics, 0, sizeof(*out_metrics));
  out_metrics->struct_size = sizeof(*out_metrics);
  out_metrics->physical_width = width;
  out_metrics->physical_height = height;
  out_metrics->display_scale = window_display_scale(window->window);
  out_metrics->pixel_density = window_pixel_density(window->window);
  return 1;
}

void dui_window_set_background(DuiWindow* window, uint32_t rgba) {
SdlScope lock;
  if (window) window->background_rgba = rgba;
}

int32_t dui_window_start_text_input(DuiWindow* window) {
SdlScope lock;
  clear_error();
  if (!window || !window->window) {
    set_error("Invalid text input window.");
    return 0;
  }
  if (!SDL_StartTextInput(window->window)) {
    set_sdl_error();
    return 0;
  }
  return 1;
}

int32_t dui_window_stop_text_input(DuiWindow* window) {
SdlScope lock;
  clear_error();
  if (!window || !window->window) {
    set_error("Invalid text input window.");
    return 0;
  }
  if (!SDL_StopTextInput(window->window)) {
    set_sdl_error();
    return 0;
  }
  return 1;
}

int32_t dui_window_set_accessibility_tree(
    DuiWindow* window,
    const DuiAccessibleNode* nodes,
    size_t count) {
  SdlScope lock;
  clear_error();
  if (!window) {
    set_error("The window handle is not valid.");
    return 0;
  }
  std::vector<DuiAccessibleNodeData> tree;
  tree.reserve(count);
  for (size_t index = 0; index < count; index++) {
    const DuiAccessibleNode& node = nodes[index];
    DuiAccessibleNodeData data;
    data.role = node.role;
    data.parent = node.parent;
    data.flags = node.flags;
    data.left = node.left;
    data.top = node.top;
    data.width = node.width;
    data.height = node.height;
    if (node.name_utf8) {
      data.name.assign(node.name_utf8);
    }
    if (node.value_utf8) {
      data.value.assign(node.value_utf8);
    }
    tree.push_back(std::move(data));
  }
  window->accessible_nodes = std::move(tree);
#if defined(_WIN32)
  if (window->window) {
    dui_windows_update_uia(
        platform_window_handle(window->window),
        accessibility_snapshot(window));
  }
#endif
  return 1;
}

int32_t dui_window_get_accessibility_node_count(const DuiWindow* window) {
  SdlScope lock;
  clear_error();
  if (!window) {
    set_error("The window handle is not valid.");
    return 0;
  }
  return static_cast<int32_t>(window->accessible_nodes.size());
}

int32_t dui_window_get_accessibility_node_info(
    const DuiWindow* window,
    int32_t index,
    DuiAccessibleNodeInfo* out_info) {
  SdlScope lock;
  clear_error();
  if (!window || !out_info) {
    set_error("The window handle is not valid.");
    return 0;
  }
  if (index < 0 ||
      static_cast<size_t>(index) >= window->accessible_nodes.size()) {
    set_error("The accessible node index is out of range.");
    return 0;
  }
  const DuiAccessibleNodeData& node =
      window->accessible_nodes[static_cast<size_t>(index)];
  out_info->struct_size = sizeof(DuiAccessibleNodeInfo);
  out_info->role = node.role;
  out_info->parent = node.parent;
  out_info->flags = node.flags;
  out_info->left = node.left;
  out_info->top = node.top;
  out_info->width = node.width;
  out_info->height = node.height;
  out_info->name_length = static_cast<int32_t>(node.name.size());
  out_info->value_length = static_cast<int32_t>(node.value.size());
  return 1;
}

const char* dui_window_get_accessibility_node_name(
    const DuiWindow* window,
    int32_t index) {
  SdlScope lock;
  if (!window || index < 0 ||
      static_cast<size_t>(index) >= window->accessible_nodes.size()) {
    return nullptr;
  }
  return window->accessible_nodes[static_cast<size_t>(index)].name.c_str();
}

const char* dui_window_get_accessibility_node_value(
    const DuiWindow* window,
    int32_t index) {
  SdlScope lock;
  if (!window || index < 0 ||
      static_cast<size_t>(index) >= window->accessible_nodes.size()) {
    return nullptr;
  }
  return window->accessible_nodes[static_cast<size_t>(index)].value.c_str();
}

int32_t dui_window_text_input_active(const DuiWindow* window) {
SdlScope lock;
  clear_error();
  if (!window || !window->window) {
    set_error("Invalid text input window.");
    return -1;
  }
  return SDL_TextInputActive(window->window) ? 1 : 0;
}

int32_t dui_window_set_text_input_area(
    DuiWindow* window,
    double x,
    double y,
    double width,
    double height,
    double cursor_x) {
    SdlScope lock;
  clear_error();
  if (!window || !window->window || !std::isfinite(x) ||
      !std::isfinite(y) || !std::isfinite(width) ||
      !std::isfinite(height) || !std::isfinite(cursor_x) || width < 0 ||
      height < 0) {
    set_error("Invalid text input area arguments.");
    return 0;
  }
  SDL_Rect area{
      static_cast<int>(std::lround(content_to_window_units(window->window, x))),
      static_cast<int>(std::lround(content_to_window_units(window->window, y))),
      static_cast<int>(
          std::lround(content_to_window_units(window->window, width))),
      static_cast<int>(
          std::lround(content_to_window_units(window->window, height))),
  };
  const auto cursor = static_cast<int>(
      std::lround(content_to_window_units(window->window, cursor_x)));
  if (!SDL_SetTextInputArea(window->window, &area, cursor)) {
    set_sdl_error();
    return 0;
  }
  return 1;
}

int32_t dui_window_begin_frame(DuiWindow* window) {
SdlScope lock;
  clear_error();
  if (!window) {
    set_error("Invalid window frame arguments.");
    return 0;
  }
  if (!ensure_surface(window)) return 0;
  window->frame_active = true;
  auto* canvas = window->surface->getCanvas();
  canvas->resetMatrix();
  canvas->clear(static_cast<SkColor>(window->background_rgba));
  canvas->save();
  const auto scale = static_cast<SkScalar>(
      dui_window_get_content_scale(window));
  canvas->scale(scale, scale);
  return 1;
}

int32_t dui_window_push_clip_rect(
    DuiWindow* window,
    double x,
    double y,
    double width,
    double height) {
    SdlScope lock;
  clear_error();
  if (!window || !window->frame_active || !window->surface ||
      !std::isfinite(x) || !std::isfinite(y) || !std::isfinite(width) ||
      !std::isfinite(height) || width < 0 || height < 0) {
    set_error("Invalid clip rectangle arguments or no active frame.");
    return 0;
  }
  auto* canvas = window->surface->getCanvas();
  canvas->save();
  canvas->clipRect(
      SkRect::MakeXYWH(x, y, width, height), SkClipOp::kIntersect, true);
  return 1;
}

int32_t dui_window_pop_clip(DuiWindow* window) {
  SdlScope lock;
  clear_error();
  if (!window || !window->frame_active || !window->surface) {
    set_error("Cannot restore clip without an active frame.");
    return 0;
  }
  window->surface->getCanvas()->restore();
  return 1;
}

// The blend mode of the paint.
SkBlendMode blend_mode_for(int32_t mode) {
  switch (mode) {
    case 1:
      return SkBlendMode::kScreen;
    case 2:
      return SkBlendMode::kMultiply;
    case 3:
      return SkBlendMode::kPlus;
    case 4:
      return SkBlendMode::kDifference;
    case 5:
      return SkBlendMode::kLighten;
    case 6:
      return SkBlendMode::kDarken;
    case 7:
      return SkBlendMode::kOverlay;
    default:
      return SkBlendMode::kSrcOver;
  }
}

// The paint of a shape: the color with its transparency, the stroke and the
// blend mode.
SkPaint make_paint(const DuiPaint* paint) {
  SkPaint result;
  result.setAntiAlias(true);
  if (paint == nullptr) return result;
  uint8_t alpha = SkColorGetA(paint->rgba);
  double opacity = paint->opacity;
  if (!std::isfinite(opacity)) opacity = 1.0;
  opacity = std::clamp(opacity, 0.0, 1.0);
  if (opacity < 1.0) {
    alpha = static_cast<uint8_t>(std::lround(alpha * opacity));
  }
  result.setColor(SkColorSetARGB(
      alpha,
      SkColorGetR(paint->rgba),
      SkColorGetG(paint->rgba),
      SkColorGetB(paint->rgba)));
  result.setBlendMode(blend_mode_for(paint->blend_mode));
  if (std::isfinite(paint->stroke_width) && paint->stroke_width > 0) {
    result.setStyle(SkPaint::kStroke_Style);
    result.setStrokeWidth(static_cast<SkScalar>(paint->stroke_width));
    result.setStrokeJoin(SkPaint::kRound_Join);
    result.setStrokeCap(SkPaint::kRound_Cap);
  }
  return result;
}

// Whether the paint carries a shadow.
bool has_shadow(const DuiPaint* paint) {
  if (paint == nullptr || paint->shadow_rgba == 0) return false;
  return paint->shadow_blur > 0 || paint->shadow_dx != 0 ||
      paint->shadow_dy != 0;
}

// The paint of the shadow: the silhouette of the shape, blurred and shifted.
SkPaint make_shadow_paint(const DuiPaint* paint) {
  SkPaint result = make_paint(paint);
  result.setStyle(SkPaint::kFill_Style);
  result.setColor(SkColorSetARGB(
      SkColorGetA(paint->shadow_rgba),
      SkColorGetR(paint->shadow_rgba),
      SkColorGetG(paint->shadow_rgba),
      SkColorGetB(paint->shadow_rgba)));
  if (paint->shadow_blur > 0) {
    // The blur of Skia is the standard deviation, the radius of the shadow is
    // twice it.
    const auto sigma = static_cast<SkScalar>(paint->shadow_blur / 2);
    result.setMaskFilter(SkMaskFilter::MakeBlur(
        kNormal_SkBlurStyle, sigma, false));
  }
  return result;
}

// Draws the shape twice: the shadow under it and the shape itself.
template <typename Draw>
void draw_with_shadow(
    SkCanvas* canvas,
    const DuiPaint* paint,
    const Draw& draw) {
  if (has_shadow(paint)) {
    canvas->save();
    canvas->translate(
        static_cast<SkScalar>(paint->shadow_dx),
        static_cast<SkScalar>(paint->shadow_dy));
    draw(canvas, make_shadow_paint(paint));
    canvas->restore();
  }
  draw(canvas, make_paint(paint));
}

void dui_draw_rect(
    DuiWindow* window,
    double x,
    double y,
    double width,
    double height,
    const DuiPaint* paint) {
  SdlScope lock;
  if (!window || !window->frame_active) return;
  const auto rect = SkRect::MakeXYWH(x, y, width, height);
  draw_with_shadow(
      window->surface->getCanvas(),
      paint,
      [rect](SkCanvas* canvas, const SkPaint& value) {
        canvas->drawRect(rect, value);
      });
}

void dui_draw_rounded_rect(
    DuiWindow* window,
    double x,
    double y,
    double width,
    double height,
    double radius_x,
    double radius_y,
    const DuiPaint* paint) {
  SdlScope lock;
  if (!window || !window->frame_active) return;
  const auto rect = SkRect::MakeXYWH(x, y, width, height);
  const auto rounded_rect = SkRRect::MakeRectXY(
      rect,
      static_cast<SkScalar>(radius_x),
      static_cast<SkScalar>(radius_y));
  draw_with_shadow(
      window->surface->getCanvas(),
      paint,
      [rounded_rect](SkCanvas* canvas, const SkPaint& value) {
        canvas->drawRRect(rounded_rect, value);
      });
}

void dui_draw_line(
    DuiWindow* window,
    double x1,
    double y1,
    double x2,
    double y2,
    const DuiPaint* paint) {
  SdlScope lock;
  if (!window || !window->frame_active) return;
  const auto from = SkPoint::Make(x1, y1);
  const auto to = SkPoint::Make(x2, y2);
  draw_with_shadow(
      window->surface->getCanvas(),
      paint,
      [from, to](SkCanvas* canvas, const SkPaint& value) {
        SkPaint stroke = value;
        stroke.setStyle(SkPaint::kStroke_Style);
        const auto width = stroke.getStrokeWidth() > 0
            ? stroke.getStrokeWidth()
            : static_cast<SkScalar>(1.0);
        stroke.setStrokeWidth(width);
        canvas->drawLine(from, to, stroke);
      });
}

DuiImage* dui_image_create_from_png(const uint8_t* data, size_t size) {
  SdlScope lock;
  clear_error();
  if (!data || size == 0) {
    set_error("The image data is empty.");
    return nullptr;
  }
  // The PNG signature is checked here, so a wrong file is reported right away
  // and not at the first draw.
  static const uint8_t k_png_signature[8] = {
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A};
  if (size < sizeof(k_png_signature) ||
      std::memcmp(data, k_png_signature, sizeof(k_png_signature)) != 0) {
    set_error("The image data is not a PNG file.");
    return nullptr;
  }
  sk_sp<const SkData> encoded = SkData::MakeWithCopy(data, size);
  if (!encoded) {
    set_error("Could not copy the image data.");
    return nullptr;
  }
  sk_sp<SkImage> image = SkImages::DeferredFromEncodedData(encoded);
  if (!image) {
    set_error("Could not decode the PNG image.");
    return nullptr;
  }
  auto* handle = new (std::nothrow) DuiImage();
  if (!handle) {
    set_error("Could not allocate the image.");
    return nullptr;
  }
  handle->image = std::move(image);
  return handle;
}

void dui_image_destroy(DuiImage* image) {
  SdlScope lock;
  delete image;
}

int32_t dui_image_get_size(const DuiImage* image, DuiImageSize* out_size) {
  SdlScope lock;
  clear_error();
  if (!image || !image->image || !out_size) {
    set_error("The image handle is not valid.");
    return 0;
  }
  out_size->struct_size = sizeof(DuiImageSize);
  out_size->width = static_cast<double>(image->image->width());
  out_size->height = static_cast<double>(image->image->height());
  return 1;
}

void dui_draw_image(
    DuiWindow* window,
    const DuiImage* image,
    double x,
    double y,
    double width,
    double height,
    const DuiPaint* paint) {
  SdlScope lock;
  if (!window || !window->frame_active) return;
  if (!image || !image->image) return;
  const float natural_width = static_cast<float>(image->image->width());
  const float natural_height = static_cast<float>(image->image->height());
  const auto destination = SkRect::MakeXYWH(
      static_cast<float>(x),
      static_cast<float>(y),
      width > 0 ? static_cast<float>(width) : natural_width,
      height > 0 ? static_cast<float>(height) : natural_height);
  draw_with_shadow(
      window->surface->getCanvas(),
      paint,
      [image, destination](SkCanvas* canvas, const SkPaint& value) {
        canvas->drawImageRect(
            image->image,
            destination,
            SkSamplingOptions(SkFilterMode::kLinear),
            &value);
      });
}

void dui_draw_path(
    DuiWindow* window,
    const DuiPathCommand* commands,
    int32_t count,
    const DuiPaint* paint) {
  SdlScope lock;
  if (!window || !window->frame_active) return;
  if (!commands || count <= 0) return;
  SkPathBuilder builder;
  for (int32_t index = 0; index < count; index++) {
    const DuiPathCommand& command = commands[index];
    switch (command.operation) {
      case 0:
        builder.moveTo(command.x1, command.y1);
        break;
      case 1:
        builder.lineTo(command.x1, command.y1);
        break;
      case 2:
        builder.quadTo(command.x1, command.y1, command.x2, command.y2);
        break;
      case 3:
        builder.cubicTo(
            command.x1,
            command.y1,
            command.x2,
            command.y2,
            command.x3,
            command.y3);
        break;
      case 4:
        builder.close();
        break;
      default:
        break;
    }
  }
  const SkPath path = builder.snapshot();
  if (path.isEmpty()) return;
  draw_with_shadow(
      window->surface->getCanvas(),
      paint,
      [&path](SkCanvas* canvas, const SkPaint& value) {
        canvas->drawPath(path, value);
      });
}

int32_t dui_draw_text(
    DuiWindow* window,
    const char* text_utf8,
    double x,
    double y,
    double font_size,
    uint32_t rgba,
    int32_t alignment,
    double* out_width) {
    SdlScope lock;
  clear_error();
  if (!window || !window->frame_active || !window->surface || !text_utf8 ||
      !out_width || !std::isfinite(x) || !std::isfinite(y) ||
      !std::isfinite(font_size) || font_size <= 0 || alignment < 0 ||
      alignment > 2) {
    set_error("Invalid text drawing arguments or no active frame.");
    return 0;
  }
  try {
    const auto scale = static_cast<SkScalar>(dui_window_get_content_scale(window));
    const auto length = std::strlen(text_utf8);
    const std::string value(text_utf8, length);
    // The legacy text API never wraps: the paragraph is laid out without a
    // width limit and the alignment is applied by shifting the draw origin.
    constexpr SkScalar kUnlimitedWidth = 1.0e6f;

    auto& cache = window->legacy_text;
    if (!cache.paragraph || cache.text != value ||
        cache.font_size != font_size || cache.scale != scale) {
      cache.paragraph = create_paragraph(
          value.data(),
          value.size(),
          nullptr,
          0,
          static_cast<SkScalar>(font_size * scale),
          0,
          0,
          kUnlimitedWidth * scale);
      if (!cache.paragraph) {
        set_error("SkParagraph creation failed.");
        return 0;
      }
      cache.text = value;
      cache.font_size = font_size;
      cache.scale = scale;
    }
    auto* paragraph = cache.paragraph.get();

    const auto text_width = paragraph->getLongestLine();
    SkScalar text_offset = 0;
    switch (alignment) {
      case 1:
        text_offset = text_width * 0.5f;
        break;
      case 2:
        text_offset = text_width;
        break;
      default:
        break;
    }

    const auto utf16_length = utf16_length_of(value);
    *out_width = text_width / scale;
    if (utf16_length == 0) return 1;

    SkPaint paint;
    paint.setColor(static_cast<SkColor>(rgba));
    paint.setAntiAlias(true);
    paragraph->updateForegroundPaint(0, utf16_length, paint);

    auto* canvas = window->surface->getCanvas();
    SkAutoCanvasRestore restore(canvas, true);
    const auto inverse_scale = static_cast<SkScalar>(1.0 / scale);
    canvas->scale(inverse_scale, inverse_scale);
    // The legacy text API places the baseline at y + font_size.
    const auto baseline = static_cast<SkScalar>(y + font_size) * scale;
    paragraph->paint(
        canvas,
        static_cast<SkScalar>(x) * scale - text_offset,
        baseline - paragraph->getAlphabeticBaseline());
    return 1;
  } catch (const std::exception& error) {
    set_error(error.what());
    return 0;
  } catch (...) {
    set_error("Unknown native text drawing error.");
    return 0;
  }
}

DuiTextLayout* dui_text_layout_create(const DuiTextLayoutOptions* options) {
SdlScope lock;
  clear_error();
  if (!options || options->struct_size != sizeof(*options) ||
      (!options->text_utf8 && options->text_length != 0) ||
      (!options->font_family_utf8 && options->font_family_length != 0) ||
      !std::isfinite(options->font_size) || options->font_size <= 0 ||
      std::isnan(options->max_width) || options->max_width <= 0 ||
      !std::isfinite(options->scale) || options->scale <= 0 ||
      options->alignment < 0 || options->alignment > 2 ||
      options->direction < 0 || options->direction > 1 ||
      !std::isfinite(options->font_size * options->scale) ||
      std::isnan(options->max_width * options->scale) ||
      options->max_width * options->scale <= 0) {
    set_error("Invalid text layout arguments.");
    return nullptr;
  }

  try {
    auto layout = std::make_unique<DuiTextLayout>();
    if (options->text_length != 0) {
      layout->text.assign(options->text_utf8, options->text_length);
    }
    layout->scale = options->scale;

    size_t current = 0;
    uint64_t utf16_length = 0;
    while (current < layout->text.size()) {
      uint32_t code_point = 0;
      size_t next = 0;
      if (!decode_utf8(layout->text, current, &code_point, &next)) {
        set_error("Text layout input is not valid UTF-8.");
        return nullptr;
      }
      utf16_length += code_point > 0xFFFF ? 2 : 1;
      if (utf16_length > std::numeric_limits<uint32_t>::max()) {
        set_error("Text layout input is too long.");
        return nullptr;
      }
      current = next;
    }
    layout->utf16_length = static_cast<uint32_t>(utf16_length);

    layout->paragraph = create_paragraph(
        layout->text.data(),
        layout->text.size(),
        options->font_family_utf8,
        options->font_family_length,
        static_cast<SkScalar>(options->font_size * options->scale),
        options->alignment,
        options->direction,
        static_cast<SkScalar>(options->max_width * options->scale));
    if (!layout->paragraph) {
      set_error("SkParagraph creation failed.");
      return nullptr;
    }
    return layout.release();
  } catch (const std::exception& error) {
    set_error(error.what());
    return nullptr;
  } catch (...) {
    set_error("Unknown native text layout creation error.");
    return nullptr;
  }
}

void dui_text_layout_destroy(DuiTextLayout* layout) {
SdlScope lock;
  clear_error();
  delete layout;
}

int32_t dui_text_layout_measure(
    DuiTextLayout* layout,
    DuiTextMetrics* out_metrics) {
    SdlScope lock;
  clear_error();
  if (!layout || !layout->paragraph || !out_metrics) {
    set_error("Invalid text measurement arguments.");
    return 0;
  }
  try {
    std::memset(out_metrics, 0, sizeof(*out_metrics));
    out_metrics->struct_size = sizeof(*out_metrics);
    const auto longest_line = layout->text.empty()
                                  ? 0.0f
                                  : layout->paragraph->getLongestLine();
    out_metrics->width = longest_line / layout->scale;
    out_metrics->height = layout->paragraph->getHeight() / layout->scale;
    out_metrics->baseline =
        layout->paragraph->getAlphabeticBaseline() / layout->scale;
    return 1;
  } catch (const std::exception& error) {
    set_error(error.what());
    return 0;
  } catch (...) {
    set_error("Unknown native text measurement error.");
    return 0;
  }
}

int32_t dui_text_layout_draw(
    DuiWindow* window,
    DuiTextLayout* layout,
    double x,
    double y,
    uint32_t rgba) {
    SdlScope lock;
  clear_error();
  if (!window || !window->frame_active || !window->surface ||
      !layout || !layout->paragraph ||
      !std::isfinite(x) || !std::isfinite(y)) {
    set_error("Invalid text drawing arguments or no active frame.");
    return 0;
  }
  try {
    SkPaint paint;
    paint.setColor(static_cast<SkColor>(rgba));
    paint.setAntiAlias(true);
    layout->paragraph->updateForegroundPaint(
        0,
        layout->utf16_length,
        paint);

    auto* canvas = window->surface->getCanvas();
    SkAutoCanvasRestore restore(canvas, true);
    const auto inverse_scale = static_cast<SkScalar>(1.0 / layout->scale);
    canvas->scale(inverse_scale, inverse_scale);
    layout->paragraph->paint(
        canvas,
        static_cast<SkScalar>(x * layout->scale),
        static_cast<SkScalar>(y * layout->scale));
    return 1;
  } catch (const std::exception& error) {
    set_error(error.what());
    return 0;
  } catch (...) {
    set_error("Unknown native text drawing error.");
    return 0;
  }
}

int32_t dui_text_layout_hit_test(
    DuiTextLayout* layout,
    double x,
    double y,
    DuiTextPosition* out_position) {
    SdlScope lock;
  clear_error();
  if (!layout || !layout->paragraph || !out_position ||
      !std::isfinite(x) || !std::isfinite(y)) {
    set_error("Invalid text hit test arguments.");
    return 0;
  }
  try {
    const auto position = layout->paragraph->getGlyphPositionAtCoordinate(
        static_cast<SkScalar>(x * layout->scale),
        static_cast<SkScalar>(y * layout->scale));
    // Current SkParagraph editing APIs return UTF-16 offsets despite the
    // legacy "glyph position" comment in Paragraph.h.
    const auto non_negative_position = std::max(position.position, 0);
    const auto utf16_offset = static_cast<uint32_t>(std::min(
        static_cast<uint64_t>(non_negative_position),
        static_cast<uint64_t>(layout->utf16_length)));
    std::memset(out_position, 0, sizeof(*out_position));
    out_position->struct_size = sizeof(*out_position);
    out_position->offset_utf16 = utf16_offset;
    return 1;
  } catch (const std::exception& error) {
    set_error(error.what());
    return 0;
  } catch (...) {
    set_error("Unknown native text hit test error.");
    return 0;
  }
}

int32_t dui_text_layout_caret_rect(
    DuiTextLayout* layout,
    uint32_t offset_utf16,
    DuiRect* out_rect) {
    SdlScope lock;
  clear_error();
  if (!layout || !layout->paragraph || !out_rect) {
    set_error("Invalid caret rectangle arguments.");
    return 0;
  }
  try {
    size_t byte_offset = 0;
    if (!utf16_to_utf8_offset(*layout, offset_utf16, &byte_offset)) {
      set_error("Caret offset is outside a UTF-16 text boundary.");
      return 0;
    }
    if (layout->utf16_length == 0) {
      write_rect(out_rect, SkRect::MakeWH(0, layout->paragraph->getHeight()), layout->scale);
      return 1;
    }

    if (offset_utf16 < layout->utf16_length) {
      skia::textlayout::Paragraph::GlyphInfo info{};
      if (layout->paragraph->getGlyphInfoAtUTF16Offset(offset_utf16, &info)) {
        const auto& bounds = info.fGraphemeLayoutBounds;
        const auto left = info.fDirection == skia::textlayout::TextDirection::kRtl
            ? bounds.right()
            : bounds.left();
        write_rect(
            out_rect,
            SkRect::MakeXYWH(left, bounds.top(), 0, bounds.height()),
            layout->scale);
        return 1;
      }
    } else {
      const auto boxes = layout->paragraph->getRectsForRange(
          0,
          offset_utf16,
          skia::textlayout::RectHeightStyle::kMax,
          skia::textlayout::RectWidthStyle::kTight);
      if (!boxes.empty()) {
        const auto& box = boxes.back();
        const auto left = box.direction == skia::textlayout::TextDirection::kRtl
            ? box.rect.left()
            : box.rect.right();
        write_rect(
            out_rect,
            SkRect::MakeXYWH(left, box.rect.top(), 0, box.rect.height()),
            layout->scale);
        return 1;
      }
    }

    set_error("SkParagraph could not resolve the caret geometry.");
    return 0;
  } catch (const std::exception& error) {
    set_error(error.what());
    return 0;
  } catch (...) {
    set_error("Unknown native caret rectangle error.");
    return 0;
  }
}

int32_t dui_text_layout_selection_rects(
    DuiTextLayout* layout,
    uint32_t start_utf16,
    uint32_t end_utf16,
    DuiRect* out_rects,
    uint32_t rect_capacity,
    uint32_t* out_count) {
    SdlScope lock;
  clear_error();
  if (!layout || !layout->paragraph || !out_count || start_utf16 > end_utf16) {
    set_error("Invalid selection rectangle arguments.");
    return 0;
  }
  *out_count = 0;
  try {
    size_t start = 0;
    size_t end = 0;
    if (!utf16_to_utf8_offset(*layout, start_utf16, &start) ||
        !utf16_to_utf8_offset(*layout, end_utf16, &end)) {
      set_error("Selection offsets are outside UTF-16 text boundaries.");
      return 0;
    }
    const auto boxes = layout->paragraph->getRectsForRange(
        start_utf16,
        end_utf16,
        skia::textlayout::RectHeightStyle::kMax,
        skia::textlayout::RectWidthStyle::kTight);
    if (boxes.size() > std::numeric_limits<uint32_t>::max()) {
      set_error("Too many selection rectangles.");
      return 0;
    }
    *out_count = static_cast<uint32_t>(boxes.size());
    if (!out_rects) return 1;
    if (rect_capacity < boxes.size()) {
      set_error("Selection rectangle buffer is too small.");
      return 0;
    }
    for (size_t index = 0; index < boxes.size(); ++index) {
      write_rect(&out_rects[index], boxes[index].rect, layout->scale);
    }
    return 1;
  } catch (const std::exception& error) {
    set_error(error.what());
    return 0;
  } catch (...) {
    set_error("Unknown native selection rectangle error.");
    return 0;
  }
}

int32_t dui_window_present(DuiWindow* window) {
SdlScope lock;
  clear_error();
  if (!window || !window->frame_active || !window->surface) {
    set_error("No active frame to present.");
    return 0;
  }

  window->surface->getCanvas()->restore();
  void* pixels = nullptr;
  int pitch = 0;
  if (!SDL_LockTexture(window->texture, nullptr, &pixels, &pitch)) {
    set_sdl_error();
    return 0;
  }
  SkPixmap pixmap;
  if (!window->surface->peekPixels(&pixmap)) {
    SDL_UnlockTexture(window->texture);
    set_error("Skia could not expose raster pixels.");
    return 0;
  }
  const size_t source_pitch = pixmap.rowBytes();
  const size_t row_bytes = std::min(
      source_pitch,
      static_cast<size_t>(pitch));
  auto* destination = static_cast<unsigned char*>(pixels);
  const auto* source = static_cast<const unsigned char*>(pixmap.addr());
  for (int row = 0; row < window->pixel_height; ++row) {
    std::memcpy(destination + static_cast<size_t>(row) * pitch,
                source + static_cast<size_t>(row) * source_pitch,
                row_bytes);
  }
  SDL_UnlockTexture(window->texture);

  // Resize notifications can arrive before SDL resets the renderer output.
  // Always present to the full current target, not the previous viewport.
  if (!SDL_SetRenderViewport(window->renderer, nullptr) ||
      !SDL_SetRenderClipRect(window->renderer, nullptr) ||
      !SDL_RenderClear(window->renderer) ||
      !SDL_RenderTexture(window->renderer, window->texture, nullptr, nullptr) ||
      !SDL_RenderPresent(window->renderer)) {
    set_sdl_error();
    return 0;
  }
  window->frame_active = false;
  return 1;
}
