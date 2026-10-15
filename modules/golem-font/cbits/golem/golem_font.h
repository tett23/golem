#ifndef GOLEM_FONT_H
#define GOLEM_FONT_H
#include <stddef.h>
#include <stdint.h>

typedef struct golem_font golem_font;

/* The font is copied; NULL when FreeType or HarfBuzz cannot read it. */
golem_font *golem_font_open(const uint8_t *data, size_t len);
void golem_font_close(golem_font *f);

int golem_font_upem(golem_font *f);
int golem_font_fstype(golem_font *f);
int golem_font_is_cff(golem_font *f);
int golem_font_num_glyphs(golem_font *f);
/* ascender, descender, cap height; font units */
void golem_font_extents(golem_font *f, int32_t *asc, int32_t *desc, int32_t *cap);
/* The height of the centre of the ideographic em box above the baseline
   (HarfBuzz's ideoEmboxCentral baseline, horizontal, script hani); font
   units. Falls back to HarfBuzz's estimate without a BASE table. */
int golem_font_embox_central(golem_font *f);
/* advance (h, v), bbox (xmin, ymin, xmax, ymax); font units. 0 on success. */
int golem_font_glyph_metrics(golem_font *f, uint32_t gid, int32_t *out6);

/* The vertical origin of a glyph (hb_font_get_glyph_v_origin): the point
   that vertical shaping subtracts from each glyph's offsets; font units. */
void golem_font_v_origin(golem_font *f, uint32_t gid, int32_t *x, int32_t *y);

/* Shapes UTF-8 text. vertical: 0 or 1. features: comma-separated
   HarfBuzz feature strings or NULL. Returns the glyph count, or -1.
   The arrays must hold max_glyphs entries; out_pos holds 4 per glyph
   (x_advance, y_advance, x_offset, y_offset) in font units. */
int golem_font_shape(golem_font *f, const char *utf8, int len, const char *script,
                     const char *lang, int vertical, const char *features,
                     uint32_t *out_gids, uint32_t *out_clusters, int32_t *out_pos,
                     int max_glyphs);

/* Subsets to the glyphs, keeping glyph ids. Returns a malloc'd buffer
   (free with golem_free) and its length, or NULL. */
uint8_t *golem_font_subset(golem_font *f, const uint32_t *gids, int n, size_t *out_len);
char *golem_font_postscript_name(golem_font *f);
uint32_t golem_font_cid(golem_font *f, uint32_t gid);
/* The ROS of a CID-keyed CFF font (the strings belong to the font).
   0 on success; -1 for any other font. */
int golem_font_ros(golem_font *f, const char **registry, const char **ordering,
                   int *supplement);
void golem_free(void *p);
#endif
