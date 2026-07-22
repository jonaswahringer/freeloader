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
                            for i in offsets { context.delete(books[i]) }
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
                _ = try await PDFImporter.importPDF(at: url, into: context)
            } catch {
                importError = error.localizedDescription
            }
        }
    }
}

private struct BookRow: View {
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(book.title)
                .font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
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
