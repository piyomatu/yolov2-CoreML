import UIKit
import AVFoundation
import CoreVideo

//protocal
public protocol VideoCaptureDelegate: class {
  func videoCapture(_ capture: VideoCapture, didCaptureVideoFrame: CVPixelBuffer?, timestamp: CMTime)
}


public class VideoCapture: NSObject {
    
  public var previewLayer: AVCaptureVideoPreviewLayer?
  public weak var delegate: VideoCaptureDelegate?
  public var desiredFrameRate = 30
    // デバイスからの入力と出力を管理するオブジェクトの作成
  let captureSession = AVCaptureSession()
    //ビデオデータ出力
  let videoOutput = AVCaptureVideoDataOutput()
    //DispatchQueue: 非同期処理 = 処理を同時に行い、早いものから出力可能
  let queue = DispatchQueue(label: "net.machinethink.camera-queue")
    
   
    
    
    //@escapingは関数の呼び出しが終了した後でもクロージャが使い続ける可能性がある場合に必要な修飾詞
    //= .medium, → .hight に変更(映像の荒さを改善したいため。)
  public func setUp(sessionPreset: AVCaptureSession.Preset = .high,
                    completion: @escaping (Bool) -> Void) {
    queue.async {
      let success = self.setUpCamera(sessionPreset: sessionPreset)
      DispatchQueue.main.async {
        completion(success)
      }
    }
  }
    
    
    //カメラの設定
  func setUpCamera(sessionPreset: AVCaptureSession.Preset) -> Bool {
    //設定の開始
    captureSession.beginConfiguration()
    // sessionPreset: キャプチャ・クオリティの設定
    captureSession.sessionPreset = sessionPreset
    //captureDeviceをビデオに設定
    guard let captureDevice = AVCaptureDevice.default(for: AVMediaType.video) else {
      print("Error: no video devices available")
      return false
    }
    //ビデオ入力をcaptureDeviceに設定
    guard let videoInput = try? AVCaptureDeviceInput(device: captureDevice) else {
      print("Error: could not create AVCaptureDeviceInput")
      return false
    }
    // 指定した入力をセッションに追加
    if captureSession.canAddInput(videoInput) {
      captureSession.addInput(videoInput)
    }
    //キャプチャされたビデオを表示するアニメーションレイヤー
    //デバイスにビデオを表示させる
    //.resizeAspect:アスペクトサイズの変更(縦横比)
    //.portrait: プレビューレイヤの表示の向きを設定
    let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
    previewLayer.videoGravity = AVLayerVideoGravity.resizeAspect
    previewLayer.connection?.videoOrientation = .portrait
    self.previewLayer = previewLayer
    
    //バッファに使用される1つ以上のピクセル形式タイプ
    //ピクセルフォーマットを 32bit BGR + A
    let settings: [String : Any] = [
      kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32BGRA),
    ]

    //AVCaptureVideoDataOutput:動画フレームデータを出力に設定
    videoOutput.videoSettings = settings
    //遅いビデオフレームを常に破棄する
    // リアルタイムキャプチャーしながら画像処理をするときは必須
    videoOutput.alwaysDiscardsLateVideoFrames = true
    // フレームをキャプチャするためのサブスレッド用のシリアルキューを用意
    videoOutput.setSampleBufferDelegate(self, queue: queue)
    if captureSession.canAddOutput(videoOutput) {
      captureSession.addOutput(videoOutput)
    }

    // We want the buffers to be in portrait orientation otherwise they are
    // rotated by 90 degrees. Need to set this _after_ addOutput()!
    //画面が90度回転してしまう対策
    videoOutput.connection(with: AVMediaType.video)?.videoOrientation = .portrait

    // Based on code from https://github.com/dokun1/Lumina/
    //ビデオのサイズを（エンコードされたピクセルで）返します。
    let activeDimensions = CMVideoFormatDescriptionGetDimensions(captureDevice.activeFormat.formatDescription)
    for vFormat in captureDevice.formats {
      let dimensions = CMVideoFormatDescriptionGetDimensions(vFormat.formatDescription)
      let ranges = vFormat.videoSupportedFrameRateRanges as [AVFrameRateRange]
      if let frameRate = ranges.first,
         frameRate.maxFrameRate >= Float64(desiredFrameRate) &&
         frameRate.minFrameRate <= Float64(desiredFrameRate) &&
         activeDimensions.width == dimensions.width &&
         activeDimensions.height == dimensions.height &&
         CMFormatDescriptionGetMediaSubType(vFormat.formatDescription) == 875704422 { // meant for full range 420f
        //deviceをロックして設定(カメラの設定を触るときはデバイスをロックする)
        //カメラにフレームレートを設定する
        do {
          try captureDevice.lockForConfiguration()
          captureDevice.activeFormat = vFormat as AVCaptureDevice.Format
          captureDevice.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: Int32(desiredFrameRate))
          captureDevice.activeVideoMaxFrameDuration = CMTimeMake(value: 1, timescale: Int32(desiredFrameRate))
        // デバイスのアンロック
          captureDevice.unlockForConfiguration()
          break
        } catch {
          continue
        }
      }
    }
    print("Camera format:", captureDevice.activeFormat)
    //設定を合わせる
    captureSession.commitConfiguration()
    return true
  }
   
    
    
    
    
    //スタート
  public func start() {
    if !captureSession.isRunning {
      captureSession.startRunning()
    }
  }
    //ストップ
  public func stop() {
    if captureSession.isRunning {
      captureSession.stopRunning()
    }
  }
}
//extension:拡張機能
//ビデオフレームデータを処理するデリゲートメソッド
//新しいビデオフレームが書き込まれたことをデリゲートに通知
extension VideoCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
  public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    //現在時刻
    let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
    delegate?.videoCapture(self, didCaptureVideoFrame: imageBuffer, timestamp: timestamp)
  }
  //ビデオフレームが破棄されたことをデリゲートに通知
  public func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    //print("dropped frame")
  }
    
    
    
    
    
}
