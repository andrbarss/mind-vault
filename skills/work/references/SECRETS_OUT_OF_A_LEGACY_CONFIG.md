# Converting credentials out of a legacy config file, and checking one account with them

Load when a step writes a tool that reads secrets from a legacy configuration file written as code (PHP
assignments, a Python settings module, a shell env script) and emits them in another format, or a tool that makes
one real request with a stored credential to prove an account works. Each item below was a defect an architect
review, an independent review or a review engine found in such a pair of tools; the first design looked careful.

## Reading the file

1. **Never execute the input; tokenise it.** The language's own tokenizer (PHP `token_get_all()` without
   `TOKEN_PARSE`) needs no successful parse, so a truncated or broken file is fine, and it tells a plain literal
   from one the language would compute (interpolation, heredoc).
2. **"Read the entries, skip the rest" fails open.** A reader that looks for the statements it knows and ignores
   everything else accepts a file whose *other* statements change what the legacy program serves: a chained
   assignment (`$a->Name = $b->Password = "…";` — `b`'s file kept the old password), a call inside a constant
   definition (`define('X', array_pop($list))`), a second definition of the list, a class default or constructor.
   Make the reader a **whitelist grammar**: a closed list of statement forms, each right-hand side exactly one
   literal token, and refuse the **whole run** on anything else, with the line number and no value. A statement that
   can touch another entry cannot be a per-entry refusal.
3. **Prove it by running the same synthetic file with the language** and comparing what the program holds with
   what the tool wrote — as a standing test over the accepted fixtures, and as the way to reproduce every claimed
   fail-open before fixing it. One fixture file per refusal rule.
4. **A value is what the language evaluates, not the characters between the quotes.** Without a backslash the
   body is the value, exact by construction. With one, use a small unescaper and compare it in the *test suite*
   with the language's own evaluation over a few thousand generated literals, on every runtime version the legacy
   program ran on, so that evaluation never happens in the tool that holds real secrets. The comparison found an
   escape the specification missed (`\X41` as well as `\x41`). Refuse what the unescaper does not cover.
5. **The target format has its own limits.** A line-based `KEY=VALUE` reader cannot hold a line break and may
   drop a trailing carriage return silently: refuse such values instead of writing something else.
6. **Say what the tool can see about loose legacy comparisons.** Where the legacy program compared with a loose
   operator (numeric strings compared as numbers) and the new one compares exactly, a credential that worked in
   another spelling stops working. Report the property ("this password is a numeric string"), never the value.

## Not leaking

7. **A stock runtime image prints a failing call's arguments.** An uncaught exception printed
   `put('account', '<secret>')`. The script sets its own error settings as its first statements
   (`display_errors=0`, `log_errors=0`, `zend.exception_ignore_args=1` in PHP), has one top-level catch that prints
   class and line only, marks value-carrying parameters sensitive, and the wrapper passes the same flags. Test the
   no-leak property three ways: a clean run, a run forced to fail mid-way, and a run **without the wrapper's
   flags** — a no-leak test is green on any tool that never errors.
8. **No value in argv, the environment, a shell variable or a file name.** The wrapper handles paths and account
   names only. Print an account name only when it matches the name pattern: a raw one can carry terminal escapes.
9. **The output directory**: outside any version-controlled tree, checked on the *resolved* path and by walking
   the parents for a `.git` entry whatever the VCS command says; no `..` component; the parent must exist (make one
   directory, never a path); `umask` before `mkdir`; write under a temporary name and rename; a manifest with the
   input's hash, the tool's commit and per account *written / refused (field and rule) / not asked for*, no value.
10. **A cleanup trap must never touch a directory the run refused.** An output given as a symlink to a directory
    that already held secrets passed the emptiness check (`find` does not follow a starting-point link), was
    refused later — after the trap was armed — and the cleanup deleted that directory's files. Refuse a symlink
    outright before anything, use `find -H`, and clear the path variable in *every* refusal branch.
11. **Assert the sandbox flags.** Removing `--network none` from the container left every test green until a
    recording stand-in for the container CLI asserted the flags of each container the wrapper starts.

## What a check proves

12. **A check that feeds the old program the converted values cannot prove the conversion.** It proves the
    written values survive the old login path (transport, lookup, the loose compare). That they equal the
    original literals rests on the reader. The stronger check runs the original file, which is the thing the tool
    must not do; make that an explicit owner decision and write down which claim each check supports.
13. **Pick a probe the old program answers differently for an accepted and a refused login without calling
    anything**: where the login is checked before the request type, an unknown request type does it. Run the old
    program with no network and its log directories in memory: it logs request bodies.

## One real request with a stored credential

14. **Take the credential from what the running service compares, not from the file.** Compare the file with the
    service's loaded copy field by field; when they differ, name the fields and send nothing. A request with a
    wrong password is then never sent, which matters where failed logins count against the account's real user.
    A modification-time heuristic is defeated by `cp -p`.
15. **The destination comes from configuration, never from the operator's typing.** Accept only a URL already in
    the deployment's own list; follow no redirect (a 307 re-posts the body); send once, never retry with real
    credentials (re-read the log instead).
16. **Report counts and outcomes only.** Upstream error text is clipped and stripped of control, C1 and bidi
    characters; never a response body or a log line. When a credential cannot travel in the request's encoding
    (invalid UTF-8 in XML), send nothing and say so: the escaped empty value would count as a failed login.
17. **The tool can send exactly one kind of request**: one constant, no parameter that names it, and a test that
    reads the mock's journal for the read-only calls it should cause and nothing else.
