# Release notes

Write the next release's notes in `next.md`. Its name has no version, so nothing has to be decided in advance. The release workflow works out the version from the `patch`/`minor`/`major` choice, renames `next.md` to `<version>.md`, and puts a fresh copy of `TEMPLATE.md` in its place.

The workflow refuses to release while `next.md` is still the unedited template, or when `<version>.md` already exists.

The file becomes the body of the GitHub release, under a header that the workflow adds with the Clair version, the build number and the ungoogled-chromium version. `scripts/render-notes.sh` converts it to the HTML fragment embedded in the appcast's `<description>`. Clair shows no Sparkle dialog, so that HTML is only for completeness. The GitHub release page is where people read it, so write for users rather than summarizing commits. A Chromium security update deserves a line too:

```markdown
- New: Something people asked for
- Fixed: Something that was broken
- Security: Updated to Chromium 156.0.8078.60 (ungoogled-chromium 156.0.8078.60-1)
```

Lists, paragraphs, bold, italic, links, tables, task lists, and strikethrough all work. Two things are rejected, because each would reach one destination and not the other:

- **HTML tags**. GitHub renders them, but the appcast conversion drops them.
- **Code blocks**, including a line indented four spaces. The appcast is indented to match, and that indentation would show inside a `<pre>`.

Footnotes are the one GitHub construct left unsupported, and render as literal `[^1]` markers.

Rendering uses [cmark-gfm](https://github.com/github/cmark-gfm), GitHub's own Markdown implementation. To run the script tests locally: `brew install cmark-gfm`.

The `<version>.md` files are the archive of what shipped in each release.

Adapted from Front Row's `.sparkle/notes/README.md`.
