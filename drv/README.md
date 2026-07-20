> Vendored from https://github.com/BryceVandegrift/drv for the manjaro-sl
> component build.

# drv

Read the Word of God from your terminal

## Usage

    usage: drv [flags] [reference...]

    Flags:
      -A num  show num verses of context after matching verses
      -B num  show num verses of context before matching verses
      -C      show matching verses in context of the chapter
      -e      highlighting of chapters and verse numbers
              (default when output is a TTY)
      -p      output to less with chapter grouping, spacing, indentation,
              and line wrapping
              (default when output is a TTY)
      -l      list books
      -h      show help

    Reference:
        <Book>
            Individual book
        <Book>:<Chapter>
            Individual chapter of a book
        <Book>:<Chapter>:<Verse>[,<Verse>]...
            Individual verse(s) of a specific chapter of a book
        <Book>:<Chapter>-<Chapter>
            Range of chapters in a book
        <Book>:<Chapter>:<Verse>-<Verse>
            Range of verses in a book chapter
        <Book>:<Chapter>:<Verse>-<Chapter>:<Verse>
            Range of chapters and verses in a book

        /<Search>
            All verses that match a pattern
        <Book>/<Search>
            All verses in a book that match a pattern
        <Book>:<Chapter>/<Search>
            All verses in a chapter of a book that match a pattern

## Build

drv can be built by cloning the repository and then running make:

    git clone https://github.com/BryceVandegrift/drv.git
    cd drv
    make

## License

Public domain

## Rationale

This program was forked from [here](https://github.com/layeh/kjv). Instead of
using the King James translation, I used the Douay-Rheims translation
(specifically the Challoner revision). Despite the popular misconception, the
Douay-Rheims translation is actually the oldest reliable English translation
(*yes*, even older than the King James translation). This translation includes
the Catholic deuterocanonical books:

- Tobit
- Judith
- Baruch
- Sirach
- Wisdom
- 1 Maccabees
- 2 Maccabees
- As well as a few minor additions

I find that the Douay-Rheims translation is more accurate, while also preserving
the correct Canon of the Old Testament. Not only that, but "KJV-onlyism" is
quite dumb.
