#ifndef DUI_NATIVE_H_
#define DUI_NATIVE_H_

#include <stdint.h>

#if defined(_WIN32)
#define DUI_API __declspec(dllexport)
#else
#define DUI_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct DuiHost DuiHost;
typedef struct DuiWindow DuiWindow;

enum DuiEventType {
  DUI_EVENT_NONE = 0,
  DUI_EVENT_QUIT = 1,
  DUI_EVENT_CLOSE = 2,
  DUI_EVENT_RESIZE = 3,
  DUI_EVENT_POINTER_DOWN = 4,
  DUI_EVENT_POINTER_UP = 5,
  DUI_EVENT_POINTER_MOVE = 6,
  DUI_EVENT_TEXT_INPUT = 7,
  DUI_EVENT_KEY_DOWN = 8
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
  const char* text_utf8;
} DuiEvent;

DUI_API uint32_t dui_abi_version(void);
DUI_API const char* dui_last_error_message(void);

DUI_API DuiHost* dui_host_create(void);
DUI_API void dui_host_destroy(DuiHost* host);
DUI_API int32_t dui_host_next_event(DuiHost* host, DuiEvent* out_event);

DUI_API DuiWindow* dui_window_create(
    DuiHost* host,
    const char* title_utf8,
    int32_t width,
    int32_t height);
DUI_API void dui_window_destroy(DuiHost* host, DuiWindow* window);
DUI_API uint64_t dui_window_get_id(const DuiWindow* window);
DUI_API void dui_window_set_background(DuiWindow* window, uint32_t rgba);

DUI_API int32_t dui_window_begin_frame(DuiWindow* window);
DUI_API void dui_draw_rect(
    DuiWindow* window,
    double x,
    double y,
    double width,
    double height,
    uint32_t rgba);
DUI_API void dui_draw_text(
    DuiWindow* window,
    const char* text_utf8,
    double x,
    double y,
    double font_size,
    uint32_t rgba,
    int32_t alignment);
DUI_API int32_t dui_window_present(DuiWindow* window);

#ifdef __cplusplus
}
#endif

#endif
