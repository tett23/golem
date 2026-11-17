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
#include FT_DRIVER_H
#include FT_FONT_FORMATS_H
#include FT_MODULE_H
#include FT_MULTIPLE_MASTERS_H

struct golem_font {
  uint8_t *bytes;
  size_t len;
  /* the library of the font, with its own memory (Golem ADR 0390) */
  FT_Library lib;
  struct FT_MemoryRec_ *memory;
  FT_Face face;
  /* the metrics of the glyphs of a font of the CFF driver, each read once
     from a face opened for the glyph (Golem ADR 0390): NULL for another
     font; 0 not read yet, 1 read, -1 not readable */
  signed char *read;
  int32_t *metrics;
  int num_glyphs;
  /* held while the face is used; the HarfBuzz objects need no lock */
  pthread_mutex_t ft_lock;
  hb_blob_t *blob;
  hb_face_t *hbface;
  hb_font_t *hbfont;
  /* the coordinates of the axes, 16.16 in the order of fvar, that shaping,
     the metrics and the subset are given (Golem ADR 0358); none for a font
     that is not variable */
  int ncoords;
  uint32_t *tags;
  int32_t *coords;
};

static void *ft_alloc(FT_Memory memory, long size) { (void)memory; return malloc((size_t)size); }
static void ft_free(FT_Memory memory, void *block) { (void)memory; free(block); }
static void *ft_realloc(FT_Memory memory, long cur_size, long new_size, void *block) {
  (void)memory;
  (void)cur_size;
  return realloc(block, (size_t)new_size);
}

/* The library of a font, made without reading the environment (Golem ADR
   0390): FT_New_Library with a memory of malloc, realloc and free, and the
   drivers of golem_ftmodule.h. The FREETYPE_PROPERTIES of the environment
   is read only by the default initialisation, which Golem does not call. The
   random seed of the cff driver is 0 before any face is opened, so that a
   subfont starts its random state from initialRandomSeed of its Private
   DICT (987654321 when that is 0) and the driver seed never moves: every
   face opened in the library starts from the same state. */
static int open_library(golem_font *f) {
  f->memory = malloc(sizeof *f->memory);
  if (!f->memory) return -1;
  f->memory->user = NULL;
  f->memory->alloc = ft_alloc;
  f->memory->free = ft_free;
  f->memory->realloc = ft_realloc;
  if (FT_New_Library(f->memory, &f->lib)) { free(f->memory); return -1; }
  FT_Add_Default_Modules(f->lib);
  FT_Int32 seed = 0;
  if (FT_Property_Set(f->lib, "cff", "random-seed", &seed)) {
    FT_Done_Library(f->lib);
    free(f->memory);
    return -1;
  }
  return 0;
}

static void close_library(golem_font *f) {
  FT_Done_Library(f->lib);
  free(f->memory);
}

golem_font *golem_font_open(const uint8_t *data, size_t len) {
  golem_font *f = calloc(1, sizeof *f);
  if (!f) return NULL;
  f->bytes = malloc(len ? len : 1);
  if (!f->bytes) { free(f); return NULL; }
  memcpy(f->bytes, data, len);
  f->len = len;
  if (open_library(f)) { free(f->bytes); free(f); return NULL; }
  if (FT_New_Memory_Face(f->lib, f->bytes, (FT_Long)len, 0, &f->face)) {
    close_library(f); free(f->bytes); free(f); return NULL;
  }
  /* the fonts of the CFF driver: CFF in sfnt, CFF2 and bare CFF (Golem ADR 0390) */
  const char *format = FT_Get_Font_Format(f->face);
  f->num_glyphs = f->face->num_glyphs > 0 ? (int)f->face->num_glyphs : 0;
  if (format && strcmp(format, "CFF") == 0 && f->num_glyphs > 0) {
    f->read = calloc((size_t)f->num_glyphs, 1);
    f->metrics = malloc(sizeof(int32_t) * 6 * (size_t)f->num_glyphs);
    if (!f->read || !f->metrics) {
      free(f->read); free(f->metrics);
      FT_Done_Face(f->face); close_library(f); free(f->bytes); free(f); return NULL;
    }
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
  close_library(f);
  pthread_mutex_destroy(&f->ft_lock);
  free(f->read);
  free(f->metrics);
  free(f->tags);
  free(f->coords);
  free(f->bytes);
  free(f);
}


int golem_font_upem(golem_font *f) { return (int)hb_face_get_upem(f->hbface); }
#define LOCK_FT(f) pthread_mutex_lock(&(f)->ft_lock)
#define UNLOCK_FT(f) pthread_mutex_unlock(&(f)->ft_lock)

/* Sets the coordinates of the font on a face of FreeType (Golem ADR 0358). */
static int set_face_coords(golem_font *f, FT_Face face) {
  FT_Fixed fixed[64];
  if (f->ncoords > 64) return -1;
  for (int i = 0; i < f->ncoords; i++) fixed[i] = (FT_Fixed)f->coords[i];
  return FT_Set_Var_Design_Coordinates(face, (FT_UInt)f->ncoords, fixed) == 0 ? 0 : -1;
}

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

int golem_font_is_cff2(golem_font *f) {
  hb_blob_t *b = hb_face_reference_table(f->hbface, HB_TAG('C','F','F','2'));
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

/* The metrics of the glyph in a face: 0 on success. */
static int load_metrics(FT_Face face, uint32_t gid, int32_t *out) {
  if (FT_Load_Glyph(face, gid, FT_LOAD_NO_SCALE | FT_LOAD_NO_HINTING)) return -1;
  FT_Glyph_Metrics *m = &face->glyph->metrics;
  out[0] = (int32_t)m->horiAdvance;
  out[1] = (int32_t)m->vertAdvance;
  out[2] = (int32_t)m->horiBearingX;
  out[3] = (int32_t)(m->horiBearingY - m->height);
  out[4] = (int32_t)(m->horiBearingX + m->width);
  out[5] = (int32_t)m->horiBearingY;
  return 0;
}

/* FT_Load_Glyph loads into the face's one glyph slot: the lock is held
   until the metrics are read from it. The random state of the cff driver
   moves with each random a CharString runs and is never set back, so a
   glyph of a font of the CFF driver is read from a face opened for it,
   whose state is that of a face just opened, and once (Golem ADR 0390):
   its metrics depend on the bytes of the font and the glyph only. */
int golem_font_glyph_metrics(golem_font *f, uint32_t gid, int32_t *out) {
  LOCK_FT(f);
  int r;
  if (!f->read) {
    r = load_metrics(f->face, gid, out);
  } else if (gid >= (uint32_t)f->num_glyphs) {
    r = -1;
  } else {
    if (f->read[gid] == 0) {
      FT_Face face = NULL;
      int ok = FT_New_Memory_Face(f->lib, f->bytes, (FT_Long)f->len, 0, &face) == 0;
      /* at the coordinates of the font, as its own face (Golem ADR 0358) */
      if (ok && f->ncoords > 0) ok = set_face_coords(f, face) == 0;
      if (ok) ok = load_metrics(face, gid, f->metrics + 6 * (size_t)gid) == 0;
      if (face) FT_Done_Face(face);
      f->read[gid] = ok ? 1 : -1;
    }
    r = f->read[gid] == 1 ? 0 : -1;
    if (r == 0) memcpy(out, f->metrics + 6 * (size_t)gid, sizeof(int32_t) * 6);
  }
  UNLOCK_FT(f);
  return r;
}

void golem_font_v_origin(golem_font *f, uint32_t gid, int32_t *x, int32_t *y) {
  hb_position_t ox = 0, oy = 0;
  hb_font_get_glyph_v_origin(f->hbfont, gid, &ox, &oy);
  *x = (int32_t)ox;
  *y = (int32_t)oy;
}

/* Every feature given goes to HarfBuzz, however many (docs/adr/0268):
   room for nfeatures of them is taken. */
int golem_font_shape(golem_font *f, const char *utf8, int len, const char *script,
                     const char *lang, int vertical, const char *features, int nfeatures,
                     uint32_t *out_gids, uint32_t *out_clusters, int32_t *out_pos,
                     int max_glyphs) {
  hb_feature_t *feats = NULL;
  unsigned nfeat = 0;
  if (features && *features && nfeatures > 0) {
    feats = malloc(sizeof(hb_feature_t) * (size_t)nfeatures);
    if (!feats) return -1;
    const char *p = features;
    while (*p && nfeat < (unsigned)nfeatures) {
      const char *e = strchr(p, ',');
      int n = e ? (int)(e - p) : (int)strlen(p);
      if (hb_feature_from_string(p, n, &feats[nfeat])) nfeat++;
      if (!e) break;
      p = e + 1;
    }
  }
  hb_buffer_t *buf = hb_buffer_create();
  hb_buffer_add_utf8(buf, utf8, len, 0, len);
  hb_buffer_set_direction(buf, vertical ? HB_DIRECTION_TTB : HB_DIRECTION_LTR);
  if (script && *script) hb_buffer_set_script(buf, hb_script_from_string(script, -1));
  if (lang && *lang) hb_buffer_set_language(buf, hb_language_from_string(lang, -1));
  hb_buffer_guess_segment_properties(buf);
  hb_shape(f->hbfont, buf, feats, nfeat);
  free(feats);
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

/* The tags of the FeatureList of GSUB and then of GPOS, of every script
   and language system, with repeats (docs/adr/0268): the first max of them
   are written to out; the number of all of them is returned. */
int golem_font_feature_tags(golem_font *f, uint32_t *out, int max) {
  hb_tag_t tables[2] = {HB_OT_TAG_GSUB, HB_OT_TAG_GPOS};
  int total = 0;
  for (int i = 0; i < 2; i++) {
    unsigned n = hb_ot_layout_table_get_feature_tags(f->hbface, tables[i], 0, NULL, NULL);
    for (unsigned k = 0; k < n; k++, total++) {
      hb_tag_t got = HB_TAG_NONE;
      unsigned one = 1;
      hb_ot_layout_table_get_feature_tags(f->hbface, tables[i], k, &one, &got);
      if (total < max) out[total] = (uint32_t)got;
    }
  }
  return total;
}

/* A coordinate of 16.16 as a float, as HarfBuzz reads the values of fvar:
   the integer as a float, divided by 65536 (Golem ADR 0358). */
static float coord_float(int32_t c) { return (float)c / 65536.f; }

/* Every axis of the subset is fixed at the coordinates of the font, so that
   the subset keeps no variation data (Golem ADR 0358). */
static void pin_axes(golem_font *f, hb_subset_input_t *input) {
  for (int i = 0; i < f->ncoords; i++)
    hb_subset_input_pin_axis_location(input, f->hbface, f->tags[i], coord_float(f->coords[i]));
}

/* The axes of fvar, 4 values for each (the tag, the minimum, the default
   and the maximum in 16.16): the first max of them to out; returns the
   number of axes, 0 for a font that is not variable (Golem ADR 0358). */
int golem_font_axes(golem_font *f, int32_t *out, int max) {
  FT_MM_Var *mm = NULL;
  LOCK_FT(f);
  int n = 0;
  if (FT_HAS_MULTIPLE_MASTERS(f->face) && FT_Get_MM_Var(f->face, &mm) == 0) {
    n = (int)mm->num_axis;
    for (int i = 0; i < n && i < max; i++) {
      out[4 * i] = (int32_t)(uint32_t)mm->axis[i].tag;
      out[4 * i + 1] = (int32_t)mm->axis[i].minimum;
      out[4 * i + 2] = (int32_t)mm->axis[i].def;
      out[4 * i + 3] = (int32_t)mm->axis[i].maximum;
    }
    FT_Done_MM_Var(f->lib, mm);
  }
  UNLOCK_FT(f);
  return n;
}

/* The named instances of fvar, 1 + the number of axes values for each (the
   name ID of the subfamily name, then the coordinates in 16.16): the first
   max values to out; returns the number of instances (Golem ADR 0358). */
int golem_font_instances(golem_font *f, int32_t *out, int max) {
  FT_MM_Var *mm = NULL;
  LOCK_FT(f);
  int n = 0;
  if (FT_HAS_MULTIPLE_MASTERS(f->face) && FT_Get_MM_Var(f->face, &mm) == 0) {
    n = (int)mm->num_namedstyles;
    int per = 1 + (int)mm->num_axis, k = 0;
    for (int i = 0; i < n; i++)
      for (int j = 0; j < per; j++, k++)
        if (k < max) out[k] = j == 0 ? (int32_t)mm->namedstyle[i].strid : (int32_t)mm->namedstyle[i].coords[j - 1];
    FT_Done_MM_Var(f->lib, mm);
  }
  UNLOCK_FT(f);
  return n;
}

/* The English name of a name ID in UTF-8, as HarfBuzz chooses it: the first
   cap - 1 bytes and a NUL to buf; returns the length of the whole name. */
int golem_font_name(golem_font *f, unsigned id, char *buf, int cap) {
  unsigned size = (unsigned)cap;
  return (int)hb_ot_name_get_utf8(f->hbface, id, hb_language_from_string("en", -1), &size, buf);
}

/* Sets the coordinates of every axis, in the order of fvar (Golem ADR
   0358): HarfBuzz shapes with them, FreeType measures with them, and the
   subset is fixed at them. Called once, before the font is used. */
int golem_font_set_coords(golem_font *f, const int32_t *coords, int n) {
  if (n <= 0) return 0;
  int32_t axes[4 * 64];
  int naxes = golem_font_axes(f, axes, 64);
  if (naxes != n || n > 64) return -1;
  f->tags = malloc(sizeof(uint32_t) * (size_t)n);
  f->coords = malloc(sizeof(int32_t) * (size_t)n);
  hb_variation_t *vars = malloc(sizeof(hb_variation_t) * (size_t)n);
  if (!f->tags || !f->coords || !vars) { free(vars); return -1; }
  for (int i = 0; i < n; i++) {
    f->tags[i] = (uint32_t)axes[4 * i];
    f->coords[i] = coords[i];
    vars[i].tag = f->tags[i];
    vars[i].value = coord_float(coords[i]);
  }
  f->ncoords = n;
  LOCK_FT(f);
  int r = set_face_coords(f, f->face);
  UNLOCK_FT(f);
  hb_font_set_variations(f->hbfont, vars, (unsigned)n);
  free(vars);
  return r;
}

/* The coordinates as each user holds them, as floats in the order of fvar
   (Golem ADR 0358, I1): use 0 is the HarfBuzz font that shapes, 1 the
   FreeType face that measures, 2 the input of the subset. The first max to
   out; returns how many the user holds. */
int golem_font_coords_for(golem_font *f, int use, float *out, int max) {
  int n = 0;
  if (use == 0) {
    unsigned len = 0;
    const float *c = hb_font_get_var_coords_design(f->hbfont, &len);
    n = (int)len;
    for (int i = 0; i < n && i < max; i++) out[i] = c[i];
  } else if (use == 1) {
    if (f->ncoords == 0) return 0;
    FT_Fixed fixed[64];
    LOCK_FT(f);
    int ok = f->ncoords <= 64 && FT_Get_Var_Design_Coordinates(f->face, (FT_UInt)f->ncoords, fixed) == 0;
    UNLOCK_FT(f);
    if (!ok) return -1;
    n = f->ncoords;
    for (int i = 0; i < n && i < max; i++) out[i] = coord_float((int32_t)fixed[i]);
  } else {
    hb_subset_input_t *input = hb_subset_input_create_or_fail();
    if (!input) return -1;
    pin_axes(f, input);
    for (int i = 0; i < f->ncoords; i++) {
      float lo = 0, hi = 0, def = 0;
      if (!hb_subset_input_get_axis_range(input, f->tags[i], &lo, &hi, &def)) { hb_subset_input_destroy(input); return -1; }
      if (i < max) out[i] = def;
    }
    n = f->ncoords;
    hb_subset_input_destroy(input);
  }
  return n;
}

uint8_t *golem_font_subset(golem_font *f, const uint32_t *gids, int n, size_t *out_len) {
  hb_subset_input_t *input = hb_subset_input_create_or_fail();
  if (!input) return NULL;
  pin_axes(f, input);
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

/* Whether the font is a CID-keyed CFF font, whose glyphs have CIDs
   (docs/adr ADR 0034: Golem reads them all when it opens the font). */
int golem_font_is_cid_keyed(golem_font *f) {
  FT_Bool is_cid = 0;
  LOCK_FT(f);
  int r = FT_Get_CID_Is_Internally_CID_Keyed(f->face, &is_cid) == 0 && is_cid;
  UNLOCK_FT(f);
  return r;
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

void golem_font_free(void *p) { free(p); }
