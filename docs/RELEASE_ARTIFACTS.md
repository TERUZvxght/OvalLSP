# Release artifacts

The SHA-256 of every VSIX this project has published, and an explicit row
for every tag that was never published.

`docs/PUBLISHING.md` has asked for the hash to be "computed and recorded"
since the first Preview. Nowhere said *where*, so for fourteen tags it was
computed and then discarded — a hash nobody wrote down cannot be compared
against anything later, which is the only thing a hash is for.

**English only, deliberately.** This is operational data rather than
prose, the same category as `RELEASE_CHECKLIST.md`, `SBOM.md` and
`SECURITY_CHECKLIST.md`, and a translated copy of a hash table is a
second place for a digit to be wrong.

## How to verify a row yourself

Every hash below was taken from the artifact the Marketplace actually
serves, not from a local build. The Marketplace serves it gzipped, which
is the one step that makes a naive `curl | shasum` disagree:

```bash
curl -sSL -o published.gz \
  "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/teruz/vsextensions/ovallsp/<version>/vspackage?targetPlatform=darwin-arm64"
gunzip -c published.gz > published.vsix
shasum -a 256 published.vsix
```

A local build of the same version is *not* guaranteed to match, and the
reason is worth knowing: native gem extensions do not compile
byte-reproducibly, so building twice gives two different VSIXs.
`release.sh` publishes with `--packagePath` precisely so that the file it
verified is the file that ships — which is why the local artifact and the
published one do match for every version below that was built that way.

## Published

| Version | SHA-256 | Channel |
|---|---|---|
| 0.2.6 | `62e4dc19e3556c84b7e439ddf2fa0bcc48c3ec8487fc04b902fd15b094957cf6` | Pre-Release |
| 0.2.5 | `4749ca71bf419684cf2bdd48119bebbcd054ffa21b9cb9c83ea4358bd7e77889` | Pre-Release |
| 0.2.4 | `8256812e67e09a5628901ea87afbf22772e7dd94a19008ed0824d067bd012662` | Pre-Release |
| 0.2.3 | `514bcdc433d65c1141a897665324dee07689ae00944f5bf44707a6eb887321c1` | Pre-Release |
| 0.2.2 | `7cadd7da2f4422eaea060ae1657b9c84652f0f3484377f4a4d7fffa50c65807b` | Pre-Release |
| 0.2.1 | `b759fc111a32b441164d9796f31a94947dcf73c0d77e817ea045c5f155141e22` | Pre-Release |
| 0.2.0 | `f4f98df1ca06ca8ea11186973ca830087fa2e77f0c031b6aa213787d1a3c2b24` | Pre-Release |
| 0.1.13 | `5e756d5ccab480826b001877d42a7ba64b18cf5d77deefc36b02d38938731f5e` | Pre-Release |
| 0.1.12 | `64c92b44809dd34b0e223036a9a4c68ce2fbc71c551563724eb2cd74a8e114d8` | Pre-Release |
| 0.1.11 | `50724eda1410afd3908378a21d43361c8e2e768a386be9e7d60da17a4677acda` | Pre-Release |
| 0.1.10 | `ff38ba64b7892f8bd946297cc061ed7706fcfea5cd30b760950801b7e4d23ecd` | Pre-Release |
| 0.1.9 | `66a5cf0a885cc14695d6f3fa1818b492442aee0d5990531569420796dae9284f` | Pre-Release |
| 0.1.8 | `d4603930babe6e85f45b3648de3724111bd3d751689b05c54f74b788936198e4` | Pre-Release |
| 0.1.7 | `3856feb7f9886aa5fe05c7168e1978e79d1305ee0deb3a2b9c8039221a50aeee` | Pre-Release |
| 0.1.6 | `3701e54f8f36dc6a0ed51aba05d74575faa857383c6b1f42af7222e833520827` | Pre-Release |
| 0.1.5 | `3f457abd27c2fcdd97c483893fd09a9b85455aa32bbdf96fae58fec18718329f` | Pre-Release |
| 0.1.4 | `ec7d64ade7447762827cd07734d41f392635b8a4c5b7497926d858dc927ee12a` | Pre-Release |
| 0.1.3 | `e14c1570ae4c2e4f9ef8cabc7d6929e68304bf5ba9a72958318c87802f8cb4e3` | Pre-Release |
| 0.1.2 | `0a5c91831654fca1bd7cc2ba4f8b32cfb5aea306b4602bc1dd1b4852857d1590` | Pre-Release |
| 0.1.1 | `df18b12aa1fd3a3f59293e9595c941986892b4b3c861a06cb49676e5bde515cd` | Pre-Release |

Every target is `darwin-arm64`; no other platform has ever been
published (024.R4).

## Tagged and never published

| Version | Why |
|---|---|
| 0.1.15 | Marketplace returns 404 for it. No VSIX was ever built — 0.1.14 and 0.1.15 were correction releases, and 0.2.0 carries both. |
| 0.1.14 | Same. |

That is the good outcome rather than an oversight to regret: 0.1.14
removed about twelve thousand wrong reports and introduced a handful of
its own, and 0.1.15 is those corrections. Because neither shipped, no
user was ever on the intermediate state — a 0.1.13 install upgrades
straight to 0.2.0 and receives all three at once.

## No GitHub Release until 1.0.0

Every version above is a git tag with no GitHub Release behind it, and
that is deliberate through 0.x — the changelog is the release note, and a
Release would be a third copy of it. `docs/PUBLISHING.md` records the
decision and what changes at 1.0.0, where every tag gets one and its body
carries the SHA-256 from this table.

## After the next publish

`release.sh` prints the row to add here as its last line. Add it in the
same commit that follows the publish; `core/spec/meta/release_artifacts_spec.rb`
fails on any `v*` tag this file does not account for, in either table.
