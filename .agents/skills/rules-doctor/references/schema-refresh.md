# Schema refresh protocol

Follow this only when the snapshot date in SKILL.md is more than 3
months old, or the date cannot be determined.

## Check the date

Run `date` via Bash and compare against the snapshot date.  Within 3
months: stop here, validate against the snapshot tables.

## Fetch

Reuse a schema already fetched this session.  Otherwise fetch with
whatever URL-fetching tool the harness provides:

- pi-rules:
  <https://raw.githubusercontent.com/quanpersie2001/pi-rules/refs/heads/main/README.md>
- Claude Code rules: <https://code.claude.com/docs/en/memory>

Follow the README to other files only if it has no schema table.  Do
not crawl the rest of either repo.

## Parse

Re-derive the key list, types, defaults, and routing conditions from
what the page currently says.  Rendered fetches can flatten a Markdown
table into a `Field / Type / Description` list with no column markers;
the fields still appear in that fixed order per row, so read them
positionally.  If the order looks scrambled or row boundaries are
unclear, treat it as a fetch failure -- a misaligned schema is worse
than a stale one.

## On success

Update SKILL.md itself: replace whatever changed in the schema tables
and set the snapshot date to today.  Only a confidently-parsed fetch
earns the date bump; the bump is what lets the next 3 months of checks
skip fetching.

## On failure

Narrow the check instead of trusting a possibly-stale snapshot: verify
only that `paths` is present and is a string or array of strings, skip
the unknown-key and never-fires checks, and report the reduced
confidence:

```
WARNING: could not refresh the rules schema (reason: <404, network
unavailable, unparseable response, ...>).  Only checked that `paths` is
well-formed; unknown-key and never-fires checks were skipped because
the embedded snapshot may be stale.
```
