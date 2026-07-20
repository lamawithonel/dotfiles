---
applyAlways: true
---
# Markdown, Code Comment, and Commit Message Style Guide

Use this guide for all writing in all Markdown files, code comments for any
language, and VCS commit messages (e.g., git messages).

## Text wrapping

- Wrap text after the first word extended beyond 72 characters, and do not
  exceed 80 characters.  Wrap before 72 characters if the last word would
  extend beyond 80 characters.
- Exceptions include URLs, links, quoted text where the line length is
  meaningful and important, or where format preservation requires it.

## Markdown syntax rules

- Do not wrap URLs in bold markdown (`**`).  Use plain URLs or `[label](url)`
  format.
- Do not use Markdown forced line breaks (two or more spaces at the end of
  a line.)
- Do not use Unicode symbols that have ASCII equivalents.  Write `->` not
  "→", `>=`/`<=` not "≥"/"≤", `+/-` not "±", `!=` not "≠", and so on.
- Include one blank line between headings, content, and lists
- Prefer reference-style [Markdown links][^markdown-link-styles] with short
  superscript tags.

[^markdown-link-styles]: https://gist.githubusercontent.com/emedinaa/28ed71b450243aba48accd634679f805/raw/fff0e8b872079030aacd64d69f0ef1ebcf2a9bee/Markdown%2520reference%2520links

## Examples

### Correct line spacing / Correct line wrapping / Correct sentence spacing

```Markdown
### Heading 3

Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor
incididunt ut labore et dolore magna aliqua.  Ut enim ad minim veniam, quis
nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.
Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore
eu fugiat nulla pariatur.  Excepteur sint occaecat cupidatat non proident,
sunt in culpa qui officia deserunt mollit anim id est laborum.

- Item 1
- Item 2
- Item 3
```

### Correct line spacing / Correct line wrapping / Incorrect sentence spacing

```Markdown
### Heading 3

Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor
incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis
nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.
Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore
eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident,
sunt in culpa qui officia deserunt mollit anim id est laborum.

- Item 1
- Item 2
- Item 3
```

### Correct line spacing / Incorrect line wrapping / Correct sentence spacing

```Markdown
### Heading 3

Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor
incididunt ut labore et dolore magna aliqua.  Ut enim ad minim veniam, quis
nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.
Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu
fugiat nulla pariatur.  Excepteur sint occaecat cupidatat non proident, sunt in
culpa qui officia deserunt mollit anim id est laborum.

- Item 1
- Item 2
- Item 3
```

### Correct line spacing / Incorrect line wrapping / Incorrect sentence spacing

```Markdown
### Heading 3

Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor
incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis
nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.
Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu
fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in
culpa qui officia deserunt mollit anim id est laborum.

- Item 1
- Item 2
- Item 3
```

### Incorrect line spacing / Correct line wrapping / Correct sentence spacing

```Markdown
### Heading 3
Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor
incididunt ut labore et dolore magna aliqua.  Ut enim ad minim veniam, quis
nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.
Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore
eu fugiat nulla pariatur.  Excepteur sint occaecat cupidatat non proident,
sunt in culpa qui officia deserunt mollit anim id est laborum.
- Item 1
- Item 2
- Item 3
```

### Incorrect line spacing / Correct line wrapping / Incorrect sentence spacing

```Markdown
### Heading 3
Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor
incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis
nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.
Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore
eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident,
sunt in culpa qui officia deserunt mollit anim id est laborum.
- Item 1
- Item 2
- Item 3
```

### Incorrect line spacing / Incorrect line wrapping / Correct sentence spacing

```Markdown
### Heading 3
Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor
incididunt ut labore et dolore magna aliqua.  Ut enim ad minim veniam, quis
nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.
Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu
fugiat nulla pariatur.  Excepteur sint occaecat cupidatat non proident, sunt in
culpa qui officia deserunt mollit anim id est laborum.


- Item 1
- Item 2
- Item 3
```

### Incorrect line spacing / Incorrect line wrapping / Incorrect sentence spacing

```Markdown
### Heading 3


Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor
incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis
nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.
Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu
fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in
culpa qui officia deserunt mollit anim id est laborum.
- Item 1
- Item 2
- Item 3
```
