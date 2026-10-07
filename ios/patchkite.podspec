#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint patchkite.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'patchkite'
  s.version          = '1.0.0'
  s.summary          = 'Patchkite OTA updates for Flutter (no-op on iOS).'
  s.description      = <<-DESC
iOS side of the Patchkite Flutter plugin. Apple forbids loading new AOT code,
so the API reports "up to date" on iOS while keeping the Dart API identical.
                       DESC
  s.homepage         = 'https://github.com/patchkite/flutter'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Patchkite' => 'https://github.com/patchkite' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'patchkite_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
