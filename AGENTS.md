# WorkspaceManager.spoon Notes

## Releases

- `init.lua` version must match the release tag.
- Validate before tagging:
  - `luac -p init.lua workspace_manager.lua screens.lua summon.lua tests/init_spec.lua tests/runtime_spec.lua tests/summon_spec.lua`
  - `lua tests/runtime_spec.lua && lua tests/summon_spec.lua && lua tests/init_spec.lua`
  - `./scripts/package_spoon.sh "$(./scripts/version.sh current)" dist`
- Create an annotated tag with a title and short multiline summary:
  - ```sh
    git -c tag.gpgsign=false tag -a vX.Y.Z -F - <<'EOF'
    vX.Y.Z

    ## Summary

    - Fix summon edge cases.
    - Harden focus retries for rapid app switching.
    - Refresh tests and release docs.
    EOF
    ```
- Keep the tag body Markdown-friendly if you write one, but note: the current GitHub release workflows use `--generate-notes`, so the tag body is not published as the release description.
- Push `main`, then push the tag:
  - `git push origin HEAD:main`
  - `git push origin refs/tags/vX.Y.Z`
- Pushing `v*` triggers the `Publish Release` GitHub Actions workflow, which builds and publishes the release assets.
