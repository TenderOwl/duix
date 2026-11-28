#include "uia_windows.h"

#if defined(_WIN32)

#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <windows.h>

#include <algorithm>
#include <map>
#include <memory>
#include <mutex>
#include <vector>

#include <uiautomation.h>

// The provider implements three interfaces of UI Automation, and every one of
// them derives from IUnknown, so the base of the class is ambiguous. The class
// implements the methods of IUnknown itself and casts to the interfaces
// explicitly, so the ambiguity does not harm the calls.
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Winaccessible-base"
#endif

namespace {

// The flags of a node of the published tree.
constexpr uint32_t kFocused = 1 << 0;
constexpr uint32_t kDisabled = 1 << 1;

// The index of the root of the fragment, the element that holds the tree of
// the widgets.
constexpr int32_t kFragmentRoot = -1;

// The index of a node that does not exist.
constexpr int32_t kNoNode = -2;

// The element id of the root element of UI Automation.
constexpr LONG kUiaRootElementId = -25;

class Provider;
class RootProvider;
class ValueProvider;

// Converts UTF-8 into UTF-16, the encoding of the strings of COM.
std::wstring widen(const std::string& text) {
  if (text.empty()) return std::wstring();
  const int length = static_cast<int>(text.size());
  const int size = MultiByteToWideChar(CP_UTF8, 0, text.c_str(), length,
                                        nullptr, 0);
  if (size <= 0) return std::wstring();
  std::wstring result(static_cast<size_t>(size), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.c_str(), length, result.data(), size);
  return result;
}

CONTROLTYPEID control_type_for(int32_t role) {
  switch (role) {
    case 1:
      return UIA_ButtonControlTypeId;
    case 2:
      return UIA_EditControlTypeId;
    case 3:
      return UIA_TextControlTypeId;
    case 4:
      return UIA_GroupControlTypeId;
    case 5:
      return UIA_ListControlTypeId;
    case 6:
      return UIA_ImageControlTypeId;
    case 7:
      return UIA_WindowControlTypeId;
    default:
      return UIA_CustomControlTypeId;
  }
}

// The state of the bridge of one window.
//
// The snapshot is replaced as a whole and never changed in place, so a reader
// that got a copy of it keeps a consistent tree. The clients of UI Automation
// call the provider from their own threads, so the copy is taken under a lock.
struct Bridge {
  mutable std::mutex mutex;
  std::shared_ptr<const DuiUiaSnapshot> snapshot =
      std::make_shared<const DuiUiaSnapshot>();
  // The providers of the nodes of the tree. UI Automation identifies an
  // element by its provider, so the provider of a node has to be the same
  // object every time the client asks for it.
  mutable std::map<int32_t, Provider*> providers;
  WNDPROC original = nullptr;
};

// The provider of a node of the tree. The root of the fragment has its own
// class, which is known here only after it is defined.
Provider* create_provider(const std::shared_ptr<const Bridge>& bridge,
                          int32_t index);

// The pattern of the value of a text field, which is made by a function that
// knows the class only after it is defined.
IUnknown* create_value_provider(const std::shared_ptr<const Bridge>& bridge,
                                int32_t index);

// The bridges of the windows of the process.
std::map<HWND, std::shared_ptr<Bridge>>& bridges() {
  static std::map<HWND, std::shared_ptr<Bridge>> instance;
  return instance;
}

// The provider of one element of the tree.
//
// UI Automation asks a window for its provider with WM_GETOBJECT. The provider
// serves the element, its properties and the navigation inside the tree, so
// the assistive technologies see the same tree as the semantics tree of the
// widgets.
//
// The root of the fragment is the element the window gives to UI Automation.
// It holds the tree of the widgets and has no properties of its own, for the
// window of the application has them.
class Provider : public IUnknown,
                 public IRawElementProviderSimple,
                 public IRawElementProviderFragment {
 public:
  Provider(std::shared_ptr<const Bridge> bridge, int32_t index)
      : bridge_(std::move(bridge)), index_(index) {}
  virtual ~Provider() = default;

  // IUnknown.
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid,
                                           void** object) override {
    if (object == nullptr) return E_POINTER;
    // Every interface has its own subobject in the class, so the pointer of
    // the asked interface has to be returned.
    if (riid == IID_IUnknown) {
      *object = static_cast<IUnknown*>(
          static_cast<IRawElementProviderSimple*>(this));
    } else if (riid == IID_IRawElementProviderSimple) {
      *object = static_cast<IRawElementProviderSimple*>(this);
    } else if (riid == IID_IRawElementProviderFragment) {
      *object = static_cast<IRawElementProviderFragment*>(this);
    } else if (riid == IID_IRawElementProviderFragmentRoot) {
      IRawElementProviderFragmentRoot* root = as_fragment_root();
      if (root == nullptr) {
        *object = nullptr;
        return E_NOINTERFACE;
      }
      *object = root;
    } else {
      *object = nullptr;
      return E_NOINTERFACE;
    }
    AddRef();
    return S_OK;
  }

  ULONG STDMETHODCALLTYPE AddRef() override {
    return static_cast<ULONG>(InterlockedIncrement(&references_));
  }

  ULONG STDMETHODCALLTYPE Release() override {
    const LONG count = InterlockedDecrement(&references_);
    if (count == 0) delete this;
    return static_cast<ULONG>(count);
  }

  // IRawElementProviderSimple.
  HRESULT STDMETHODCALLTYPE get_ProviderOptions(
      ProviderOptions* options) override {
    if (options == nullptr) return E_POINTER;
    // The provider lives in the process of the application, and UI Automation
    // reaches it with the calls of its clients, which may live in other
    // processes.
    *options = static_cast<ProviderOptions>(ProviderOptions_ServerSideProvider |
                                           ProviderOptions_UseComThreading);
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE GetPatternProvider(PATTERNID pattern_id,
                                                IUnknown** provider) override {
    if (provider == nullptr) return E_POINTER;
    *provider = nullptr;
    if (pattern_id != UIA_ValuePatternId) return UIA_E_ELEMENTNOTAVAILABLE;
    const auto snapshot = current_snapshot();
    const DuiUiaNode* node = node_of(snapshot);
    if (node == nullptr || node->role != 2) return UIA_E_ELEMENTNOTAVAILABLE;
    *provider = create_value_provider(bridge_, index_);
    return *provider == nullptr ? E_OUTOFMEMORY : S_OK;
  }

  HRESULT STDMETHODCALLTYPE GetPropertyValue(PROPERTYID property_id,
                                               VARIANT* value) override {
    return property_value(property_id, value);
  }

  HRESULT STDMETHODCALLTYPE get_HostRawElementProvider(
      IRawElementProviderSimple** provider) override {
    if (provider == nullptr) return E_POINTER;
    if (index_ != kFragmentRoot) {
      // The nodes of the tree are not hosted in a window of their own, so the
      // navigation to and from them is served by the tree itself.
      return E_NOTIMPL;
    }
    *provider = nullptr;
    // The root of the fragment is hosted in the window of the application, so
    // the navigation between the window and the tree is left to the default
    // provider of the window.
    const auto snapshot = current_snapshot();
    if (snapshot->hwnd == nullptr) return S_OK;
    return UiaHostProviderFromHwnd(static_cast<HWND>(snapshot->hwnd),
                                   provider);
  }

  // IRawElementProviderFragment.
  HRESULT STDMETHODCALLTYPE Navigate(NavigateDirection direction,
                                     IRawElementProviderFragment** provider) override {
    if (provider == nullptr) return E_POINTER;
    *provider = nullptr;
    const int32_t target = navigate_target(direction);
    if (target == kNoNode) return UIA_E_ELEMENTNOTAVAILABLE;
    Provider* node = provider_for(target);
    if (node == nullptr) return UIA_E_ELEMENTNOTAVAILABLE;
    node->AddRef();
    *provider = static_cast<IRawElementProviderFragment*>(node);
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE GetRuntimeId(SAFEARRAY** runtime_id) override {
    if (runtime_id == nullptr) return E_POINTER;
    if (index_ == kFragmentRoot) {
      // The window of the application identifies the root of the fragment.
      SAFEARRAY* empty = SafeArrayCreateVector(VT_I4, 0, 0);
      if (empty == nullptr) return E_OUTOFMEMORY;
      *runtime_id = empty;
      return S_OK;
    }
    SAFEARRAY* array = SafeArrayCreateVector(VT_I4, 0, 2);
    if (array == nullptr) return E_OUTOFMEMORY;
    LONG id[2] = {3, index_};
    for (LONG position = 0; position < 2; position++) {
      SafeArrayPutElement(array, &position, &id[position]);
    }
    *runtime_id = array;
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE get_BoundingRectangle(UiaRect* rectangle) override {
    if (rectangle == nullptr) return E_POINTER;
    rectangle->left = 0.0;
    rectangle->top = 0.0;
    rectangle->width = 0.0;
    rectangle->height = 0.0;
    if (index_ == kFragmentRoot) {
      // The window of the application gives the bounds of the root.
      return S_OK;
    }
    const auto snapshot = current_snapshot();
    const DuiUiaNode* node = node_of(snapshot);
    if (node == nullptr) return UIA_E_ELEMENTNOTAVAILABLE;
    const double scale = snapshot->scale > 0 ? snapshot->scale : 1.0;
    rectangle->left = snapshot->window_x + node->left * scale;
    rectangle->top = snapshot->window_y + node->top * scale;
    rectangle->width = node->width * scale;
    rectangle->height = node->height * scale;
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE GetEmbeddedFragmentRoots(
      SAFEARRAY** roots) override {
    if (roots == nullptr) return E_POINTER;
    SAFEARRAY* array = SafeArrayCreateVector(VT_DISPATCH, 0, 0);
    if (array == nullptr) return E_OUTOFMEMORY;
    *roots = array;
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE SetFocus() override {
    return UIA_E_ELEMENTNOTAVAILABLE;
  }

  HRESULT STDMETHODCALLTYPE get_FragmentRoot(
      IRawElementProviderFragmentRoot** root) override {
    if (root == nullptr) return E_POINTER;
    Provider* fragment = provider_for(kFragmentRoot);
    if (fragment == nullptr) return UIA_E_ELEMENTNOTAVAILABLE;
    IRawElementProviderFragmentRoot* value = fragment->as_fragment_root();
    if (value == nullptr) return UIA_E_ELEMENTNOTAVAILABLE;
    fragment->AddRef();
    *root = value;
    return S_OK;
  }

 protected:
  // The current tree of the bridge. The snapshot is never changed in place,
  // so the copy stays valid after the lock is released.
  std::shared_ptr<const DuiUiaSnapshot> current_snapshot() const {
    std::lock_guard<std::mutex> lock(bridge_->mutex);
    return bridge_->snapshot;
  }

  // The provider of a node of the tree. The providers are kept by the bridge,
  // so the client always gets the same object for the same node.
  Provider* provider_for(int32_t index) const {
    std::lock_guard<std::mutex> lock(bridge_->mutex);
    auto it = bridge_->providers.find(index);
    if (it != bridge_->providers.end()) return it->second;
    Provider* provider = create_provider(bridge_, index);
    bridge_->providers.emplace(index, provider);
    return provider;
  }

  // The provider of the root of the fragment, which only it has.
  virtual IRawElementProviderFragmentRoot* as_fragment_root() { return nullptr; }

  // The node of the provider, or null for the root of the fragment.
  const DuiUiaNode* node_of(
      const std::shared_ptr<const DuiUiaSnapshot>& snapshot) const {
    if (index_ == kFragmentRoot) return nullptr;
    const auto& nodes = snapshot->nodes;
    if (index_ < 0 || static_cast<size_t>(index_) >= nodes.size()) {
      return nullptr;
    }
    return &nodes[static_cast<size_t>(index_)];
  }

  bool is_focused(const DuiUiaNode* node) const {
    return node != nullptr && (node->flags & kFocused) != 0;
  }

  // The index of the parent of a node. The root of the tree of the widgets
  // hangs under the root of the fragment.
  int32_t parent_index(const DuiUiaNode* node) const {
    if (node == nullptr) return kNoNode;
    if (node->parent < 0) return kFragmentRoot;
    return node->parent;
  }

  std::vector<int32_t> child_indices(
      const std::shared_ptr<const DuiUiaSnapshot>& snapshot) const {
    std::vector<int32_t> children;
    const auto& nodes = snapshot->nodes;
    for (size_t index = 0; index < nodes.size(); index++) {
      if (nodes[index].parent == index_) {
        children.push_back(static_cast<int32_t>(index));
      }
    }
    return children;
  }

  int32_t navigate_target(NavigateDirection direction) const {
    const auto snapshot = current_snapshot();
    const std::vector<int32_t> children = child_indices(snapshot);
    switch (direction) {
      case NavigateDirection_Parent:
        return parent_index(node_of(snapshot));
      case NavigateDirection_FirstChild:
        return children.empty() ? kNoNode : children.front();
      case NavigateDirection_LastChild:
        return children.empty() ? kNoNode : children.back();
      case NavigateDirection_NextSibling:
      case NavigateDirection_PreviousSibling: {
        const int32_t parent = parent_index(node_of(snapshot));
        std::vector<int32_t> siblings;
        const auto& nodes = snapshot->nodes;
        for (size_t index = 0; index < nodes.size(); index++) {
          if (nodes[index].parent == parent) {
            siblings.push_back(static_cast<int32_t>(index));
          }
        }
        const auto position =
            std::find(siblings.begin(), siblings.end(), index_);
        if (position == siblings.end()) return kNoNode;
        if (direction == NavigateDirection_NextSibling) {
          if (position + 1 >= siblings.end()) return kNoNode;
          return *(position + 1);
        }
        if (position == siblings.begin()) return kNoNode;
        return *(position - 1);
      }
      default:
        return kNoNode;
    }
  }

  // The index of the focused node of the tree.
  int32_t focused_index() const {
    const auto snapshot = current_snapshot();
    const auto& nodes = snapshot->nodes;
    for (size_t index = 0; index < nodes.size(); index++) {
      if ((nodes[index].flags & kFocused) != 0) {
        return static_cast<int32_t>(index);
      }
    }
    return kNoNode;
  }

  // The index of the deepest node at a point of the screen.
  int32_t node_at(double x, double y) const {
    const auto snapshot = current_snapshot();
    const double scale = snapshot->scale > 0 ? snapshot->scale : 1.0;
    const auto& nodes = snapshot->nodes;
    int32_t found = kNoNode;
    for (size_t index = 0; index < nodes.size(); index++) {
      const DuiUiaNode& node = nodes[index];
      const double left = snapshot->window_x + node.left * scale;
      const double top = snapshot->window_y + node.top * scale;
      if (x >= left && x <= left + node.width * scale &&
          y >= top && y <= top + node.height * scale) {
        found = static_cast<int32_t>(index);
      }
    }
    return found;
  }

  HRESULT property_value(PROPERTYID property_id, VARIANT* value) {
    if (value == nullptr) return E_POINTER;
    VariantInit(value);
    if (index_ == kFragmentRoot) {
      // The root of the fragment is the element the window gives to UI
      // Automation, so its answers are the answers of the window. The root
      // keeps to itself, for the tree it holds is shown instead of it.
      const auto snapshot = current_snapshot();
      switch (property_id) {
        case UIA_ControlTypePropertyId:
          V_VT(value) = VT_I4;
          V_I4(value) = UIA_WindowControlTypeId;
          return S_OK;
        case UIA_NamePropertyId:
          return string_value(snapshot->title, value);
        case UIA_BoundingRectanglePropertyId: {
          UiaRect rectangle{};
          rectangle.left = snapshot->window_x;
          rectangle.top = snapshot->window_y;
          rectangle.width = snapshot->window_width;
          rectangle.height = snapshot->window_height;
          double values[4] = {
              rectangle.left, rectangle.top, rectangle.width, rectangle.height};
          VARIANT array{};
          VariantInit(&array);
          array.vt = VT_ARRAY | VT_R8;
          array.parray = SafeArrayCreateVector(VT_R8, 0, 4);
          if (array.parray == nullptr) return E_OUTOFMEMORY;
          for (LONG position = 0; position < 4; position++) {
            SafeArrayPutElement(array.parray, &position, &values[position]);
          }
          *value = array;
          return S_OK;
        }
        case UIA_IsEnabledPropertyId:
          V_VT(value) = VT_BOOL;
          V_BOOL(value) = VARIANT_TRUE;
          return S_OK;
        case UIA_IsOffscreenPropertyId:
          V_VT(value) = VT_BOOL;
          V_BOOL(value) = VARIANT_FALSE;
          return S_OK;
        case UIA_IsKeyboardFocusablePropertyId:
        case UIA_HasKeyboardFocusPropertyId:
          V_VT(value) = VT_BOOL;
          V_BOOL(value) = VARIANT_FALSE;
          return S_OK;
        case UIA_IsControlElementPropertyId:
        case UIA_IsContentElementPropertyId:
          V_VT(value) = VT_BOOL;
          V_BOOL(value) = VARIANT_TRUE;
          return S_OK;
        case UIA_ProcessIdPropertyId:
          V_VT(value) = VT_I4;
          V_I4(value) = static_cast<int>(GetCurrentProcessId());
          return S_OK;
        case UIA_NativeWindowHandlePropertyId:
          V_VT(value) = VT_I4;
          V_I4(value) = static_cast<int>(
              reinterpret_cast<intptr_t>(snapshot->hwnd));
          return S_OK;
        case UIA_FrameworkIdPropertyId:
          return string_value("Dui", value);
        default:
          return S_OK;
      }
    }
    const auto snapshot = current_snapshot();
    const DuiUiaNode* node = node_of(snapshot);
    switch (property_id) {
      case UIA_ControlTypePropertyId:
        V_VT(value) = VT_I4;
        V_I4(value) = control_type_for(node != nullptr ? node->role : 0);
        return S_OK;
      case UIA_NamePropertyId:
        return string_value(node != nullptr ? node->name : std::string(), value);
      case UIA_ValueValuePropertyId:
        return string_value(node != nullptr ? node->value : std::string(), value);
      case UIA_HelpTextPropertyId:
        return string_value(node != nullptr ? node->name : std::string(), value);
      case UIA_AutomationIdPropertyId:
        return string_value(std::string(), value);
      case UIA_FrameworkIdPropertyId:
        return string_value("Dui", value);
      case UIA_IsEnabledPropertyId:
        V_VT(value) = VT_BOOL;
        V_BOOL(value) =
            (node == nullptr || (node->flags & kDisabled) == 0)
                ? VARIANT_TRUE
                : VARIANT_FALSE;
        return S_OK;
      case UIA_IsKeyboardFocusablePropertyId:
        V_VT(value) = VT_BOOL;
        V_BOOL(value) = VARIANT_TRUE;
        return S_OK;
      case UIA_HasKeyboardFocusPropertyId:
        V_VT(value) = VT_BOOL;
        V_BOOL(value) = is_focused(node) ? VARIANT_TRUE : VARIANT_FALSE;
        return S_OK;
      case UIA_IsOffscreenPropertyId:
        V_VT(value) = VT_BOOL;
        V_BOOL(value) = VARIANT_FALSE;
        return S_OK;
      case UIA_IsContentElementPropertyId:
      case UIA_IsControlElementPropertyId:
        V_VT(value) = VT_BOOL;
        V_BOOL(value) = VARIANT_TRUE;
        return S_OK;
      case UIA_NativeWindowHandlePropertyId:
        V_VT(value) = VT_I4;
        V_I4(value) = static_cast<int>(
            reinterpret_cast<intptr_t>(snapshot->hwnd));
        return S_OK;
      case UIA_BoundingRectanglePropertyId: {
        UiaRect rectangle{};
        const HRESULT result = get_BoundingRectangle(&rectangle);
        if (FAILED(result)) return result;
        double values[4] = {
            rectangle.left, rectangle.top, rectangle.width, rectangle.height};
        VARIANT array{};
        VariantInit(&array);
        array.vt = VT_ARRAY | VT_R8;
        array.parray = SafeArrayCreateVector(VT_R8, 0, 4);
        if (array.parray == nullptr) return E_OUTOFMEMORY;
        for (LONG index = 0; index < 4; index++) {
          SafeArrayPutElement(array.parray, &index, &values[index]);
        }
        *value = array;
        return S_OK;
      }
      default:
        // The properties the node does not have are left empty, so UI
        // Automation falls back to its own values.
        return S_OK;
    }
  }

  static HRESULT string_value(const std::string& text, VARIANT* value) {
    const std::wstring wide = widen(text);
    BSTR string = SysAllocString(wide.c_str());
    if (string == nullptr) return E_OUTOFMEMORY;
    V_VT(value) = VT_BSTR;
    V_BSTR(value) = string;
    return S_OK;
  }

  std::shared_ptr<const Bridge> bridge_;
  int32_t index_;
  LONG references_ = 1;
};

// The provider of the root of the fragment.
//
// The root of the fragment is the element the window gives to UI Automation.
// It holds the tree of the widgets, and it is the only element that can tell
// which node of the tree is at a point of the screen and which node holds the
// focus.
class RootProvider final : public Provider,
                            public IRawElementProviderFragmentRoot {
 public:
  using Provider::Provider;

  // The root of the fragment holds the interfaces of COM on its own, for the
  // base of the class is ambiguous.
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid,
                                           void** object) override {
    if (object == nullptr) return E_POINTER;
    if (riid == IID_IUnknown) {
      *object = static_cast<IUnknown*>(
          static_cast<IRawElementProviderSimple*>(this));
    } else if (riid == IID_IRawElementProviderSimple) {
      *object = static_cast<IRawElementProviderSimple*>(this);
    } else if (riid == IID_IRawElementProviderFragment) {
      *object = static_cast<IRawElementProviderFragment*>(this);
    } else if (riid == IID_IRawElementProviderFragmentRoot) {
      *object = static_cast<IRawElementProviderFragmentRoot*>(this);
    } else {
      *object = nullptr;
      return E_NOINTERFACE;
    }
    AddRef();
    return S_OK;
  }

  ULONG STDMETHODCALLTYPE AddRef() override { return Provider::AddRef(); }

  ULONG STDMETHODCALLTYPE Release() override { return Provider::Release(); }

  // IRawElementProviderFragmentRoot.
  HRESULT STDMETHODCALLTYPE ElementProviderFromPoint(
      double x, double y, IRawElementProviderFragment** provider) override {
    if (provider == nullptr) return E_POINTER;
    *provider = nullptr;
    const int32_t target = node_at(x, y);
    if (target == kNoNode) return UIA_E_ELEMENTNOTAVAILABLE;
    Provider* node = provider_for(target);
    if (node == nullptr) return UIA_E_ELEMENTNOTAVAILABLE;
    node->AddRef();
    *provider = static_cast<IRawElementProviderFragment*>(node);
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE GetFocus(
      IRawElementProviderFragment** provider) override {
    if (provider == nullptr) return E_POINTER;
    *provider = nullptr;
    const int32_t target = focused_index();
    if (target == kNoNode) return UIA_E_ELEMENTNOTAVAILABLE;
    Provider* node = provider_for(target);
    if (node == nullptr) return UIA_E_ELEMENTNOTAVAILABLE;
    node->AddRef();
    *provider = static_cast<IRawElementProviderFragment*>(node);
    return S_OK;
  }

 protected:
  IRawElementProviderFragmentRoot* as_fragment_root() override {
    return static_cast<IRawElementProviderFragmentRoot*>(this);
  }
};

// The pattern of the value of a text field.
//
// The value of a field is read and written through this pattern.
class ValueProvider final : public IUnknown, public IValueProvider {
 public:
  ValueProvider(std::shared_ptr<const Bridge> bridge, int32_t index)
      : bridge_(std::move(bridge)), index_(index) {}
  ~ValueProvider() = default;

  // IUnknown.
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid,
                                           void** object) override {
    if (object == nullptr) return E_POINTER;
    if (riid == IID_IUnknown) {
      *object = static_cast<IUnknown*>(
          static_cast<IValueProvider*>(this));
    } else if (riid == IID_IValueProvider) {
      *object = static_cast<IValueProvider*>(this);
    } else {
      *object = nullptr;
      return E_NOINTERFACE;
    }
    AddRef();
    return S_OK;
  }

  ULONG STDMETHODCALLTYPE AddRef() override {
    return static_cast<ULONG>(InterlockedIncrement(&references_));
  }

  ULONG STDMETHODCALLTYPE Release() override {
    const LONG count = InterlockedDecrement(&references_);
    if (count == 0) delete this;
    return static_cast<ULONG>(count);
  }

  // IValueProvider.
  HRESULT STDMETHODCALLTYPE SetValue(LPCWSTR value) override {
    (void)value;
    // The value of a field is changed by the application, not by the
    // assistive technologies.
    return UIA_E_NOTSUPPORTED;
  }

  HRESULT STDMETHODCALLTYPE get_Value(BSTR* value) override {
    if (value == nullptr) return E_POINTER;
    *value = nullptr;
    std::lock_guard<std::mutex> lock(bridge_->mutex);
    const auto& nodes = bridge_->snapshot->nodes;
    if (index_ < 0 || static_cast<size_t>(index_) >= nodes.size()) {
      return UIA_E_ELEMENTNOTAVAILABLE;
    }
    const std::wstring wide = widen(nodes[static_cast<size_t>(index_)].value);
    BSTR string = SysAllocString(wide.c_str());
    if (string == nullptr) return E_OUTOFMEMORY;
    *value = string;
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE get_IsReadOnly(BOOL* read_only) override {
    if (read_only == nullptr) return E_POINTER;
    *read_only = TRUE;
    return S_OK;
  }

 private:
  std::shared_ptr<const Bridge> bridge_;
  int32_t index_;
  LONG references_ = 1;
};

// The pattern of the value of a text field.
IUnknown* create_value_provider(const std::shared_ptr<const Bridge>& bridge,
                                int32_t index) {
  return new ValueProvider(bridge, index);
}

// The provider of a node of the tree.
Provider* create_provider(const std::shared_ptr<const Bridge>& bridge,
                          int32_t index) {
  if (index == kFragmentRoot) return new RootProvider(bridge, index);
  return new Provider(bridge, index);
}

// Tells the assistive technologies that the focus moved to a node.
void raise_focus_changed(const std::shared_ptr<const Bridge>& bridge,
                         int32_t index) {
  Provider* provider = nullptr;
  {
    std::lock_guard<std::mutex> lock(bridge->mutex);
    const auto& nodes = bridge->snapshot->nodes;
    if (index < 0 || static_cast<size_t>(index) >= nodes.size()) return;
    auto it = bridge->providers.find(index);
    if (it == bridge->providers.end()) return;
    provider = it->second;
  }
  provider->AddRef();
  UiaRaiseAutomationEvent(provider, UIA_AutomationFocusChangedEventId);
  provider->Release();
}

// Tells the assistive technologies that a property of a node changed.
void raise_property_changed(const std::shared_ptr<const Bridge>& bridge,
                             int32_t index,
                             PROPERTYID property_id,
                             const std::string& old_text,
                             const std::string& new_text) {
  Provider* provider = nullptr;
  {
    std::lock_guard<std::mutex> lock(bridge->mutex);
    const auto& nodes = bridge->snapshot->nodes;
    if (index < 0 || static_cast<size_t>(index) >= nodes.size()) return;
    auto it = bridge->providers.find(index);
    if (it == bridge->providers.end()) return;
    provider = it->second;
  }
  VARIANT old_value{};
  VariantInit(&old_value);
  old_value.vt = VT_BSTR;
  old_value.bstrVal = SysAllocString(widen(old_text).c_str());
  VARIANT new_value{};
  VariantInit(&new_value);
  new_value.vt = VT_BSTR;
  new_value.bstrVal = SysAllocString(widen(new_text).c_str());
  provider->AddRef();
  UiaRaiseAutomationPropertyChangedEvent(provider, property_id, old_value,
                                         new_value);
  provider->Release();
  VariantClear(&old_value);
  VariantClear(&new_value);
}

// Compares the trees of two frames and tells the assistive technologies about
// the changes they can see.
void raise_changes(const std::shared_ptr<const Bridge>& bridge,
                   const DuiUiaSnapshot& previous,
                   const DuiUiaSnapshot& current) {
  int32_t old_focus = kNoNode;
  int32_t new_focus = kNoNode;
  for (size_t index = 0; index < previous.nodes.size(); index++) {
    if ((previous.nodes[index].flags & kFocused) != 0) {
      old_focus = static_cast<int32_t>(index);
      break;
    }
  }
  for (size_t index = 0; index < current.nodes.size(); index++) {
    if ((current.nodes[index].flags & kFocused) != 0) {
      new_focus = static_cast<int32_t>(index);
      break;
    }
  }
  if (new_focus != kNoNode && new_focus != old_focus) {
    raise_focus_changed(bridge, new_focus);
  }
  const size_t count = std::min(previous.nodes.size(), current.nodes.size());
  for (size_t index = 0; index < count; index++) {
    if (previous.nodes[index].name != current.nodes[index].name) {
      raise_property_changed(bridge, static_cast<int32_t>(index),
                              UIA_NamePropertyId, previous.nodes[index].name,
                              current.nodes[index].name);
    }
    if (previous.nodes[index].value != current.nodes[index].value) {
      raise_property_changed(bridge, static_cast<int32_t>(index),
                              UIA_ValueValuePropertyId,
                              previous.nodes[index].value,
                              current.nodes[index].value);
    }
  }
}

std::shared_ptr<const Bridge> bridge_for(HWND hwnd) {
  auto it = bridges().find(hwnd);
  if (it == bridges().end()) return nullptr;
  return it->second;
}

LRESULT CALLBACK window_proc(HWND hwnd,
                              UINT message,
                              WPARAM wparam,
                              LPARAM lparam) {
  if (message == WM_GETOBJECT) {
    const DWORD request = static_cast<DWORD>(lparam);
    if (request == static_cast<DWORD>(kUiaRootElementId)) {
      const std::shared_ptr<const Bridge> bridge = bridge_for(hwnd);
      if (bridge) {
        // The root of the fragment is the element the window gives to UI
        // Automation. The helper of the subsystem marshals it for the
        // clients that live in other processes.
        Provider* provider = nullptr;
        {
          std::lock_guard<std::mutex> lock(bridge->mutex);
          auto it = bridge->providers.find(kFragmentRoot);
          if (it == bridge->providers.end()) {
            provider = new RootProvider(bridge, kFragmentRoot);
            bridge->providers.emplace(kFragmentRoot, provider);
          } else {
            provider = it->second;
          }
        }
        provider->AddRef();
        const LRESULT result =
            UiaReturnRawElementProvider(hwnd, wparam, lparam, provider);
        provider->Release();
        return result;
      }
    }
  }
  auto it = bridges().find(hwnd);
  if (it != bridges().end() && it->second->original != nullptr) {
    return CallWindowProcW(it->second->original, hwnd, message, wparam, lparam);
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}

}  // namespace

#if defined(__clang__)
#pragma clang diagnostic pop
#endif

void dui_windows_install_uia(void* hwnd) {
  if (hwnd == nullptr) return;
  HWND handle = static_cast<HWND>(hwnd);
  if (bridges().count(handle) != 0) return;
  auto bridge = std::make_shared<Bridge>();
  bridge->original =
      reinterpret_cast<WNDPROC>(SetWindowLongPtrW(handle, GWLP_WNDPROC,
                                                reinterpret_cast<LONG_PTR>(
                                                    &window_proc)));
  if (bridge->original == nullptr) return;
  bridges().emplace(handle, bridge);
}

void dui_windows_update_uia(void* hwnd, const DuiUiaSnapshot& snapshot) {
  if (hwnd == nullptr) return;
  HWND handle = static_cast<HWND>(hwnd);
  auto it = bridges().find(handle);
  if (it == bridges().end()) return;
  DuiUiaSnapshot previous;
  {
    std::lock_guard<std::mutex> lock(it->second->mutex);
    previous = *it->second->snapshot;
    it->second->snapshot = std::make_shared<const DuiUiaSnapshot>(snapshot);
  }
  raise_changes(it->second, previous, snapshot);
}

void dui_windows_remove_uia(void* hwnd) {
  if (hwnd == nullptr) return;
  HWND handle = static_cast<HWND>(hwnd);
  auto it = bridges().find(handle);
  if (it == bridges().end()) return;
  if (it->second->original != nullptr) {
    SetWindowLongPtrW(handle, GWLP_WNDPROC,
                      reinterpret_cast<LONG_PTR>(it->second->original));
  }
  {
    std::lock_guard<std::mutex> lock(it->second->mutex);
    for (auto& entry : it->second->providers) {
      entry.second->Release();
      delete entry.second;
    }
    it->second->providers.clear();
  }
  bridges().erase(it);
}

#else

void dui_windows_install_uia(void* hwnd) {}

void dui_windows_update_uia(void* hwnd, const DuiUiaSnapshot& snapshot) {}

void dui_windows_remove_uia(void* hwnd) {}

#endif
