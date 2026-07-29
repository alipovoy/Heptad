# Security Policy

## Reporting a vulnerability

**Please do not report security vulnerabilities through public GitHub issues,
discussions, or pull requests.**

Instead, use GitHub's private vulnerability reporting:

1. Go to the [Security tab](https://github.com/alipovoy/Heptad/security) of this
   repository.
2. Click **Report a vulnerability** to open a private advisory.
3. Describe the issue with as much detail as possible.

A good report includes:

* the platform and OS version you reproduced on,
* the commit or branch you built from,
* a description of the vulnerability and its potential impact,
* step-by-step instructions to reproduce it,
* any proof-of-concept code, configuration, or screenshots, and
* any suggested mitigation, if you have one.

## What to expect

* We aim to acknowledge new reports within **7 days**.
* We will keep you informed as we investigate and work on a fix.
* Once a fix is merged, we are happy to credit you in the advisory unless you prefer
  to remain anonymous.

## Threat model

Heptad's attack surface is deliberately small. All seven notes live entirely on the
local device in a SwiftData store; nothing is uploaded, synced, or shared. The
codebase contains no network code at all — no `URLSession`, no `Network` framework,
no web views, and no CloudKit — so there is no server, no account, and no data in
transit to attack.

The macOS app runs in the App Sandbox: its entitlements grant the sandbox and nothing
else, with no network client or server entitlement. The iOS app is sandboxed by the
platform. Reports that show a way to read or modify another app's data, escape the
sandbox, or expose note contents to another process or user on the same machine are
firmly in scope.

## Scope

Heptad ships as source with no signed or notarized binary releases, so reports about
code signing, notarization, or Gatekeeper are out of scope.

Thank you for helping keep Heptad and its users safe.
