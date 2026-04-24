#!/usr/bin/env python3
"""
Post-process Flutter's generated Android files for pilot Option A:
- Release signing from android/key.properties (if present)
- networkSecurityConfig + cleartext pilot overlay

Idempotent: safe to run multiple times.
"""
from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]  # apps/driver_pilot
ANDROID = ROOT / "android"
APP_BUILD = ANDROID / "app" / "build.gradle"
APP_BUILD_KTS = ANDROID / "app" / "build.gradle.kts"
MANIFEST = ANDROID / "app" / "src" / "main" / "AndroidManifest.xml"
OVERLAY_XML = ROOT / "tooling" / "android_overlay" / "app" / "src" / "main" / "res" / "xml" / "network_security_config.xml"
DEST_XML = ANDROID / "app" / "src" / "main" / "res" / "xml" / "network_security_config.xml"


def _read(p: Path) -> str:
    return p.read_text(encoding="utf-8")


def _write(p: Path, s: str) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(s, encoding="utf-8")


def inject_network_security() -> None:
    if not MANIFEST.exists():
        raise SystemExit(f"Missing {MANIFEST} — run `flutter create .` first.")
    if not OVERLAY_XML.exists():
        raise SystemExit(f"Missing overlay {OVERLAY_XML}")

    DEST_XML.parent.mkdir(parents=True, exist_ok=True)
    DEST_XML.write_bytes(OVERLAY_XML.read_bytes())

    m = _read(MANIFEST)
    if "networkSecurityConfig" in m:
        return

    m2, n = re.subn(
        r"<application",
        '<application android:networkSecurityConfig="@xml/network_security_config"',
        m,
        count=1,
    )
    if n != 1:
        raise SystemExit("Could not patch AndroidManifest.xml <application> tag")
    _write(MANIFEST, m2)


def inject_gradle_signing_groovy() -> None:
    if not APP_BUILD.exists():
        return

    s = _read(APP_BUILD)
    if "signingConfigs.release" in s:
        return

    block = r'''
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

android {
'''.lstrip()

    if "android {" not in s:
        raise SystemExit("Unexpected android/app/build.gradle format (missing android {)")

    s2 = s.replace("android {", block, 1)

    # Insert signingConfigs + release signingConfig if key.properties exists
    inject = r'''
    signingConfigs {
        release {
            if (keystorePropertiesFile.exists()) {
                keyAlias keystoreProperties['keyAlias']
                keyPassword keystoreProperties['keyPassword']
                storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
                storePassword keystoreProperties['storePassword']
            }
        }
    }
'''.rstrip()

    # Insert before buildTypes
    if "buildTypes" not in s2:
        raise SystemExit("Unexpected android/app/build.gradle format (missing buildTypes)")

    s3 = s2.replace("buildTypes {", inject + "\n    buildTypes {", 1)

    # wire release buildType
    s4 = re.sub(
        r"release\s*\{",
        "release {\n            signingConfig signingConfigs.release\n",
        s3,
        count=1,
    )
    _write(APP_BUILD, s4)


def main() -> None:
    inject_network_security()
    inject_gradle_signing_groovy()
    # Kotlin DSL templates vary; signing injection for .kts is left manual (see docs).


if __name__ == "__main__":
    main()
