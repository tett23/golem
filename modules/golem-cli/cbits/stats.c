#include <stddef.h>
#include <stdint.h>
#include "libgrapheme/grapheme.h"

static int letter_or_number(uint_least32_t ch) {
    static const uint32_t ranges[][2] = {
#include "letter-number.h"
    };
    size_t low = 0, high = sizeof ranges / sizeof ranges[0];
    while (low < high) {
        size_t mid = low + (high - low) / 2;
        if (ch < ranges[mid][0]) high = mid;
        else if (ch > ranges[mid][1]) low = mid + 1;
        else return 1;
    }
    return 0;
}

size_t golem_stats_words(const char *text, size_t len) {
    size_t words = 0;
    while (len) {
        size_t span = grapheme_next_word_break_utf8(text, len);
        for (size_t i = 0; i < span;) {
            uint_least32_t cp;
            i += grapheme_decode_utf8(text + i, span - i, &cp);
            if (letter_or_number(cp)) { ++words; break; }
        }
        text += span;
        len -= span;
    }
    return words;
}

size_t golem_stats_characters(const char *text, size_t len) {
    size_t count = 0;
    while (len) {
        size_t span = grapheme_next_character_break_utf8(text, len);
        text += span;
        len -= span;
        ++count;
    }
    return count;
}
