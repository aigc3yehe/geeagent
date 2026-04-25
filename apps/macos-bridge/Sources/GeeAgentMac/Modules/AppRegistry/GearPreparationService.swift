import Foundation

actor GearPreparationService {
    static let shared = GearPreparationService()

    private let preflight: GearDependencyPreflight
    private let runner: GearCommandRunning
    private let store: GearPreparationStore

    init(
        runner: GearCommandRunning = GearShellCommandRunner(),
        store: GearPreparationStore = GearPreparationStore()
    ) {
        self.runner = runner
        self.preflight = GearDependencyPreflight(runner: runner)
        self.store = store
    }

    func cachedSnapshot(for gearID: String) -> GearPreparationSnapshot? {
        store.load(gearID: gearID)
    }

    func prepareIfNeeded(
        manifest: GearManifest,
        progress: (@Sendable (GearPreparationSnapshot) async -> Void)? = nil
    ) async -> GearPreparationSnapshot {
        let checking = GearPreparationSnapshot(
            gearID: manifest.id,
            state: .checking,
            summary: "Checking dependencies...",
            detail: nil,
            missingDependencyIDs: [],
            updatedAt: Date()
        )
        store.save(checking)
        await progress?(checking)

        let missing = await missingDependencies(for: manifest)
        guard !missing.isEmpty else {
            let ready = GearPreparationSnapshot.ready(gearID: manifest.id)
            store.save(ready)
            await progress?(ready)
            return ready
        }

        let needsSetup = GearPreparationSnapshot(
            gearID: manifest.id,
            state: .needsSetup,
            summary: missingSummary(missing),
            detail: missing.map(\.summary).joined(separator: "\n"),
            missingDependencyIDs: missing.map(\.item.id),
            updatedAt: Date()
        )
        store.save(needsSetup)
        await progress?(needsSetup)

        let installable = missing.filter { $0.item.installer?.type == .recipe }
        guard installable.count == missing.count else {
            let blocked = GearPreparationSnapshot(
                gearID: manifest.id,
                state: .installFailed,
                summary: "Some dependencies need manual setup.",
                detail: needsSetup.detail,
                missingDependencyIDs: needsSetup.missingDependencyIDs,
                updatedAt: Date()
            )
            store.save(blocked)
            await progress?(blocked)
            return blocked
        }

        let installing = GearPreparationSnapshot(
            gearID: manifest.id,
            state: .installing,
            summary: "Installing dependencies...",
            detail: installable.map { $0.item.id }.joined(separator: ", "),
            missingDependencyIDs: needsSetup.missingDependencyIDs,
            updatedAt: Date()
        )
        store.save(installing)
        await progress?(installing)

        var installLogs: [String] = []
        for check in installable {
            let installingItem = GearPreparationSnapshot(
                gearID: manifest.id,
                state: .installing,
                summary: "Installing \(check.item.id)...",
                detail: installLogs.filter { !$0.isEmpty }.joined(separator: "\n\n"),
                missingDependencyIDs: needsSetup.missingDependencyIDs,
                updatedAt: Date()
            )
            store.save(installingItem)
            await progress?(installingItem)

            let result = await install(check.item)
            installLogs.append(result.combinedOutput)
            guard result.exitCode == 0 else {
                let failed = GearPreparationSnapshot(
                    gearID: manifest.id,
                    state: .installFailed,
                    summary: "Dependency setup failed for \(check.item.id).",
                    detail: installLogs.filter { !$0.isEmpty }.joined(separator: "\n\n"),
                    missingDependencyIDs: needsSetup.missingDependencyIDs,
                    updatedAt: Date()
                )
                store.save(failed)
                await progress?(failed)
                return failed
            }
        }

        let afterInstall = await missingDependencies(for: manifest)
        guard afterInstall.isEmpty else {
            let failed = GearPreparationSnapshot(
                gearID: manifest.id,
                state: .installFailed,
                summary: missingSummary(afterInstall),
                detail: (installLogs + afterInstall.map(\.summary)).filter { !$0.isEmpty }.joined(separator: "\n\n"),
                missingDependencyIDs: afterInstall.map(\.item.id),
                updatedAt: Date()
            )
            store.save(failed)
            await progress?(failed)
            return failed
        }

        let ready = GearPreparationSnapshot.ready(gearID: manifest.id, summary: "Dependencies ready.")
        store.save(ready)
        await progress?(ready)
        return ready
    }

    private func missingDependencies(for manifest: GearManifest) async -> [GearDependencyCheckResult] {
        let results = await preflight.check(plan: manifest.dependencies, rootURL: manifest.rootURL)
        return results.filter { !$0.isSatisfied }
    }

    private func install(_ item: GearDependencyItem) async -> GearCommandResult {
        guard let installer = item.installer, installer.type == .recipe, let id = installer.id else {
            return GearCommandResult(exitCode: 1, stdout: "", stderr: "No installer recipe for \(item.id).")
        }

        switch id {
        case "brew.install.node":
            return await runBrewInstall(package: "node")
        case "brew.install.ffmpeg":
            return await runBrewInstall(package: "ffmpeg")
        case "npm.install.global.hyperframes":
            let version = installer.version ?? "0.4.20"
            return await runner.run("npm", arguments: ["install", "-g", "hyperframes@\(version)"])
        default:
            return GearCommandResult(exitCode: 1, stdout: "", stderr: "Unknown installer recipe `\(id)`.")
        }
    }

    private func runBrewInstall(package: String) async -> GearCommandResult {
        let brewCheck = await runner.run("command", arguments: ["-v", "brew"])
        guard brewCheck.exitCode == 0 else {
            return GearCommandResult(
                exitCode: 127,
                stdout: "",
                stderr: "Homebrew is not installed. Install Homebrew, then retry setup."
            )
        }
        return await runner.run("brew", arguments: ["install", package])
    }

    private func missingSummary(_ missing: [GearDependencyCheckResult]) -> String {
        let names = missing.map(\.item.id).joined(separator: ", ")
        return "Missing dependencies: \(names)"
    }
}

struct GearPreparationStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let keyPrefix = "geeagent.gear.preparation."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(gearID: String) -> GearPreparationSnapshot? {
        guard let data = defaults.data(forKey: keyPrefix + gearID) else {
            return nil
        }
        return try? JSONDecoder().decode(GearPreparationSnapshot.self, from: data)
    }

    func save(_ snapshot: GearPreparationSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        defaults.set(data, forKey: keyPrefix + snapshot.gearID)
    }
}
