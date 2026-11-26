#ifndef DUI_NATIVE_H_
#define DUI_NATIVE_H_

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#define DUI_API __declspec(dllexport)
#else
#define DUI_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Threading contract:
 * - Create, use and destroy a DuiHost on the same OS thread.
 * - Call all functions for its DuiWindow objects on that same thread.
 * - Create, use and destroy each DuiTextLayout on that same thread.
 * - Do not call host, window or text layout functions concurrently; the API
 *   is not internally synchronized.
 * - The live resize callback runs synchronously on the host thread inside SDL
 *   event processing. It may render and present, but must not throw across ABI.
 * - dui_abi_version() may be called on any thread.
 * - dui_last_error_message() reads thread-local error state. The returned
 *   pointer remains valid until the next native call on that thread.
 */

typedef struct DuiHost DuiHost;
typedef struct DuiWindow DuiWindow;
typedef struct DuiTextLayout DuiTextLayout;

enum DuiEventType {
  DUI_EVENT_NONE = 0,
  DUI_EVENT_QUIT = 1,
  DUI_EVENT_CLOSE = 2,
  DUI_EVENT_RESIZE = 3,
  DUI_EVENT_POINTER_DOWN = 4,
  DUI_EVENT_POINTER_UP = 5,
  DUI_EVENT_POINTER_MOVE = 6,
  DUI_EVENT_TEXT_INPUT = 7,
  DUI_EVENT_KEY_DOWN = 8,
  DUI_EVENT_TEXT_EDITING = 9,
  DUI_EVENT_MOUSE_WHEEL = 10
};

typedef struct DuiEvent {
  uint32_t struct_size;
  uint32_t type;
  uint64_t window_id;
  double x;
  double y;
  double width;
  double height;
  int32_t key_code;
  uint16_t modifiers;
  const char* text_utf8;
  /* Composition selection offsets are UTF-16 code units; negative means unset. */
  int32_t composition_start;
  int32_t composition_length;
  /* SDL scancode for physical key position; key_code is layout-dependent. */
  int32_t scan_code;
} DuiEvent;

typedef void (*DuiLiveResizeCallback)(
    void* user_data,
    uint64_t window_id,
    double logical_width,
    double logical_height);

typedef struct DuiWindowMetrics {
  uint32_t struct_size;
  int32_t physical_width;
  int32_t physical_height;
  double display_scale;
  double pixel_density;
} DuiWindowMetrics;

typedef struct DuiTextLayoutOptions {
  uint32_t struct_size;
  const char* text_utf8;
  size_t text_length;
  const char* font_family_utf8;
  size_t font_family_length;
  double font_size;
  double max_width;
  double scale;
  int32_t alignment;
} DuiTextLayoutOptions;

typedef struct DuiTextMetrics {
  uint32_t struct_size;
  double width;
  double height;
  double baseline;
} DuiTextMetrics;

typedef struct DuiTextPosition {
  uint32_t struct_size;
  uint32_t offset_utf16;
} DuiTextPosition;

typedef struct DuiRect {
  uint32_t struct_size;
  double left;
  double top;
  double width;
  double height;
} DuiRect;

DUI_API uint32_t dui_abi_version(void);
DUI_API const char* dui_last_error_message(void);

/* Clipboard text is UTF-8. Returned strings must be freed with
 * dui_clipboard_free_text(). An empty clipboard returns NULL. */
DUI_API int32_t dui_clipboard_set_text(const char* text_utf8);
DUI_API char* dui_clipboard_get_text(void);
DUI_API void dui_clipboard_free_text(char* text);

/* Formatted clipboard data is copied on write. Returned read buffers belong to
 * SDL and must be freed with dui_clipboard_free_data(). Missing formats return
 * NULL with out_size set to zero. */
DUI_API int32_t dui_clipboard_set_data(
    const char* const* mime_types,
    const uint8_t* const* data,
    const size_t* sizes,
    size_t count);
DUI_API int32_t dui_clipboard_has_data(const char* mime_type);
DUI_API void* dui_clipboard_get_data(const char* mime_type, size_t* out_size);
DUI_API void dui_clipboard_free_data(void* data);

DUI_API DuiHost* dui_host_create(void);
DUI_API void dui_host_destroy(DuiHost* host);
DUI_API int32_t dui_host_next_event(DuiHost* host, DuiEvent* out_event);
DUI_API int32_t dui_host_wait_event(
    DuiHost* host, DuiEvent* out_event, int32_t timeout_ms);
DUI_API int32_t dui_host_wake_up(DuiHost* host);
/* Pass NULL to disable. The queued resize event is still delivered normally. */
DUI_API int32_t dui_host_set_live_resize_callback(
    DuiHost* host,
    DuiLiveResizeCallback callback,
    void* user_data);

DUI_API DuiWindow* dui_window_create(
    DuiHost* host,
    const char* title_utf8,
    int32_t width,
    int32_t height);
DUI_API void dui_window_destroy(DuiHost* host, DuiWindow* window);
DUI_API int32_t dui_window_set_size(
    DuiWindow* window,
    int32_t logical_width,
    int32_t logical_height);
DUI_API uint64_t dui_window_get_id(const DuiWindow* window);
DUI_API double dui_window_get_content_scale(const DuiWindow* window);
DUI_API int32_t dui_window_get_metrics(
    const DuiWindow* window,
    DuiWindowMetrics* out_metrics);
DUI_API void dui_window_set_background(DuiWindow* window, uint32_t rgba);
DUI_API int32_t dui_window_start_text_input(DuiWindow* window);
DUI_API int32_t dui_window_stop_text_input(DuiWindow* window);
DUI_API int32_t dui_window_text_input_active(const DuiWindow* window);
/* Area and cursor use logical UI units and are converted to SDL window units. */
DUI_API int32_t dui_window_set_text_input_area(
    DuiWindow* window,
    double x,
    double y,
    double width,
    double height,
    double cursor_x);

DUI_API int32_t dui_window_begin_frame(DuiWindow* window);
DUI_API int32_t dui_window_push_clip_rect(
    DuiWindow* window,
    double x,
    double y,
    double width,
    double height);
DUI_API int32_t dui_window_pop_clip(DuiWindow* window);
DUI_API void dui_draw_rect(
    DuiWindow* window,
    double x,
    double y,
    double width,
    double height,
    uint32_t rgba);
DUI_API void dui_draw_rounded_rect(
    DuiWindow* window,
    double x,
    double y,
    double width,
    double height,
    double radius_x,
    double radius_y,
    uint32_t rgba,
    double stroke_width);
DUI_API void dui_draw_text(
    DuiWindow* window,
    const char* text_utf8,
    double x,
    double y,
    double font_size,
    uint32_t rgba,
    int32_t alignment);

/* Text offsets are UTF-16 code units. All text buffers are UTF-8 with an
 * explicit byte length and need not be null-terminated. Output storage belongs
 * to the caller. Call selection_rects with out_rects == NULL to query count. */
DUI_API DuiTextLayout* dui_text_layout_create(
    const DuiTextLayoutOptions* options);
DUI_API void dui_text_layout_destroy(DuiTextLayout* layout);
DUI_API int32_t dui_text_layout_measure(
    DuiTextLayout* layout,
    DuiTextMetrics* out_metrics);
DUI_API int32_t dui_text_layout_draw(
    DuiWindow* window,
    DuiTextLayout* layout,
    double x,
    double y,
    uint32_t rgba);
DUI_API int32_t dui_text_layout_hit_test(
    DuiTextLayout* layout,
    double x,
    double y,
    DuiTextPosition* out_position);
DUI_API int32_t dui_text_layout_caret_rect(
    DuiTextLayout* layout,
    uint32_t offset_utf16,
    DuiRect* out_rect);
DUI_API int32_t dui_text_layout_selection_rects(
    DuiTextLayout* layout,
    uint32_t start_utf16,
    uint32_t end_utf16,
    DuiRect* out_rects,
    uint32_t rect_capacity,
    uint32_t* out_count);
DUI_API int32_t dui_window_present(DuiWindow* window);

#ifdef __cplusplus
}
#endif

#endif
