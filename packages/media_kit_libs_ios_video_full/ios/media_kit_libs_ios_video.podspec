Pod::Spec.new do |s|
  system("make")

  s.name = 'media_kit_libs_ios_video'
  s.version = '1.0.4'
  s.summary = 'iOS dependency package for package:media_kit using full libmpv codecs'
  s.homepage = 'https://github.com/media-kit/media-kit.git'
  s.license = { :file => '../LICENSE' }
  s.author = { 'Hitesh Kumar Saini' => 'saini123hitesh@gmail.com' }
  s.source = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.vendored_frameworks = 'Frameworks/*.xcframework'
  s.platform = :ios, '9.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
  s.swift_version = '5.0'
end
