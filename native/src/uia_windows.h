#ifndef DUI_UIA_WINDOWS_H_
#define DUI_UIA_WINDOWS_H_

#include <cstdint>
#include <string>
#include <vector>

// The bridge to Windows UI Automation.
//
// The Dart layer publishes the semantics tree of a window, and the bridge
// serves it to the assistive technologies of Windows as a tree of providers.
// On the other platforms the functions do nothing, so the rest of the native
// code stays the same everywhere.

// One node of the published tree.
struct DuiUiaNode {
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

// The state of the bridge of one window.
struct DuiUiaSnapshot {
  std::vector<DuiUiaNode> nodes;
  // The window handle of the platform.
  void* hwnd = nullptr;
  std::string title;
  // The scale between the logical units and the pixels.
  double scale = 1.0;
  // The position and the size of the window on the screen, in pixels.
  int32_t window_x = 0;
  int32_t window_y = 0;
  int32_t window_width = 0;
  int32_t window_height = 0;
};

// Starts the bridge of the window and hooks its window procedure.
void dui_windows_install_uia(void* hwnd);

// Publishes a new tree to the bridge of the window.
void dui_windows_update_uia(void* hwnd, const DuiUiaSnapshot& snapshot);

// Stops the bridge of the window and restores its window procedure.
void dui_windows_remove_uia(void* hwnd);

#endif  // DUI_UIA_WINDOWS_H_
