Pod::Spec.new do |s|
  s.name             = 'uaepass'
  s.version          = '0.0.1'
  s.summary          = 'UAE PASS authentication for Flutter on iOS.'
  s.homepage         = 'https://github.com/Alkhajeh/UAEPass'
  s.license          = { :file => '../LICENSE' }
  s.author           = 'Ali Alkhajeh'
  s.source           = { :path => '.' }
  s.source_files     = 'uaepass/Sources/uaepass/**/*.swift'
  s.dependency 'Flutter'
  s.dependency 'webview_flutter_wkwebview'
  s.platform = :ios, '15.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
