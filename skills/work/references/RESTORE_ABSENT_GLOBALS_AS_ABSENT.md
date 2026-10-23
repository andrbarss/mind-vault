# Restore an absent global as absent — a registered `null` is not "unset"

Load when a suite is green in file order but one test errors under random order. The error should
come from a test that checks whether a process-wide key **exists**: a registry entry, a service
container binding, an environment variable, a superglobal or a static property. The usual
symptom is a path built from an empty value (`/log/<name>_.log`, `//cache/…`) or a "not
configured" branch that was not taken.

## The shape

A test saves a global, overrides it, and restores it in teardown:

```php
$prev = Registry::isRegistered('theme') ? Registry::get('theme') : null;
Registry::set('theme', 'fixture');
// … tearDown:
Registry::set('theme', $prev);      // absent before → now registered, value null
```

If the key was absent before the test, it is now **present with value `null`**. Code that reads
the key with `get(k) !== null` cannot see the difference. Code that guards with presence
(`isRegistered(k)`, `array_key_exists`, `getenv(k) !== false`, `'K' in os.environ`) takes the
"configured" branch with an empty value. Only a test that runs **after** the leaking one sees
it, so the failure moves with the seed and names a file the leaking test never touches.

Field case: a gate's default logger built its log path only when the theme key was registered.
Two model tests restored an absent theme and document root as registered nulls. Under one seed,
the gate's "inert without the registry" test then tried to write `/log/…-revive_.log` and
errored.

## The fix

Record presence separately from the value, and restore each state as it was:

```php
// setUp
$this->saved[$k] = Registry::isRegistered($k) ? [Registry::get($k)] : [];
// tearDown
foreach ($this->saved as $k => $was) {
    if ($was) { Registry::set($k, $was[0]); }
    else      { Registry::getInstance()->offsetUnset($k); }
}
```

The same pattern applies elsewhere:

- `putenv('K')` to remove a variable, not `putenv('K=')`;
- `unset($_SERVER['K'])`;
- `os.environ.pop('K', None)`, not `os.environ['K'] = ''`;
- `monkeypatch.delenv('K', raising=False)`;
- unbinding a container entry rather than binding `null`.

The test that tripped over the leak can also pin its own precondition. If it expects the key
to be absent, assert that in `setUp`, so the next leak fails with a clear message instead of
inside the code under test.

## Diagnosis

1. **Reproduce on the right tree first.** A pasted failing run can come from the base branch.
   Replay the same seed on both trees before deciding the change caused it.
2. **Replay by seed.** `--order-by=random --random-order-seed=<n>` in PHPUnit, `--randomly-seed=<n>` with
   pytest-randomly. A real leak reproduces every time with the same seed.
3. **Name the key, then grep the whole suite for writers of that key.** Do not stop at the file a
   bisect points to. The first fix in one file did not turn the seed green, because a sibling
   test file used the same save-and-restore idiom. Look for every `set(<key>, $prev…)` and every
   `$prev = … ? get(...) : null`.
4. **Then run many seeds**, not just the one you were given. The field fix was proven on 24 seeds.

The in-browser sibling [`CROSS_SPEC_UI_LEAKAGE.md`](CROSS_SPEC_UI_LEAKAGE.md) covers the same
diagnosis (A/B the suite, replay by seed, never pin the order) for artefacts left in a shared page.

## Anti-patterns

- ❌ `set(k, $prev)` where `$prev` stood for "was absent".
- ❌ Fixing the one file the bisect named and declaring the seed fixed without re-running it.
- ❌ Pinning the suite order or skipping the failing test because it "only fails randomly".
- ❌ Changing the production guard from presence to non-null to make the test pass. The guard is
  right, and the test harness is what leaked.
