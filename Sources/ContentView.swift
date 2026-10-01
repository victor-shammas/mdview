import SwiftUI

struct FindBar: View {
    @ObservedObject var document: DocumentState
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 12))

                TextField("Find\u{2026}", text: $document.findQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                            document.findPrevious()
                        } else {
                            document.findNext()
                        }
                    }

                if !document.findQuery.isEmpty {
                    Text(matchCountText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )

            Button(action: { document.findPrevious() }) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)
            .disabled(document.findMatchCount == 0)

            Button(action: { document.findNext() }) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)
            .disabled(document.findMatchCount == 0)

            Button("Done") {
                document.hideFindBar()
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .onAppear { isTextFieldFocused = true }
        .onChange(of: document.findBarFocusTrigger) {
            isTextFieldFocused = true
        }
    }

    private var matchCountText: String {
        if document.findMatchCount == 0 {
            return "No matches"
        }
        return "\(document.findCurrentMatch + 1) of \(document.findMatchCount)"
    }
}

struct FolderAccessBar: View {
    let folder: URL
    let onAllow: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
            Text("Some images are in \u{201C}\(folder.lastPathComponent)\u{201D}, which Plainview needs permission to read.")
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button("Allow Access\u{2026}", action: onAllow)
                .controlSize(.small)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help("Dismiss")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var document: DocumentState

    var body: some View {
        Group {
            if let html = document.renderedHTML {
                VStack(spacing: 0) {
                    if let folder = document.folderNeedingAccess {
                        FolderAccessBar(
                            folder: folder,
                            onAllow: {
                                appState.requestFolderAccess(suggested: folder, for: NSApp.keyWindow)
                            },
                            onDismiss: { document.folderNeedingAccess = nil }
                        )
                    }
                    if document.isFindBarVisible {
                        FindBar(document: document)
                    }
                    MarkdownWebView(
                        html: html,
                        contentVersion: document.contentVersion,
                        fileURL: document.fileURL,
                        fontSize: appState.fontSize,
                        maxWidth: appState.maxWidth,
                        fontFamily: appState.selectedFont.css,
                        appearance: appState.appearance,
                        textAlignment: appState.textAlignment,
                        findQuery: document.findQuery,
                        findMatchIndex: document.findCurrentMatch,
                        onFindResults: { count in
                            document.findMatchCount = count
                            document.findCurrentMatch = 0
                        },
                        onImageAccessDenied: { imageURL in
                            document.imageAccessDenied(imageURL)
                        }
                    )
                }
                .onChange(of: appState.folderAccessVersion) {
                    if document.folderNeedingAccess != nil {
                        document.reload()
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 48, weight: .thin))
                        .foregroundStyle(.tertiary)
                    Text("Open a Markdown File")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("\u{2318}O to open  \u{00B7}  Drop a file here")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: NSURL.self) { url, _ in
                guard let url = url as? URL, MarkdownFile.canOpen(url) else { return }
                DispatchQueue.main.async {
                    self.document.open(url)
                }
            }
            return true
        }
    }
}
