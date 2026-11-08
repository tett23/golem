/* The number of the charmaps that FreeType keeps of a font in memory, for
 * the test of the cmap that it refuses (docs/adr/0238, I3): only the test
 * suite calls it, so the library has no new function. -1 when FreeType
 * cannot open the font. */
#include <stddef.h>
#include <ft2build.h>
#include FT_FREETYPE_H

int golem_test_num_charmaps(const unsigned char *bytes, size_t len) {
  FT_Library lib;
  FT_Face face;
  int n;
  if (FT_Init_FreeType(&lib)) return -1;
  if (FT_New_Memory_Face(lib, bytes, (FT_Long)len, 0, &face)) {
    FT_Done_FreeType(lib);
    return -1;
  }
  n = face->num_charmaps;
  FT_Done_Face(face);
  FT_Done_FreeType(lib);
  return n;
}
