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
#include "include/core/SkSurface.h"
#include "include/core/SkTypeface.h"

#if defined(_WIN32)
#include "include/ports/SkTypeface_win.h"
#endif

#include <algorithm>
#include <cmath>
#include <cstring>
#include <memory>
#include <new>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

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
};

namespace {

thread_local std::string last_error;

void clear_error() { last_error.clear(); }

void set_error(const char* message) { last_error = message; }

void set_sdl_error() { last_error = SDL_GetError(); }

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

DuiHost* dui_host_create(void) {
  clear_error();
  try {
    if (!SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS)) {
      set_sdl_error();
      return nullptr;
    }
    return new DuiHost();
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
  for (auto& window : host->windows) destroy_window_resources(window.get());
  host->windows.clear();
  delete host;
  SDL_Quit();
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
    case SDL_EVENT_TEXT_INPUT:
      out_event->type = DUI_EVENT_TEXT_INPUT;
      out_event->window_id = source.text.windowID;
      host->text_storage = source.text.text ? source.text.text : "";
      out_event->text_utf8 = host->text_storage.c_str();
      break;
    case SDL_EVENT_KEY_DOWN:
      out_event->type = DUI_EVENT_KEY_DOWN;
      out_event->window_id = source.key.windowID;
      out_event->key_code = static_cast<int32_t>(source.key.key);
      break;
    default:
      out_event->type = DUI_EVENT_NONE;
      break;
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

int32_t dui_window_begin_frame(DuiWindow* window) {
  clear_error();
  if (!window || !ensure_surface(window)) return 0;
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

  if (!SDL_RenderClear(window->renderer) ||
      !SDL_RenderTexture(window->renderer, window->texture, nullptr, nullptr) ||
      !SDL_RenderPresent(window->renderer)) {
    set_sdl_error();
    return 0;
  }
  window->frame_active = false;
  return 1;
}
