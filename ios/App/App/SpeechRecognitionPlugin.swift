import Foundation
import Capacitor
import Speech
import AVFoundation

/**
 * Native dictation for iOS.
 *
 * The community speech-recognition plugin has no Package.swift, so Capacitor 8's
 * SPM-only iOS build silently leaves it out. This plugin fills that gap with
 * Apple's own Speech framework and deliberately exposes the SAME JS surface the
 * community plugin uses on Android — `checkPermissions`, `requestPermissions`,
 * `start`, `stop`, and a `partialResults` event — so www/index.html needs no
 * per-platform branching.
 */
@objc(SpeechRecognitionPlugin)
public class SpeechRecognitionPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "SpeechRecognitionPlugin"
    public let jsName = "SpeechRecognition"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "available", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "start", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stop", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "checkPermissions", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "requestPermissions", returnType: CAPPluginReturnPromise)
    ]

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()
    private var pendingCall: CAPPluginCall?
    private var lastTranscript = ""

    // MARK: - permissions

    @objc func checkPermissions(_ call: CAPPluginCall) {
        call.resolve(["speechRecognition": permissionState()])
    }

    @objc func requestPermissions(_ call: CAPPluginCall) {
        SFSpeechRecognizer.requestAuthorization { _ in
            AVAudioSession.sharedInstance().requestRecordPermission { _ in
                DispatchQueue.main.async {
                    call.resolve(["speechRecognition": self.permissionState()])
                }
            }
        }
    }

    /// Both the speech engine and the microphone must be granted before we can listen.
    private func permissionState() -> String {
        let speech = SFSpeechRecognizer.authorizationStatus()
        let mic = AVAudioSession.sharedInstance().recordPermission

        if speech == .denied || speech == .restricted || mic == .denied { return "denied" }
        if speech == .authorized && mic == .granted { return "granted" }
        return "prompt"
    }

    @objc func available(_ call: CAPPluginCall) {
        let r = SFSpeechRecognizer(locale: Locale.current)
        call.resolve(["available": r?.isAvailable ?? false])
    }

    // MARK: - listening

    @objc func start(_ call: CAPPluginCall) {
        guard permissionState() == "granted" else {
            call.reject("Microphone or speech recognition permission is not granted")
            return
        }
        if task != nil { stopListening() }

        let language = call.getString("language") ?? Locale.current.identifier
        let partial = call.getBool("partialResults") ?? true

        recognizer = SFSpeechRecognizer(locale: Locale(identifier: language))
            ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer = recognizer, recognizer.isAvailable else {
            call.reject("Speech recognition isn't available for \(language)")
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            call.reject("Couldn't start the audio session: \(error.localizedDescription)")
            return
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = partial
        /* keep audio on the device when the OS can manage it — nothing leaves the phone */
        if #available(iOS 13, *) { req.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition }
        request = req

        /* The JS side treats start()'s resolution as "recognition ended", so the
           call is parked here and resolved once, from finish(). */
        pendingCall = call
        lastTranscript = ""

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let text = result.bestTranscription.formattedString
                self.lastTranscript = text
                if partial && !result.isFinal {
                    self.notifyListeners("partialResults", data: ["matches": [text]])
                }
                if result.isFinal { self.finish(matches: [text], error: nil) }
            }
            if error != nil {
                /* a stop() after real speech surfaces as an error too — keep the words */
                if self.lastTranscript.isEmpty {
                    self.finish(matches: [], error: error?.localizedDescription)
                } else {
                    self.finish(matches: [self.lastTranscript], error: nil)
                }
            }
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            self.request?.append(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            finish(matches: [], error: "Couldn't start the microphone: \(error.localizedDescription)")
        }
    }

    @objc func stop(_ call: CAPPluginCall) {
        stopListening()
        call.resolve()
    }

    /// Stops capture and lets the recognizer deliver whatever it has.
    private func stopListening() {
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.finish()
    }

    /// Resolves the parked start() call exactly once and tears everything down.
    private func finish(matches: [String], error: String?) {
        guard let call = pendingCall else { return }
        pendingCall = nil

        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        task = nil
        request = nil
        try? AVAudioSession.sharedInstance().setActive(false)

        DispatchQueue.main.async {
            if let error = error { call.reject(error) } else { call.resolve(["matches": matches]) }
        }
    }
}
