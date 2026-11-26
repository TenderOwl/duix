#include "dui_native.h"

#include <SDL3/SDL.h>

#import <AppKit/AppKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include <string>

namespace {

NSString* file_extension(NSString* pattern, NSError** error) {
  NSString* value =
      [pattern stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([value hasPrefix:@"*."]) {
    value = [value substringFromIndex:2];
  } else if ([value hasPrefix:@"."]) {
    value = [value substringFromIndex:1];
  }
  if (value.length == 0 ||
      [value rangeOfCharacterFromSet:
                  [NSCharacterSet characterSetWithCharactersInString:@"*?/\\"]]
              .location != NSNotFound) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"duix.FileDialog"
                     code:1
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       [NSString stringWithFormat:
                                     @"Unsupported file dialog pattern: %@",
                                     pattern]
                 }];
    }
    return nil;
  }
  return value;
}

}  // namespace

char* dui_macos_open_file_dialog(
    SDL_Window* window,
    const char* title_utf8,
    const char* initial_directory_utf8,
    const DuiFileDialogFilter* filters,
    size_t filter_count,
    std::string* error) {
  @autoreleasepool {
    if (![NSThread isMainThread]) {
      *error = "The system open-file dialog must run on the main thread.";
      return nullptr;
    }
    if (filter_count > 0 && !filters) {
      *error = "Invalid open-file dialog filters.";
      return nullptr;
    }

    @try {
      NSOpenPanel* panel = [NSOpenPanel openPanel];
      panel.canChooseFiles = YES;
      panel.canChooseDirectories = NO;
      panel.allowsMultipleSelection = NO;
      if (title_utf8 && *title_utf8) {
        panel.title = [NSString stringWithUTF8String:title_utf8];
      }
      if (initial_directory_utf8 && *initial_directory_utf8) {
        NSString* directory =
            [NSString stringWithUTF8String:initial_directory_utf8];
        panel.directoryURL =
            [NSURL fileURLWithPath:directory isDirectory:YES];
      }

      if (filter_count > 0) {
        NSMutableArray<NSString*>* extensions = [NSMutableArray array];
        bool allow_all_files = false;
        for (size_t index = 0; index < filter_count; ++index) {
          const auto& filter = filters[index];
          if (!filter.name_utf8 || !filter.spec_utf8) {
            *error = "Invalid UTF-8 in the open-file dialog filters.";
            return nullptr;
          }
          NSString* spec = [NSString stringWithUTF8String:filter.spec_utf8];
          for (NSString* pattern in [spec componentsSeparatedByString:@";"]) {
            NSString* trimmed =
                [pattern stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (trimmed.length == 0) continue;
            if ([trimmed isEqualToString:@"*"] ||
                [trimmed isEqualToString:@"*.*"]) {
              allow_all_files = true;
              continue;
            }
            NSError* pattern_error = nil;
            NSString* extension = file_extension(trimmed, &pattern_error);
            if (!extension) {
              *error = pattern_error.localizedDescription.UTF8String;
              return nullptr;
            }
            [extensions addObject:extension];
          }
        }
        if (!allow_all_files) {
          if (extensions.count == 0) {
            *error = "An open-file dialog filter has no patterns.";
            return nullptr;
          }
          if (@available(macOS 11.0, *)) {
            NSMutableArray<UTType*>* content_types = [NSMutableArray array];
            for (NSString* extension in extensions) {
              UTType* type = [UTType typeWithFilenameExtension:extension];
              if (type) [content_types addObject:type];
            }
            if (content_types.count == 0) {
              *error = "Couldn't resolve the open-file dialog filters.";
              return nullptr;
            }
            panel.allowedContentTypes = content_types;
          } else {
            panel.allowedFileTypes = extensions;
          }
        }
      }

      NSWindow* parent = nullptr;
      if (window) {
        parent = (__bridge NSWindow*)SDL_GetPointerProperty(
            SDL_GetWindowProperties(window),
            SDL_PROP_WINDOW_COCOA_WINDOW_POINTER,
            nullptr);
      }

      __block NSModalResponse response = NSModalResponseCancel;
      if (parent) {
        __block bool finished = false;
        CFRunLoopRef run_loop = CFRunLoopGetCurrent();
        [panel beginSheetModalForWindow:parent
                      completionHandler:^(NSModalResponse result) {
                        response = result;
                        finished = true;
                        CFRunLoopStop(run_loop);
                      }];
        while (!finished) {
          CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, true);
        }
      } else {
        response = [panel runModal];
      }

      if (response == NSModalResponseCancel) return nullptr;
      if (response != NSModalResponseOK) {
        *error = "The system open-file dialog failed to display.";
        return nullptr;
      }
      NSString* path = panel.URL.path;
      const char* utf8 = path.UTF8String;
      if (!utf8) {
        *error = "Couldn't read the selected file path.";
        return nullptr;
      }
      char* result = SDL_strdup(utf8);
      if (!result) *error = "Couldn't allocate the selected file path.";
      return result;
    } @catch (NSException* exception) {
      *error = std::string("The system open-file dialog failed: ") +
               exception.reason.UTF8String;
      return nullptr;
    }
  }
}
