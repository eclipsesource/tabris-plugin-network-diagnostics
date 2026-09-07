# Open questions

One line per item; the default the code follows is stated, the decision is the
user's.

- **Plugin-injected build settings.** The review of the plugin skeleton rated
  the `<config-file target="config.xml">` injection of `deployment-target` and
  `SwiftVersion` as a high risk because two plugins could inject conflicting
  values. Default kept: inject them (an app's own preference takes precedence
  and every Swift Tabris plugin so far needs the same two values); rationale in
  `docs/decisions/2026-09-07T2015Z-build-settings-via-preferences.md`. The
  alternative is documenting both as host-app requirements only.
- **License.** The source project ships no `LICENSE`; none was added. The older
  plugin repositories use the Revised BSD License.
