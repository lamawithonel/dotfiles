---
name: english-writing-style-guide
description: |
  The user's authoritative writing style guide.  Apply these rules when writing
  any English prose, including, but not limited to, code comments, commit
  messages, log messages, web pages, Markdown / Commonmark files and snippets,
  presentations, reports, emails, and business communications.
user-invocable: false
---
# English Writing Style Guide

## Reference Guides

- For all technical writing, including, but not limited to, documentation,
  READMEs, code comments, VSC commit messages, log messages, and technical
  presentations, use ASD-STE100 Simplified Technical English (STE).
- For a all non-technical written prose or copy, follow the Chicago Manual
  of Style.
- The reference guides not withstanding, always follow rules in this file.

## Text wrapping

- Wrap text after the first word extended beyond 72 characters, and do not
  exceed 80 characters.  Wrap before 72 characters if the last word would
  extend beyond 80 characters.
- Exceptions include URLs, links, quoted text where the line length is truly
  meaningful and important, or where format preservation requires it.

## Punctuation and spacing

- Separate sentences with two spaces.
- Close every dash tight against the word before it, then put exactly one
  space after it: `finished-- and continued`.  Never leave a space in front
  of an em-dash used in written prose or copy.
- Use the serial (Oxford) comma before the final conjunction of every list
  of three or more items, whether the list is joined by "and" or by "or".
- Include one blank line between headings, content, and lists.

## Abbreviations and acronyms

- Spell out every acronym or initialism on first use in a file or
  document, with the short form in parentheses immediately after,
  e.g. `representational state transfer (REST)`.  "First use" means
  the first occurrence reading top to bottom in that file, even when
  the file is one fragment of a larger website or documentation
  set-- each file stands on its own.  After that, the short form
  alone is fine: the Microsoft Writing Style Guide states, "On
  subsequent mentions in the same article, page, or screen, you can
  use the acronym without spelling it out."[^acronyms-first-use]

[^acronyms-first-use]: https://learn.microsoft.com/en-us/style-guide/acronyms

## Markdown syntax rules

- Obey the markdownlint style rules for all Markdown / Commonmark files and
  snippets, including code comments and commit messages written in a Markdown
  style.
- The markdownlint rules notwithstanding, follow every rule in this file.
- Prefer reference-style [Markdown links][^markdown-link-styles] with short
  superscript tags.  Treat this as the default for every link you write: put
  the definition at the bottom and cite its tag inline.
- Do not wrap URLs in bold markdown (`**`).  Use plain URLs or `[label](url)`
  format.
- Do not use Markdown forced line breaks (two or more spaces at the end of
  a line.)
- Do not use Unicode symbols that have ASCII equivalents.  Write `->` not
  `→`, `>=`/`<=` not `≥`/`≤`, `+/-` not `±`, `!=` not `≠`, and so on.

[^markdown-link-styles]: https://gist.githubusercontent.com/emedinaa/28ed71b450243aba48accd634679f805/raw/fff0e8b872079030aacd64d69f0ef1ebcf2a9bee/Markdown%2520reference%2520links

## Example

```Markdown
### Heading 3

A write-through cache commits every update to the backing store before
acknowledging the caller-- it trades write latency for a guarantee that a
crash never loses confirmed data, unlike a cache that only serves, expires,
or purges what it was told to.  Readers therefore never observe a value the
store itself does not yet hold.

- Item 1
- Item 2
- Item 3
```
