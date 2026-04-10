import UIKit
import Flutter
import AVFoundation // এটি যোগ করুন

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // অডিও সেশন সেটআপ
    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}