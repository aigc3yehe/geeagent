import Foundation

struct PreviewWorkbenchRuntimeClient: WorkbenchRuntimeClient {
    func loadSnapshot() -> WorkbenchSnapshot {
        let previewApps = GearHost.mergedWithGears([
            InstalledAppRecord(
                id: "app-release-board",
                name: "Release Board",
                categoryLabel: "Delivery",
                versionLabel: "v1.4.2",
                healthLabel: "Healthy",
                installState: .installed,
                summary: "Coordinates release checklists, approvals, and rollout windows.",
                displayMode: .inNav
            ),
            InstalledAppRecord(
                id: "app-crm-enrichment",
                name: "CRM Enrichment",
                categoryLabel: "Revenue",
                versionLabel: "v0.9.8",
                healthLabel: "Waiting on access",
                installState: .needsPermission,
                summary: "Enriches account records with meeting notes and opportunity changes.",
                displayMode: .inNav
            ),
            InstalledAppRecord(
                id: "app-support-desk",
                name: "Support Desk",
                categoryLabel: "Customer Ops",
                versionLabel: "v2.1.0",
                healthLabel: "Update ready",
                installState: .updateAvailable,
                summary: "Imports escalations and tracks manual follow-up work.",
                displayMode: .inNav
            )
        ])

        return WorkbenchSnapshot(
            homeSummary: WorkbenchHomeSummary(
                openTasksCount: 7,
                approvalsCount: 2,
                nextAutomationLabel: "Daily triage at 08:30",
                installedAppsCount: previewApps.count
            ),
            homeItems: [
                WorkbenchHomeItem(
                    id: "home-approval-budget",
                    title: "Approve budget sync release",
                    detail: "Finance Sync is waiting on a production approval.",
                    statusLabel: "Needs approval in 12m",
                    actionLabel: "Review approval",
                    kind: .approval
                ),
                WorkbenchHomeItem(
                    id: "home-task-incident",
                    title: "Resolve macOS runtime verify failure",
                    detail: "The runtime build is blocked on a failing verification step.",
                    statusLabel: "Blocked",
                    actionLabel: "Open task",
                    kind: .task
                ),
                WorkbenchHomeItem(
                    id: "home-automation-inbox",
                    title: "Confirm inbox digest schedule",
                    detail: "Morning digest will run against the Singapore workspace.",
                    statusLabel: "Next run 08:30",
                    actionLabel: "Inspect automation",
                    kind: .automation
                ),
                WorkbenchHomeItem(
                    id: "home-app-crm",
                    title: "Grant CRM Enrichment access",
                    detail: "The app is installed but cannot reach the workspace directory yet.",
                    statusLabel: "Permission review",
                    actionLabel: "Review app access",
                    kind: .app
                )
            ],
            conversations: [
                ConversationThread(
                    id: "chat-product-launch",
                    title: "Product launch checklist",
                    participantLabel: "Ops Channel",
                    previewText: "Finance has been added. I queued the draft and linked it to the launch task.",
                    statusLabel: "Active",
                    lastActivityLabel: "2m ago",
                    unreadCount: 2,
                    linkedTaskTitle: "Finalize launch runbook",
                    linkedAppName: "Release Board",
                    messages: [
                        ConversationMessage(
                            id: "msg-1",
                            role: .assistant,
                            content: "The launch runbook is ready. Two approvals are still open: release window and customer notice.",
                            timestampLabel: "09:12"
                        ),
                        ConversationMessage(
                            id: "msg-2",
                            role: .user,
                            content: "Route the release window approval to finance and queue the customer notice draft.",
                            timestampLabel: "09:13"
                        ),
                        ConversationMessage(
                            id: "msg-3",
                            role: .assistant,
                            content: "Finance has been added. I queued the draft and linked it to the launch task.",
                            timestampLabel: "09:14"
                        )
                    ]
                ),
                ConversationThread(
                    id: "chat-support-triage",
                    title: "Support triage",
                    participantLabel: "Customer Ops",
                    previewText: "Three tickets need a manual response because they include billing exceptions.",
                    statusLabel: "Waiting",
                    lastActivityLabel: "18m ago",
                    unreadCount: 0,
                    linkedTaskTitle: "Review escalated ticket batch",
                    linkedAppName: "Support Desk",
                    messages: [
                        ConversationMessage(
                            id: "msg-4",
                            role: .system,
                            content: "Imported 14 tickets tagged urgent from Support Desk.",
                            timestampLabel: "08:44"
                        ),
                        ConversationMessage(
                            id: "msg-5",
                            role: .assistant,
                            content: "Three tickets need a manual response because they include billing exceptions.",
                            timestampLabel: "08:47"
                        )
                    ]
                ),
                ConversationThread(
                    id: "chat-field-research",
                    title: "Field research digest",
                    participantLabel: "Insights",
                    previewText: "The April interviews are summarized and grouped by workflow bottleneck.",
                    statusLabel: "Ready",
                    lastActivityLabel: "1h ago",
                    unreadCount: 1,
                    linkedTaskTitle: nil,
                    linkedAppName: "Research Vault",
                    messages: [
                        ConversationMessage(
                            id: "msg-6",
                            role: .assistant,
                            content: "The April interviews are summarized and grouped by workflow bottleneck.",
                            timestampLabel: "08:02"
                        )
                    ]
                )
            ],
            tasks: [
                WorkbenchTaskRecord(
                    id: "task-launch-runbook",
                    title: "Finalize launch runbook",
                    ownerLabel: "Operations",
                    appName: "Release Board",
                    status: .needsApproval,
                    priorityLabel: "P1",
                    dueLabel: "Due today",
                    updatedLabel: "Updated 4m ago",
                    summary: "Waiting on release window approval before publishing the final checklist.",
                    artifactCount: 3,
                    approvalRequestID: "approval-launch-runbook"
                ),
                WorkbenchTaskRecord(
                    id: "task-runtime-verify",
                    title: "Repair macOS runtime verification",
                    ownerLabel: "Native Shell",
                    appName: "Build Monitor",
                    status: .blocked,
                    priorityLabel: "P1",
                    dueLabel: "Due today",
                    updatedLabel: "Updated 12m ago",
                    summary: "Verification fails after packaging because a launch dependency is missing.",
                    artifactCount: 2,
                    moduleRunID: "module-run-runtime-verify",
                    canRetry: true
                ),
                WorkbenchTaskRecord(
                    id: "task-support-batch",
                    title: "Review escalated ticket batch",
                    ownerLabel: "Support",
                    appName: "Support Desk",
                    status: .running,
                    priorityLabel: "P2",
                    dueLabel: "Due in 1h",
                    updatedLabel: "Updated 3m ago",
                    summary: "Escalated billing exceptions are being classified for manual response.",
                    artifactCount: 6
                ),
                WorkbenchTaskRecord(
                    id: "task-digest-template",
                    title: "Refresh automation digest template",
                    ownerLabel: "Workflows",
                    appName: "Automation Studio",
                    status: .queued,
                    priorityLabel: "P3",
                    dueLabel: "Due tomorrow",
                    updatedLabel: "Queued 25m ago",
                    summary: "The new digest template will ship once the morning triage workflow completes.",
                    artifactCount: 1
                ),
                WorkbenchTaskRecord(
                    id: "task-customer-notice",
                    title: "Draft customer notice",
                    ownerLabel: "Communications",
                    appName: "Campaign Desk",
                    status: .completed,
                    priorityLabel: "P2",
                    dueLabel: "Completed",
                    updatedLabel: "Finished 9m ago",
                    summary: "The draft is ready for the launch checklist and attached to the release thread.",
                    artifactCount: 4
                ),
                WorkbenchTaskRecord(
                    id: "task-retention-query",
                    title: "Run retention backfill",
                    ownerLabel: "Data",
                    appName: "Analytics",
                    status: .failed,
                    priorityLabel: "P2",
                    dueLabel: "Retry today",
                    updatedLabel: "Failed 31m ago",
                    summary: "The backfill stopped when the source export returned an incomplete partition.",
                    artifactCount: 2,
                    moduleRunID: "module-run-retention-query",
                    canRetry: true
                )
            ],
            automations: [
                AutomationRecord(
                    id: "automation-daily-triage",
                    name: "Daily triage",
                    scopeLabel: "Workspace",
                    scheduleLabel: "Weekdays at 08:30",
                    nextRunLabel: "Tomorrow 08:30",
                    lastRunLabel: "Today 08:30",
                    status: .active,
                    summary: "Builds the morning operational digest and flags approvals."
                ),
                AutomationRecord(
                    id: "automation-release-watch",
                    name: "Release watch",
                    scopeLabel: "Launch",
                    scheduleLabel: "Hourly",
                    nextRunLabel: "In 22m",
                    lastRunLabel: "38m ago",
                    status: .attention,
                    summary: "Monitors the release board for failed packaging and approval drift."
                ),
                AutomationRecord(
                    id: "automation-support-sweep",
                    name: "Support sweep",
                    scopeLabel: "Customer Ops",
                    scheduleLabel: "Every 2 hours",
                    nextRunLabel: "At 11:00",
                    lastRunLabel: "At 09:00",
                    status: .active,
                    summary: "Pulls urgent tickets and groups them by response owner."
                ),
                AutomationRecord(
                    id: "automation-research-digest",
                    name: "Research digest",
                    scopeLabel: "Insights",
                    scheduleLabel: "Paused",
                    nextRunLabel: "Manual only",
                    lastRunLabel: "Yesterday 17:00",
                    status: .paused,
                    summary: "Packages field notes and tags themes for the weekly product review."
                )
            ],
            installedApps: previewApps,
            agentSkins: [
                AgentSkinRecord(
                    id: "skin-operator",
                    name: "Operator",
                    toneLabel: "Direct",
                    activationLabel: "Current",
                    summary: "Default operational voice for workbench and approvals."
                ),
                AgentSkinRecord(
                    id: "skin-analyst",
                    name: "Analyst",
                    toneLabel: "Methodical",
                    activationLabel: "Available",
                    summary: "Leans toward structured summaries and evidence-forward reporting."
                ),
                AgentSkinRecord(
                    id: "skin-concierge",
                    name: "Concierge",
                    toneLabel: "Warm",
                    activationLabel: "Available",
                    summary: "Optimized for inbox support, scheduling, and status updates."
                )
            ],
            availableAgentProfiles: [
                AgentProfileRecord(
                    id: "gee",
                    name: "Gee",
                    tagline: "Local-first workbench operator",
                    personalityPrompt: "You are Gee, a calm and capable local-first workbench operator who helps the user move work forward without hiding complexity.",
                    appearance: .abstract,
                    globalBackground: .none,
                    visualOptions: .empty,
                    skills: [
                        AgentSkillReferenceRecord(id: "workspace.chat", name: "Workspace Chat"),
                        AgentSkillReferenceRecord(id: "workspace.tasks", name: "Workspace Tasks")
                    ],
                    allowedToolIDs: nil,
                    source: .firstParty,
                    version: "1.0.0"
                ),
                AgentProfileRecord(
                    id: "companion",
                    name: "Companion",
                    tagline: "Warm follow-through",
                    personalityPrompt: "Stay patient with loose ends and gently push open threads back to the operator.",
                    appearance: .abstract,
                    globalBackground: .none,
                    visualOptions: .empty,
                    skills: [
                        AgentSkillReferenceRecord(id: "workspace.follow_up", name: "Workspace Follow Up")
                    ],
                    allowedToolIDs: nil,
                    source: .userCreated,
                    version: "1.0.0"
                )
            ],
            activeAgentProfileID: "gee",
            skillSources: .empty,
            settings: [
                SettingsPaneSummary(
                    id: "settings-runtime",
                    title: "Runtime",
                    summary: "Execution workspace, approvals, and command safety.",
                    items: [
                        SettingValue(id: "runtime-workspace", label: "Workspace", value: "geeagent"),
                        SettingValue(id: "runtime-approvals", label: "Approvals", value: "Required for sensitive actions"),
                        SettingValue(id: "runtime-shell", label: "Shell", value: "zsh")
                    ]
                ),
                SettingsPaneSummary(
                    id: "settings-notifications",
                    title: "Notifications",
                    summary: "Alert routing for approvals, failures, and automation runs.",
                    items: [
                        SettingValue(id: "notifications-approvals", label: "Approvals", value: "Banner + sound"),
                        SettingValue(id: "notifications-failures", label: "Failures", value: "Persistent until cleared"),
                        SettingValue(id: "notifications-digests", label: "Daily digest", value: "Delivered at 08:30")
                    ]
                ),
                SettingsPaneSummary(
                    id: "settings-models",
                    title: "Models",
                    summary: "Default routing preferences for chat and automations.",
                    items: [
                        SettingValue(id: "models-chat", label: "Chat default", value: "GPT-5"),
                        SettingValue(id: "models-automation", label: "Automation default", value: "GPT-5 mini"),
                        SettingValue(id: "models-fallback", label: "Fallback", value: "Disabled")
                    ]
                ),
                SettingsPaneSummary(
                    id: "settings-storage",
                    title: "Storage",
                    summary: "Snapshots, logs, and retained artifacts.",
                    items: [
                        SettingValue(id: "storage-logs", label: "Logs", value: "30 days"),
                        SettingValue(id: "storage-artifacts", label: "Artifacts", value: "Keep until archived"),
                        SettingValue(id: "storage-location", label: "Root", value: "~/Library/Application Support/GeeAgent")
                    ]
                )
            ]
        )
    }

    func createConversation(in snapshot: WorkbenchSnapshot) async throws -> WorkbenchSnapshot {
        var nextSnapshot = snapshot
        let newConversation = ConversationThread(
            id: "chat-\(UUID().uuidString)",
            title: "New Conversation",
            participantLabel: "Ready to chat",
            previewText: "Fresh conversation ready for the next request.",
            statusLabel: "Active",
            lastActivityLabel: "Just now",
            unreadCount: 0,
            linkedTaskTitle: nil,
            linkedAppName: nil,
            messages: [],
            isActive: true
        )
        nextSnapshot.conversations = nextSnapshot.conversations.map {
            var conversation = $0
            conversation.isActive = false
            return conversation
        }
        nextSnapshot.conversations.insert(newConversation, at: 0)
        nextSnapshot.lastOutcome = nil
        nextSnapshot.preferredSection = .chat
        return nextSnapshot
    }

    func activateConversation(
        _ conversationID: ConversationThread.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot {
        var nextSnapshot = snapshot
        nextSnapshot.conversations = nextSnapshot.conversations.map { conversation in
            var updatedConversation = conversation
            updatedConversation.isActive = conversation.id == conversationID
            updatedConversation.statusLabel = conversation.id == conversationID ? "Active" : conversation.statusLabel
            return updatedConversation
        }
        nextSnapshot.preferredSection = .chat
        return nextSnapshot
    }

    func deleteConversation(
        _ conversationID: ConversationThread.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot {
        var nextSnapshot = snapshot
        let deletedWasActive = nextSnapshot.conversations.first(where: { $0.id == conversationID })?.isActive == true
        nextSnapshot.conversations.removeAll { $0.id == conversationID }
        if nextSnapshot.conversations.isEmpty {
            nextSnapshot = try await createConversation(in: nextSnapshot)
        } else if deletedWasActive {
            let nextActiveID = nextSnapshot.conversations.first?.id
            nextSnapshot.conversations = nextSnapshot.conversations.map { conversation in
                var updatedConversation = conversation
                updatedConversation.isActive = conversation.id == nextActiveID
                return updatedConversation
            }
        }
        nextSnapshot.lastOutcome = WorkbenchRequestOutcome(
            kind: .firstPartyAction,
            detail: "Preview deleted the selected chat.",
            taskID: nil
        )
        nextSnapshot.preferredSection = .chat
        return nextSnapshot
    }

    func sendMessage(
        _ message: String,
        in snapshot: WorkbenchSnapshot,
        conversationID: ConversationThread.ID,
        allowAutoRouting: Bool
    ) async throws -> WorkbenchSnapshot {
        _ = allowAutoRouting
        var nextSnapshot = snapshot
        guard let conversationIndex = nextSnapshot.conversations.firstIndex(where: { $0.id == conversationID }) else {
            return snapshot
        }

        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            return snapshot
        }

        let response = previewAssistantReply(for: trimmedMessage)
        nextSnapshot.conversations[conversationIndex].messages.append(
            ConversationMessage(
                id: "msg-user-\(nextSnapshot.conversations[conversationIndex].messages.count + 1)",
                role: .user,
                content: trimmedMessage,
                timestampLabel: "Just now"
            )
        )
        nextSnapshot.conversations[conversationIndex].messages.append(
            ConversationMessage(
                id: "msg-assistant-\(nextSnapshot.conversations[conversationIndex].messages.count + 1)",
                role: .assistant,
                content: response,
                timestampLabel: "Just now"
            )
        )
        nextSnapshot.conversations[conversationIndex].statusLabel = "Active"
        nextSnapshot.conversations[conversationIndex].lastActivityLabel = "Just now"
        nextSnapshot.conversations[conversationIndex].previewText = response
        nextSnapshot.conversations[conversationIndex].unreadCount = 0
        nextSnapshot.conversations[conversationIndex].isActive = true
        nextSnapshot.lastOutcome = WorkbenchRequestOutcome(
            kind: .chatReply,
            detail: "Replied in the current conversation.",
            taskID: nil
        )
        nextSnapshot.preferredSection = .chat

        if let taskIndex = nextSnapshot.tasks.firstIndex(where: {
            $0.status == .running || $0.status == .needsApproval || $0.status == .blocked
        }) {
            nextSnapshot.tasks[taskIndex].updatedLabel = "Updated just now"
            nextSnapshot.tasks[taskIndex].summary = "Latest chat direction captured and folded into the active task."
        }

        return nextSnapshot
    }

    func performTaskAction(
        _ action: WorkbenchTaskAction,
        in snapshot: WorkbenchSnapshot,
        taskID: WorkbenchTaskRecord.ID
    ) async throws -> WorkbenchSnapshot {
        var nextSnapshot = snapshot
        guard let taskIndex = nextSnapshot.tasks.firstIndex(where: { $0.id == taskID }) else {
            return snapshot
        }

        switch action {
        case .allowOnce:
            nextSnapshot.tasks[taskIndex].status = .running
            nextSnapshot.tasks[taskIndex].updatedLabel = "Allowed once just now"
            nextSnapshot.tasks[taskIndex].summary = "GeeAgent continued the task for this one terminal run."
        case .alwaysAllow:
            nextSnapshot.tasks[taskIndex].status = .running
            nextSnapshot.tasks[taskIndex].updatedLabel = "Always-allow saved just now"
            nextSnapshot.tasks[taskIndex].summary = "GeeAgent saved the terminal permission and continued the task."
        case .deny:
            nextSnapshot.tasks[taskIndex].status = .blocked
            nextSnapshot.tasks[taskIndex].updatedLabel = "Denied just now"
            nextSnapshot.tasks[taskIndex].summary = "GeeAgent blocked that terminal access and kept the task ready for the next instruction."
        case .retry:
            nextSnapshot.tasks[taskIndex].status = .running
            nextSnapshot.tasks[taskIndex].updatedLabel = "Retried just now"
            nextSnapshot.tasks[taskIndex].summary = "Work resumed from the workbench."
        case .complete:
            nextSnapshot.tasks[taskIndex].status = .completed
            nextSnapshot.tasks[taskIndex].dueLabel = "Completed"
            nextSnapshot.tasks[taskIndex].updatedLabel = "Finished just now"
            nextSnapshot.tasks[taskIndex].summary = "Marked complete from the workbench."
        }

        nextSnapshot.lastOutcome = WorkbenchRequestOutcome(
            kind: .firstPartyAction,
            detail: "Task state updated from the workbench.",
            taskID: taskID
        )
        nextSnapshot.preferredSection = .tasks
        return nextSnapshot
    }

    func setActiveAgentProfile(
        _ profileID: AgentProfileRecord.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot {
        var nextSnapshot = snapshot
        guard nextSnapshot.availableAgentProfiles.contains(where: { $0.id == profileID }) else {
            return snapshot
        }
        nextSnapshot.activeAgentProfileID = profileID
        return nextSnapshot
    }

    func submitQuickPrompt(
        _ prompt: String,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return snapshot }
        var created = try await createConversation(in: snapshot)
        guard let conversationID = created.conversations.first(where: \.isActive)?.id ?? created.conversations.first?.id,
              let conversationIndex = created.conversations.firstIndex(where: { $0.id == conversationID })
        else {
            return snapshot
        }
        created.conversations[conversationIndex].tags = ["quick-input"]
        var next = try await sendMessage(
            trimmed,
            in: created,
            conversationID: conversationID,
            allowAutoRouting: false
        )
        let reply = "Preview: started a new quick-input conversation for \"\(trimmed)\"."
        next.quickReply = reply
        next.lastOutcome = WorkbenchRequestOutcome(kind: .chatReply, detail: reply, taskID: nil)
        return next
    }

    func completeHostActionTurn(
        _ completions: [WorkbenchHostActionCompletion],
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot {
        var next = snapshot
        let succeeded = completions.filter { $0.status == "succeeded" }.count
        let failed = completions.count - succeeded
        let reply = failed > 0
            ? "Preview: Gear actions finished with \(failed) failure(s)."
            : "Preview: Gear actions finished successfully."
        next.quickReply = reply
        next.lastOutcome = WorkbenchRequestOutcome(
            kind: .firstPartyAction,
            detail: reply,
            taskID: nil
        )
        return next
    }

    func installAgentPack(
        at packPath: String,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot {
        let trimmed = packPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return snapshot }

        let packURL = URL(fileURLWithPath: trimmed)
        let lastComponent = packURL.deletingPathExtension().lastPathComponent
        let sanitizedID = lastComponent
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "_", with: "-")
        guard !sanitizedID.isEmpty else { return snapshot }
        guard !snapshot.availableAgentProfiles.contains(where: { $0.id == sanitizedID }) else {
            throw NSError(
                domain: "PreviewWorkbenchRuntimeClient",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Preview already contains a persona named `\(sanitizedID)`."]
            )
        }

        var nextSnapshot = snapshot
        let imported = AgentProfileRecord(
            id: sanitizedID,
            name: lastComponent.isEmpty ? sanitizedID : lastComponent,
            tagline: "Preview agent definition import",
            personalityPrompt: "[IDENTITY]\nYou are a preview-imported GeeAgent definition.\n\n[SOUL]\nStay steady and helpful.\n\n[PLAYBOOK]\nExplain what you are doing and ask before risky actions.",
            appearance: .staticImage(assetPath: "/tmp/\(sanitizedID)/appearance/hero.png"),
            globalBackground: .none,
            visualOptions: AgentProfileVisualOptionsRecord(
                live2DBundlePath: nil,
                videoAssetPath: nil,
                imageAssetPath: "/tmp/\(sanitizedID)/appearance/hero.png"
            ),
            skills: [],
            allowedToolIDs: nil,
            source: .modulePack,
            version: "1.0.0",
            fileState: AgentProfileFileStateRecord(
                workspaceRootPath: "/tmp/\(sanitizedID)",
                manifestPath: "/tmp/\(sanitizedID)/agent.json",
                identityPromptPath: "/tmp/\(sanitizedID)/identity-prompt.md",
                soulPath: "/tmp/\(sanitizedID)/soul.md",
                playbookPath: "/tmp/\(sanitizedID)/playbook.md",
                toolsContextPath: "/tmp/\(sanitizedID)/tools.md",
                memorySeedPath: "/tmp/\(sanitizedID)/memory.md",
                heartbeatPath: "/tmp/\(sanitizedID)/heartbeat.md",
                visualFiles: [AgentProfileFileEntryRecord(title: "hero.png", path: "/tmp/\(sanitizedID)/appearance/hero.png")],
                supplementalFiles: [],
                canReload: true,
                canDelete: true
            )
        )
        nextSnapshot.availableAgentProfiles.insert(imported, at: 0)
        nextSnapshot.activeAgentProfileID = nextSnapshot.activeAgentProfileID ?? imported.id
        nextSnapshot.lastOutcome = WorkbenchRequestOutcome(
            kind: .firstPartyAction,
            detail: "Preview imported agent definition \(imported.name).",
            taskID: nil
        )
        return nextSnapshot
    }

    func reloadAgentProfile(
        _ profileID: AgentProfileRecord.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot {
        guard snapshot.availableAgentProfiles.contains(where: { $0.id == profileID }) else {
            return snapshot
        }
        var nextSnapshot = snapshot
        nextSnapshot.lastOutcome = WorkbenchRequestOutcome(
            kind: .firstPartyAction,
            detail: "Preview reloaded agent definition \(profileID).",
            taskID: nil
        )
        return nextSnapshot
    }

    func deleteAgentProfile(
        _ profileID: AgentProfileRecord.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot {
        guard let profile = snapshot.availableAgentProfiles.first(where: { $0.id == profileID }) else {
            return snapshot
        }
        guard profile.source != .firstParty else { return snapshot }
        var nextSnapshot = snapshot
        nextSnapshot.availableAgentProfiles.removeAll { $0.id == profileID }
        if nextSnapshot.activeAgentProfileID == profileID {
            nextSnapshot.activeAgentProfileID = "gee"
        }
        nextSnapshot.lastOutcome = WorkbenchRequestOutcome(
            kind: .firstPartyAction,
            detail: "Preview deleted agent definition \(profileID).",
            taskID: nil
        )
        return nextSnapshot
    }

    func addSystemSkillSource(
        at sourcePath: String,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot {
        var nextSnapshot = snapshot
        let source = SkillSourceRecord(
            id: "preview-system-\(UUID().uuidString)",
            path: sourcePath,
            scope: "system",
            profileID: nil,
            enabled: true,
            addedAt: "Preview",
            lastScannedAt: "Preview",
            status: "ready",
            error: nil,
            skills: []
        )
        nextSnapshot.skillSources.systemSources.append(source)
        return nextSnapshot
    }

    func removeSystemSkillSource(
        _ sourceID: SkillSourceRecord.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot {
        var nextSnapshot = snapshot
        nextSnapshot.skillSources.systemSources.removeAll { $0.id == sourceID }
        return nextSnapshot
    }

    func addPersonaSkillSource(
        profileID: AgentProfileRecord.ID,
        sourcePath: String,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot {
        var nextSnapshot = snapshot
        var sources = nextSnapshot.skillSources.personaSources[profileID] ?? []
        sources.append(
            SkillSourceRecord(
                id: "preview-persona-\(UUID().uuidString)",
                path: sourcePath,
                scope: "persona",
                profileID: profileID,
                enabled: true,
                addedAt: "Preview",
                lastScannedAt: "Preview",
                status: "ready",
                error: nil,
                skills: []
            )
        )
        nextSnapshot.skillSources.personaSources[profileID] = sources
        return nextSnapshot
    }

    func removePersonaSkillSource(
        profileID: AgentProfileRecord.ID,
        sourceID: SkillSourceRecord.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot {
        var nextSnapshot = snapshot
        nextSnapshot.skillSources.personaSources[profileID]?.removeAll { $0.id == sourceID }
        return nextSnapshot
    }

    func deleteTerminalPermissionRule(
        _ ruleID: TerminalPermissionRuleRecord.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot {
        var nextSnapshot = snapshot
        nextSnapshot.terminalPermissionRules.removeAll { $0.id == ruleID }
        nextSnapshot.lastOutcome = WorkbenchRequestOutcome(
            kind: .firstPartyAction,
            detail: "Preview removed a saved terminal permission.",
            taskID: nil
        )
        return nextSnapshot
    }

    func setHighestAuthorizationEnabled(
        _ enabled: Bool,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot {
        var nextSnapshot = snapshot
        nextSnapshot.securityPreferences.highestAuthorizationEnabled = enabled
        nextSnapshot.lastOutcome = WorkbenchRequestOutcome(
            kind: .firstPartyAction,
            detail: enabled ? "Preview enabled highest authorization." : "Preview disabled highest authorization.",
            taskID: nil
        )
        return nextSnapshot
    }

    func loadChatRoutingSettings() async throws -> ChatRoutingSettings {
        ChatRoutingSettings(
            defaultRouteClass: "default",
            allowUserOverrides: true,
            providerChoices: ["openai", "xenodia"],
            routeClasses: [
                RouteClassSetting(
                    name: "default",
                    provider: "xenodia",
                    model: "gpt-5.4",
                    reasoningEffort: "medium",
                    fallbackModel: "gpt-5.4"
                )
            ],
            profiles: []
        )
    }

    func saveChatRoutingSettings(
        _ settings: ChatRoutingSettings,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot {
        var nextSnapshot = snapshot
        nextSnapshot.runtimeStatus = WorkbenchRuntimeStatus(
            state: .live,
            detail: "Preview routing uses \(settings.selectedRouteClass?.model ?? "the selected model").",
            providerName: settings.selectedRouteClass?.provider
        )
        return nextSnapshot
    }

    func invokeTool(_ invocation: ToolInvocation) async throws -> WorkbenchToolOutcome {
        // Preview client: fake out the most common v1 calls so UI builds that
        // depend on this client aren't dead-ended.
        switch invocation.toolID {
        case "navigate.openSection":
            if case let .string(raw)? = invocation.arguments["section"],
               WorkbenchSection(rawValue: raw) != nil
            {
                return .completed(
                    toolID: invocation.toolID,
                    payload: ["intent": "navigate.section", "section": raw]
                )
            }
            return .error(
                toolID: invocation.toolID,
                code: "args.section",
                message: "preview client: bad or missing section"
            )
        case "gee.app.openSection":
            if case let .string(raw)? = invocation.arguments["section"],
               WorkbenchSection(rawValue: raw) != nil
            {
                return .completed(
                    toolID: invocation.toolID,
                    payload: ["intent": "navigate.section", "section": raw]
                )
            }
            return .error(
                toolID: invocation.toolID,
                code: "args.section",
                message: "preview client: bad or missing section"
            )
        case "navigate.openModule":
            if case let .string(moduleID)? = invocation.arguments["module_id"], !moduleID.isEmpty {
                return .completed(
                    toolID: invocation.toolID,
                    payload: ["intent": "navigate.module", "module_id": moduleID]
                )
            }
            return .error(
                toolID: invocation.toolID,
                code: "args.module_id",
                message: "preview client: bad or missing module_id"
            )
        case "gee.app.openSurface":
            let surfaceID: String?
            if case let .string(raw)? = invocation.arguments["surface_id"] {
                surfaceID = raw
            } else if case let .string(raw)? = invocation.arguments["gear_id"] {
                surfaceID = raw
            } else if case let .string(raw)? = invocation.arguments["module_id"] {
                surfaceID = raw
            } else {
                surfaceID = nil
            }
            if let surfaceID, !surfaceID.isEmpty {
                return .completed(
                    toolID: invocation.toolID,
                    payload: ["intent": "navigate.module", "module_id": surfaceID]
                )
            }
            return .error(
                toolID: invocation.toolID,
                code: "args.surface_id",
                message: "preview client: bad or missing surface_id"
            )
        case "gee.gear.listCapabilities":
            var payload: [String: Any] = [
                "intent": "gear.list_capabilities",
                "detail": stringArgument("detail", in: invocation) ?? "summary"
            ]
            if let gearID = stringArgument("gear_id", in: invocation) {
                payload["gear_id"] = gearID
            }
            if let capabilityID = stringArgument("capability_id", in: invocation) {
                payload["capability_id"] = capabilityID
            }
            return .completed(toolID: invocation.toolID, payload: payload)
        case "gee.gear.invoke":
            guard let gearID = stringArgument("gear_id", in: invocation),
                  let capabilityID = stringArgument("capability_id", in: invocation)
            else {
                return .error(
                    toolID: invocation.toolID,
                    code: "args.gear",
                    message: "preview client: bad or missing gear invocation ids"
                )
            }
            return .completed(
                toolID: invocation.toolID,
                payload: [
                    "intent": "gear.invoke",
                    "gear_id": gearID,
                    "capability_id": capabilityID,
                    "args": nestedObjectArgument("args", in: invocation) ?? [:]
                ]
            )
        case "files.writeText", "shell.run":
            if let token = invocation.approvalToken,
               !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                return .completed(
                    toolID: invocation.toolID,
                    payload: ["preview": true]
                )
            }
            return .needsApproval(
                toolID: invocation.toolID,
                blastRadius: .external,
                prompt: "Preview: this tool requires approval."
            )
        default:
            return .completed(
                toolID: invocation.toolID,
                payload: ["preview": true]
            )
        }
    }

    private func stringArgument(_ key: String, in invocation: ToolInvocation) -> String? {
        guard case let .string(value)? = invocation.arguments[key] else {
            return nil
        }
        return value
    }

    private func nestedObjectArgument(_ key: String, in invocation: ToolInvocation) -> [String: Any]? {
        guard case let .object(object)? = invocation.arguments[key] else {
            return nil
        }
        return WorkbenchToolArgumentCodec.encode(object)
    }

    private func previewAssistantReply(for message: String) -> String {
        let lowercasedMessage = message.lowercased()
        if lowercasedMessage.contains("ship") || lowercasedMessage.contains("launch") {
            return "Understood. I kept this thread focused on the shipping path and updated the active work."
        }

        if lowercasedMessage.contains("follow up") || lowercasedMessage.contains("reply") {
            return "Captured. I treated that as the next operator follow-up for the current workflow."
        }

        return "Captured. I folded that direction into the current thread and kept the work moving."
    }
}
