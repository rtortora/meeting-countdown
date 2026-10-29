#!/usr/bin/env bash
# Packages tools/release-notes-vscode (the Apply / Cancel buttons on the release notes draft)
# as a .vsix and installs it into VS Code. release.sh runs this when the installed copy is
# missing or older. A .vsix is a zip of the extension plus a manifest, so no vsce/node needed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/tools/release-notes-vscode"
CODE="$(command -v code || echo "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code")"
field() { plutil -extract "$1" raw "$SRC/package.json"; }
VERSION="$(field version)"
STAGING="$ROOT/build/vsix"
VSIX="$ROOT/build/release-notes-$VERSION.vsix"

rm -rf "$STAGING" "$VSIX"
mkdir -p "$STAGING/extension"
cp "$SRC/package.json" "$SRC/extension.js" "$STAGING/extension/"
cat >"$STAGING/[Content_Types].xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension=".json" ContentType="application/json"/>
  <Default Extension=".js" ContentType="application/javascript"/>
  <Default Extension=".vsixmanifest" ContentType="text/xml"/>
</Types>
XML
cat >"$STAGING/extension.vsixmanifest" <<XML
<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011">
  <Metadata>
    <Identity Language="en-US" Id="$(field name)" Version="$VERSION" Publisher="$(field publisher)"/>
    <DisplayName>$(field displayName)</DisplayName>
    <Description xml:space="preserve">$(field description)</Description>
    <Properties>
      <Property Id="Microsoft.VisualStudio.Code.Engine" Value="$(field engines.vscode)"/>
    </Properties>
  </Metadata>
  <Installation>
    <InstallationTarget Id="Microsoft.VisualStudio.Code"/>
  </Installation>
  <Dependencies/>
  <Assets>
    <Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true"/>
  </Assets>
</PackageManifest>
XML
(cd "$STAGING" && zip -qrX "$VSIX" .)
rm -rf "$STAGING"
"$CODE" --install-extension "$VSIX" --force
