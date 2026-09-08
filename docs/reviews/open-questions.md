# Open questions

One line per item; the default the code follows is stated, the decision is the
user's.

None open.

## Decided

- **Plugin-injected build settings.** The review of the plugin skeleton rated
  the `<config-file target="config.xml">` injection of `deployment-target` and
  `SwiftVersion` a high risk, because two plugins can inject conflicting values.
  Decided on 2026-09-08 in favour of the stated alternative: the host app
  declares them, together with the local network usage description.
  `docs/decisions/2026-09-08T1200Z-host-app-owns-required-configuration.md`.
- **License.** Revised BSD (3-clause), as in the older plugin repositories.
  `LICENSE`.
