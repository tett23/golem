/* A thin C layer over HarfBuzz and FreeType for golem-font
   (ADR 0001, 0002). All values are integers in font units.

   Threads: Golem calls these functions from several OS threads at once
   (the Haskell side looks pure). The HarfBuzz objects (blob, face, font)
   are only read after golem_font_open, and HarfBuzz allows that from
   any number of threads; each shaping has its own buffer. An FT_Face may
   be used by one thread at a time (FT_Load_Glyph writes its one glyph
   slot), so every function that touches the face holds the font's
   ft_lock. */
#include "golem_font.h"
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <hb.h>
#include <hb-ot.h>
#include <hb-subset.h>
#include <ft2build.h>
#include FT_FREETYPE_H
#include FT_TRUETYPE_TABLES_H
#include FT_CID_H

struct golem_font {
  uint8_t *bytes;
  size_t len;
  FT_Library lib;
  FT_Face face;
  /* held while the face is used; the HarfBuzz objects need no lock */
  pthread_mutex_t ft_lock;
  hb_blob_t *blob;
  hb_face_t *hbface;
  hb_font_t *hbfont;
};

golem_font *golem_font_open(const uint8_t *data, size_t len) {
  golem_font *f = calloc(1, sizeof *f);
  if (!f) return NULL;
  f->bytes = malloc(len ? len : 1);
  if (!f->bytes) { free(f); return NULL; }
  memcpy(f->bytes, data, len);
  f->len = len;
  if (FT_Init_FreeType(&f->lib)) { free(f->bytes); free(f); return NULL; }
  if (FT_New_Memory_Face(f->lib, f->bytes, (FT_Long)len, 0, &f->face)) {
    FT_Done_FreeType(f->lib); free(f->bytes); free(f); return NULL;
  }
  pthread_mutex_init(&f->ft_lock, NULL);
  f->blob = hb_blob_create((const char *)f->bytes, (unsigned)len, HB_MEMORY_MODE_READONLY, NULL, NULL);
  f->hbface = hb_face_create(f->blob, 0);
  f->hbfont = hb_font_create(f->hbface);
  int upem = (int)hb_face_get_upem(f->hbface);
  hb_font_set_scale(f->hbfont, upem, upem);
  return f;
}

void golem_font_close(golem_font *f) {
  if (!f) return;
  hb_font_destroy(f->hbfont);
  hb_face_destroy(f->hbface);
  hb_blob_destroy(f->blob);
  FT_Done_Face(f->face);
  FT_Done_FreeType(f->lib);
  pthread_mutex_destroy(&f->ft_lock);
  free(f->bytes);
  free(f);
}

int golem_font_upem(golem_font *f) { return (int)hb_face_get_upem(f->hbface); }
#define LOCK_FT(f) pthread_mutex_lock(&(f)->ft_lock)
#define UNLOCK_FT(f) pthread_mutex_unlock(&(f)->ft_lock)

int golem_font_fstype(golem_font *f) {
  LOCK_FT(f);
  int r = (int)FT_Get_FSType_Flags(f->face);
  UNLOCK_FT(f);
  return r;
}

int golem_font_num_glyphs(golem_font *f) {
  LOCK_FT(f);
  int r = (int)f->face->num_glyphs;
  UNLOCK_FT(f);
  return r;
}

int golem_font_is_cff(golem_font *f) {
  hb_blob_t *b = hb_face_reference_table(f->hbface, HB_TAG('C','F','F',' '));
  int r = hb_blob_get_length(b) > 0;
  hb_blob_destroy(b);
  return r;
}

void golem_font_extents(golem_font *f, int32_t *asc, int32_t *desc, int32_t *cap) {
  LOCK_FT(f);
  *asc = f->face->ascender;
  *desc = f->face->descender;
  TT_OS2 *os2 = (TT_OS2 *)FT_Get_Sfnt_Table(f->face, FT_SFNT_OS2);
  *cap = (os2 && os2->version >= 2) ? os2->sCapHeight : f->face->ascender;
  UNLOCK_FT(f);
}

int golem_font_embox_central(golem_font *f) {
  hb_position_t coord = 0;
  hb_ot_layout_get_baseline_with_fallback(f->hbfont, HB_OT_LAYOUT_BASELINE_TAG_IDEO_EMBOX_CENTRAL,
                                          HB_DIRECTION_LTR, HB_TAG('h','a','n','i'),
                                          HB_TAG_NONE, &coord);
  return (int)coord;
}

/* FT_Load_Glyph loads into the face's one glyph slot: the lock is held
   until the metrics are read from it. */
int golem_font_glyph_metrics(golem_font *f, uint32_t gid, int32_t *out) {
  LOCK_FT(f);
  if (FT_Load_Glyph(f->face, gid, FT_LOAD_NO_SCALE | FT_LOAD_NO_HINTING)) { UNLOCK_FT(f); return -1; }
  FT_Glyph_Metrics *m = &f->face->glyph->metrics;
  out[0] = (int32_t)m->horiAdvance;
  out[1] = (int32_t)m->vertAdvance;
  out[2] = (int32_t)m->horiBearingX;
  out[3] = (int32_t)(m->horiBearingY - m->height);
  out[4] = (int32_t)(m->horiBearingX + m->width);
  out[5] = (int32_t)m->horiBearingY;
  UNLOCK_FT(f);
  return 0;
}

void golem_font_v_origin(golem_font *f, uint32_t gid, int32_t *x, int32_t *y) {
  hb_position_t ox = 0, oy = 0;
  hb_font_get_glyph_v_origin(f->hbfont, gid, &ox, &oy);
  *x = (int32_t)ox;
  *y = (int32_t)oy;
}

int golem_font_shape(golem_font *f, const char *utf8, int len, const char *script,
                     const char *lang, int vertical, const char *features,
                     uint32_t *out_gids, uint32_t *out_clusters, int32_t *out_pos,
                     int max_glyphs) {
  hb_buffer_t *buf = hb_buffer_create();
  hb_buffer_add_utf8(buf, utf8, len, 0, len);
  hb_buffer_set_direction(buf, vertical ? HB_DIRECTION_TTB : HB_DIRECTION_LTR);
  if (script && *script) hb_buffer_set_script(buf, hb_script_from_string(script, -1));
  if (lang && *lang) hb_buffer_set_language(buf, hb_language_from_string(lang, -1));
  hb_buffer_guess_segment_properties(buf);
  hb_feature_t feats[32];
  unsigned nfeat = 0;
  if (features && *features) {
    const char *p = features;
    while (*p && nfeat < 32) {
      const char *e = strchr(p, ',');
      int n = e ? (int)(e - p) : (int)strlen(p);
      if (hb_feature_from_string(p, n, &feats[nfeat])) nfeat++;
      if (!e) break;
      p = e + 1;
    }
  }
  hb_shape(f->hbfont, buf, feats, nfeat);
  unsigned count = 0;
  hb_glyph_info_t *info = hb_buffer_get_glyph_infos(buf, &count);
  hb_glyph_position_t *pos = hb_buffer_get_glyph_positions(buf, &count);
  if ((int)count > max_glyphs) { hb_buffer_destroy(buf); return -(int)count - 1; }
  for (unsigned i = 0; i < count; i++) {
    out_gids[i] = info[i].codepoint;
    out_clusters[i] = info[i].cluster;
    out_pos[4 * i] = pos[i].x_advance;
    out_pos[4 * i + 1] = pos[i].y_advance;
    out_pos[4 * i + 2] = pos[i].x_offset;
    out_pos[4 * i + 3] = pos[i].y_offset;
  }
  hb_buffer_destroy(buf);
  return (int)count;
}

uint8_t *golem_font_subset(golem_font *f, const uint32_t *gids, int n, size_t *out_len) {
  hb_subset_input_t *input = hb_subset_input_create_or_fail();
  if (!input) return NULL;
  hb_set_t *glyphs = hb_subset_input_glyph_set(input);
  for (int i = 0; i < n; i++) hb_set_add(glyphs, gids[i]);
  hb_subset_input_set_flags(input, HB_SUBSET_FLAGS_RETAIN_GIDS);
  hb_face_t *sub = hb_subset_or_fail(f->hbface, input);
  hb_subset_input_destroy(input);
  if (!sub) return NULL;
  hb_blob_t *blob = hb_face_reference_blob(sub);
  unsigned len = 0;
  const char *data = hb_blob_get_data(blob, &len);
  uint8_t *out = malloc(len ? len : 1);
  if (out) { memcpy(out, data, len); *out_len = len; }
  hb_blob_destroy(blob);
  hb_face_destroy(sub);
  return out;
}

/* The CID of a glyph in a CID-keyed CFF font; the glyph id otherwise. */
uint32_t golem_font_cid(golem_font *f, uint32_t gid) {
  FT_UInt cid = 0;
  FT_Bool is_cid = 0;
  LOCK_FT(f);
  int found = FT_Get_CID_Is_Internally_CID_Keyed(f->face, &is_cid) == 0 && is_cid &&
              FT_Get_CID_From_Glyph_Index(f->face, gid, &cid) == 0;
  UNLOCK_FT(f);
  return found ? cid : gid;
}

/* The ROS of a CID-keyed CFF font (golem-pdf ADR 0006). */
int golem_font_ros(golem_font *f, const char **registry, const char **ordering,
                   int *supplement) {
  FT_Bool is_cid = 0;
  const char *r = NULL, *o = NULL;
  FT_Int s = 0;
  LOCK_FT(f);
  int found = FT_Get_CID_Is_Internally_CID_Keyed(f->face, &is_cid) == 0 && is_cid &&
              FT_Get_CID_Registry_Ordering_Supplement(f->face, &r, &o, &s) == 0 && r && o;
  UNLOCK_FT(f);
  if (!found) return -1;
  *registry = r;
  *ordering = o;
  *supplement = (int)s;
  return 0;
}

char *golem_font_postscript_name(golem_font *f) {
  LOCK_FT(f);
  const char *n = FT_Get_Postscript_Name(f->face);
  UNLOCK_FT(f);
  return (char *)(n ? n : "");
}

void golem_free(void *p) { free(p); }
