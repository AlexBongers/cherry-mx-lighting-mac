import SwiftUI
import IOKit.hid
import ServiceManagement

// MARK: - Keys

struct Key: Identifiable, Hashable {
    let id: UInt64
    let name: String
}

private func kb(_ usage: UInt64, _ name: String) -> Key { Key(id: 0x7_0000_0000 | usage, name: name) }
private func media(_ usage: UInt64, _ name: String) -> Key { Key(id: 0xC_0000_0000 | usage, name: name) }

let allKeys: [Key] = {
    var keys: [Key] = [
        kb(0x39, "Caps Lock"), kb(0x29, "Esc"), kb(0x2B, "Tab"), kb(0x28, "Return"),
        kb(0x2C, "Spatie"), kb(0x2A, "Backspace"), kb(0x4C, "Forward Delete"),
        kb(0xE0, "Control (links)"), kb(0xE1, "Shift (links)"), kb(0xE2, "Option (links)"), kb(0xE3, "Command (links)"),
        kb(0xE4, "Control (rechts)"), kb(0xE5, "Shift (rechts)"), kb(0xE6, "Option (rechts)"), kb(0xE7, "Command (rechts)"),
        kb(0x46, "Print Screen"), kb(0x47, "Scroll Lock"), kb(0x48, "Pause"), kb(0x65, "Menu"),
        kb(0x49, "Insert"), kb(0x4A, "Home"), kb(0x4D, "End"), kb(0x4B, "Page Up"), kb(0x4E, "Page Down"),
        kb(0x50, "Pijl links"), kb(0x4F, "Pijl rechts"), kb(0x52, "Pijl omhoog"), kb(0x51, "Pijl omlaag"),
    ]
    for i in 0..<12 { keys.append(kb(0x3A + UInt64(i), "F\(i + 1)")) }
    keys += [
        media(0xE2, "Dempen"), media(0xE9, "Volume omhoog"), media(0xEA, "Volume omlaag"),
        media(0xCD, "Afspelen/Pauze"), media(0xB5, "Volgend nummer"), media(0xB6, "Vorig nummer"),
    ]
    return keys
}()

func keyName(_ id: UInt64) -> String { allKeys.first { $0.id == id }?.name ?? String(format: "0x%llX", id) }

struct Mapping: Codable, Identifiable, Equatable {
    var id = UUID()
    var src: UInt64
    var dst: UInt64
}

struct Preset: Identifiable {
    let id = UUID()
    let name: String
    let pairs: [(UInt64, UInt64)]
}

let presets: [Preset] = [
    Preset(name: "Caps Lock → Esc", pairs: [(0x7_0000_0039, 0x7_0000_0029)]),
    Preset(name: "Caps Lock → Control", pairs: [(0x7_0000_0039, 0x7_0000_00E0)]),
    Preset(name: "Windows-indeling → Mac (Option ⇄ Command)", pairs: [
        (0x7_0000_00E2, 0x7_0000_00E3), (0x7_0000_00E3, 0x7_0000_00E2),
        (0x7_0000_00E6, 0x7_0000_00E7), (0x7_0000_00E7, 0x7_0000_00E6),
    ]),
    Preset(name: "F7–F12 als mediatoetsen", pairs: [
        (0x7_0000_0040, 0xC_0000_00B6), (0x7_0000_0041, 0xC_0000_00CD), (0x7_0000_0042, 0xC_0000_00B5),
        (0x7_0000_0043, 0xC_0000_00E2), (0x7_0000_0044, 0xC_0000_00EA), (0x7_0000_0045, 0xC_0000_00E9),
    ]),
]

// MARK: - Store

let cherryVendorID = 0x046A

final class Store: ObservableObject {
    @Published var mappings: [Mapping] { didSet { save(); apply() } }
    @Published var cherryOnly: Bool { didSet { UserDefaults.standard.set(cherryOnly, forKey: "cherryOnly"); clearAll(); apply() } }
    @Published var status = ""
    private var manager: IOHIDManager?

    init() {
        if let data = UserDefaults.standard.data(forKey: "mappings"),
           let m = try? JSONDecoder().decode([Mapping].self, from: data) { mappings = m } else { mappings = [] }
        cherryOnly = UserDefaults.standard.object(forKey: "cherryOnly") as? Bool ?? true
        apply()
        watchDevice()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(mappings) { UserDefaults.standard.set(data, forKey: "mappings") }
    }

    func add(_ src: UInt64, _ dst: UInt64) {
        mappings.removeAll { $0.src == src }
        mappings.append(Mapping(src: src, dst: dst))
    }

    func apply(clear: Bool = false) {
        let list: [[String: NSNumber]] = clear ? [] : mappings.map {
            ["HIDKeyboardModifierMappingSrc": NSNumber(value: $0.src), "HIDKeyboardModifierMappingDst": NSNumber(value: $0.dst)]
        }
        run(["UserKeyMapping": list], matching: cherryOnly ? ["VendorID": cherryVendorID] : nil)
    }

    /// Reset both targets, so switching "only Cherry / all keyboards" leaves nothing behind.
    func clearAll() {
        run(["UserKeyMapping": []], matching: ["VendorID": cherryVendorID])
        run(["UserKeyMapping": []], matching: nil)
    }

    private func run(_ props: [String: Any], matching: [String: Any]?) {
        guard let json = try? JSONSerialization.data(withJSONObject: props),
              let jsonStr = String(data: json, encoding: .utf8) else { return }
        var args = ["property"]
        if let matching, let m = try? JSONSerialization.data(withJSONObject: matching), let ms = String(data: m, encoding: .utf8) {
            args += ["--matching", ms]
        }
        args += ["--set", jsonStr]
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        p.arguments = args
        let err = Pipe()
        p.standardError = err; p.standardOutput = Pipe()
        do {
            try p.run(); p.waitUntilExit()
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                self.status = p.terminationStatus == 0 ? "\(self.mappings.count) remap(s) actief" : "Fout: \(msg)"
            }
        } catch {
            DispatchQueue.main.async { self.status = "hidutil niet gestart: \(error.localizedDescription)" }
        }
    }

    /// hidutil mappings vanish when the keyboard is unplugged, so re-apply whenever a Cherry device appears.
    private func watchDevice() {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(mgr, [kIOHIDVendorIDKey: cherryVendorID] as CFDictionary)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, { context, _, _, _ in
            guard let context else { return }
            let store = Unmanaged<Store>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { store.apply() }
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = mgr
    }
}

// MARK: - UI

// Plain ObservableObject: the CommandLineTools toolchain has no SwiftUI macro plugin, so @State is unavailable.
final class FormState: ObservableObject {
    @Published var newSrc: UInt64 = allKeys[0].id
    @Published var newDst: UInt64 = allKeys[1].id
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
}

struct ContentView: View {
    @ObservedObject var store: Store
    @ObservedObject var lighting: Lighting
    @StateObject private var form = FormState()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cherry MX 10.0N RGB").font(.headline)

            GroupBox("Verlichting") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Modus", selection: $lighting.mode) {
                        ForEach(lightModes) { Text($0.name).tag($0.id) }
                    }
                    HStack {
                        Text("Snelheid")
                        Text("snel").font(.caption).foregroundStyle(.secondary)
                        Slider(value: $lighting.speed, in: 0...4, step: 1)
                        Text("traag").font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Helderheid")
                        Text("uit").font(.caption).foregroundStyle(.secondary)
                        Slider(value: $lighting.brightness, in: 0...4, step: 1)
                        Text("max").font(.caption).foregroundStyle(.secondary)
                    }
                    ColorPicker("Kleur", selection: $lighting.color, supportsOpacity: false)
                    HStack {
                        Button("Toepassen") { lighting.apply() }
                        Button("Uit") { lighting.turnOff() }
                        Button("Zoek toetsenbord") { lighting.describeInterfaces() }
                        Spacer()
                    }
                    if !lighting.status.isEmpty {
                        Text(lighting.status).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Voorinstellingen") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(presets) { p in
                        Button(p.name) { p.pairs.forEach { store.add($0.0, $0.1) } }.buttonStyle(.link)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Actieve remaps") {
                VStack(alignment: .leading, spacing: 6) {
                    if store.mappings.isEmpty { Text("Geen").foregroundStyle(.secondary) }
                    ForEach(store.mappings) { m in
                        HStack {
                            Text("\(keyName(m.src)) → \(keyName(m.dst))")
                            Spacer()
                            Button { store.mappings.removeAll { $0.id == m.id } } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Nieuwe remap") {
                HStack {
                    Picker("", selection: $form.newSrc) { ForEach(allKeys) { Text($0.name).tag($0.id) } }.labelsHidden()
                    Image(systemName: "arrow.right")
                    Picker("", selection: $form.newDst) { ForEach(allKeys) { Text($0.name).tag($0.id) } }.labelsHidden()
                    Button("Voeg toe") { store.add(form.newSrc, form.newDst) }
                }
            }

            Toggle("Alleen op het Cherry-toetsenbord", isOn: $store.cherryOnly)
            Toggle("Open bij inloggen", isOn: $form.launchAtLogin)
                .onChange(of: form.launchAtLogin) { _, on in
                    do { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
                    catch { store.status = "Inloggen-instelling mislukt: \(error.localizedDescription)" }
                }

            HStack {
                Text(store.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                Button("Alles uit") { store.mappings = [] }
                Button("Stop") { store.apply(clear: true); NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 420)
    }
}

@main
struct CherryRemapApp: App {
    init() { Lighting.handleCommandLine() }

    @StateObject private var store = Store()
    @StateObject private var lighting = Lighting()
    var body: some Scene {
        MenuBarExtra("Cherry Remap", systemImage: "keyboard") { ContentView(store: store, lighting: lighting) }
            .menuBarExtraStyle(.window)
    }
}
