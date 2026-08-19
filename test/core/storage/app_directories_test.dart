import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/storage/app_directories.dart';

void main() {
  // These exact strings were read off a live sandbox container on 2026-08-19.
  // They are macOS's layout, not ours -- don't "tidy" them.
  test('builds the legacy container paths from home and bundle id', () {
    expect(
      legacyContainerSupportDirectory('/Users/x', 'com.hickory.hickory').path,
      '/Users/x/Library/Containers/com.hickory.hickory/Data/Library/'
      'Application Support/com.hickory.hickory',
    );
    expect(
      legacyContainerDocumentsDirectory('/Users/x', 'com.hickory.hickory').path,
      '/Users/x/Library/Containers/com.hickory.hickory/Data/Documents',
    );
  });

  test('derives the bundle id from the resolved support directory', () {
    expect(
      bundleIdOfSupportDirectory(
        '/Users/x/Library/Application Support/com.hickory.hickory',
      ),
      'com.hickory.hickory',
    );
  });

  test('derives the home directory from the resolved support directory', () {
    // Platform.environment['HOME'] is not usable for this: macOS redirects it
    // into the container for a sandboxed app, so it points at the very place we
    // are trying to migrate out of. The resolved support directory always ends
    // in <home>/Library/Application Support/<bundleId>.
    expect(
      homeOfSupportDirectory(
        '/Users/x/Library/Application Support/com.hickory.hickory',
      ),
      '/Users/x',
    );
  });

  test('recognises a support directory inside a sandbox container', () {
    expect(
      isSandboxContainerPath(
        '/Users/x/Library/Containers/com.hickory.hickory/Data/Library/'
        'Application Support/com.hickory.hickory',
      ),
      isTrue,
    );
    expect(
      isSandboxContainerPath(
        '/Users/x/Library/Application Support/com.hickory.hickory',
      ),
      isFalse,
    );
  });
}
