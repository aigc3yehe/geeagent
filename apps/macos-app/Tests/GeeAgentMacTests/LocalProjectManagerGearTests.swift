import XCTest
@testable import GeeAgentMac

final class LocalProjectManagerGearTests: XCTestCase {
    func testManifestDeclaresNativeGearWithoutAgentCapabilities() throws {
        let manifestURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Gears/local.project.manager/gear.json")
        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(GearManifest.self, from: data)

        XCTAssertEqual(manifest.id, LocalProjectManagerGearDescriptor.gearID)
        XCTAssertEqual(manifest.entry.nativeID, LocalProjectManagerGearDescriptor.gearID)
        XCTAssertEqual(manifest.kind, .atmosphere)
        XCTAssertEqual(manifest.agent?.enabled, false)
        XCTAssertEqual(manifest.agent?.capabilities.isEmpty, true)
    }

    func testGearHostRegistersLocalProjectManagerNativeWindow() {
        XCTAssertEqual(
            GearHost.localProjectManagerWindowDescriptor.gearID,
            LocalProjectManagerGearDescriptor.gearID
        )
        XCTAssertEqual(GearHost.localProjectManagerWindowDescriptor.windowID, GearHost.localProjectManagerWindowID)
        XCTAssertTrue(GearHost.nativeWindowDescriptors.contains(GearHost.localProjectManagerWindowDescriptor))
        XCTAssertTrue(GearHost.nativeGearIDs.contains(LocalProjectManagerGearDescriptor.gearID))
    }

    func testCommandIdentityExtractsDirectoryAndLaunchNeedlesFromMultilineCommand() {
        let identity = LocalProjectCommandIdentity(command: """
        cd /Volumes/video_bucket/documents/yunfuwu
        ./bin/vpnctl web
        """)

        XCTAssertEqual(identity.workingDirectoryPath, "/Volumes/video_bucket/documents/yunfuwu")
        XCTAssertEqual(identity.launchLine, "./bin/vpnctl web")
        XCTAssertEqual(identity.executableName, "vpnctl")
        XCTAssertTrue(identity.matches(command: "/Volumes/video_bucket/documents/yunfuwu/bin/vpnctl web --port 5173"))
        XCTAssertFalse(identity.matches(command: "/usr/bin/python other-service.py"))
    }

    func testStatusResolverPrefersReachableFrontendPortOverCommandMatch() {
        let project = LocalProjectRecord(
            id: "project-1",
            name: "Yunfuwu",
            command: "cd /Volumes/video_bucket/documents/yunfuwu\n./bin/vpnctl web",
            frontendPort: 5173,
            lastManagedPID: nil,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let resolver = LocalProjectStatusResolver()
        let status = resolver.resolve(
            project: project,
            processSnapshots: [
                LocalProjectProcessSnapshot(
                    pid: 42,
                    command: "/Volumes/video_bucket/documents/yunfuwu/bin/vpnctl web"
                )
            ],
            portListeners: [5173: [88]],
            aliveManagedPIDs: []
        )

        XCTAssertEqual(status.state, .running)
        XCTAssertEqual(status.source, .frontendPort)
        XCTAssertEqual(status.pids, [88])
        XCTAssertEqual(status.frontendURL?.absoluteString, "http://localhost:5173")
    }

    func testStatusResolverUsesManagedPIDBeforeHeuristicCommandMatch() {
        let project = LocalProjectRecord(
            id: "project-2",
            name: "Backend",
            command: "cd /tmp/backend\nnpm run dev",
            frontendPort: nil,
            lastManagedPID: 333,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let resolver = LocalProjectStatusResolver()
        let status = resolver.resolve(
            project: project,
            processSnapshots: [
                LocalProjectProcessSnapshot(pid: 333, command: "/bin/zsh -lc npm run dev"),
                LocalProjectProcessSnapshot(pid: 444, command: "npm run dev")
            ],
            portListeners: [:],
            aliveManagedPIDs: [333]
        )

        XCTAssertEqual(status.state, .running)
        XCTAssertEqual(status.source, .managedProcess)
        XCTAssertEqual(status.pids, [333])
    }

    func testTilePrimaryActionStartsStoppedProjectsAndStopsRunningProjects() {
        let stopped = LocalProjectTilePrimaryAction(status: .stopped(projectID: "project-1"))
        XCTAssertEqual(stopped, .start)
        XCTAssertEqual(stopped.systemImageName, "play.fill")

        let running = LocalProjectTilePrimaryAction(
            status: LocalProjectStatus(
                projectID: "project-1",
                state: .running,
                source: .frontendPort,
                pids: [88],
                frontendURL: URL(string: "http://localhost:5173"),
                detail: "Listening on :5173"
            )
        )
        XCTAssertEqual(running, .stop)
        XCTAssertEqual(running.systemImageName, "stop.fill")
    }

    func testTileShowsOpenPageForRunningProjectsWithConfiguredFrontendPort() {
        let project = LocalProjectRecord(
            id: "project-4",
            name: "Frontend",
            command: "cd /tmp/frontend\nnpm run dev",
            frontendPort: 5173,
            lastManagedPID: 444,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let runningByManagedPID = LocalProjectStatus(
            projectID: "project-4",
            state: .running,
            source: .managedProcess,
            pids: [444],
            frontendURL: nil,
            detail: "Managed pid 444"
        )

        XCTAssertTrue(LocalProjectTileOpenPageAction(project: project, status: runningByManagedPID).isVisible)
        XCTAssertEqual(
            LocalProjectTileOpenPageAction(project: project, status: runningByManagedPID).url?.absoluteString,
            "http://localhost:5173"
        )

        let stopped = LocalProjectStatus.stopped(projectID: "project-4")
        XCTAssertFalse(LocalProjectTileOpenPageAction(project: project, status: stopped).isVisible)
    }

    func testCommandOutputCapturesLargeOutputWithoutBlockingProcessExit() {
        let output = LocalProjectCommandOutput.run(
            executable: "/bin/sh",
            arguments: [
                "-c",
                "i=0; while [ $i -lt 3000 ]; do printf 'line-%04d 0123456789012345678901234567890123456789\\n' $i; i=$((i + 1)); done"
            ]
        )

        XCTAssertEqual(output.split(separator: "\n").count, 3000)
        XCTAssertTrue(output.contains("line-2999"))
    }

    func testProjectDeletionRemovesOnlySavedConfiguration() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("local-project-manager-tests-\(UUID().uuidString)", isDirectory: true)
        let projectDirectory = root.appendingPathComponent("project", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)

        let database = LocalProjectFileDatabase(rootURL: root.appendingPathComponent("gear-data", isDirectory: true))
        let record = LocalProjectRecord(
            id: "project-3",
            name: "Local Project",
            command: "cd \(projectDirectory.path)\nnpm run dev",
            frontendPort: 3000,
            lastManagedPID: nil,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        try database.saveProjects([record])
        XCTAssertEqual(try database.loadProjects().map(\.id), ["project-3"])

        try database.deleteProject(id: "project-3")

        XCTAssertEqual(try database.loadProjects(), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: projectDirectory.path))
    }
}
