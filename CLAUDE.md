# Working in this repository

This repository is field notes, not code. It records how to build an AppImage that runs on
Tails, with the evidence for each claim, so that the next person or agent does not repeat the
experiments.

## The rule that gives this repository its value

**Every claim here is verified, and the verification is named.** No recalled version numbers,
no "should work", no library recommended without checking whether it is still maintained.

If you cannot verify something, say so in the text rather than rounding it up to a fact.

The single most reusable habit: **what Tails provides is a published manifest**, at
`https://tails.net/torrents/files/tails-amd64-<version>.packages`. Grep it. Do not ask a human
to boot a USB stick to answer a question that file answers in ten seconds.

## Updating for a new Tails release

1. Fetch the new manifest.
2. Re-check the table in the README: the WebKitGTK major version is the one that actually
   changes and breaks things. Debian 13 dropped webkit2gtk-4.0.
3. Update the version and the date in the heading. Do not silently edit a version number and
   leave the date, since the date is what tells a reader how stale this is.

## Writing style

No em dashes and no en dashes. Use a colon, semicolon, comma, parentheses, or a sentence break.

State facts rather than commenting on how well the prose states them.

## Attribution

Commits and pull requests do not carry "Generated with Claude Code" or a `Co-Authored-By`
trailer. Where attribution is wanted, add a small italic *Collaboration by Claude* line.
