import SwiftUI
import IOKit.hid

// Protocol reverse-engineered from Cherry Utility traffic, see ../protocol-notes.md.
// Every change is five 64-byte output reports (report ID 4); only the second carries mode and speed.

struct LightMode: Identifiable, Hashable {
    let id: UInt8
    let name: String
}

let lightModes: [LightMode] = [
    LightMode(id: 0x00, name: "Wave"), LightMode(id: 0x01, name: "Spectrum"),
    LightMode(id: 0x02, name: "Breathing"), LightMode(id: 0x03, name: "Static"),
    LightMode(id: 0x0a, name: "Rolling"), LightMode(id: 0x0c, name: "Curve"),
    LightMode(id: 0x0f, name: "Scan"), LightMode(id: 0x12, name: "Radiation"),
    LightMode(id: 0x13, name: "Ripples"), LightMode(id: 0x15, name: "Single Key"),
]

final class Lighting: ObservableObject {
    @Published var mode: UInt8 { didSet { UserDefaults.standard.set(Int(mode), forKey: "lightMode") } }
    /// 0 = fast, 4 = slow, as the device expects it.
    @Published var speed: Double { didSet { UserDefaults.standard.set(speed, forKey: "lightSpeed") } }
    /// Byte 9 of the mode report; 4 is what Cherry Utility sent, so 0...4 is assumed.
    @Published var brightness: Double { didSet { UserDefaults.standard.set(brightness, forKey: "lightBrightness") } }
    @Published var color: Color { didSet { saveColor() } }
    @Published var status = ""

    private func saveColor() {
        let c = rgb
        UserDefaults.standard.set([Int(c.0), Int(c.1), Int(c.2)], forKey: "lightColor")
    }

    var rgb: (UInt8, UInt8, UInt8) {
        let n = NSColor(color).usingColorSpace(.sRGB) ?? .white
        func b(_ v: CGFloat) -> UInt8 { UInt8(max(0, min(255, Int((v * 255).rounded())))) }
        return (b(n.redComponent), b(n.greenComponent), b(n.blueComponent))
    }

    init() {
        mode = UInt8(UserDefaults.standard.object(forKey: "lightMode") as? Int ?? 0)
        speed = UserDefaults.standard.object(forKey: "lightSpeed") as? Double ?? 2
        brightness = UserDefaults.standard.object(forKey: "lightBrightness") as? Double ?? 4
        let c = UserDefaults.standard.array(forKey: "lightColor") as? [Int] ?? [255, 255, 255]
        color = Color(.sRGB, red: Double(c[0]) / 255, green: Double(c[1]) / 255, blue: Double(c[2]) / 255)
    }

    private func cherryDevices() -> [IOHIDDevice] {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(mgr, [kIOHIDVendorIDKey: cherryVendorID, kIOHIDProductIDKey: 0x00E2] as CFDictionary)
        IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        let set = IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice> ?? []
        return Array(set)
    }

    private func intProp(_ d: IOHIDDevice, _ key: String) -> Int {
        (IOHIDDeviceGetProperty(d, key as CFString) as? NSNumber)?.intValue ?? 0
    }

    /// The configuration interface is the one that takes 64-byte output reports.
    private func lightingDevice() -> IOHIDDevice? {
        cherryDevices().first { intProp($0, kIOHIDMaxOutputReportSizeKey) >= 63 }
    }

    func describeInterfaces() {
        let devs = cherryDevices()
        if devs.isEmpty { status = L("No Cherry keyboard found (is it still attached to a VM?)"); return }
        let lines = devs.map {
            "page \(intProp($0, kIOHIDPrimaryUsagePageKey)) usage \(intProp($0, kIOHIDPrimaryUsageKey)) out \(intProp($0, kIOHIDMaxOutputReportSizeKey))"
        }
        status = L("%d interface(s): %@", devs.count, lines.joined(separator: "; "))
    }

    /// Switches all lighting off without touching the stored settings, so `apply()` brings them back.
    func turnOff() { apply(brightnessOverride: 0) }

    func apply() { apply(brightnessOverride: nil) }

    private func apply(brightnessOverride: UInt8?) {
        guard let dev = lightingDevice() else {
            status = L("No lighting interface found")
            return
        }
        guard IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            status = L("Opening failed: allow the app under Privacy & Security > Input Monitoring")
            return
        }
        defer { IOHIDDeviceClose(dev, IOOptionBits(kIOHIDOptionsTypeNone)) }

        let speedByte = UInt8(max(0, min(4, Int(speed.rounded()))))
        let brightnessByte = brightnessOverride ?? UInt8(max(0, min(4, Int(brightness.rounded()))))
        let rgb = self.rgb
        var frames: [[UInt8]] = [
            [0x04, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x55],
            [0x04, 0x00, 0x00, 0x06, 0x08, 0x01, 0x00, 0x55, mode, brightnessByte, speedByte, 0x01, 0x00, rgb.0, rgb.1, rgb.2],
            [0x04, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x55],
            [0x04, 0x00, 0x00, 0x05, 0x01, 0x15, 0x00, 0x55],
            [0x04, 0x00, 0x00, 0x05, 0x08, 0x01, 0x00, 0x55],
        ]
        for i in frames.indices { frames[i] += [UInt8](repeating: 0, count: 64 - frames[i].count) }

        for frame in frames {
            let r = IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, CFIndex(frame[0]), frame, frame.count)
            guard r == kIOReturnSuccess else {
                status = L("Writing failed (0x%08X)", r)
                return
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        status = brightnessOverride == 0 ? L("Lighting off") : L("Lighting set")
    }
}

extension Lighting {
    /// `CherryRemap --apply <modus hex> <snelheid 0-4> [helderheid 0-4] [kleur RRGGBB]`: apply once, log the result, quit.
    static func handleCommandLine() {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: "--apply") else { return }
        let l = Lighting()
        if i + 1 < a.count, let m = UInt8(a[i + 1], radix: 16) { l.mode = m }
        if i + 2 < a.count, let sp = Double(a[i + 2]) { l.speed = sp }
        if i + 3 < a.count, let br = Double(a[i + 3]) { l.brightness = br }
        if i + 4 < a.count, a[i + 4].count == 6, let v = UInt32(a[i + 4], radix: 16) {
            l.color = Color(.sRGB, red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255)
        }
        l.describeInterfaces()
        let found = l.status
        l.apply()
        try? "\(found)\n\(l.status)\n".write(toFile: "/private/tmp/cherry-lighting.log", atomically: true, encoding: .utf8)
        exit(0)
    }
}
