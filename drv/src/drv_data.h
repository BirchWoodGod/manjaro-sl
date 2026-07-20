#pragma once

typedef struct {
    int number;
    char *name;
    char *abbr;
} drv_book;

typedef struct {
    int book;
    int chapter;
    int verse;
    char *text;
} drv_verse;

extern drv_verse drv_verses[];

extern int drv_verses_length;

extern drv_book drv_books[];

extern int drv_books_length;
