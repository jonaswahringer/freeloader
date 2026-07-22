import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Book.addedAt, order: .reverse) private var books: [Book]

    @State private var showImporter = false
    @State private var isImporting = false
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            Group {
                if books.isEmpty && !isImporting {
                    ContentUnavailableView {
                        Label("No Books Yet", systemImage: "books.vertical")
                    } description: {
                        Text("Import a PDF to start reading.")
                    } actions: {
                        Button("Import PDF…") { showImporter = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(books) { book in
                            NavigationLink(value: book) {
                                BookRow(book: book)
                            }
                        }
                        .onDelete { offsets in
                            for i in offsets {
                                if let wikiID = books[i].wikiID { BookWiki.remove(wikiID: wikiID) }
                                context.delete(books[i])
                            }
                        }
                    }
                }
            }
            .navigationTitle("Freeloader")
            .navigationDestination(for: Book.self) { book in
                ReadingView(book: book)
            }
            .toolbar {
                ToolbarItem {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Import PDF", systemImage: "plus")
                    }
                    .disabled(isImporting)
                }
            }
            .overlay {
                if isImporting {
                    ProgressView("Importing…")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.pdf]
            ) { result in
                guard case .success(let url) = result else { return }
                importBook(at: url)
            }
            .task(id: books.count) {
                // Retroactive pass: build wikis for books imported before this
                // feature existed (or left incomplete by a quit mid-generation).
                WikiGenerator.shared.scan(books: books)
            }
            .alert("Import Failed", isPresented: .init(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
        }
    }

    private func importBook(at url: URL) {
        isImporting = true
        Task {
            defer { isImporting = false }
            do {
                let book = try await PDFImporter.importPDF(at: url, into: context)
                WikiGenerator.shared.ensureWiki(for: book)
            } catch {
                importError = error.localizedDescription
            }
        }
    }
}

private struct BookRow: View {
    let book: Book
    @Environment(\.colorScheme) private var scheme

    private var wikiProgress: WikiProgress? {
        WikiGenerator.shared.progress(for: book)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(book.title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            wikiIndicator
        }
        .padding(.vertical, 2)
    }

    // Unobtrusive wiki-generation status: a small amber ring that fills as
    // chapters finish, then simply disappears. Failures whisper, not shout.
    @ViewBuilder
    private var wikiIndicator: some View {
        if let progress = wikiProgress {
            switch progress.phase {
            case .generating:
                ZStack {
                    Circle()
                        .stroke(.quaternary, lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: max(progress.fraction, 0.04))
                        .stroke(
                            ReadingPalette.brand(scheme),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 14, height: 14)
                .animation(.smooth(duration: 0.4), value: progress.completed)
                .help("Preparing book notes — \(progress.completed) of \(progress.total) chapters")
                .accessibilityLabel("Preparing book notes, \(progress.completed) of \(progress.total) chapters")
            case .failed(let reason):
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .help("Book notes incomplete: \(reason)")
            case .unavailable, .done:
                EmptyView() // quiet — reading works fine without notes
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let author = book.author { parts.append(author) }
        parts.append("\(book.chapters.count) chapters")
        return parts.joined(separator: " · ")
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Book.self, inMemory: true)
}
