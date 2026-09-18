# Releasing

Cutting a release is one command once the tokens below are in place:

```
git tag v1.0.1
git push origin v1.0.1
```

The GitHub Action builds the zip and uploads it to every site it holds a
token for. A site with no token is skipped silently, so this works with only
CurseForge configured and gains the others as you add them.

## The IDs the packager needs

Each site identifies the project by an id in `Denizens.toc`:

| Site | TOC field | Status |
| --- | --- | --- |
| CurseForge | `## X-Curse-Project-ID` | **1700738** |
| WoWInterface | `## X-WoWI-ID` | not created yet |
| Wago | `## X-Wago-ID` | not created yet |

Without the id for a site, that site is skipped even if the token exists.

## The tokens

Add each as a GitHub repository secret under
**Settings -> Secrets and variables -> Actions -> New repository secret**.
They go straight into GitHub; nothing needs to be pasted into a chat or
stored on disk.

| Secret | Where to generate it |
| --- | --- |
| `CF_API_KEY` | authors.curseforge.com -> your avatar -> My API Tokens |
| `WOWI_API_TOKEN` | wowinterface.com -> account -> API token (needs an account) |
| `WAGO_API_TOKEN` | addons.wago.io -> account -> API keys (needs an account) |

`GITHUB_TOKEN` is provided by Actions automatically; nothing to do.

## Bumping a version

Three places, and they must agree:

1. `## Version:` in `Denizens.toc`
2. the git tag
3. `ns.BUILT_FOR` in `Core.lua` — only if the client's `## Interface:` number
   changes. It is duplicated there because `GetAddOnMetadata` cannot read the
   Interface field back out of the TOC, and the login line compares against it
   to warn when the addon is out of date.
