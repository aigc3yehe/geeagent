import SwiftUI

struct WeChatWatcherGearModuleView: View {
    var body: some View {
        WeChatWatcherGearWindow()
    }
}

struct WeChatWatcherGearWindow: View {
    @StateObject private var model = WeChatWatcherGearStore.shared

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                sessionAndSearchPanel
                    .frame(width: min(max(proxy.size.width * 0.32, 360), 460))

                Divider()

                accountsPanel
                    .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                runPanel
                    .frame(width: min(max(proxy.size.width * 0.3, 340), 460))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .onAppear {
            model.load()
        }
    }

    private var sessionAndSearchPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("WeChat Watcher")
                        .font(.title2.weight(.semibold))
                    Text(model.sessionConfigured ? "Backend session configured" : "Backend session missing")
                        .font(.caption)
                        .foregroundStyle(model.sessionConfigured ? .green : .secondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Session")
                    .font(.headline)

                SecureField("mp.weixin token", text: $model.tokenDraft)
                    .textFieldStyle(.roundedBorder)

                TextEditor(text: $model.cookieDraft)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 86, maxHeight: 110)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.25))
                    }

                TextField("User-Agent", text: $model.userAgentDraft)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button {
                        model.saveSessionFromDrafts()
                    } label: {
                        Label("Save", systemImage: "key")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        model.clearSession()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Search")
                    .font(.headline)

                HStack(spacing: 8) {
                    TextField("Public account name", text: $model.searchQuery)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            model.searchCurrentQuery()
                        }

                    Button {
                        model.searchCurrentQuery()
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isBusy)
                    .help("Search")
                }

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(model.searchResults) { result in
                            WeChatWatcherSearchResultRow(result: result) {
                                model.watch(result)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Circle()
                    .fill(model.isBusy ? Color.blue : Color.green)
                    .frame(width: 8, height: 8)
                Text(model.isBusy ? "Working" : "Ready")
                    .font(.caption.weight(.semibold))
                Text(model.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(20)
        .background(.thinMaterial)
    }

    private var accountsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Watchlist")
                        .font(.title3.weight(.semibold))
                    Text("\(model.accounts.count) account\(model.accounts.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.load()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .help("Refresh")

                Button {
                    model.checkAllAccounts()
                } label: {
                    Label("Check All", systemImage: "bolt")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy || model.accounts.isEmpty)
            }

            if model.accounts.isEmpty {
                ContentUnavailableView(
                    "No watched accounts",
                    systemImage: "person.crop.circle.badge.plus",
                    description: Text("Search an account name and add an explicit backend account result.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.accounts) { account in
                            Button {
                                model.selectedAccountID = account.id
                            } label: {
                                WeChatWatcherAccountRow(
                                    account: account,
                                    selected: model.selectedAccountID == account.id
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }

                HStack {
                    Button {
                        model.checkSelectedAccount()
                    } label: {
                        Label("Check Selected", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isBusy || model.selectedAccountID == nil)

                    Spacer()
                }
            }
        }
        .padding(22)
    }

    private var runPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Updates")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("\(model.runs.first?.articles.count ?? 0) latest")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let latest = model.runs.first {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(latest.status.rawValue.capitalized, systemImage: latest.status == .completed ? "checkmark.circle" : "exclamationmark.triangle")
                            .foregroundStyle(latest.status == .completed ? .green : .orange)
                        Spacer()
                        Text(WeChatWatcherDateCodec.localDisplay(from: latest.completedAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !latest.errors.isEmpty {
                        Text(latest.errors.joined(separator: "\n"))
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(model.runs.prefix(12)) { run in
                        WeChatWatcherRunRow(run: run)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(20)
        .background(.thinMaterial)
    }
}

private struct WeChatWatcherSearchResultRow: View {
    var result: WeChatWatcherSearchResult
    var onWatch: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "person.crop.square")
                .foregroundStyle(.blue)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(result.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if let intro = result.intro?.nilIfBlank {
                    Text(intro)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(result.fakeID)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                onWatch()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.bordered)
            .help("Watch")
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct WeChatWatcherAccountRow: View {
    var account: WeChatWatcherAccountRecord
    var selected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: account.enabled ? "dot.radiowaves.left.and.right" : "pause.circle")
                .foregroundStyle(account.enabled ? .blue : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(account.name)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text(account.enabled ? "Enabled" : "Paused")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(account.enabled ? .green : .secondary)
                }
                if let intro = account.intro?.nilIfBlank {
                    Text(intro)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 10) {
                    Text("Last check: \(WeChatWatcherDateCodec.localDisplay(from: account.lastCheckedAt))")
                    if let lastPublishTime = account.lastPublishTime {
                        Text("Latest: \(lastPublishTime)")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(selected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(selected ? Color.accentColor.opacity(0.55) : Color.secondary.opacity(0.12), lineWidth: 1)
        }
    }
}

private struct WeChatWatcherRunRow: View {
    var run: WeChatWatcherCheckRunRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(run.articles.count) new article\(run.articles.count == 1 ? "" : "s")")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(WeChatWatcherDateCodec.localDisplay(from: run.completedAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ForEach(run.articles.prefix(4)) { article in
                Button {
                    if let url = URL(string: article.url) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        Text(article.title)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.primary)
            }
            if run.articles.count > 4 {
                Text("+ \(run.articles.count - 4) more")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}
