import SwiftUI
import uKiviShared

struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Hero()

                if model.extensionsMissing {
                    MissingExtensionsCard()
                } else if model.hasCheckedStates && !model.allEnabled {
                    SetupCard()
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(text: "Blockers")
                    Card {
                        ForEach(Array(Blocker.allCases.enumerated()), id: \.element) { index, blocker in
                            if index > 0 { RowDivider() }
                            BlockerRow(blocker: blocker)
                        }
                    }
                    UpdateButton()
                    UpdateFooter()
                }

                AllowlistSection()

                CustomListsSection()

                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(text: "uKivi Extras")
                    ExtrasCard()
                }

            }
            .padding(.horizontal, 18)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await model.refreshStates() }
        .background(Theme.background.ignoresSafeArea())
    }
}

// MARK: - Hero

private struct Hero: View {
    @Environment(AppModel.self) private var model

    private var isProtecting: Bool { model.allEnabled && !model.blockingPaused }

    private var totalRules: Int {
        Blocker.allCases
            .filter { model.states[$0] == true }
            .compactMap { model.ruleCount(for: $0) }
            .reduce(0, +)
    }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.red.opacity(isProtecting ? 0.28 : 0.06))
                    .frame(width: 170, height: 170)
                    .blur(radius: 40)
                KiviLogo()
                    .frame(width: 128, height: 128)
                    .saturation(model.blockingPaused ? 0 : 1)
                    .opacity(model.blockingPaused ? 0.45 : 1)
            }
            .frame(height: 150)
            .animation(.easeInOut(duration: 0.3), value: model.blockingPaused)

            Text("uKivi")
                .font(.system(size: 40, weight: .heavy, design: .rounded))

            StatusPill(
                isOn: isProtecting,
                isKnown: model.hasCheckedStates,
                isMissing: model.extensionsMissing,
                isPaused: model.blockingPaused
            )

            if totalRules > 0 && !model.blockingPaused {
                Text("\(totalRules.formatted()) rules active in Safari")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)
            }

            PowerSwitch()
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }
}

/// The main on/off switch for all blocking.
private struct PowerSwitch: View {
    @Environment(AppModel.self) private var model

    private var isOn: Bool { !model.blockingPaused }

    var body: some View {
        Button {
            Task { await model.setBlocking(enabled: !isOn) }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(isOn ? AnyShapeStyle(Theme.redGradient) : AnyShapeStyle(Color.white.opacity(0.08)))
                        .frame(width: 46, height: 46)
                        .shadow(color: isOn ? Theme.red.opacity(0.6) : .clear, radius: 12)
                    if model.isSwitching {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "power")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(isOn ? .white : Theme.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(isOn ? "Blocking is on" : "Blocking is off")
                        .font(.headline)
                    Text(model.isSwitching ? "Applying in Safari…" : isOn ? "Tap to turn off everywhere" : "Tap to turn back on")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                }
                Spacer()
            }
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(isOn ? Theme.red.opacity(0.45) : Theme.cardBorder)
            )
            .animation(.easeInOut(duration: 0.25), value: isOn)
        }
        .buttonStyle(.plain)
        .disabled(model.isSwitching)
        .sensoryFeedback(.impact(weight: .medium), trigger: model.blockingPaused)
        .accessibilityLabel(isOn ? "Turn blocking off" : "Turn blocking on")
    }
}

private struct StatusPill: View {
    let isOn: Bool
    let isKnown: Bool
    let isMissing: Bool
    let isPaused: Bool

    private var label: String {
        if !isKnown { return "Checking…" }
        if isMissing { return "Extensions not installed" }
        if isPaused { return "Paused" }
        return isOn ? "Protection on" : "Setup needed"
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isOn ? Theme.red : Color.white.opacity(0.35))
                .frame(width: 8, height: 8)
                .shadow(color: isOn ? Theme.red : .clear, radius: 6)
            Text(label)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.06), in: Capsule())
        .overlay(Capsule().strokeBorder(isOn ? Theme.red.opacity(0.5) : Theme.cardBorder))
    }
}

// MARK: - Blockers

private struct BlockerRow: View {
    @Environment(AppModel.self) private var model
    let blocker: Blocker

    var body: some View {
        let isEnabled = model.states[blocker]

        HStack(spacing: 14) {
            Image(systemName: blocker.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isEnabled == true ? .white : Theme.secondary)
                .frame(width: 42, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isEnabled == true ? AnyShapeStyle(Theme.redGradient) : AnyShapeStyle(Color.white.opacity(0.06)))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(blocker.title)
                    .font(.headline)
                Text(blocker.summary)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                if let rules = model.ruleCount(for: blocker) {
                    Text("\(rules.formatted()) rules")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.secondary.opacity(0.8))
                }
                if let error = model.updateErrors[blocker] ?? model.reloadErrors[blocker] {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Theme.red)
                }
            }

            Spacer(minLength: 8)

            Text(isEnabled == true ? "ON" : isEnabled == false ? "OFF" : model.missing.contains(blocker) ? "MISSING" : "—")
                .font(.caption.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(isEnabled == true ? Theme.red : Theme.secondary)
        }
        .padding(16)
    }
}

private struct UpdateButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            Task { await model.updateFilters() }
        } label: {
            HStack(spacing: 10) {
                if model.isUpdating {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "arrow.down.circle.fill")
                }
                Text(model.isUpdating ? (model.updateStatus ?? "Updating…") : "Update filters")
                    .contentTransition(.opacity)
                    .animation(.default, value: model.updateStatus)
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.redGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Theme.red.opacity(0.35), radius: 14, y: 6)
        }
        .disabled(model.isUpdating || model.isReloading)
        .padding(.top, 4)
    }
}

/// "Updated 2 days ago · Reload", plus any update error.
private struct UpdateFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let date = model.listsDate {
                    Text("Lists updated \(date, format: .relative(presentation: .named))")
                } else {
                    Text("Lists not updated yet")
                }
                Text("·")
                Button(model.isReloading ? "Reloading…" : "Reload") {
                    Task { await model.reloadRules() }
                }
                .disabled(model.isReloading || model.isUpdating)
                .foregroundStyle(Theme.red)
            }
            .font(.footnote)
            .foregroundStyle(Theme.secondary)

            if let failure = model.updateFailure {
                Text(failure)
                    .font(.footnote)
                    .foregroundStyle(Theme.red)
            }
            ForEach(model.updateWarnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 6)
    }
}

// MARK: - Setup

private struct SetupCard: View {
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Label("Finish setup", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.red)
                step(1, "Open **Settings → Apps → Safari → Extensions**.")
                step(2, "Turn on **uKivi Ads** and **uKivi Privacy**.")
                step(3, "Optional: turn on **uKivi Extras** and set it to **Allow** on every website.")
                step(4, "Come back here. The status above turns red when it's on.")
            }
            .padding(18)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Theme.red.opacity(0.45))
        )
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .frame(width: 22, height: 22)
                .background(Theme.red.opacity(0.18), in: Circle())
                .foregroundStyle(Theme.red)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct MissingExtensionsCard: View {
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label("Safari can't find uKivi's blockers", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.red)
                Text("The blockers are app extensions, and they weren't installed with the app.")
                    .font(.subheadline)
                bullet("**SideStore / AltStore:** reinstall and choose to **keep** app extensions. Each one needs a free App ID (4 in total).")
                bullet("**LiveContainer** can't run app extensions, so blocking won't work there.")
                bullet("**xtool:** run `./run.sh` on your computer with the iPhone connected.")
            }
            .padding(18)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Theme.red.opacity(0.45))
        )
    }

    private func bullet(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle().fill(Theme.red).frame(width: 6, height: 6)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Allowlist

private struct AllowlistSection: View {
    @Environment(AppModel.self) private var model
    @State private var newDomain = ""
    @State private var showInvalidDomain = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Allowed sites")
            Card {
                ForEach(model.allowlist, id: \.self) { domain in
                    HStack {
                        Image(systemName: "globe")
                            .foregroundStyle(Theme.secondary)
                        Text(domain)
                        Spacer()
                        Button {
                            model.removeFromAllowlist(domain)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(Theme.secondary)
                        }
                        .accessibilityLabel("Remove \(domain)")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    RowDivider()
                }

                HStack(spacing: 10) {
                    TextField("", text: $newDomain, prompt: Text("example.com").foregroundStyle(Theme.secondary.opacity(0.7)))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .submitLabel(.done)
                        .focused($fieldFocused)
                        .onSubmit(addDomain)
                    Button(action: addDomain) {
                        Image(systemName: "plus")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(
                                Circle().fill(newDomain.isEmpty ? AnyShapeStyle(Color.white.opacity(0.08)) : AnyShapeStyle(Theme.redGradient))
                            )
                    }
                    .disabled(newDomain.isEmpty)
                    .accessibilityLabel("Add site")
                }
                .padding(.leading, 16)
                .padding(.trailing, 10)
                .padding(.vertical, 8)
            }
            Text("Nothing is blocked on these sites or their subdomains.")
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
                .padding(.leading, 6)
        }
        .alert("That doesn't look like a website address.", isPresented: $showInvalidDomain) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Enter a domain like example.com.")
        }
    }

    private func addDomain() {
        if model.addToAllowlist(newDomain) {
            newDomain = ""
            fieldFocused = false
        } else {
            showInvalidDomain = true
        }
    }
}

// MARK: - Custom filter lists

private struct SuggestedList: Identifiable {
    let name: String
    let url: String
    var id: String { url }

    static let all: [SuggestedList] = [
        .init(name: "Peter Lowe's list", url: "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=adblockplus&showintro=0&mimetype=plaintext"),
        .init(name: "uBlock Badware risks", url: "https://ublockorigin.github.io/uAssets/filters/badware.txt"),
        .init(name: "uBlock Quick fixes", url: "https://ublockorigin.github.io/uAssets/filters/quick-fixes.txt"),
        .init(name: "HaGeZi Light (big)", url: "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/light.txt"),
    ]
}

private struct CustomListsSection: View {
    @Environment(AppModel.self) private var model
    @State private var newURL = ""
    @State private var showInvalidURL = false
    @State private var editingFilters = false
    @FocusState private var fieldFocused: Bool

    private var suggestions: [SuggestedList] {
        SuggestedList.all.filter { !model.customListURLs.contains($0.url) }
    }

    private var ownFilterCount: Int {
        model.customFilters.split(whereSeparator: \.isNewline)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.hasPrefix("!") }
            .count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "My filter lists")
            Card {
                ForEach(model.customListURLs, id: \.self) { url in
                    HStack(spacing: 12) {
                        Image(systemName: "list.bullet.rectangle")
                            .foregroundStyle(Theme.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name(for: url))
                                .lineLimit(1)
                            Text(url)
                                .font(.caption)
                                .foregroundStyle(Theme.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Button {
                            model.removeCustomList(url)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(Theme.secondary)
                        }
                        .accessibilityLabel("Remove list")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    RowDivider()
                }

                HStack(spacing: 10) {
                    TextField("", text: $newURL, prompt: Text("https://…/list.txt").foregroundStyle(Theme.secondary.opacity(0.7)))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .submitLabel(.done)
                        .focused($fieldFocused)
                        .onSubmit(addList)
                    Button(action: addList) {
                        Image(systemName: "plus")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(
                                Circle().fill(newURL.isEmpty ? AnyShapeStyle(Color.white.opacity(0.08)) : AnyShapeStyle(Theme.redGradient))
                            )
                    }
                    .disabled(newURL.isEmpty)
                    .accessibilityLabel("Add list")
                }
                .padding(.leading, 16)
                .padding(.trailing, 10)
                .padding(.vertical, 8)

                RowDivider()

                Button {
                    editingFilters = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "pencil.and.list.clipboard")
                            .foregroundStyle(Theme.red)
                        Text("My filters")
                            .foregroundStyle(.white)
                        Spacer()
                        Text(ownFilterCount == 0 ? "None" : "\(ownFilterCount)")
                            .foregroundStyle(Theme.secondary)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions) { list in
                            Button {
                                _ = model.addCustomList(list.url)
                            } label: {
                                Label(list.name, systemImage: "plus")
                                    .font(.footnote.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.white.opacity(0.06), in: Capsule())
                                    .overlay(Capsule().strokeBorder(Theme.cardBorder))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }

            Text("Any uBlock Origin or AdBlock Plus list works. They're added to the Trackers blocker, which has the most room, and apply after the next update.")
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
                .padding(.leading, 6)
        }
        .alert("That isn't a list link.", isPresented: $showInvalidURL) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Paste a link starting with https://")
        }
        .sheet(isPresented: $editingFilters) {
            FiltersEditor(initialText: model.customFilters) { model.saveCustomFilters($0) }
        }
    }

    private func name(for url: String) -> String {
        SuggestedList.all.first { $0.url == url }?.name ?? URL(string: url)?.host() ?? url
    }

    private func addList() {
        if model.addCustomList(newURL) {
            newURL = ""
            fieldFocused = false
        } else {
            showInvalidURL = true
        }
    }
}

/// Plain-text editor for the user's own filters.
private struct FiltersEditor: View {
    let initialText: String
    let onSave: (String) -> Void
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("One filter per line, in uBlock Origin syntax. Lines starting with ! are comments.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    example("||ads.example.com^", "block a domain")
                    example("example.com##.banner", "hide an element on a site")
                    example("@@||example.com^", "allow something a list blocks")
                }
                TextEditor(text: $text)
                    .font(.system(.footnote, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.cardBorder))
            }
            .padding(18)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("My filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(text)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.red)
        .onAppear { text = initialText }
    }

    private func example(_ filter: String, _ meaning: String) -> some View {
        HStack(spacing: 8) {
            Text(filter)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.red)
            Text(meaning)
                .font(.caption)
                .foregroundStyle(Theme.secondary)
        }
    }
}

// MARK: - Extras

private struct ExtrasCard: View {
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text("A Safari extension for what content blockers can't do.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)
                feature("hand.tap.fill", "Tap any element to hide it")
                feature("pause.circle.fill", "Pause blocking on a site")
                Text("Open it from the **puzzle piece** in Safari's address bar.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
            }
            .padding(18)
        }
    }

    private func feature(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.red)
                .frame(width: 24)
            Text(text)
        }
    }
}

private struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.cardBorder)
            .frame(height: 1)
            .padding(.leading, 16)
    }
}
