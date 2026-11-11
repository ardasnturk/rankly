import SwiftUI

struct AddAppSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var country: String
    var onAdd: (AppInfo, Bool) -> Void

    @State private var query = ""
    @State private var results: [AppInfo] = []
    @State private var loading = false
    @State private var error: String?
    @State private var asCompetitor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Uygulama Ekle").font(.title2.bold())
            HStack {
                TextField("Uygulama adı, App Store ID veya linki", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(search)
                CountryPicker(country: $country).frame(width: 170)
                Button("Ara", action: search).keyboardShortcut(.defaultAction)
            }
            Toggle("Rakip olarak ekle", isOn: $asCompetitor)
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            List(results) { app in
                HStack(spacing: 10) {
                    AppIcon(url: app.iconURL, size: 36)
                    VStack(alignment: .leading) {
                        Text(app.name).bold()
                        Text("\(app.developer) · \(app.genre ?? "") · \(app.ratingCount) puan")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Ekle") { onAdd(app, asCompetitor); dismiss() }
                }
                .padding(.vertical, 2)
            }
            .overlay { if loading { ProgressView() } }
            HStack { Spacer(); Button("Kapat") { dismiss() }.keyboardShortcut(.cancelAction) }
        }
        .padding(20)
        .frame(width: 620, height: 480)
    }

    private func search() {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        loading = true; error = nil
        Task {
            do { results = try await AppStoreClient.shared.findApps(query: query, country: country) }
            catch { self.error = error.localizedDescription }
            if results.isEmpty && error == nil { error = "Sonuç bulunamadı" }
            loading = false
        }
    }
}

struct CountryPicker: View {
    @Binding var country: String
    var body: some View {
        Picker("", selection: $country) {
            ForEach(Storefronts.all.sorted { $0.name < $1.name }) { sf in
                Text("\(sf.flag) \(sf.name)").tag(sf.code)
            }
        }
        .labelsHidden()
    }
}
