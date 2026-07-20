#pragma once

#include "drv_config.h"
#include "drv_ref.h"

typedef struct {
    int start;
    int end;
} drv_range;

typedef struct {
    int current;
    int next_match;
    drv_range matches[2];
} drv_next_data;

int
drv_next_verse(const drv_ref *ref, const drv_config *config, drv_next_data *next);
