Pod::Spec.new do |s|
  s.name             = 'MoolreCore'
  s.version          = '1.0.0'
  s.summary          = 'Core models and networking shared by every Moolre iOS SDK module.'
  s.description      = <<-DESC
    The Moolre iOS SDK brings Moolre services to UIKit and SwiftUI apps,
    starting with hosted Moolre checkout for payments. MoolreCore is one module of
    the SDK.
  DESC
  s.homepage         = 'https://github.com/moolrehq/moolre-ios-sdk'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Moolre' => 'https://moolre.com' }
  s.source           = { :git => 'https://github.com/moolrehq/moolre-ios-sdk.git', :tag => "v#{s.version}" }

  s.ios.deployment_target = '15.0'
  s.swift_versions   = ['5.0']
  s.module_name      = 'MoolreCore'
  s.source_files     = 'Sources/MoolreCore/**/*.swift'
  s.resource_bundles = { 'MoolreCore_Privacy' => ['Sources/MoolreCore/PrivacyInfo.xcprivacy'] }

end
