# Restricting HTTP verbs on an existing API

Load when a step narrows which HTTP verbs a route answers: "reads GET, writes POST", dropping a `match(['get','post'])`,
moving an admin action to POST, or any change that turns a previously accepted verb into a 405. The code change is one
line per route. The risk is everywhere that still sends the old verb, and in tests that cannot tell a refusal from
success.

## 1. Let a 405 fail the test suite

A feature test that sends the old verb to a write gets the router's 405, and nothing is written. Every assertion of the
shape "the refusal wrote nothing", "no row changed" or "the second call was refused" still passes. The test goes green
because it never reached the action.

Put a guard in the feature-test base class. Override the one method every request helper funnels through (Laravel:
`MakesHttpRequests::call()`; Django test client: `generic()`; a hand-rolled client: its send method). Fail on a 405
unless the test opted in:

```php
public function call($method, $uri, $parameters = [], $cookies = [], $files = [], $server = [], $content = null)
{
    $response = parent::call($method, $uri, $parameters, $cookies, $files, $server, $content);
    if ($response->getStatusCode() === 405 && !$this->methodNotAllowedExpected) {
        $this->fail("{$method} {$uri} answered 405: send the method's verb, or call expectsMethodNotAllowed()");
    }
    return $response;
}
```

The same guard is the **discovery tool** for the change. Flip the routes first, run the suite, and the failures list
every call site that still sends the old verb, with its file and test name. Then flip those sites mechanically. Only
the tests *about* the 405 opt in: the verb test itself, the envelope test, and a former "POST is accepted" case
rewritten as a refusal.

Prove the guard bites. Remove one opt-in, run that file, and expect the guard's message; then restore it.

Signature trap: `get($uri, $headers)` vs `post($uri, $data, $headers)`. A mechanical `get(` → `post(` rewrite of a call
that passed headers sends them as form data. Rewrite such calls as `post($uri, [], $headers)` and grep for them.

## 2. One expected-verb table, held to the router

Write the expectation down once: a small table of read paths and write paths, with a `verb(path)` helper. A test holds
the router to it:

- every route under the API prefix is classified exactly once, and every classified path has a route (match the alias
  routes too; leave docs/UI routes out on purpose);
- each route's methods equal the expected set (`['GET','HEAD']` or `['POST']`);
- for every write, GET / PUT / PATCH / DELETE answer 405 with the exact refusal text and `Allow: POST`; HEAD answers 405
  too (its body is empty); for every read, POST etc. answer 405 with `Allow: GET, HEAD`;
- OPTIONS is **not** a 405: the router answers it with `Allow`, and a CORS preflight is handled before routing.

Every other sender reads its verb from the same table: the parity runner, the write-parity harness, the smoke script.

When the codebase also has a "paths that write rows" list (a tripwire, an audit list), pin the difference between the
two lists in the same test. A read can still write a counter. Without the pin, a later reader merges the two meanings.

## 3. "Not logged, not counted" needs a positive control

The router refuses a wrong verb **while matching the route**, before any route middleware runs: no throttle, no
authentication, no request log, no counter. Global middleware (trusted proxies, CORS, body-size checks, input trimming)
does run, so write "before any *route* middleware", not "before any middleware".

Assert the absence against controls that show the check can see a write:

- **Counter:** the test double records calls. After the 405s, `calls === []`. In the same test, the right verb on a
  refusal that writes nothing (a missing required id → 400) must record exactly one call.
- **Request log:** compare the log directory's byte count before and after the 405s; the control request must grow it.
- **Framework log:** listen for the log event (Laravel `MessageLogged`). Log one line yourself first and assert the
  listener saw it. If the control request logs nothing, an empty list proves nothing.
- Send one 405 **without credentials**. It must still be a 405, not a 401/403, which proves the refusal precedes
  authentication.

## 4. Sweep the docs' commands, not only the code

Runbooks and guides carry executable examples that hard-code a verb. The field case: a new-server guide wrapped every
call in `api() { … curl -sS -G … "$@"; }`. Because of `-G`, every write in its "prove the queue" chain became a GET and
would have answered 405 on the first write. No test runs a runbook. Only an independent review caught it.

```bash
grep -rnE 'curl[^|]*(-G|--get|-X ?GET)|http(ie)? GET|wget ' docs/ README* ansible/ docker/
grep -rnE 'GET[ |]+/.*/(create|cancel|install|clear|cache)' docs/
```

Give writes a second helper: tenant and routing parameters in the URL, the method parameters as `-d` form fields, no
`-G`. Run the helper against the dev stack once, on a refusal that writes nothing.

Also sweep the prose claims the change makes false or too broad. "A JSON body is ignored" is false for a route whose
request class validates `input()`, which reads JSON. A token check that reads the parsed body refuses a token *in* JSON.
Grep each universal claim against every route class it covers.

## 5. Redirects and other hops that rewrite the method

An http → https redirect with **301 or 302** is followed by most clients as a GET, so a POST to the `http://` URL ends in
the write's 405. Use **308**, which keeps the method and body (or 307 for a temporary redirect). Check every hop: the
host's site config, a load balancer, a CDN rule, framework-level `secure()` middleware.

## 6. A rollback target and the previous release

- **The system this one replaces may accept any verb.** Run the parity harnesses with the *same* verb on both hosts, so
  the comparison proves the old system answers the new verb identically. Then a rollback to it needs no client change.
  Check that its front proxy accepts the new verb too (`limit_except`, WAF rules). That config often lives in no
  repository, so make it a runbook check with an exact command and expected output.
- **Rolling back to the previous release of this system can break clients.** Routes that were GET-only before the
  change answer 405 to clients already moved to POST. Write that asymmetry into the release's deploy note and the
  rollback section, naming the routes.
- The release is breaking for a caller of the dropped verb. Say so in the changelog, quote the exact 405 text, and state
  the version decision explicitly.

## Checklist

- [ ] A 405 guard in the feature-test base, opt-in per test, mutation-checked
- [ ] Routes flipped first; the guard's failure list drives the call-site flips; header-passing calls rewritten by hand
- [ ] One expected-verb table; a router test covering classification, verbs, the exact 405 text, OPTIONS, HEAD
- [ ] "Not logged / not counted" asserted with a positive control for each sink; one 405 sent without credentials
- [ ] A form-body case per write path, matching what the spec documents
- [ ] Docs' command examples grepped for `-G` / GET helpers; universal prose claims checked per route class
- [ ] Every redirect hop 307/308
- [ ] Parity sends the same verb to both hosts; the rollback target's proxy checked; the release's rollback asymmetry
      written down
