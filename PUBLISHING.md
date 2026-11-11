# Publishing a post

**Medium is home.** Every post is published there first and in full. dev.to gets
a complete cross-post with its canonical link pointed back at Medium. LinkedIn
drives traffic. Reddit gets the discussion.

Order matters: the Medium URL has to exist before anything else can point at it.

---

## 0. Before anything goes public

Run this checklist on every post. The technical substance survives
genericisation completely; none of these posts need a real identifier to land.

- [ ] No real schema or database names
- [ ] No real table names that carry the business domain
- [ ] No storage account, container, or bucket names
- [ ] No hostnames (metastore, edge nodes, Thrift URIs)
- [ ] No HDFS nameservice names
- [ ] No filesystem paths that include an org or project name
- [ ] No service account or username
- [ ] No DAG, task, or job IDs
- [ ] No internal distribution lists, Slack channels, or on-call tooling
- [ ] Query IDs and application IDs redacted or replaced
- [ ] Row counts and timings kept — these are the point and are not sensitive

Grep for the obvious ones before committing. The terms to search for are
employer- and project-specific, so they live in `scrub-terms.txt`, which is
gitignored and never published — keep one term per line:

```powershell
$terms = (Get-Content .\scrub-terms.txt | Where-Object { $_ -and $_ -notmatch '^#' }) -join '|'
Get-ChildItem .\posts -Recurse -Include *.md,*.mmd,*.svg,*.txt,*.sql,*.diff |
  Select-String -Pattern "(?i)($terms)"
```

An empty result is what you want. Keep the `-Include` filter: without it the scan
reaches the PNGs under `assets/`, and compressed image bytes will coincidentally
match short terms, burying a real hit in dozens of false ones.

---

## 1. Export every diagram to PNG

Two hard constraints from Medium, both worth knowing because they are not
negotiable:

- The editor accepts **only JPG, JPEG, GIF and PNG**, up to 25 MB. SVG cannot be
  uploaded at all, and Mermaid obviously cannot be rendered.
- An image must be **at least 1192px wide** or Medium hides some of the
  placement options, so you cannot make it full-width.

Both are stated in [Medium's own help page on images][mediumimages].

So PNG export is mandatory and comes first. One command does all of it:

```powershell
powershell -ExecutionPolicy Bypass -File tools\render-diagrams.ps1 -Post 001-work-that-cannot-be-parallelised
powershell -ExecutionPolicy Bypass -File tools\render-diagrams.ps1 -Post 002-managed-vs-external
```

That script drives headless Chrome, so there is **no Node, npm or Puppeteer
install needed**. For every `.mmd` in the post's `diagrams/` folder it writes a
matching `.svg` next to the source and a wide `.png` into `assets/`, and it
rasterises hand-authored SVGs like `where-the-time-went.svg` the same way. Add
`-Only <name>` to redo a single diagram.

Three details in there exist because of bugs worth not re-discovering:

- **White background is forced.** A transparent PNG makes dark diagram text
  invisible to anyone reading Medium in dark mode.
- **Mermaid runs with `htmlLabels: false`.** HTML labels render into
  `<foreignObject>`, which browsers ignore when an SVG is loaded through an
  `<img>` tag — the export would come out blank. The cost is that `<b>` tags in
  node labels do nothing, so do not use them.
- **Chrome's stdout is decoded as UTF-8 explicitly.** Without that, PowerShell
  uses the console codepage and every em dash and middot in a diagram turns to
  mojibake.

Commit the PNGs. They are the published artifact and you will want them again for
LinkedIn.

[mediumimages]: https://help.medium.com/hc/en-us/articles/215679797-Using-images

---

## 2. Medium — the canonical home

### AI disclosure — decide this before you draft

Medium's [AI content policy][mediumai] requires that any story incorporating AI
assistance be labelled as such **within the first two paragraphs**. Undisclosed
AI-assisted or AI-generated text is restricted to **Network Only** distribution.

What that restriction does and does not cost is worth being precise about.
Network Only removes the story from Medium's internal feeds and digest emails.
It does **not** affect Google indexing, direct links, or readers arriving from
LinkedIn or X — Medium's [distribution guidelines][mediumdist] say so explicitly.
So if traffic comes from social and search, the real losses are Boost
eligibility and any publication that bans AI content.

Disclosure is **not** required for AI used only as an outliner, grammar or
spelling checker, or fact-checker. The line is **who wrote the sentences**. If
you produce the words — even as a rough voice-memo transcript — and AI only
tightens grammar and ordering, no disclosure is needed and strict publications
stay open to you.

For post 001 the disclosure sits directly after the opening paragraph:

> *Disclosure: I used an AI assistant to help draft and structure this write-up.
> The investigation, the production logs and every number in it are my own.*

For later posts, prefer writing the prose yourself. Talking into a voice recorder
for ten minutes produces more words than a post of this length needs, and keeps
Boost and the publications available.

[mediumai]: https://help.medium.com/hc/en-us/articles/22576852947223-Artificial-Intelligence-AI-content-policy
[mediumdist]: https://help.medium.com/hc/en-us/articles/360006362473-Medium-s-Distribution-Guidelines-How-curators-review-stories-for-Boost-General-and-Network-Distribution

### Creating the draft

1. Go to <https://medium.com/new>
2. Paste the body of `index.md` — **not** the YAML front matter.
3. **Set the three title elements.** Medium infers these from position plus
   formatting, which is unintuitive enough that most people never set them. In
   the editor, select a line and use the two `T` buttons — large `T` is a
   header, small `T` is a subheader:
   - **Title** — the first line of the story, formatted with the large `T`.
   - **Subtitle** — the line directly *below* the title, formatted with the
     small `T`. Always set one. It shows up in search results and link previews,
     and a story without it looks unfinished.
   - **Kicker** — optional single word *above* the title, small `T`. Use it as a
     category signpost. `HIVE` or `PERFORMANCE` works for this material.
4. **Add a featured image.** The first image in the story becomes the one Medium
   uses in the feed and in every social share card, including the LinkedIn and
   X previews later. Use `where-the-time-went.png` — it carries the whole
   argument by itself. Then click it and:
   - set **alt text** (accessibility, and it is indexed),
   - write a **caption** — captions get read more than body text,
   - set the **focal point** with alt-click so Medium crops the preview
     sensibly rather than through the middle of a bar.
5. **Code blocks.** This is the one real weakness of Medium as a home for
   technical writing, so handle it deliberately:
   - Short snippets (1–3 lines): Medium's inline code block is fine. Type three
     backticks and Enter.
   - Anything longer — the SQL, the Task Execution Summary, the progress table,
     the config diff — put in a [GitHub Gist](https://gist.github.com) and paste
     the Gist URL on its own empty line. Medium embeds it with real syntax
     highlighting and horizontal scrolling. Name each Gist file with the right
     extension (`.sql`, `.diff`, `.txt`) so highlighting picks the right
     language. The filename is visible in the embed, so it doubles as a caption.

   Post 001's three blocks live in one multi-file Gist under the
   `GangothriGadige` account. Medium embeds a single file from a multi-file Gist
   only via a `?file=` **query parameter**; the `#file-` anchor that GitHub's own
   UI links to does not work. The URLs to paste:

   ```
   https://gist.github.com/GangothriGadige/efd392095bfdf01b75e4532322db6932?file=the-query.sql
   https://gist.github.com/GangothriGadige/efd392095bfdf01b75e4532322db6932?file=task-execution-summary.txt
   https://gist.github.com/GangothriGadige/efd392095bfdf01b75e4532322db6932?file=progress-at-99-percent.txt
   ```

   Build the full URL somewhere else and paste it complete, as plain text, on an
   empty line. Medium resolves an embed once, on paste, and will not re-resolve
   if you add `?file=` afterwards — you get all three files stacked in one embed
   and cannot edit your way out. Delete the block and redo it instead.
6. Upload the remaining PNGs where the ` ```mermaid ` blocks sit in the markdown,
   and delete those blocks — they are for GitHub and dev.to, not here. Give each
   image alt text and a caption too.
7. Add up to five tags. Medium allows five, dev.to only four, so the two lists
   differ slightly. For this post on Medium: `data engineering`, `hive`,
   `optimization`, `performance`, `big data`
8. Publish

**Alternative to pasting: the import tool.** <https://medium.com/p/import> takes
a public URL and converts the page into a Medium draft, and it sets the canonical
link back to the source automatically. That is useful once posts live somewhere
public, but it is the wrong way round while Medium is the canonical home — the
import would credit GitHub instead. Paste manually for now.

**Reach.** Submitting to a publication is what gets a post past your own
followers. Relevant ones here: *Data Engineer Things*, *Towards Data Science*,
*Dev Genius*, *Towards Dev*. All require writer access first, which is a separate
application about you rather than about any one post — so apply early and
unconditionally.

*Data Engineer Things* is the best fit for this material: it is in Medium's Boost
Nomination Pilot Program, so its editors can nominate a story for a Boost. Apply
via the form linked from [Write for Data Engineer Things][detwrite]. Turnaround
is about a week. Note their rule that AI-generated content is not accepted, which
is stricter than Medium's own disclosure-based policy.

**Submit the published story, not the draft.** This ordering matters. Per
[Medium's help pages][mediumsubmit], submitting a *draft* to a publication locks
it — you cannot publish it yourself until an editor approves, which can take a
week. Submitting an *already-published* story instead means:

- it goes live on your profile on your schedule,
- editors review it and can accept it into the publication afterwards,
- a rejection costs nothing, because the post is already up and stays up.

Some publications filter their inbox to unpublished drafts only, in which case
the option simply will not appear. No harm in checking.

[detwrite]: https://blog.dataengineerthings.org/write-for-data-engineer-things-32dc9294c5db
[mediumsubmit]: https://help.medium.com/hc/en-us/articles/213904978-How-to-submit-a-story-to-a-publication

**Copy the published URL.** Everything below needs it.

---

## 3. dev.to — the cross-post

dev.to is the better technical renderer, so this copy is worth having even though
it is not the canonical one. It renders ` ```mermaid ` blocks natively, so you can
publish the markdown as-is without the PNG substitution.

1. Open `index.md` and fill in the front matter:

   ```yaml
   canonical_url: https://medium.com/@you/your-post-slug
   ```

2. Sign in at <https://dev.to> → **Create Post**
3. Switch the editor to **Markdown** via the settings gear if it is not already
4. Paste the whole file, front matter included. dev.to reads `title`, `tags`,
   `description`, `canonical_url` and `published` directly from it
5. Upload `where-the-time-went.svg` with the toolbar image button and replace the
   `./diagrams/...` path with the URL dev.to returns. Leave the ` ```mermaid `
   blocks exactly as they are
6. Save with `published: false`, check the preview — especially that both Mermaid
   diagrams rendered — then set `published: true` and save again

Four tags maximum, lowercase, no spaces — this is why `bigdata` is dropped here
but kept on Medium: `hive`, `dataengineering`, `performance`, `optimization`.

With `canonical_url` set, dev.to displays an "Originally published at medium.com"
line and tells search engines to credit the Medium URL. That consolidates your
search ranking onto one page instead of splitting it between two identical
articles.

---

## 4. LinkedIn — traffic, not hosting

Do **not** paste the whole post here. Two formats work:

### A native post (default choice)

- 150–250 words. State the finding and the number, not the methodology.
- Put the Medium link **in the first comment**, not the post body. LinkedIn
  reduces the reach of posts containing external links.
- One image — use `where-the-time-went.png`. It carries the whole argument on its
  own.
- Three to five hashtags: `#dataengineering #hive #bigdata #performance`

Opening line draft for this post:

> A nightly Hive job hit 99% in three and a half minutes, then sat at 99% for the
> next two and a half hours.
>
> The real work was done in those first few minutes: a scan of 510 million rows,
> five dimension joins and a GROUP BY. The remaining 98% of the runtime was a
> single task computing column statistics that nothing in the pipeline would
> ever read. One `SET` removed it and the job finished in 16 minutes.

Do not write "the real work took 185 seconds". 185 s is the *sum* of the other
thirteen vertices' `DURATION` values, and durations overlap in a DAG, so it is
not an elapsed time. The measured numbers are 206 s to first reach 99% and
8,973 s held there.
>
> More containers would not have helped. Some work cannot be parallelised, and
> that work sets the floor on your runtime.

### A document carousel (higher engagement, more effort)

Export 6–10 slides to a single PDF and upload it as a document post. These
perform unusually well for technical content and work around LinkedIn's inability
to format code. Good slide order: the symptom, the summary table, the three
tells, the mechanism, the one-line fix, the result, when not to do it.

---

## 4b. X / Twitter — worth doing, not worth optimising

Be clear-eyed about this one. For a data engineer building a professional
footprint, **LinkedIn is where the career value is** — that is where recruiters,
hiring managers and your peers actually are, and it is where the data
engineering conversation has largely moved. X has a thinner data-engineering
community than it used to, and building an audience there from zero is slow.

But the marginal cost once the post exists is about five minutes, and unlike
LinkedIn, posts on X stay findable and linkable, so it is worth doing as an
afterthought rather than a strategy.

- Post a **thread**, not a single tweet with a link. A bare link gets suppressed
  the same way it does on LinkedIn.
- Three or four tweets: the hook, the counterintuitive number, the fix, then the
  link in the last one.
- Attach `where-the-time-went.png` to the first tweet. Images carry threads.
- Two hashtags at most. `#dataengineering` and `#hive`.

Tweet one should be the hook alone, with the image:

> A Hive query hit 99% in 3.5 minutes.
>
> Then sat at 99% for 2.5 hours.
>
> 98% of the runtime was one task doing work nobody asked for. 🧵

**Do not** cross-post the same text to LinkedIn and X on the same day. The
audiences overlap enough to notice, and the formats reward different things.

---

## 5. r/dataengineering — the practitioners

- Post the **substance in the body as a text post**. A bare link reads as
  self-promotion and gets downvoted or removed.
- Paste the Task Execution Summary and the fix inline. Link the full post at the
  bottom as "longer write-up here" if you want.
- Read the subreddit's self-promotion rules first; they change.
- Expect to be challenged on specifics. That is the value — it is the best
  technical review you will get for free.

---

## 6. Stack Overflow — for the narrow ones

Not every post, but for sharply specific errors it is the highest-leverage place
and the content is permanent. Find the existing question about the error and write
an answer explaining the mechanism rather than just the workaround. People will
land on it for years.

Applies to planned post 3 (the `OVERWRITE` + `UNION ALL` lock failure) and post 8
(Spark's `DELETE` on a non-Delta table).

---

## 7. After publishing

- [ ] `canonical_url` in the front matter points at the Medium URL, and committed
- [ ] `published: true` in the front matter, and committed
- [ ] Live URLs recorded in `README.md`
- [ ] PNGs committed under `assets/`
- [ ] Status updated in the backlog canvas

### Post 001 — sync log

| Item | Status |
|------|--------|
| `published: true` + `published_at` + `publication` in `posts/001-.../index.md` | Done (2026-11-10) |
| `canonical_url` → Medium | Done |
| `README.md` table + backlog | Done |
| `det_url` in front matter (publication URL on `blog.dataengineerthings.org`) | **Todo** — paste from browser when on the live DET page |
| dev.to cross-post (`published: true`, same `canonical_url`) | Not done |
| LinkedIn / X / Reddit (optional) | Not tracked here |

---

## Front matter reference

```yaml
---
title: "My Hive query sat at 99% for two and a half hours"
published: false
description: "One sentence. Shows up in search results and link previews."
tags: [hive, dataengineering, performance, optimization]
canonical_url:  # the Medium URL, filled in after step 2
---
```

`tags` must be four or fewer, lowercase, no spaces or punctuation. This front
matter is read by dev.to; Medium ignores it, which is why you paste the body
only.
