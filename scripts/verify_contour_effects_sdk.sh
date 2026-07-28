#!/bin/zsh
# SPDX-FileCopyrightText: 2026 Daito Manabe
# SPDX-License-Identifier: BSD-3-Clause

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/contour-effects-sdk.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT
FORBIDDEN_PATTERN='-lglic_metal|-framework Syphon|-framework Vision|-framework CoreML|-module-name ContourFlow|Sources/ContourFlow/|glic-metal/(include|build)|Syphon\.framework|GlicMetal\.xcframework|GlicMetalResources\.bundle|/\.codex/shared/syphon'
LICENSE_FILE="LICENSE"
MANIFEST_FILE="SDK/contour-effects-sdk.json"
CANONICAL_LICENSE_SHA="eab08c648f647e0f64f60d950dd4f10b8c3a65f0bf23b3990040d64b7306ab97"

echo "== SDK license and scope =="
[[ "$(head -n 1 "$LICENSE_FILE")" == \
  "Copyright (c) 2026 Daito Manabe" ]] || {
  echo "error: unexpected ContourEffects copyright holder" >&2
  exit 1
}
[[ "$(plutil -extract sdk.firstPartyLicense.spdxExpression raw \
  "$MANIFEST_FILE")" == "BSD-3-Clause" ]] || {
  echo "error: SDK manifest license is not BSD-3-Clause" >&2
  exit 1
}
[[ "$(plutil -extract sdk.firstPartyLicense.scopePolicy raw \
  "$MANIFEST_FILE")" == "closed-whitelist-with-spdx-headers" ]] || {
  echo "error: SDK manifest does not use the closed-whitelist scope policy" >&2
  exit 1
}
[[ "$(plutil -extract sdk.firstPartyLicense.unlistedRepositoryFilesLicensed raw \
  "$MANIFEST_FILE")" == "false" ]] || {
  echo "error: SDK manifest licenses unlisted repository files" >&2
  exit 1
}
[[ "$(jq -r '.sdk.supportedArchitectures | join(",")' \
  "$MANIFEST_FILE")" == "arm64" ]] || {
  echo "error: current SDK preview architecture contract is not arm64" >&2
  exit 1
}
jq -e \
  '.sdk.repository == "https://github.com/daitomanabe/contour-effects-sdk.git"
    and .sdk.swiftPMRemoteIdentity == "contour-effects-sdk"
    and .sdk.localPackageAlias == "ContourEffectsSDK"' \
  "$MANIFEST_FILE" > /dev/null || {
  echo "error: standalone SDK repository identity contract is invalid" >&2
  exit 1
}
[[ "$(plutil -extract sdk.firstPartyLicense.licensePath raw \
  "$MANIFEST_FILE")" == "$LICENSE_FILE" ]] || {
  echo "error: SDK manifest does not point to the root LICENSE" >&2
  exit 1
}
EXPECTED_LICENSE_SHA="$(plutil -extract sdk.firstPartyLicense.sha256 raw \
  "$MANIFEST_FILE")"
ACTUAL_LICENSE_SHA="$(shasum -a 256 "$LICENSE_FILE" | awk '{print $1}')"
[[ "$CANONICAL_LICENSE_SHA" == "$ACTUAL_LICENSE_SHA" ]] || {
  echo "error: LICENSE is not the reviewed canonical BSD-3-Clause text" >&2
  exit 1
}
[[ "$EXPECTED_LICENSE_SHA" == "$ACTUAL_LICENSE_SHA" ]] || {
  echo "error: LICENSE does not match the pinned manifest hash" >&2
  exit 1
}
for required_path in \
  "$(plutil -extract sdk.firstPartyLicense.licensePath raw "$MANIFEST_FILE")" \
  "$(plutil -extract sdk.firstPartyLicense.scopePath raw "$MANIFEST_FILE")" \
  "$(plutil -extract sdk.firstPartyLicense.attributionPath raw "$MANIFEST_FILE")"; do
  [[ -f "$required_path" ]] || {
    echo "error: missing SDK license metadata file: $required_path" >&2
    exit 1
  }
done
for documentation_key in quickStart apiManual optionalDependencies; do
  documentation_path="$(plutil -extract documentation.$documentation_key raw \
    "$MANIFEST_FILE")"
  [[ -f "$documentation_path" ]] || {
    echo "error: missing SDK documentation file: $documentation_path" >&2
    exit 1
  }
done
for documentation_key in coreDocCCatalog metalDocCCatalog; do
  documentation_path="$(plutil -extract documentation.$documentation_key raw \
    "$MANIFEST_FILE")"
  [[ -d "$documentation_path" ]] || {
    echo "error: missing SDK DocC catalog: $documentation_path" >&2
    exit 1
  }
done
[[ "$(jq '.examples | length' "$MANIFEST_FILE")" -gt 0 ]] || {
  echo "error: SDK manifest has no example packages" >&2
  exit 1
}
while IFS= read -r example_path; do
  case "$example_path" in
    Examples/*)
      ;;
    *)
      echo "error: SDK example is outside Examples/: $example_path" >&2
      exit 1
      ;;
  esac
  [[ "$example_path" != *".."* ]] || {
    echo "error: SDK example path traverses outside its root: $example_path" >&2
    exit 1
  }
  [[ -f "$example_path/Package.swift" ]] || {
    echo "error: missing SDK example package: $example_path" >&2
    exit 1
  }
done < <(jq -r '.examples[].packagePath' "$MANIFEST_FILE")
for product_index in 0 1; do
  case "$product_index" in
    0)
      expected_product="ContourEffectsCore"
      expected_root="Sources/ContourEffectsCore"
      ;;
    1)
      expected_product="ContourEffectsMetal"
      expected_root="Sources/ContourEffectsMetal"
      ;;
  esac
  [[ "$(plutil -extract products.$product_index.name raw \
    "$MANIFEST_FILE")" == "$expected_product" ]] || {
    echo "error: unexpected SDK product at manifest index $product_index" >&2
    exit 1
  }
  [[ "$(plutil -extract products.$product_index.declaredLicense raw \
    "$MANIFEST_FILE")" == "BSD-3-Clause" ]] || {
    echo "error: $expected_product is not declared BSD-3-Clause" >&2
    exit 1
  }
  [[ "$(plutil -extract products.$product_index.sourceRoots.0 raw \
    "$MANIFEST_FILE")" == "$expected_root" ]] || {
    echo "error: unexpected source root for $expected_product" >&2
    exit 1
  }
done

LICENSED_HEADER_FILES=(
  .gitignore
  AGENTS.md
  Package.swift
  README.md
  ThirdPartyNotices/README.md
  docs/CONTOUR_EFFECTS_API.md
  docs/CONTOUR_EFFECTS_SDK.md
  docs/CONTOUR_EFFECTS_THIRD_PARTY.md
  SDK/ATTRIBUTION.md
  SDK/SCOPE.md
  scripts/verify_contour_effects_sdk.sh
)
while IFS= read -r file; do
  LICENSED_HEADER_FILES+=("$file")
done < <(
  git ls-files --cached --others --exclude-standard -- \
    Sources/ContourEffectsCore \
    Sources/ContourEffectsMetal \
    Tests/ContourEffectsCoreTests \
    Tests/ContourEffectsMetalTests \
    Examples/MinimalContourEffectsHost \
    Examples/ContourEffectsExamples
)
for file in "${LICENSED_HEADER_FILES[@]}"; do
  grep -Fq "SPDX-FileCopyrightText: 2026 Daito Manabe" "$file" || {
    echo "error: missing SPDX copyright header: $file" >&2
    exit 1
  }
  grep -Fq "SPDX-License-Identifier: BSD-3-Clause" "$file" || {
    echo "error: missing BSD-3-Clause SPDX header: $file" >&2
    exit 1
  }
done

while IFS= read -r -d '' file; do
  if grep -Fq "SPDX-FileCopyrightText: 2026 Daito Manabe" "$file" || \
      grep -Fq "SPDX-License-Identifier: BSD-3-Clause" "$file"; then
    case "$file" in
      .gitignore | \
      AGENTS.md | \
      Package.swift | \
      README.md | \
      ThirdPartyNotices/README.md | \
      docs/CONTOUR_EFFECTS_API.md | \
      docs/CONTOUR_EFFECTS_SDK.md | \
      docs/CONTOUR_EFFECTS_THIRD_PARTY.md | \
      SDK/ATTRIBUTION.md | \
      SDK/SCOPE.md | \
      scripts/verify_contour_effects_sdk.sh | \
      Sources/ContourEffectsCore/* | \
      Sources/ContourEffectsMetal/* | \
      Tests/ContourEffectsCoreTests/* | \
      Tests/ContourEffectsMetalTests/* | \
      Examples/MinimalContourEffectsHost/* | \
      Examples/ContourEffectsExamples/*)
        ;;
      *)
        echo "error: ContourEffects BSD header entered an excluded path: $file" >&2
        exit 1
        ;;
    esac
  fi
done < <(
  git ls-files -z
  git ls-files -z --others --exclude-standard
)

echo "== Standalone package contract =="
if ! xcrun swift package dump-package > "$SCRATCH/package.json"; then
  echo "error: could not inspect the root Swift package" >&2
  exit 1
fi
jq -e \
  '.name == "ContourEffectsSDK"
    and (.products | length) == 2
    and ([.products[].name] | sort)
      == ["ContourEffectsCore", "ContourEffectsMetal"]
    and ([.products[] | select(.type.library != null)] | length) == 2
    and (.targets | length) == 4
    and ([.targets[].name] | sort)
      == [
        "ContourEffectsCore",
        "ContourEffectsCoreTests",
        "ContourEffectsMetal",
        "ContourEffectsMetalTests"
      ]' \
  "$SCRATCH/package.json" > /dev/null || {
  echo "error: root Swift package is not the expected two-product/four-target SDK" >&2
  exit 1
}

echo "== SDK unit tests =="
if ! xcrun swift test \
    --scratch-path "$SCRATCH/sdk-tests" \
    -v > "$SCRATCH/sdk-tests.log" 2>&1; then
  cat "$SCRATCH/sdk-tests.log" >&2
  exit 1
fi
if grep -En -- "$FORBIDDEN_PATTERN" "$SCRATCH/sdk-tests.log"; then
  echo "error: an app-only dependency entered the SDK test closure" >&2
  exit 1
fi

echo "== SDK target closure =="
if ! xcrun swift build \
    --target ContourEffectsMetal \
    --scratch-path "$SCRATCH/sdk-target" \
    -v > "$SCRATCH/sdk-target.log" 2>&1; then
  cat "$SCRATCH/sdk-target.log" >&2
  exit 1
fi
if grep -En -- "$FORBIDDEN_PATTERN" "$SCRATCH/sdk-target.log"; then
  echo "error: an app-only dependency entered the SDK target closure" >&2
  exit 1
fi

echo "== Independent host build =="
if ! xcrun swift build \
    --package-path Examples/MinimalContourEffectsHost \
    --scratch-path "$SCRATCH/consumer" \
    -v > "$SCRATCH/consumer.log" 2>&1; then
  cat "$SCRATCH/consumer.log" >&2
  exit 1
fi
if grep -En -- "$FORBIDDEN_PATTERN" "$SCRATCH/consumer.log"; then
  echo "error: an optional dependency became transitive" >&2
  exit 1
fi

BIN_DIR="$(xcrun swift build \
  --package-path Examples/MinimalContourEffectsHost \
  --scratch-path "$SCRATCH/consumer" \
  --show-bin-path)"
CONSUMER="$BIN_DIR/MinimalContourEffectsHost"
if otool -L "$CONSUMER" | grep -En 'Syphon|Vision|CoreML|glic'; then
  echo "error: the minimal host links an optional dependency" >&2
  exit 1
fi
find "$BIN_DIR" -maxdepth 3 -type f -print > "$SCRATCH/consumer-files.txt"
if grep -En 'YOLO|DepthAnything|\.mlmodelc|Syphon|Glic' \
  "$SCRATCH/consumer-files.txt"; then
  echo "error: the minimal host contains an optional model or SDK resource" >&2
  exit 1
fi

echo "== Executable SDK examples =="
EXAMPLES_PACKAGE="$(
  jq -r \
    '.examples[] | select(.name == "ContourEffectsExamples") | .packagePath' \
    "$MANIFEST_FILE"
)"
[[ -n "$EXAMPLES_PACKAGE" ]] || {
  echo "error: SDK manifest is missing ContourEffectsExamples" >&2
  exit 1
}
EXAMPLE_EXECUTABLE_COUNT="$(
  jq \
    '[.examples[]
      | select(.name == "ContourEffectsExamples")
      | .executables[]] | length' \
    "$MANIFEST_FILE"
)"
[[ "$EXAMPLE_EXECUTABLE_COUNT" -gt 0 ]] || {
  echo "error: ContourEffectsExamples has no executables" >&2
  exit 1
}
jq -e \
  '[.examples[]
    | select(.name == "ContourEffectsExamples")
    | .executables[]] as $names
   | ($names | length) == ($names | unique | length)' \
  "$MANIFEST_FILE" > /dev/null || {
  echo "error: ContourEffectsExamples contains duplicate executable names" >&2
  exit 1
}
if ! xcrun swift build \
    --package-path "$EXAMPLES_PACKAGE" \
    --scratch-path "$SCRATCH/examples" \
    -v > "$SCRATCH/examples.log" 2>&1; then
  cat "$SCRATCH/examples.log" >&2
  exit 1
fi
if grep -En -- "$FORBIDDEN_PATTERN" "$SCRATCH/examples.log"; then
  echo "error: an optional dependency entered the example target closure" >&2
  exit 1
fi
EXAMPLES_BIN_DIR="$(xcrun swift build \
  --package-path "$EXAMPLES_PACKAGE" \
  --scratch-path "$SCRATCH/examples" \
  --show-bin-path)"
while IFS= read -r executable; do
  report="$SCRATCH/$executable.json"
  if ! "$EXAMPLES_BIN_DIR/$executable" --self-check > "$report"; then
    cat "$report" >&2
    exit 1
  fi
  jq -e '.selfCheck == true' "$report" > /dev/null || {
    echo "error: $executable did not complete its self-check" >&2
    cat "$report" >&2
    exit 1
  }
  if otool -L "$EXAMPLES_BIN_DIR/$executable" \
      | grep -En 'Syphon|Vision|CoreML|glic'; then
    echo "error: $executable links an optional host dependency" >&2
    exit 1
  fi
done < <(
  jq -r \
    '.examples[]
      | select(.name == "ContourEffectsExamples")
      | .executables[]' \
    "$MANIFEST_FILE"
)
jq -e '.state.unknownKeyPreserved == true' \
  "$SCRATCH/ContourEffectsCatalogStateExample.json" > /dev/null
jq -e '.alphaPreserved == true and .malformedLUTRejected == true' \
  "$SCRATCH/ContourEffectsLUTRenderExample.json" > /dev/null
jq -e \
  '.missingMaskRejected == true
    and .wrongMaskABIRejected == true
    and .unknownStatePreserved == true' \
  "$SCRATCH/ContourEffectsAnalysisMaskExample.json" > /dev/null
jq -e \
  '.clampingVerified == true
    and .alphaPreserved == true
    and .missingProvidedInputsRejected == true' \
  "$SCRATCH/ContourEffectsAudioMacroReactiveExample.json" > /dev/null
jq -e '.checks | all(. == true)' \
  "$SCRATCH/ContourEffectsGraphLifecycleExample.json" > /dev/null
jq -e \
  '.flowResolutionScale == 0.25
    and .wrongFlowFormatRejected == true
    and .wrongFlowAspectRejected == true' \
  "$SCRATCH/ContourEffectsEdgeFlowWarpExample.json" > /dev/null
jq -e \
  '.lookCount == 8
    and .distinctOutputCount == 8
    and .allLookMetadataRetained == true
    and .monochromeChannelsConverged == true' \
  "$SCRATCH/ContourEffectsColorLookGalleryExample.json" > /dev/null
jq -e \
  '.codableRoundTrip == true
    and .availability.emptyProvidersRemainAvailable == true
    and .availability.textureFlagsCannotBeForged == true' \
  "$SCRATCH/ContourEffectsLiveInputsExample.json" > /dev/null
find "$EXAMPLES_BIN_DIR" -maxdepth 3 -type f -print \
  > "$SCRATCH/example-files.txt"
if grep -En 'YOLO|DepthAnything|\.mlmodelc|Syphon|Glic' \
  "$SCRATCH/example-files.txt"; then
  echo "error: an SDK example contains an optional model or SDK resource" >&2
  exit 1
fi

echo "== DocC manuals =="
for scheme in ContourEffectsCore ContourEffectsMetal; do
  if ! xcodebuild docbuild \
      -scheme "$scheme" \
      -destination 'platform=macOS,arch=arm64' \
      -derivedDataPath "$SCRATCH/docc-$scheme" \
      CODE_SIGNING_ALLOWED=NO \
      OTHER_DOCC_FLAGS='--warnings-as-errors' \
      > "$SCRATCH/docc-$scheme.log" 2>&1; then
    cat "$SCRATCH/docc-$scheme.log" >&2
    exit 1
  fi
  find "$SCRATCH/docc-$scheme" -name "$scheme.doccarchive" -type d \
    -print -quit > "$SCRATCH/docc-$scheme.archive"
  [[ -s "$SCRATCH/docc-$scheme.archive" ]] || {
    echo "error: $scheme DocC archive was not generated" >&2
    exit 1
  }
done

echo "== Real Metal smoke frame =="
"$CONSUMER"

echo "ContourEffects SDK verification passed."
