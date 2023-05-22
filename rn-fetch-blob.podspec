require "json"
package = JSON.parse(File.read('package.json'))

Pod::Spec.new do |s|
  s.name             = 'rn-fetch-blob'
  s.version          = package['version']
  s.summary          = package['description']
  s.requires_arc = true
  s.license      = 'MIT'
  s.homepage     = 'n/a'
  s.source       = { :git => "https://github.com/joltup/rn-fetch-blob" }
  s.author       = 'Joltup'
  s.source_files = 'ios/**/*.{h,m}'
  s.platform     = :ios, "8.0"
  s.dependency 'React-Core'
  s.dependency 'QCloudCore'
  s.dependency 'QCloudCOSXML'
  s.dependency 'Reachability'
  s.frameworks = "CoreTelephony", "SystemConfiguration", "UIKit", "AVFoundation", "CoreMedia", "ImageIO"
  s.libraries = "c++", "c++abi", "z", "iconv", "icucore"

end
