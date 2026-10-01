# Working in this repo

## Naming
The project is always written `The Giver`, two words, both capitalised, article included, even mid-sentence: "open it with The Giver". Never `the giver`, `Giver` on its own, or `TheGiver` in prose. Identifiers that can't contain a space use `TheGiver` (the repo, the Swift module, the Linux application ID), `the-giver` (the Linux binary) or `the_giver` (the icon), and those are the only exceptions.

## What goes where
`README.md` is what a user needs to build The Giver, make it the default and find their way around it, nothing more. It does not carry the depth.

`docs/`, when it exists, holds one file per subject, and those files own it. A doc should stand on its own rather than assume the reader came through another one.

Technical detail is welcome in `docs/`, more so than in the README. How the applications for a file are found and where the arrangement is stored belong there.

That is mechanism, not evidence, and the distinction matters. That the picker takes its keys in `sendEvent` is mechanism and can be documented. The debugging that showed `keyDown` never arriving is evidence, and stays out under the rule below.

## Documentation voice
The house style is set by `README.md`. Match it.

**Be short.** Roughly half the length of a first draft. State what The Giver does and, if it is not obvious, why. Then stop.

**Cut the evidence, keep the consequence.** The test is whether it changes what the reader does. Measurements, worked examples and the reasoning that justifies a decision come out. A caveat that would change someone's choice stays in, even when it is unflattering: the Linux frontend cannot rearrange or hide applications yet, and a user choosing between it and Junction needs to know that.

**Name the app as the subject.** "The Giver lists...", "The Giver remembers...". Prefer that to passive voice or an abstract subject.

**Address the reader directly** for anything they do: "choose a file", "drag an application". A reference section is mostly descriptive and will barely use it, which is fine, do not manufacture instructions to satisfy the rule.

**Use a table for any fixed set a reader might look up**: keys, the source layout, supported schemes. Prose gets trimmed; tables do not.

### Mechanics
- No hard wrapping. One long line per paragraph, however wide it runs.
- No blank line between a heading and the text under it.
- Commas where a dash would be tempting. No em-dashes.
- No bold or italics in prose. Emphasis comes from sentence structure.
- Headings are short noun phrases: "Build", "Keys", "Layout".

### Common corrections
Drafts written without this file in mind tend to need the same fixes: they run about twice the necessary length, wrap lines, lean on em-dashes for asides, and explain the reasoning behind a decision where stating the decision would do.

Where a later document contradicts this file, the document is right and this file should be updated.

## Code
The Giver is a clone of Junction: it is made the default application for a file type or for links, and shows a picker of the applications that can really open them.

| Path | What |
| --- | --- |
| `macos/` | SwiftUI frontend, built by `macos/bundle.sh`. There is no Xcode project; do not add one without asking |
| `linux/` | GTK 4 frontend in C, built by Meson |

There is no shared core, on purpose. Finding the applications is one LaunchServices call on macOS and one GIO call on Linux, and everything else is interface. The two frontends are kept alike by hand instead: the same layout, the same keys, the same wording. A feature added to one should be added to the other or listed in the README as missing.

On macOS, `PickerModel` owns what is being opened and the applications offered, and `PickerPanel` owns the window and the keys. Views go through the model rather than calling `NSWorkspace` themselves. The picker is Liquid Glass and nothing else: one glass surface, with plain fills on top of it, never glass on glass.

The Giver quits when its last window closes, so anything asynchronous must finish before the window does.

Test the macOS app by opening something with it, `open -a "build/macos/The Giver.app" <file or URL>`, since a picker only exists in answer to an open request.

Code comments are the place for the reasoning the docs leave out. Explain why something is done a particular way, especially where the obvious approach fails.

## Commits
Commit messages are held to the same measure as the docs: short, plain, and specific about what changed. A subject line in the imperative, then a sentence or two on why, only when the why is not obvious from the diff.

No essays, and no restating the diff as a list of touched files. Reasoning that needs more room than that belongs in a code comment beside the thing it explains, where it stays attached to the code instead of being buried in history.
