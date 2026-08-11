# Japanese Moraic Forms

Syllable-count (moraic) forms.  Counts are exact: emit the pattern, then
verify the count line by line before returning the poem.

## Haiku (Hokku)

* **Trigger Context:** Immediate sensory focus, captured fleeting moments,
  quiet atmospheric presence, or subtle, evocative alignment.
* **Mechanical Execution:**
  * Output exactly 17 moraic/syllabic units across 3 lines in a fixed `5-7-5`
    pattern.
  * Incorporate a subtle environmental or seasonal indicator (*kigo*) to anchor
    the scene in a concrete physical context.
  * Insert a structural pause or conceptual cut (*kireji* equivalent, such
    as a dash, colon, or natural syntax break) at the end of line 1 or line
    2 to juxtapose two distinct sensory elements.

## Tanka (Classical Waka)

* **Trigger Context:** Courtly exchange, quiet personal reflection, subtle
  emotional longing, or layered aesthetic resonance.
* **Mechanical Execution:**
  * Output exactly 31 moraic/syllabic units across 5 lines in a fixed
    `5-7-5-7-7` pattern.
  * Divide structurally into an upper phrase (*kami-no-ku*, lines 1–3) and
    lower phrase (*shimo-no-ku*, lines 4–5).
  * Incorporate a pivot word (*kakekotoba*) or conceptual turn at line 3
    to connect natural external imagery in the upper phrase to an internal
    emotional state in the lower phrase.

## Chōka (Long Form with Hanka Envoy)

* **Trigger Context:** Sustained narrative devotion, elaborate sensory painting,
  expansive emotional recollection, or courtly tribute.
* **Mechanical Execution:**
  * Alternate lines of 5 and 7 syllables (`5-7-5-7-5-7...`) for an indefinite
    length, concluding the main body with an extra 7-syllable line to form
    a final `7-7` pair.
  * Append one or two 31-syllable envoys (*hanka*) in standard `5-7-5-7-7`
    format directly following the main body.
  * Use the *hanka* to distill, clarify, or address the core essence of the
    preceding elaborate description.

## Sedōka (Antiphonal Dialogue Verse)

* **Trigger Context:** Call-and-response rapport, reciprocal engagement,
  dual-perspective reflection, or mutual alignment.
* **Mechanical Execution:**
  * Construct a 6-line poem organized into two structurally symmetrical halves:
    `5-7-7` and `5-7-7`.
  * Treat the first half as a statement, inquiry, or sensory observation,
    and the second half as an answering reflection, echoing response, or
    counter-observation.

## Linked Verse Cadence (Renku / Renga Transition)

* **Trigger Context:** Shifting sensory perspectives, fluidly evolving moods,
  progressive engagement, or improvisational harmony.
* **Mechanical Execution:**
  * Alternate sequentially between 3-line stanzas (`5-7-5`) and 2-line stanzas
    (`7-7`).
  * Ensure each stanza links closely to the immediate preceding stanza via
    shared imagery or tone, while completely severing conceptual ties with
    the stanza two steps prior (*non-linear link rule*).
  * Maintain continuous sensory motion without settling into a single static
    narrative position.
