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
typedef struct DuiImage DuiImage;

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

typedef struct DuiImageSize {
  uint32_t struct_size;
  double width;
  double height;
} DuiImageSize;

/* The role of an accessible node. The values match the Dart SemanticsRole. */
enum DuiAccessibleRole {
  DUI_ACCESSIBLE_ROLE_NONE = 0,
  DUI_ACCESSIBLE_ROLE_BUTTON = 1,
  DUI_ACCESSIBLE_ROLE_TEXT_BOX = 2,
  DUI_ACCESSIBLE_ROLE_LABEL = 3,
  DUI_ACCESSIBLE_ROLE_GROUP = 4,
  DUI_ACCESSIBLE_ROLE_LIST = 5,
  DUI_ACCESSIBLE_ROLE_IMAGE = 6,
  DUI_ACCESSIBLE_ROLE_WINDOW = 7
};

/* The state of an accessible node. */
enum DuiAccessibleFlags {
  DUI_ACCESSIBLE_FOCUSED = 1 << 0,
  DUI_ACCESSIBLE_DISABLED = 1 << 1,
  DUI_ACCESSIBLE_READ_ONLY = 1 << 2,
  DUI_ACCESSIBLE_EDITABLE = 1 << 3,
  DUI_ACCESSIBLE_MULTILINE = 1 << 4,
  DUI_ACCESSIBLE_SELECTED = 1 << 5,
  DUI_ACCESSIBLE_CHECKED = 1 << 6,
  DUI_ACCESSIBLE_INDETERMINATE = 1 << 7,
  DUI_ACCESSIBLE_EXPANDED = 1 << 8,
  DUI_ACCESSIBLE_PRESSED = 1 << 9
};

/* One node of the semantics tree of a window. The strings are UTF-8 and do
 * not need to be null-terminated. */
typedef struct DuiAccessibleNode {
  uint32_t struct_size;
  int32_t role;
  /* The index of the parent node, -1 for the root. */
  int32_t parent;
  uint32_t flags;
  double left;
  double top;
  double width;
  double height;
  const char* name_utf8;
  const char* value_utf8;
} DuiAccessibleNode;

typedef struct DuiAccessibleNodeInfo {
  uint32_t struct_size;
  int32_t role;
  int32_t parent;
  uint32_t flags;
  double left;
  double top;
  double width;
  double height;
  int32_t name_length;
  int32_t value_length;
} DuiAccessibleNodeInfo;

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
DUI_API int32_t dui_clipboard_clear(void);
/* Returned array and strings must be freed with
 * dui_clipboard_free_mime_types() using the returned count. */
DUI_API char** dui_clipboard_get_mime_types(size_t* out_count);
DUI_API void dui_clipboard_free_mime_types(char** mime_types, size_t count);

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
typedef struct DuiFileDialogFilter {
  const char* name_utf8;
  const char* spec_utf8;
} DuiFileDialogFilter;

/* Shows the platform open-file dialog. A NULL window creates an unowned dialog.
 * Filter specs use platform patterns such as "*.txt;*.md". A NULL result means
 * cancellation; errors are available through dui_last_error_message(). Free
 * paths with dui_file_dialog_free_path(). */
DUI_API char* dui_window_open_file_dialog(
    DuiWindow* window,
    const char* title_utf8,
    const char* initial_directory_utf8,
    const DuiFileDialogFilter* filters,
    size_t filter_count);
DUI_API void dui_file_dialog_free_path(char* path);
DUI_API double dui_window_get_content_scale(const DuiWindow* window);
DUI_API int32_t dui_window_get_metrics(
    const DuiWindow* window,
    DuiWindowMetrics* out_metrics);
DUI_API void dui_window_set_background(DuiWindow* window, uint32_t rgba);
DUI_API int32_t dui_window_start_text_input(DuiWindow* window);
DUI_API int32_t dui_window_stop_text_input(DuiWindow* window);
DUI_API int32_t dui_window_text_input_active(const DuiWindow* window);
/* Publishes the semantics tree of the window. The nodes and their strings are
 * copied, so the caller keeps no ownership of them. The nodes are stored in
 * the order they are given, and every node points at the index of its parent.
 * A count of zero clears the tree. */
DUI_API int32_t dui_window_set_accessibility_tree(
    DuiWindow* window,
    const DuiAccessibleNode* nodes,
    size_t count);
/* The number of the published nodes. */
DUI_API int32_t dui_window_get_accessibility_node_count(
    const DuiWindow* window);
/* Reads the information of a published node. */
DUI_API int32_t dui_window_get_accessibility_node_info(
    const DuiWindow* window,
    int32_t index,
    DuiAccessibleNodeInfo* out_info);
/* The name and the value of a published node. The returned pointers stay
 * valid until the next call on the same thread. */
DUI_API const char* dui_window_get_accessibility_node_name(
    const DuiWindow* window,
    int32_t index);
DUI_API const char* dui_window_get_accessibility_node_value(
    const DuiWindow* window,
    int32_t index);
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
    uint32_t rgba,
    double stroke_width);
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
/* Draws a straight line. A stroke width of zero draws a hairline. */
DUI_API void dui_draw_line(
    DuiWindow* window,
    double x1,
    double y1,
    double x2,
    double y2,
    uint32_t rgba,
    double stroke_width);
/* Decodes a PNG image from memory. The bytes are copied, so the caller keeps
 * no ownership of them. Returns NULL when the data is not a readable PNG; the
 * reason is available through dui_last_error_message(). */
DUI_API DuiImage* dui_image_create_from_png(const uint8_t* data, size_t size);
DUI_API void dui_image_destroy(DuiImage* image);
/* Writes the pixel size of the image. */
DUI_API int32_t dui_image_get_size(
    const DuiImage* image,
    DuiImageSize* out_size);
/* Draws the image into the destination rectangle. A width or height of zero
 * uses the natural size of the image. */
DUI_API void dui_draw_image(
    DuiWindow* window,
    const DuiImage* image,
    double x,
    double y,
    double width,
    double height);
/* Draws shaped text through SkParagraph. The text is never wrapped.
 * The anchor point depends on the alignment: start uses the left edge of the
 * text, center its middle and end its right edge. The baseline is placed at
 * y + font_size. [out_width] receives the logical width of the drawn text. */
DUI_API int32_t dui_draw_text(
    DuiWindow* window,
    const char* text_utf8,
    double x,
    double y,
    double font_size,
    uint32_t rgba,
    int32_t alignment,
    double* out_width);

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
