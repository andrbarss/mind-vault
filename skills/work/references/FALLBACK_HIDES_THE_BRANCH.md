# A silent fallback makes the walk green for the wrong branch

Load when a verification row claims a **branch was exercised** — "drawn with the tenant's own
template", "served from the cache", "sent through the new provider" — and the code under it has a
fallback that answers when the branch's precondition fails.

## The shape

```text
if the record names a template AND the file exists  -> draw with it
else                                                 -> draw with the default
```

The fixture names a template. The walk passes. The report says "every template branch the tenant
has". The file does not exist on that tenant: every one of those rows was drawn by the default
template, and the comparison was equal because **both sides fell back the same way**.

Nothing in the result distinguishes the two. A status, an equality with an oracle, a screenshot that
"looks right" — all are produced by the fallback as well.

## Prove which branch ran

- **Ask what the precondition needs and check that it holds for the fixture**: the file on disk, the
  row in the table, the flag on the tenant. A stored name is not a file.
- **Make the branch observable.** The signature of a document drawn by the branch differs from the
  signature of the fallback's document for the same record. Run the record both ways (precondition
  met / not met) and require the two results to differ. If they cannot differ, the row proves
  nothing about the branch.
- **When the environment has no fixture for the branch, make one reversibly** (point the record at a
  template that exists) and say so; or say the branch was not exercised and name the unit test that
  executes the choice.
- **Count what was really covered.** "16 of 16 equal" with a fixture that applied to 5 of the 8
  records is "16 equal, 10 of them through the branch".

## Word the evidence as what happened

| Written | True |
| --- | --- |
| "walked on a tenant with its own templates" | the tenant has four type templates and one bundle template; the active bundles name templates it has no file for |
| "every template branch" | the branches that have a file; two kinds of template exist on no tenant of the environment |
| "PNG verified" | verified in a container given two things the image lacks |

The documentation reviewer is the one who finds this: give that lens the file tree and the question
"for each claimed branch, does its precondition hold in the environment that was walked?".

## The same trap elsewhere

- a cache read that falls through to the source: equal answers, no hit;
- a feature flag that defaults off in the test tenant;
- a provider chosen by configuration, with the legacy provider as the default;
- a per-template or per-locale override looked up by file name;
- a **silent** file test (`is_file && is_readable`) beside a **loud** one (`file_exists`, then a
  render that throws): when extracting such a choice into one function, keep each branch's own test,
  and give the function a truth table that includes "named but missing".

## Related

- `LIVE_BEFORE_ORACLE.md` — equality with an oracle, and what it cannot show.
- `EXECUTE_OVER_PIN.md` — § doubles and pins that discriminate.
- `skills/wrap/references/IDEA_COMPLETENESS_AUDIT.md` — a criterion called met without evidence.
