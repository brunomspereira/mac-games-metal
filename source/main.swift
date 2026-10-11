import AppKit
import UniformTypeIdentifiers

enum LauncherError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let text) = self { return text }
        return nil
    }
}

func checkExecutable(_ url: URL) throws -> String {
    guard url.pathExtension.lowercased() == "exe" else {
        throw LauncherError.message("Choose a Windows .exe file.")
    }
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    let size = try file.seekToEnd()
    try file.seek(toOffset: 0)
    let header = try file.read(upToCount: 64) ?? Data()
    guard header.count == 64, header.starts(with: [0x4d, 0x5a]) else {
        throw LauncherError.message("This file is not a Windows executable.")
    }
    let offset = (0..<4).reduce(UInt64(0)) { $0 | UInt64(header[60 + $1]) << (8 * $1) }
    guard offset >= 64, offset + 24 <= size else {
        throw LauncherError.message("The Windows executable header is incomplete.")
    }
    try file.seek(toOffset: offset)
    let pe = try file.read(upToCount: 24) ?? Data()
    guard pe.count == 24, pe.starts(with: [0x50, 0x45, 0, 0]) else {
        throw LauncherError.message("The Windows executable header is invalid.")
    }
    let machine = UInt16(pe[4]) | UInt16(pe[5]) << 8
    switch machine {
    case 0x014c: return "32-bit Windows"
    case 0x8664: return "64-bit Windows"
    default: throw LauncherError.message("This engine supports Intel Windows executables only.")
    }
}

func run(_ executable: URL, _ arguments: [String], environment: [String: String]? = nil,
         directory: URL? = nil, output: FileHandle = .nullDevice,
         started: (() -> Void)? = nil) throws -> Int32 {
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    process.environment = environment
    process.currentDirectoryURL = directory
    process.standardOutput = output
    process.standardError = output
    process.standardInput = FileHandle.nullDevice
    try process.run()
    started?()
    process.waitUntilExit()
    return process.terminationStatus
}

func intelRuntimeAvailable() -> Bool {
    (try? run(URL(fileURLWithPath: "/usr/bin/arch"), ["-x86_64", "/usr/bin/true"])) == 0
}

struct Settings: Codable { var executable: String }

#if METAL_TRIAL
let isMetalTrial = true
#else
let isMetalTrial = false
#endif

final class Launcher: NSObject, NSApplicationDelegate {
    let root = Bundle.main.bundleURL.deletingLastPathComponent()
    lazy var data = root.appendingPathComponent("LauncherData", isDirectory: true)
    lazy var wine = root.appendingPathComponent("Runtime/WineCX/bin/wine")
    lazy var prefix = data.appendingPathComponent(isMetalTrial ? "Windows-Metal" : "Windows-OpenGL", isDirectory: true)
    lazy var log = data.appendingPathComponent("latest.log")
    lazy var settingsURL = data.appendingPathComponent("settings.json")
    lazy var selected = data.appendingPathComponent("Game/GTAIV/GTAIV.exe")
    lazy var status = NSTextField(wrappingLabelWithString: "Checking engine…")
    lazy var game = NSTextField(wrappingLabelWithString: "")
    lazy var detail = NSTextField(wrappingLabelWithString: "")
    var window: NSWindow!
    var actions: [NSButton] = []
    var busy = false
    var hasRosetta = false
    var rosettaButton: NSButton!

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: settingsURL.path) {
                let settings = try JSONDecoder().decode(Settings.self, from: Data(contentsOf: settingsURL))
                selected = URL(fileURLWithPath: settings.executable)
            }
        } catch { status.stringValue = "Could not load settings: \(error.localizedDescription)" }

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 390),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = isMetalTrial ? "Mac Games — Metal Test" : "Mac Games"
        let title = NSTextField(labelWithString: "Windows games on your Mac")
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        let subtitle = NSTextField(labelWithString: isMetalTrial ? "GTA IV · Experimental Metal graphics" : "Your launcher · Free Wine engine")
        subtitle.textColor = .secondaryLabelColor
        game.font = .systemFont(ofSize: 17, weight: .medium)
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        detail.maximumNumberOfLines = 3
        let choose = button("Choose Game…", #selector(chooseGame))
        let play = button("Play", #selector(playGame))
        play.keyEquivalent = "\r"
        let stop = button("Force Stop", #selector(forceStop))
        stop.toolTip = "Force-close Windows programs in this environment. Unsaved progress will be lost."
        let installer = button("Run Installer…", #selector(runInstaller))
        let logs = button("Show Log", #selector(showLog))
        let files = button("Windows Files", #selector(showFiles))
        rosettaButton = button("Install Rosetta…", #selector(installRosetta))
        let refresh = button("Check Setup", #selector(refreshSetup))
        actions = [choose, play, installer, files, rosettaButton, refresh]
        let controls = NSStackView(views: [choose, play, stop, installer])
        controls.orientation = .horizontal
        controls.spacing = 10
        let tools = NSStackView(views: [logs, files, rosettaButton, refresh])
        tools.orientation = .horizontal
        tools.spacing = 8
        let stack = NSStackView(views: [title, subtitle, game, detail, controls, status, tools])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 28),
            detail.widthAnchor.constraint(equalTo: stack.widthAnchor),
            status.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        let menu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Mac Games", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let item = NSMenuItem()
        item.submenu = appMenu
        menu.addItem(item)
        NSApp.mainMenu = menu
        refreshSetup()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func button(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    @objc func refreshSetup() {
        hasRosetta = intelRuntimeAvailable()
        let architecture = try? checkExecutable(selected)
        game.stringValue = selected.lastPathComponent == "GTAIV.exe" ? "Grand Theft Auto IV" : selected.deletingPathExtension().lastPathComponent
        detail.stringValue = "\(architecture ?? "Choose a valid game executable")\n\(selected.path)"
        rosettaButton.isHidden = hasRosetta
        if !FileManager.default.isExecutableFile(atPath: wine.path) {
            status.stringValue = "Wine is missing. Keep the Runtime folder beside this app."
        } else if !hasRosetta {
            status.stringValue = "Wine is downloaded. Install Apple's Rosetta, then click Check Setup."
        } else if architecture == nil {
            status.stringValue = "Choose the game's Windows .exe to continue."
        } else {
            status.stringValue = "Ready to test. Gameplay compatibility has not been verified."
        }
    }

    func selectFile(installer: Bool) -> URL? {
        let panel = NSOpenPanel()
        panel.title = installer ? "Select a Windows installer" : "Select the game executable"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = installer ? [.init(filenameExtension: "exe")!, .init(filenameExtension: "msi")!] : [.init(filenameExtension: "exe")!]
        panel.directoryURL = selected.deletingLastPathComponent()
        return panel.runModal() == .OK ? panel.url : nil
    }

    @objc func chooseGame() {
        guard let url = selectFile(installer: false) else { return }
        do {
            _ = try checkExecutable(url)
            let bytes = try JSONEncoder().encode(Settings(executable: url.path))
            try bytes.write(to: settingsURL, options: .atomic)
            selected = url
            refreshSetup()
        } catch { status.stringValue = error.localizedDescription }
    }

    @objc func playGame() {
        do { _ = try checkExecutable(selected) }
        catch { status.stringValue = error.localizedDescription; return }
        launch(arguments: [selected.path], directory: selected.deletingLastPathComponent(), description: "Game")
    }

    @objc func runInstaller() {
        guard let url = selectFile(installer: true) else { return }
        do {
            if url.pathExtension.lowercased() == "msi" {
                let file = try FileHandle(forReadingFrom: url)
                defer { try? file.close() }
                guard try file.read(upToCount: 8) == Data([0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1]) else {
                    throw LauncherError.message("This is not an MSI installer.")
                }
            } else { _ = try checkExecutable(url) }
        } catch { status.stringValue = error.localizedDescription; return }
        let arguments = url.pathExtension.lowercased() == "msi" ? ["msiexec", "/i", url.path] : [url.path]
        launch(arguments: arguments, directory: url.deletingLastPathComponent(), description: "Installer")
    }

    func wineEnvironment() -> [String: String] {
        let frameworks = root.appendingPathComponent("Runtime/Frameworks")
        let gst = frameworks.appendingPathComponent("GStreamer.framework/Versions/1.0")
        var environment = ProcessInfo.processInfo.environment
        environment["WINEPREFIX"] = prefix.path
        environment["WINEARCH"] = "win64"
        environment["WINEDLLOVERRIDES"] = "winemenubuilder.exe=d"
        // GTA IV needs the OpenGL backend; Wine/MoltenVK's Vulkan buffer path crashes here.
        environment["WINE_D3D_CONFIG"] = "renderer=gl"
        if isMetalTrial {
            environment.removeValue(forKey: "WINE_D3D_CONFIG")
            environment["WINEDLLOVERRIDES"] = "winemenubuilder.exe=d;d3d9=n;winemetal=b;d9mtmetal=b"
        }
        environment["WINEDEBUG"] = "-all,err+all"
        environment["WINEMSYNC"] = "1"
        environment["WINEESYNC"] = "0"
        environment["PATH"] = wine.deletingLastPathComponent().path + ":" + (environment["PATH"] ?? "/usr/bin:/bin")
        environment["DYLD_FALLBACK_LIBRARY_PATH"] = frameworks.path + ":" + gst.appendingPathComponent("lib").path
        if isMetalTrial {
            environment["DYLD_FALLBACK_LIBRARY_PATH"] = wine.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("lib/wine/x86_64-unix").path + ":" + environment["DYLD_FALLBACK_LIBRARY_PATH"]!
        }
        environment["DYLD_FALLBACK_FRAMEWORK_PATH"] = frameworks.path
        environment["GST_PLUGIN_SYSTEM_PATH_1_0"] = gst.appendingPathComponent("lib/gstreamer-1.0").path
        environment["GST_PLUGIN_SCANNER_1_0"] = gst.appendingPathComponent("libexec/gstreamer-1.0/gst-plugin-scanner").path
        environment["GST_REGISTRY_1_0"] = data.appendingPathComponent("gstreamer-registry.bin").path
        return environment
    }

    func launch(arguments: [String], directory: URL, description: String) {
        guard !busy else { return }
        guard intelRuntimeAvailable() else {
            refreshSetup()
            return
        }
        guard FileManager.default.isExecutableFile(atPath: wine.path) else {
            refreshSetup()
            return
        }
        busy = true
        actions.forEach { $0.isEnabled = false }
        status.stringValue = "Preparing the Windows environment…"
        let wine = self.wine, prefix = self.prefix, log = self.log
        var environment = wineEnvironment()
        if arguments.first?.lowercased().hasSuffix("/gtaiv.exe") == true {
            // GTA IV probes an AMD API that Wine exposes as an incomplete stub.
            environment["WINEDLLOVERRIDES"]! += ";atiadlxx=d"
        }
        let launchEnvironment = environment
        DispatchQueue.global(qos: .userInitiated).async {
            var result: String
            do {
                let environment = launchEnvironment
                // shortcut: one Windows environment, split prefixes when adding a multi-game library.
                let userFolder = prefix.appendingPathComponent("drive_c/users/\(NSUserName())")
                for folder in ["Desktop", "Documents", "Downloads", "Music", "Pictures", "Videos"] {
                    try FileManager.default.createDirectory(at: userFolder.appendingPathComponent(folder), withIntermediateDirectories: true)
                }
                try Data("\(Date())\n\(description): \(arguments.joined(separator: " "))\nSync: WINEMSYNC=\(environment["WINEMSYNC"] ?? "unset"), WINEESYNC=\(environment["WINEESYNC"] ?? "unset")\n".utf8).write(to: log, options: .atomic)
                let output = try FileHandle(forWritingTo: log)
                defer { try? output.close() }
                try output.seekToEnd()
                if isMetalTrial {
                    let smoke = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/MetalSmoke")
                    let companion = wine.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("lib/wine/x86_64-unix/d9mtmetal.so")
                    let code = try run(smoke, [companion.path], environment: environment, output: output)
                    guard code == 0 else { throw LauncherError.message("Metal shader/GPU check failed (\(code)). See Show Log.") }
                }
                for executable in [wine, wine.deletingLastPathComponent().appendingPathComponent("wineserver")] {
                    let code = try run(executable, ["--version"], environment: environment, output: output)
                    guard code == 0 else { throw LauncherError.message("Wine runtime check failed (\(code)). See Show Log.") }
                }
                let initialized = prefix.appendingPathComponent(".initialized")
                if !FileManager.default.fileExists(atPath: initialized.path) {
                    let code = try run(wine, ["wineboot", "-u"], environment: environment, output: output)
                    guard code == 0 else { throw LauncherError.message("Windows setup exited with code \(code). See Show Log.") }
                    if isMetalTrial {
                        let windows = prefix.appendingPathComponent("drive_c/windows")
                        let library = wine.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("lib/wine")
                        for (architecture, folder) in [("i386-windows", "syswow64"), ("x86_64-windows", "system32")] {
                            for name in ["winemetal.dll", "d9mtmetal.dll"] {
                                let destination = windows.appendingPathComponent(folder).appendingPathComponent(name)
                                if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
                                try FileManager.default.copyItem(at: library.appendingPathComponent(architecture).appendingPathComponent(name), to: destination)
                            }
                        }
                    }
                    try Data("WineCX 24.0.7\n".utf8).write(to: initialized, options: .atomic)
                }
                let code = try run(wine, arguments, environment: environment, directory: directory, output: output) {
                    DispatchQueue.main.async { self.status.stringValue = "\(description) process started. Waiting for it to exit…" }
                }
                result = code == 0 ? "\(description) process ended. Exit code 0; this does not confirm gameplay worked." : "\(description) exited with code \(code). See Show Log for details."
            } catch { result = "Could not launch: \(error.localizedDescription)" }
            DispatchQueue.main.async {
                self.busy = false
                self.actions.forEach { $0.isEnabled = true }
                self.status.stringValue = result
            }
        }
    }

    @objc func forceStop() {
        let server = wine.deletingLastPathComponent().appendingPathComponent("wineserver")
        let environment = wineEnvironment()
        status.stringValue = "Stopping Windows programs in this environment…"
        DispatchQueue.global(qos: .userInitiated).async {
            let result: String
            do {
                let code = try run(server, ["-k"], environment: environment)
                result = code == 0 ? "Stop requested. You can retry Play when the game closes." : "Stop failed with code \(code)."
            } catch { result = "Could not stop the game: \(error.localizedDescription)" }
            DispatchQueue.main.async { self.status.stringValue = result }
        }
    }

    @objc func showLog() {
        if FileManager.default.fileExists(atPath: log.path) { NSWorkspace.shared.open(log) }
        else { status.stringValue = "No launch log yet. The game has not run." }
    }

    @objc func showFiles() {
        let path = prefix.appendingPathComponent("drive_c")
        NSWorkspace.shared.open(FileManager.default.fileExists(atPath: path.path) ? path : data)
    }

    @objc func installRosetta() {
        let command = root.appendingPathComponent("Install Rosetta.command")
        if !NSWorkspace.shared.open(command) {
            status.stringValue = "Open Install Rosetta.command beside this app. Apple will ask you to accept its license."
        } else {
            status.stringValue = "Finish Apple's installation in Terminal, then click Check Setup."
        }
    }
}

func selfTest() throws {
    let launcher = Launcher()
    let environment = launcher.wineEnvironment()
    guard environment["WINEPREFIX"] == launcher.prefix.path,
          environment["WINEMSYNC"] == "1", environment["WINEESYNC"] == "0",
          environment["WINE_D3D_CONFIG"] == (isMetalTrial ? nil : "renderer=gl"),
          environment["WINEDLLOVERRIDES"] == (isMetalTrial ? "winemenubuilder.exe=d;d3d9=n;winemetal=b;d9mtmetal=b" : "winemenubuilder.exe=d") else {
        fatalError("Launcher environment does not match its graphics build")
    }
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let exe = folder.appendingPathComponent("Game with spaces.exe")
    var bytes = Data(repeating: 0, count: 88)
    bytes[0] = 0x4d; bytes[1] = 0x5a; bytes[60] = 64
    bytes[64] = 0x50; bytes[65] = 0x45; bytes[68] = 0x4c; bytes[69] = 0x01
    try bytes.write(to: exe)
    guard try checkExecutable(exe) == "32-bit Windows" else { fatalError("32-bit validation failed") }
    bytes[68] = 0x64; bytes[69] = 0x86
    try bytes.write(to: exe)
    guard try checkExecutable(exe) == "64-bit Windows" else { fatalError("64-bit validation failed") }
    for invalid in [Data(), Data("not an executable".utf8), bytes.prefix(70), Data(repeating: 255, count: 88)] {
        try invalid.write(to: exe)
        do { _ = try checkExecutable(exe); fatalError("Invalid executable accepted") }
        catch is LauncherError { }
    }
    let output = folder.appendingPathComponent("output.txt")
    guard FileManager.default.createFile(atPath: output.path, contents: nil) else {
        throw LauncherError.message("Could not create the self-test output file.")
    }
    let handle = try FileHandle(forWritingTo: output)
    let literal = "spaces ' quotes $HOME `command`"
    let code = try run(URL(fileURLWithPath: "/usr/bin/printf"), ["%s", literal], directory: folder, output: handle)
    try handle.close()
    guard code == 0, try String(contentsOf: output, encoding: .utf8) == literal else {
        fatalError("Arguments were not passed literally")
    }
    guard try run(URL(fileURLWithPath: "/usr/bin/false"), []) != 0 else { fatalError("Exit status lost") }
    do { _ = try run(folder.appendingPathComponent("missing"), []); fatalError("Launch failure ignored") }
    catch { }
    print("PASS: executable validation, literal arguments, exit status, launch failures.")
}

if CommandLine.arguments.contains("--self-test") {
    do { try selfTest() } catch { fputs("Self-test failed: \(error)\n", stderr); exit(1) }
} else {
    let app = NSApplication.shared
    let delegate = Launcher()
    app.setActivationPolicy(.regular)
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
