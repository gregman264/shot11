import AVFoundation
import UIKit
import SwiftUI

/// Caméra arrière avec balance des blancs VERROUILLÉE.
/// Les gains de blanc sont mesurés une fois, puis imposés à toutes les photos
/// (et ré-imposés juste avant chaque prise si iOS les avait libérés).
final class CameraService: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "shot11.camera")
    private var device: AVCaptureDevice?
    private var configured = false
    private var lockedGains: AVCaptureDevice.WhiteBalanceGains?
    private var captureCompletion: ((Data?) -> Void)?
    private var calibrating = false

    @Published var authorized = true
    @Published var running = false
    @Published var whiteBalanceLocked = false

    // MARK: Démarrage / arrêt

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { ok in
                DispatchQueue.main.async { self.authorized = ok }
                if ok { self.setupAndRun() }
            }
        default:
            DispatchQueue.main.async { self.authorized = false }
        }
    }

    func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
            DispatchQueue.main.async { self.running = false }
        }
    }

    private func setupAndRun() {
        queue.async {
            if !self.configured { self.configure() }
            guard self.configured else { return }
            if !self.session.isRunning { self.session.startRunning() }
            DispatchQueue.main.async { self.running = self.session.isRunning }
            self.applyWhiteBalance()
        }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        guard let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: dev),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        session.commitConfiguration()
        device = dev
        do {
            try dev.lockForConfiguration()
            if dev.isFocusModeSupported(.continuousAutoFocus) {
                dev.focusMode = .continuousAutoFocus
            }
            dev.unlockForConfiguration()
        } catch {}
        configured = true
    }

    // MARK: Balance des blancs

    private func clamped(_ g: AVCaptureDevice.WhiteBalanceGains, _ d: AVCaptureDevice) -> AVCaptureDevice.WhiteBalanceGains {
        let m = d.maxWhiteBalanceGain
        return AVCaptureDevice.WhiteBalanceGains(
            redGain: max(1.0, min(g.redGain, m)),
            greenGain: max(1.0, min(g.greenGain, m)),
            blueGain: max(1.0, min(g.blueGain, m)))
    }

    /// À appeler sur `queue`.
    private func applyWhiteBalance() {
        guard let d = device else { return }
        if let g = lockedGains {
            setLocked(g, d, then: nil)
        } else if !calibrating {
            calibrating = true
            DispatchQueue.main.async { self.whiteBalanceLocked = false }
            queue.asyncAfter(deadline: .now() + 1.3) { self.lockCurrent() }
        }
    }

    /// À appeler sur `queue` : fige les gains actuels.
    private func lockCurrent() {
        calibrating = false
        guard let d = device else { return }
        let g = clamped(d.deviceWhiteBalanceGains, d)
        lockedGains = g
        UserDefaults.standard.set([g.redGain, g.greenGain, g.blueGain], forKey: "wbGains")
        setLocked(g, d, then: nil)
    }

    private func setLocked(_ g: AVCaptureDevice.WhiteBalanceGains, _ d: AVCaptureDevice, then done: (() -> Void)?) {
        do {
            try d.lockForConfiguration()
            if d.isLockingWhiteBalanceWithCustomDeviceGainsSupported {
                d.setWhiteBalanceModeLocked(with: clamped(g, d)) { _ in
                    done?()
                }
            } else {
                done?()
            }
            d.unlockForConfiguration()
            DispatchQueue.main.async { self.whiteBalanceLocked = true }
        } catch {
            done?()
        }
    }

    /// Mesure de nouveau le blanc (si la lumière a changé) puis le verrouille.
    func recalibrateWhiteBalance() {
        queue.async {
            guard let d = self.device else { return }
            self.lockedGains = nil
            self.calibrating = true
            UserDefaults.standard.removeObject(forKey: "wbGains")
            DispatchQueue.main.async { self.whiteBalanceLocked = false }
            do {
                try d.lockForConfiguration()
                if d.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    d.whiteBalanceMode = .continuousAutoWhiteBalance
                }
                d.unlockForConfiguration()
            } catch {}
            self.queue.asyncAfter(deadline: .now() + 1.5) { self.lockCurrent() }
        }
    }

    /// Reprise d'un article en cours : on remet exactement les mêmes gains.
    func restoreSavedGains() {
        guard let a = UserDefaults.standard.array(forKey: "wbGains") as? [Float], a.count == 3 else { return }
        queue.async {
            self.lockedGains = AVCaptureDevice.WhiteBalanceGains(redGain: a[0], greenGain: a[1], blueGain: a[2])
        }
    }

    // MARK: Prise de vue

    func capture(_ completion: @escaping (Data?) -> Void) {
        queue.async {
            self.captureCompletion = completion
            if let g = self.lockedGains, let d = self.device, d.whiteBalanceMode != .locked {
                self.setLocked(g, d, then: { self.fire() })
            } else {
                self.fire()
            }
        }
    }

    private func fire() {
        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        settings.flashMode = .off
        if let c = photoOutput.connection(with: .video), c.isVideoOrientationSupported {
            c.videoOrientation = .portrait
        }
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
}

extension CameraService: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data: Data? = (error == nil) ? photo.fileDataRepresentation() : nil
        let cb = captureCompletion
        captureCompletion = nil
        DispatchQueue.main.async { cb?(data) }
    }
}

// MARK: Aperçu

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.backgroundColor = .black
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
