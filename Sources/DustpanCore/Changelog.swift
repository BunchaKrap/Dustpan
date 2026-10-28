import Foundation

/// A group of changes in one release, e.g. "New" or "Fixed". `title` is empty for notes without headings.
public struct ChangelogSection: Sendable, Equatable {
    public let title: String
    public let items: [String]

    public init(title: String, items: [String]) {
        self.title = title
        self.items = items
    }
}

public struct ChangelogEntry: Sendable, Equatable {
    public let version: String
    /// As written after the version, e.g. "28 October 2026".
    public let date: String?
    public let sections: [ChangelogSection]
}

/// Reads CHANGELOG.md. Format: `## <version> — <date>` per release, `### New|Improved|Fixed` groups,
/// `- item` bullets. Plain lines are kept as items too, so free-form GitHub release notes still display.
public enum Changelog {
    public static func parse(_ markdown: String) -> [ChangelogEntry] {
        var entries: [ChangelogEntry] = []
        var version: String?
        var date: String?
        var body: [Substring] = []

        func flush() {
            if let version { entries.append(ChangelogEntry(version: version, date: date, sections: sections(body.joined(separator: "\n")))) }
            body = []
        }
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("## ") {
                flush()
                let heading = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
                let parts = heading.components(separatedBy: "—").map { $0.trimmingCharacters(in: .whitespaces) }
                version = GitHubUpdater.normalized(parts[0])
                date = parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil
            } else if version != nil {
                body.append(line)
            }
        }
        flush()
        return entries
    }

    /// Splits one release's notes into groups. Accepts `###` or `##` group headings and `-`/`*` bullets.
    public static func sections(_ notes: String) -> [ChangelogSection] {
        var sections: [ChangelogSection] = []
        var title = ""
        var items: [String] = []

        func flush() {
            if !items.isEmpty { sections.append(ChangelogSection(title: title, items: items)) }
            items = []
        }
        for raw in notes.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") {
                flush()
                title = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                items.append(String(line.dropFirst(2)))
            } else if !line.isEmpty {
                // A wrapped bullet continues the previous item; anything else stands alone.
                if raw.hasPrefix("  "), let last = items.popLast() {
                    items.append(last + " " + line)
                } else {
                    items.append(line)
                }
            }
        }
        flush()
        return sections
    }

    /// Releases newer than `old` up to and including `new`, newest first.
    public static func entries(_ entries: [ChangelogEntry], after old: String, through new: String) -> [ChangelogEntry] {
        entries
            .filter { GitHubUpdater.isNewer($0.version, than: old) && !GitHubUpdater.isNewer($0.version, than: new) }
            .sorted { GitHubUpdater.isNewer($0.version, than: $1.version) }
    }

    /// The Markdown for one version exactly as written, for publishing as GitHub release notes.
    public static func notes(for version: String, in markdown: String) -> String? {
        var collecting = false
        var lines: [Substring] = []
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("## ") {
                if collecting { break }
                let heading = String(line.dropFirst(3)).components(separatedBy: "—")[0].trimmingCharacters(in: .whitespaces)
                collecting = GitHubUpdater.normalized(heading) == GitHubUpdater.normalized(version)
            } else if collecting {
                lines.append(line)
            }
        }
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
