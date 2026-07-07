#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint activity_tracker.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'activity_tracker'
  s.version          = '0.0.1'
  s.summary          = 'A new Flutter plugin project.'
  s.description      = <<-DESC
A new Flutter plugin project.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }

  s.source           = { :path => '.' }
  s.source_files = 'activity_tracker/Sources/activity_tracker/**/*'

  # If your plugin requires a privacy manifest, for example if it collects user
  # data, update the PrivacyInfo.xcprivacy file to describe your plugin's
  # privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'activity_tracker_privacy' => ['activity_tracker/Sources/activity_tracker/PrivacyInfo.xcprivacy']}

  s.dependency 'FlutterMacOS'
  # Needed for the Accessibility APIs (AXUIElement, AXIsProcessTrusted) used
  # to read window titles.
  s.frameworks = 'ApplicationServices'

  s.platform = :osx, '10.11'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
