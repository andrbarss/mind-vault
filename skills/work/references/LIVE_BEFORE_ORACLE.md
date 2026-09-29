# The default branch as a live "before" — two stacks over one database

Load when a step must prove **"no behaviour change"** for code it moves or extracts (a refactor under
a feature, a shared builder pulled out of an action), or when a "before" capture taken earlier no
longer compares because the answer depends on **today** (prices, validity dates, stock).

## The method

Serve the branch beside the default branch, both against the **same** database:

| Stack | Serves | Role |
| --- | --- | --- |
| the primary stack | the primary checkout, on the default branch | before |
| a worktree stack on its own port and network | the feature branch | after |

Send **one request to both** and compare:

- the answer, without what is generated per call (ids, codes, tokens);
- the **stored row** the request created, without id, codes, timestamps and anything random;
- the link rows and log rows the request wrote;
- then delete what both created and reset the counter.

A before / after pair taken hours apart compares two days; this compares two code versions. It also
survives the fixes that land during review: the comparison is re-run on the final head in minutes.

Conditions, checked before trusting it:

- the primary checkout has **no local edits** in the code under test (`git status` on the source
  directories there), and sits on the commit the branch was cut from or later;
- the two stacks do not share a web-server network alias (requests would alternate between the two
  code versions);
- fixtures changed for a run (a date moved into the future, a setting switched on) are switched by
  the harness and restored in `finally`; the original values are written down **before** the first
  change — a restore typed from memory put a `NULL` where a date had been;
- never flush a shared cache to "be sure": on a dev stack the same store is often the queue. Find
  out whether the value is cached at all (change it, read it).

## What the oracle cannot show

- **What the primary container lacks.** A feature that needs a system package the image does not
  ship fails identically on both sides; "equal" then means "equally broken". See the last section.
- **An intended difference.** A security fix changes an answer on purpose. Record the differing rows
  as intended, with the reason, instead of excluding them from the set.
- **A caller the request set does not reach.** Count the callers of the moved code; say which were
  not exercised.

## Comparing documents

For a rendered document the bytes are a poor key (a creation time inside) and the eye a worse one.

- **PDF:** rasterise each page on the host at a low resolution and hash the page files; compare the
  extracted text as well. Two renders of one record are equal by this measure; the bytes differ only
  across a second boundary. Equal text with different pages is a background or a layout.
- **PNG and similar:** hash the header and the image data, skip text and time chunks.
- Produce both sides **in one run on one stack**: validity computed from today differs across
  midnight, a rasteriser differs across images.
- A client that reports an **incomplete read** is reading a length header that belongs to another
  body. That is a finding, not a harness problem.

Commit a record of each comparison (request, status, content type, size, per-page signature), not
the documents.

## Before writing "not verified": try the throwaway container

"The dev image cannot do X" is a property of the image, not of the code. The container that serves
the worktree is disposable: install the package there, relax the policy there, restart it. Nothing
reaches the repository or the image.

- An image on an archived distribution release fails `apt-get install` on its security source;
  remove that source in the container and install from the base release.
- A library may be present and forbidden by policy (an image library that refuses one format).

Field case: a format conversion marked "not verifiable on the dev stack" was walked this way in ten
minutes. The ten comparisons were equal — and the walk found that the existing reader answered that
format with the **other** format's length and content type for every template that sends its own
headers. The defect was live on the default branch; no test and no review had a reason to look.

Write down what the container was given, so that the deploy check can ask the same of a server.

## Related

- `EXECUTE_OVER_PIN.md` — when a source pin is not enough; § a second environment cloned from the
  first.
- `FALLBACK_HIDES_THE_BRANCH.md` — equal documents do not say which branch drew them.
- `MUTATION_PASS_DISCIPLINE.md` — a comparison must be able to fail.
- `skills/plan/references/PREVIEW_BEFORE_CREATE.md` — the plan this method verifies.
