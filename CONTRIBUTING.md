# Contributing to Hickory

Thanks for your interest in contributing! This document covers how to set up your development environment and how to submit changes.

By participating in this project, you agree to abide by the [Code of Conduct](CODE_OF_CONDUCT.md).

## Code of Conduct

See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## Getting Started

### Prerequisites

- [Flutter](https://docs.flutter.dev/get-started/install) 3.38+ (Dart 3.12+), stable channel
- macOS or Windows (required to run and test the desktop-only features: activity tracking, sync-folder access)

### Setup

```bash
git clone https://github.com/mordilion/Hickory.git
cd Hickory
flutter pub get
```

If you change any `@riverpod`- or Drift-annotated code, regenerate the generated sources:

```bash
dart run build_runner build --delete-conflicting-outputs
```

### Running

```bash
flutter run -d macos   # or: flutter run -d windows
```

## Development Workflow

1. Fork the repository and create a branch off `main` (e.g. `feat/short-description` or `fix/short-description`).
2. Make your change, keeping it focused on a single logical concern.
3. Add or update tests for any behavior change.
4. Run the full check suite locally (see below) before opening a pull request.
5. Open a pull request against `main` describing the change and the motivation behind it.

## Coding Conventions

- Follow the lints enabled in `analysis_options.yaml` (`package:flutter_lints`); run `flutter analyze` before submitting.
- Format code with `dart format .`.
- Keep the feature-first structure under `lib/features/<feature>/`; shared code belongs in `lib/core/` or `lib/data/`.
- User-facing strings must be localized via ARB files in `lib/l10n/` (`app_de.arb` is the source locale) — never hardcode UI text.
- Never log or persist secrets (Jira credentials, tokens); they must go through `flutter_secure_storage`.

## Testing

```bash
flutter analyze
flutter test
```

Package-local tests (e.g. `packages/sync_engine`) can be run from within that package directory:

```bash
cd packages/sync_engine && dart test
```

## Commit Messages

This project follows [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/):

```
<type>[optional scope]: <description>
```

Common types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`. Use the imperative mood ("add", not "added"), and keep the description under 72 characters.

## Pull Request Process

- Ensure `flutter analyze` and `flutter test` pass.
- Update documentation (README, ARB files, code comments) alongside behavior changes.
- Keep pull requests focused; unrelated changes should be split into separate PRs.
- A maintainer will review your PR and may request changes before merging.

## Reporting Bugs & Requesting Features

Please use the [issue templates](.github/ISSUE_TEMPLATE) when opening a new issue on [GitHub Issues](https://github.com/mordilion/Hickory/issues).
