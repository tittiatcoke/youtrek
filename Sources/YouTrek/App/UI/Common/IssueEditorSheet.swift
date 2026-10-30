import SwiftUI

/// Collects the edits made in the issue editor window so they can be previewed
/// in the form and written only when the user presses Save.
@MainActor
final class DeferredIssueEdits: ObservableObject {
    @Published private(set) var patch = IssuePatch(title: nil, description: nil, status: nil, priority: nil)

    var isEmpty: Bool {
        patch.title == nil && patch.description == nil && patch.statusOption == nil
            && patch.priorityOption == nil && patch.assignee == nil && patch.projectID == nil
            && patch.customFields.isEmpty
    }

    func merge(_ next: IssuePatch) {
        var merged = patch
        if let title = next.title { merged.title = title }
        if let description = next.description { merged.description = description }
        if let option = next.statusOption { merged.statusOption = option }
        if let option = next.priorityOption { merged.priorityOption = option }
        if let assignee = next.assignee { merged.assignee = assignee }
        if let projectID = next.projectID {
            merged.projectID = projectID
            merged.projectName = next.projectName
        }
        for field in next.customFields {
            merged.customFields.removeAll { $0.normalizedName == field.normalizedName }
            merged.customFields.append(field)
        }
        patch = merged
    }

    func preview(_ issue: IssueSummary) -> IssueSummary {
        var assignee = issue.assignee
        switch patch.assignee {
        case .clear: assignee = nil
        case .set(let option): assignee = Person.from(option: option)
        case .none: break
        }
        var customFields = issue.customFieldValues
        for field in patch.customFields {
            let values = Self.values(from: field.value)
            if values.isEmpty {
                customFields.removeValue(forKey: field.normalizedName)
            } else {
                customFields[field.normalizedName] = values
            }
        }
        return IssueSummary(
            id: issue.id,
            readableID: issue.readableID,
            title: patch.title ?? issue.title,
            projectName: patch.projectName ?? issue.projectName,
            updatedAt: issue.updatedAt,
            updatedBy: issue.updatedBy,
            assignee: assignee,
            reporter: issue.reporter,
            priority: patch.priorityOption.map(IssuePriority.init(option:)) ?? issue.priority,
            status: patch.statusOption.map(IssueStatus.init(option:)) ?? issue.status,
            tags: issue.tags,
            customFieldValues: customFields,
            draftID: issue.draftID
        )
    }

    func preview(_ detail: IssueDetail?) -> IssueDetail? {
        guard let detail else { return nil }
        return detail.replacing(title: patch.title, description: patch.description)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static func values(from value: IssueDraftFieldValue) -> [String] {
        switch value {
        case .none: return []
        case .string(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [] : [trimmed]
        case .integer(let number): return [String(number)]
        case .number(let number): return [String(number)]
        case .bool(let flag): return [flag ? "Yes" : "No"]
        case .date(let date): return [dateFormatter.string(from: date)]
        case .option(let option): return [option.displayName]
        case .options(let options): return options.map(\.displayName)
        }
    }
}

/// Modal editor opened by clicking an issue. It shows everything the side panel
/// shows; field edits are buffered and only written on Save. Cancel discards them.
/// Comments, attachments and sub-issue actions still apply immediately.
struct IssueEditorSheet: View {
    @EnvironmentObject private var container: AppContainer
    @ObservedObject private var appState: AppState
    @StateObject private var edits = DeferredIssueEdits()
    let issue: IssueSummary

    init(issue: IssueSummary, appState: AppState) {
        self.issue = issue
        self.appState = appState
    }

    var body: some View {
        let currentIssue = appState.issues.first(where: { $0.id == issue.id }) ?? issue
        VStack(spacing: 0) {
            IssueDetailView(
                issue: edits.preview(currentIssue),
                detail: edits.preview(appState.issueDetail(for: currentIssue)),
                isLoadingDetail: appState.isIssueDetailLoading(issue.id),
                onSubmitPatch: { edits.merge($0) }
            )
            Divider()
            HStack {
                if !edits.isEmpty {
                    Text("Unsaved changes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { close() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save(currentIssue) }
                    .keyboardShortcut("s", modifiers: [.command])
                    .disabled(edits.isEmpty)
            }
            .padding(12)
        }
        .frame(minWidth: 640, idealWidth: 720, minHeight: 600, idealHeight: 760)
        .task { await container.loadIssueDetail(for: issue) }
    }

    private func save(_ current: IssueSummary) {
        var patch = edits.patch
        patch.issueReadableID = current.readableID
        if let detail = appState.issueDetail(for: current) {
            appState.updateIssueDetail(detail.replacing(title: patch.title, description: patch.description))
        }
        let issueID = issue.id
        Task { [container] in
            await container.updateIssue(id: issueID, patch: patch)
        }
        close()
    }

    private func close() {
        appState.dismissIssueEditor()
    }
}
