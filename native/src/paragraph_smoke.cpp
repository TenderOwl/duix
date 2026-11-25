#include <iostream>
#include <memory>

#include "include/core/SkFontMgr.h"
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

sk_sp<SkFontMgr> create_font_manager() {
#if defined(_WIN32)
  return SkFontMgr_New_DirectWrite();
#elif defined(__APPLE__)
  return SkFontMgr_New_CoreText(nullptr);
#else
  return SkFontMgr_New_FontConfig(nullptr, SkFontScanner_Make_FreeType());
#endif
}

int main() {
  auto unicode = SkUnicodes::ICU::Make();
  auto fonts = sk_make_sp<skia::textlayout::FontCollection>();
  fonts->setDefaultFontManager(create_font_manager());
  if (!unicode || !fonts->getFallbackManager()) {
    std::cerr << "SkParagraph font/unicode initialization failed.\n";
    return 1;
  }

  skia::textlayout::TextStyle text_style;
  text_style.setFontSize(16);
  skia::textlayout::ParagraphStyle paragraph_style;
  paragraph_style.setTextStyle(text_style);
  auto builder = skia::textlayout::ParagraphBuilder::make(
      paragraph_style,
      fonts,
      unicode);
  if (!builder) {
    std::cerr << "SkParagraph builder creation failed.\n";
    return 1;
  }

  builder->addText("ASCII, \xD0\xBA\xD0\xB8\xD1\x80\xD0\xB8\xD0\xBB\xD0\xBB\xD0\xB8\xD1\x86\xD0\xB0");
  auto paragraph = builder->Build();
  paragraph->layout(240);
  if (paragraph->getLongestLine() <= 0 || paragraph->getHeight() <= 0) {
    std::cerr << "SkParagraph returned invalid measurements.\n";
    return 1;
  }

  std::cout << "SkParagraph smoke passed: width="
            << paragraph->getLongestLine()
            << ", height=" << paragraph->getHeight() << '\n';
  return 0;
}
