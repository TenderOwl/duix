#include "dui_native.h"

#include <SDL3/SDL.h>

#include "include/core/SkCanvas.h"
#include "include/core/SkColor.h"
#include "include/core/SkFont.h"
#include "include/core/SkFontMgr.h"
#include "include/core/SkFontStyle.h"
#include "include/core/SkImageInfo.h"
#include "include/core/SkPaint.h"
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
#include <cstring>
#include <limits>
#include <memory>
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
};

struct DuiHost {
  std::vector<std::unique_ptr<DuiWindow>> windows;
  std::string text_storage;
  SDL_ThreadID thread_id = 0;
  DuiLiveResizeCallback live_resize_callback = nullptr;
  void* live_resize_user_data = nullptr;
  bool live_resize_active = false;
};

namespace {

thread_local std::string last_error;
std::unordered_map<std::string, std::vector<uint8_t>> clipboard_formats;

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

void clear_error() { last_error.clear(); }

void set_error(const char* message) { last_error = message; }

void set_sdl_error() { last_error = SDL_GetError(); }

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

void destroy_window_resources(DuiWindow* window) {
  window->surface.reset();
  if (window->window && SDL_TextInputActive(window->window)) {
    SDL_StopTextInput(window->window);
  }
  if (window->texture) SDL_DestroyTexture(window->texture);
  if (window->renderer) SDL_DestroyRenderer(window->renderer);
  if (window->window) SDL_DestroyWindow(window->window);
  window->texture = nullptr;
  window->renderer = nullptr;
  window->window = nullptr;
}

}  // namespace

uint32_t dui_abi_version(void) { return 1; }

const char* dui_last_error_message(void) { return last_error.c_str(); }

int32_t dui_clipboard_set_text(const char* text_utf8) {
  clear_error();
  if (!text_utf8) {
    set_error("Clipboard text must not be null.");
    return 0;
  }
  if (!SDL_SetClipboardText(text_utf8)) {
    set_sdl_error();
    return 0;
  }
  return 1;
}

char* dui_clipboard_get_text(void) {
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
      mime_type_names.push_back(mime_type);
    }
    clipboard_formats = std::move(replacement);
    if (!SDL_SetClipboardData(
            clipboard_data_callback,
            clipboard_cleanup_callback,
            nullptr,
            mime_type_names.data(),
            count)) {
      clipboard_formats.clear();
      set_sdl_error();
      return 0;
    }
    return 1;
  } catch (const std::exception& error) {
    clipboard_formats.clear();
    set_error(error.what());
    return 0;
  }
}

int32_t dui_clipboard_has_data(const char* mime_type) {
  clear_error();
  if (!mime_type || !*mime_type) {
    set_error("Clipboard MIME type must not be empty.");
    return 0;
  }
  return SDL_HasClipboardData(mime_type) ? 1 : 0;
}

void* dui_clipboard_get_data(const char* mime_type, size_t* out_size) {
  clear_error();
  if (!mime_type || !*mime_type || !out_size) {
    set_error("Invalid formatted clipboard read arguments.");
    return nullptr;
  }
  *out_size = 0;
  if (!SDL_HasClipboardData(mime_type)) return nullptr;
  void* data = SDL_GetClipboardData(mime_type, out_size);
  if (!data) set_sdl_error();
  return data;
}

void dui_clipboard_free_data(void* data) { SDL_free(data); }

DuiHost* dui_host_create(void) {
  clear_error();
  try {
    if (!SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS)) {
      set_sdl_error();
      return nullptr;
    }
    auto host = std::make_unique<DuiHost>();
    host->thread_id = SDL_GetCurrentThreadID();
    if (!SDL_AddEventWatch(live_resize_event_watch, host.get())) {
      set_sdl_error();
      SDL_Quit();
      return nullptr;
    }
    return host.release();
  } catch (const std::exception& error) {
    set_error(error.what());
    SDL_Quit();
    return nullptr;
  } catch (...) {
    set_error("Unknown native host creation error.");
    SDL_Quit();
    return nullptr;
  }
}

void dui_host_destroy(DuiHost* host) {
  if (!host) return;
  SDL_RemoveEventWatch(live_resize_event_watch, host);
  for (auto& window : host->windows) destroy_window_resources(window.get());
  host->windows.clear();
  delete host;
  SDL_Quit();
}

int32_t dui_host_set_live_resize_callback(
    DuiHost* host,
    DuiLiveResizeCallback callback,
    void* user_data) {
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
  return window && window->window ? SDL_GetWindowID(window->window) : 0;
}

double dui_window_get_content_scale(const DuiWindow* window) {
  return window ? window_display_scale(window->window) : 1.0;
}

int32_t dui_window_get_metrics(
    const DuiWindow* window,
    DuiWindowMetrics* out_metrics) {
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
  if (window) window->background_rgba = rgba;
}

int32_t dui_window_start_text_input(DuiWindow* window) {
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

int32_t dui_window_text_input_active(const DuiWindow* window) {
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
  clear_error();
  if (!window || !window->frame_active || !window->surface) {
    set_error("Cannot restore clip without an active frame.");
    return 0;
  }
  window->surface->getCanvas()->restore();
  return 1;
}

void dui_draw_rect(
    DuiWindow* window,
    double x,
    double y,
    double width,
    double height,
    uint32_t rgba) {
  if (!window || !window->frame_active) return;
  SkPaint paint;
  paint.setColor(static_cast<SkColor>(rgba));
  paint.setAntiAlias(true);
  window->surface->getCanvas()->drawRect(
      SkRect::MakeXYWH(x, y, width, height),
      paint);
}

void dui_draw_rounded_rect(
    DuiWindow* window,
    double x,
    double y,
    double width,
    double height,
    double radius_x,
    double radius_y,
    uint32_t rgba,
    double stroke_width) {
  if (!window || !window->frame_active) return;
  SkPaint paint;
  paint.setColor(static_cast<SkColor>(rgba));
  paint.setAntiAlias(true);
  if (std::isfinite(stroke_width) && stroke_width > 0) {
    paint.setStyle(SkPaint::kStroke_Style);
    paint.setStrokeWidth(static_cast<SkScalar>(stroke_width));
  }
  const auto rect = SkRect::MakeXYWH(x, y, width, height);
  const auto rounded_rect = SkRRect::MakeRectXY(
      rect,
      static_cast<SkScalar>(radius_x),
      static_cast<SkScalar>(radius_y));
  window->surface->getCanvas()->drawRRect(rounded_rect, paint);
}

void dui_draw_text(
    DuiWindow* window,
    const char* text_utf8,
    double x,
    double y,
    double font_size,
    uint32_t rgba,
    int32_t alignment) {
  if (!window || !window->frame_active || !text_utf8) return;
  SkPaint paint;
  paint.setColor(static_cast<SkColor>(rgba));
  paint.setAntiAlias(true);
#if defined(_WIN32)
  static const sk_sp<SkFontMgr> font_manager = SkFontMgr_New_DirectWrite();
#else
  static const sk_sp<SkFontMgr> font_manager = SkFontMgr::RefEmpty();
#endif
  SkFont font(
      font_manager->legacyMakeTypeface(nullptr, SkFontStyle()),
      static_cast<SkScalar>(font_size));
  font.setEdging(SkFont::Edging::kAntiAlias);
  font.setSubpixel(true);
  const size_t length = std::strlen(text_utf8);
  const SkScalar measured_width = font.measureText(
      text_utf8,
      length,
      SkTextEncoding::kUTF8);
  SkScalar text_offset = 0;
  switch (alignment) {
    case 1:
      text_offset = measured_width * 0.5;
      break;
    case 2:
      text_offset = measured_width;
      break;
    default:
      break;
  }
  window->surface->getCanvas()->drawSimpleText(
      text_utf8,
      length,
      SkTextEncoding::kUTF8,
      static_cast<SkScalar>(x) - text_offset,
      static_cast<SkScalar>(y + font_size),
      font,
      paint);
}

DuiTextLayout* dui_text_layout_create(const DuiTextLayoutOptions* options) {
  clear_error();
  if (!options || options->struct_size != sizeof(*options) ||
      (!options->text_utf8 && options->text_length != 0) ||
      (!options->font_family_utf8 && options->font_family_length != 0) ||
      !std::isfinite(options->font_size) || options->font_size <= 0 ||
      std::isnan(options->max_width) || options->max_width <= 0 ||
      !std::isfinite(options->scale) || options->scale <= 0 ||
      options->alignment < 0 || options->alignment > 2 ||
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

    auto unicode = SkUnicodes::ICU::Make();
    auto fonts = sk_make_sp<skia::textlayout::FontCollection>();
    fonts->setDefaultFontManager(create_font_manager());
    if (!unicode || !fonts->getFallbackManager()) {
      set_error("SkParagraph font/unicode initialization failed.");
      return nullptr;
    }

    skia::textlayout::TextStyle text_style;
    text_style.setFontSize(static_cast<SkScalar>(
        options->font_size * options->scale));
    if (options->font_family_length != 0) {
      text_style.setFontFamilies({SkString(
          options->font_family_utf8,
          options->font_family_length)});
    }
    skia::textlayout::ParagraphStyle paragraph_style;
    paragraph_style.setTextStyle(text_style);
    switch (options->alignment) {
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

    auto builder = skia::textlayout::ParagraphBuilder::make(
        paragraph_style,
        fonts,
        unicode);
    if (!builder) {
      set_error("SkParagraph builder creation failed.");
      return nullptr;
    }
    builder->addText(layout->text.data(), layout->text.size());
    layout->paragraph = builder->Build();
    if (!layout->paragraph) {
      set_error("SkParagraph creation failed.");
      return nullptr;
    }
    layout->paragraph->layout(static_cast<SkScalar>(
        options->max_width * options->scale));
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
  clear_error();
  delete layout;
}

int32_t dui_text_layout_measure(
    DuiTextLayout* layout,
    DuiTextMetrics* out_metrics) {
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
        layout->text.size(),
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
