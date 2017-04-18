import Foundation
import AVFoundation

@objc(DBMeter) class DBMeter : CDVPlugin {

  fileprivate let LOG_TAG = "DBMeter"
  fileprivate let REQ_CODE = 0
  fileprivate var isListening: Bool = false
  fileprivate var audioRecorder: AVAudioRecorder!
  fileprivate var command: CDVInvokedUrlCommand!
  fileprivate var timer: DispatchSource!
  fileprivate var isTimerExists: Bool = false

  /**
   This plugin provides the decibel level from the microphone.
   */
  init(commandDelegate: CDVCommandDelegate) {
    super.init()
    self.commandDelegate = commandDelegate
  }

  /**
   Permits to free the memory from the audioRecord instance
   */
  func destroy(_ command: CDVInvokedUrlCommand) {
    if (self.isListening) {
      self.timer.suspend()
      self.isListening = false
    }

    self.command = nil

    if (self.audioRecorder != nil) {

      self.audioRecorder.stop()
      self.audioRecorder = nil

      let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK)
      self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
    } else {
      self.sendPluginError(command.callbackId, errorCode: PluginError.DBMETER_NOT_INITIALIZED, errorMessage: "DBMeter is not initialized")
    }
  }

  /**
   Starts listening the audio signal and sends dB values as a
   CDVPluginResult keeping the same calback alive.
   */
  func start(_ command: CDVInvokedUrlCommand) {
    self.commandDelegate!.run(inBackground: {
      self.command = command

      if (!self.isTimerExists) {
        self.timer = DispatchSource.makeTimerSource(flags: DispatchSource.TimerFlags(rawValue: UInt(0)), queue: DispatchQueue.global(priority: DispatchQueue.GlobalQueuePriority.default)) /*Migrator FIXME: Use DispatchSourceTimer to avoid the cast*/ as! DispatchSource
        self.timer.setEventHandler(handler: self.timerCallBack)
        self.timer.scheduleRepeating(deadline: .now() + .milliseconds(300), interval: .milliseconds(300), leeway: .milliseconds(1))

        // self.timer.setTimer(start: DispatchTime.now(), interval: NSEC_PER_SEC / 300, leeway: 0)
        self.isTimerExists = true
      }

      if (self.audioRecorder == nil) {
        let url: URL = URL(fileURLWithPath: "/dev/null")

        let settings: [String: Any] = [
          AVFormatIDKey: Int(kAudioFormatAppleLossless),
          AVSampleRateKey: 44100.0,
          AVNumberOfChannelsKey: 1 as NSNumber,
          AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
          let audioSession: AVAudioSession = AVAudioSession.sharedInstance()
          try audioSession.setCategory(AVAudioSessionCategoryRecord)
          try audioSession.setActive(true)

          self.audioRecorder = try AVAudioRecorder(url: url, settings: settings)
          self.audioRecorder.isMeteringEnabled = true
        } catch {
          self.sendPluginError(command.callbackId, errorCode: PluginError.DBMETER_NOT_INITIALIZED, errorMessage: "Error while initializing DBMeter")
        }
      }
      if (!self.isListening) {
        self.isListening = true
        self.audioRecorder.record()

        self.timer.resume()
      }
    })
  }

  /**
   Stops listening the audio signal.
   Even if stopped, the AVAudioRecorder instance still exist.
   To destroy this instance, please use the destroy method.
   */
  func stop(_ command: CDVInvokedUrlCommand) {
    self.commandDelegate!.run(inBackground: {
      if (self.isListening) {
        self.isListening = false

        if (self.audioRecorder != nil && self.audioRecorder.isRecording) {
          self.timer.suspend()
          self.audioRecorder.stop()
        }

        let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK)
        self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
      } else {
        self.sendPluginError(command.callbackId, errorCode: PluginError.DBMETER_NOT_LISTENING, errorMessage: "DBMeter is not listening")
      }
    })
  }

  /**
   Returns whether the DBMeter is listening.
   */
  func isListening(_ command: CDVInvokedUrlCommand?) -> Bool {
    if (command != nil) {
      let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: self.isListening)
      self.commandDelegate!.send(pluginResult, callbackId: command!.callbackId)
    }
    return self.isListening;
  }

  fileprivate func timerCallBack()  {
    autoreleasepool {
      if (self.isListening && self.audioRecorder != nil) {
        self.audioRecorder.updateMeters()

        let peakPowerForChannel = pow(10, (self.audioRecorder.averagePower(forChannel: 0) / 20))
        let db = Int32(round(20 * log10(peakPowerForChannel) + 90))

        let pluginResult:CDVPluginResult! = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: db)
        
            pluginResult.setKeepCallbackAs(true)
            self.commandDelegate!.send(pluginResult, callbackId: self.command.callbackId)
        
        
      }
    }
  }

  /**
   Convenient method to send plugin errors.
   */
  fileprivate func sendPluginError(_ callbackId: String, errorCode: PluginError, errorMessage: String) {
    let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: ["code": errorCode.hashValue, "message": errorMessage])
    self.commandDelegate!.send(pluginResult, callbackId: callbackId)
  }

  enum PluginError: String {
    case DBMETER_NOT_INITIALIZED = "0"
    case DBMETER_NOT_LISTENING = "1"
  }
}
