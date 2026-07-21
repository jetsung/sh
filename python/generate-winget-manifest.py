#!/usr/bin/env python3

#============================================================
# File: generate-winget-manifest.py
# Description: 从 GitHub Release 资源生成 WinGet 清单文件
# URL: https://fx4.cn/winget
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2026-07-21
# UpdatedAt: 2026-07-21
#============================================================

import argparse
import hashlib
import json
import os
import sys
import urllib.request
from pathlib import Path

MANIFEST_VERSION = "1.12.0"
GITHUB_API_BASE = os.environ.get("GITHUB_API_BASE", "https://api.github.com").rstrip("/")


def github_api(url: str) -> dict:
    req = urllib.request.Request(url)
    req.add_header("User-Agent", "generate-winget-manifest/1.0")
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    if token := os.environ.get("GITHUB_TOKEN"):
        req.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read().decode("utf-8"))


def download_and_hash(url: str) -> str:
    sha256 = hashlib.sha256()
    req = urllib.request.Request(url)
    req.add_header("User-Agent", "generate-winget-manifest/1.0")
    with urllib.request.urlopen(req, timeout=120) as resp:
        while chunk := resp.read(8192):
            sha256.update(chunk)
    return sha256.hexdigest().upper()


def arch_from_filename(filename: str) -> str | None:
    """Map Rust-style Windows target arch to WinGet architecture."""
    if "x86_64" in filename or "x64" in filename:
        return "x64"
    if "aarch64" in filename or "arm64" in filename:
        return "arm64"
    if "x86" in filename or "i386" in filename or "i686" in filename:
        return "x86"
    return None


LOCALE_ALIASES = {"cn": "zh-CN"}


def normalize_locale(code: str) -> str:
    """Normalize a locale code. Only the alias ``cn`` expands to ``zh-CN``;
    any other value is treated as a full locale code (e.g. zh-CN, zh-HK, en-UK)."""
    code = code.strip()
    return LOCALE_ALIASES.get(code.lower(), code)


def get_release(repo: str, version: str | None) -> tuple[str, str, list[dict]]:
    if version:
        url = f"{GITHUB_API_BASE}/repos/{repo}/releases/tags/v{version}"
    else:
        url = f"{GITHUB_API_BASE}/repos/{repo}/releases/latest"
    release = github_api(url)
    tag = release["tag_name"]
    version_no_v = tag.lstrip("v")
    release_date = release.get("published_at", "")[:10]
    return version_no_v, release_date, release.get("assets", [])


def get_repo_info(repo: str) -> dict:
    return github_api(f"{GITHUB_API_BASE}/repos/{repo}")


def get_user_info(user: str) -> dict:
    return github_api(f"{GITHUB_API_BASE}/users/{user}")


def asset_digest(asset: dict) -> str:
    digest = asset.get("digest", "")
    if digest and digest.startswith("sha256:"):
        return digest.split(":", 1)[1].upper()
    print(f"  Downloading {asset['name']} to compute SHA256...")
    return download_and_hash(asset["browser_download_url"])


def generate_installer(
    package_id: str,
    version: str,
    repo: str,
    assets: list[dict],
    exe_name: str,
    release_date: str = "",
) -> str:
    arch_order = {"x86": 0, "x64": 1, "arm64": 2}
    installers = []
    for asset in assets:
        name = asset["name"]
        if not name.endswith(".zip"):
            continue
        arch = arch_from_filename(name)
        if not arch:
            continue
        url = asset["browser_download_url"]
        digest = asset_digest(asset)
        yaml_block = (
            f"  - Architecture: {arch}\n"
            f"    InstallerUrl: {url}\n"
            f"    InstallerSha256: {digest}"
        )
        installers.append((arch_order.get(arch, 99), yaml_block))

    if not installers:
        raise RuntimeError("No Windows zip assets found in release")

    installers.sort(key=lambda item: item[0])
    installers = [item[1] for item in installers]

    return f"""# yaml-language-server: $schema=https://aka.ms/winget-manifest.installer.{MANIFEST_VERSION}.schema.json

PackageIdentifier: {package_id}
PackageVersion: {version}
InstallerType: zip
NestedInstallerType: portable
NestedInstallerFiles:
  - RelativeFilePath: {exe_name}
ReleaseDate: {release_date}
Installers:
{"\n".join(installers)}
ManifestType: installer
ManifestVersion: {MANIFEST_VERSION}
"""


def generate_locale(
    package_id: str,
    version: str,
    repo: str,
    repo_info: dict,
    locale: str = "en-US",
    publisher: str | None = None,
    author: str | None = None,
    package_name: str | None = None,
    short_description: str | None = None,
    license_url: str | None = None,
    copyright: str | None = None,
    copyright_url: str | None = None,
    release_notes_url: str | None = None,
    tags: list[str] | None = None,
    documentations: list[tuple[str, str]] | None = None,
    is_default_locale: bool = True,
) -> str:
    user, project = repo.split("/", 1)
    publisher = publisher or user
    author = author or publisher
    package_name = package_name or project
    homepage = (repo_info.get("homepage") or f"https://github.com/{repo}").rstrip("/")
    description = short_description if short_description is not None else (repo_info.get("description") or "")
    license_name = repo_info.get("license", {}).get("spdx_id") or ""
    license_url = license_url or f"https://github.com/{repo}/blob/main/LICENSE"
    copyright = copyright or f"Copyright (c) {publisher}"
    copyright_url = copyright_url or license_url
    release_notes_url = release_notes_url or f"https://github.com/{repo}/releases/tag/v{version}"
    tags = tags or ["cli", "tool"]
    tags_yaml = "\n".join(f"  - {tag}" for tag in tags)
    docs_yaml = "\n".join(
        f"- DocumentLabel: {label}\n  DocumentUrl: {url}" for label, url in documentations
    ) if documentations else ""

    schema_kind = "defaultLocale" if is_default_locale else "locale"
    manifest_type = "defaultLocale" if is_default_locale else "locale"

    lines = [
        f"PackageIdentifier: {package_id}",
        f"PackageVersion: {version}",
        f"PackageLocale: {locale}",
        f"Publisher: {publisher}",
        f"PublisherUrl: https://github.com/{user}",
        f"PublisherSupportUrl: https://github.com/{repo}/issues",
        f"Author: {author}",
        f"PackageName: {package_name}",
        f"PackageUrl: {homepage}",
    ]
    if is_default_locale:
        lines += [
            f"License: {license_name}",
            f"LicenseUrl: {license_url}",
            f"Copyright: {copyright}",
            f"CopyrightUrl: {copyright_url}",
        ]
    lines += [
        f"ShortDescription: {description}",
        f"Moniker: {package_name}",
        "Tags:",
        tags_yaml,
        f"ReleaseNotesUrl: {release_notes_url}",
    ]
    if documentations:
        lines.append(docs_yaml)
    lines += [
        f"ManifestType: {manifest_type}",
        f"ManifestVersion: {MANIFEST_VERSION}",
    ]
    body = "\n".join(lines)

    return f"""# yaml-language-server: $schema=https://aka.ms/winget-manifest.{schema_kind}.{MANIFEST_VERSION}.schema.json

{body}
"""



def generate_version(package_id: str, version: str, locale: str = "en-US") -> str:
    return f"""# yaml-language-server: $schema=https://aka.ms/winget-manifest.version.{MANIFEST_VERSION}.schema.json

PackageIdentifier: {package_id}
PackageVersion: {version}
DefaultLocale: {locale}
ManifestType: version
ManifestVersion: {MANIFEST_VERSION}
"""


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate WinGet manifest files from a GitHub release.",
        epilog="""Examples:
    python generate-winget-manifest.py jetsung/xskill
    python generate-winget-manifest.py jetsung/xskill 0.1.0
    python generate-winget-manifest.py jetsung/xskill --exe-name xskill.exe --tags cli,tool
    python generate-winget-manifest.py certimate-me/certimate --lang zh-CN,zh-HK,en-UK
    python generate-winget-manifest.py certimate-me/certimate --lang cn
""",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("repo", help="Repository in the form user/repo")
    parser.add_argument("version", nargs="?", help="Version to use (default: latest release)")
    parser.add_argument(
        "--output-dir",
        default="manifests",
        help="Output directory for generated manifests (default: manifests)",
    )
    parser.add_argument(
        "--locale",
        default="en-US",
        help="Default locale (default: en-US)",
    )
    parser.add_argument(
        "--exe-name",
        default=None,
        help="Name of the executable inside the zip (default: repo.exe)",
    )
    parser.add_argument(
        "--publisher",
        default=None,
        help="Publisher name (default: GitHub user's display name)",
    )
    parser.add_argument(
        "--author",
        default=None,
        help="Author name (default: same as publisher)",
    )
    parser.add_argument(
        "--license-url",
        default=None,
        help="License URL (default: https://github.com/user/repo/blob/main/LICENSE)",
    )
    parser.add_argument(
        "--copyright",
        default=None,
        help="Copyright text (default: 'Copyright (c) <publisher>')",
    )
    parser.add_argument(
        "--copyright-url",
        default=None,
        help="Copyright URL (default: same as license-url)",
    )
    parser.add_argument(
        "--release-notes-url",
        default=None,
        help="Release notes URL (default: https://github.com/user/repo/releases/tag/v<version>)",
    )
    parser.add_argument(
        "--tags",
        default=None,
        help="Comma-separated tags (default: cli,tool)",
    )
    parser.add_argument(
        "--doc",
        action="append",
        default=None,
        metavar="LABEL|URL",
        help="Documentation entry in 'Label|URL' form. Repeatable.",
    )
    parser.add_argument(
        "--lang",
        action="append",
        default=None,
        metavar="CODE",
        help="Additional locale manifests to generate, e.g. zh-CN,zh-HK,en-UK. "
        "Only the shorthand 'cn' is expanded to 'zh-CN'; other values must be full locale codes. "
        "Repeatable or comma-separated.",
    )
    args = parser.parse_args()

    if "/" not in args.repo:
        print("Error: repo must be in the form user/repo", file=sys.stderr)
        return 1

    user, repo = args.repo.split("/", 1)
    package_id = f"{user}.{repo}"
    exe_name = args.exe_name or f"{repo}.exe"

    print(f"Fetching user info for {user}...")
    user_info = get_user_info(user)
    default_publisher = user_info.get("name") or user
    publisher = args.publisher or default_publisher
    print(f"Publisher: {publisher}")

    print(f"Fetching release info for {args.repo}...")
    version, release_date, assets = get_release(args.repo, args.version)
    print(f"Using version: {version}")
    print(f"Release date: {release_date}")

    print("Fetching repository metadata...")
    repo_info = get_repo_info(args.repo)

    output_dir = Path(args.output_dir) / user[0].lower() / user / repo / version
    output_dir.mkdir(parents=True, exist_ok=True)

    print("Generating installer manifest (downloading assets to hash)...")
    installer_yaml = generate_installer(package_id, version, args.repo, assets, exe_name, release_date)
    (output_dir / f"{package_id}.installer.yaml").write_text(installer_yaml, encoding="utf-8")

    tags = [t.strip() for t in args.tags.split(",")] if args.tags else None
    documentations = None
    if args.doc:
        documentations = []
        for entry in args.doc:
            if "|" not in entry:
                print(f"Error: --doc must be 'Label|URL', got: {entry}", file=sys.stderr)
                return 1
            label, url = entry.split("|", 1)
            documentations.append((label.strip(), url.strip()))
    locale_yaml = generate_locale(
        package_id,
        version,
        args.repo,
        repo_info,
        locale=args.locale,
        publisher=publisher,
        author=args.author,
        license_url=args.license_url,
        copyright=args.copyright,
        copyright_url=args.copyright_url,
        release_notes_url=args.release_notes_url,
        tags=tags,
        documentations=documentations,
    )
    (output_dir / f"{package_id}.locale.{args.locale}.yaml").write_text(locale_yaml, encoding="utf-8")

    if args.lang:
        requested = []
        for item in args.lang:
            requested.extend(part.strip() for part in item.split(",") if part.strip())
        generated = set()
        for raw in requested:
            locale = normalize_locale(raw)
            if locale == args.locale or locale in generated:
                continue
            generated.add(locale)
            extra_yaml = generate_locale(
                package_id,
                version,
                args.repo,
                repo_info,
                locale=locale,
                publisher=publisher,
                author=args.author,
                license_url=args.license_url,
                copyright=args.copyright,
                copyright_url=args.copyright_url,
                release_notes_url=args.release_notes_url,
                tags=tags,
                documentations=documentations,
                is_default_locale=False,
            )
            (output_dir / f"{package_id}.locale.{locale}.yaml").write_text(extra_yaml, encoding="utf-8")
            print(f"Generated {locale} locale manifest.")

    version_yaml = generate_version(package_id, version, args.locale)
    (output_dir / f"{package_id}.yaml").write_text(version_yaml, encoding="utf-8")

    print(f"Manifests written to: {output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
