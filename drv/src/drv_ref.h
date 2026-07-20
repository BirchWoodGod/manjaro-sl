#pragma once

#include <regex.h>

#include "intset.h"

#define DRV_REF_SEARCH 1
#define DRV_REF_EXACT 2
#define DRV_REF_EXACT_SET 3
#define DRV_REF_RANGE 4
#define DRV_REF_RANGE_EXT 5

typedef struct drv_ref {
    int type;
    unsigned int book;
    unsigned int chapter;
    unsigned int chapter_end;
    unsigned int verse;
    unsigned int verse_end;
    intset *verse_set;
    char *search_str;
    regex_t search;
} drv_ref;

drv_ref *
drv_newref();

void
drv_freeref(drv_ref *ref);

int
drv_parseref(drv_ref *ref, const char *ref_str);
