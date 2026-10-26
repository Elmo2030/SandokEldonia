import SwiftUI
import IPTVCore
import IPTVAppKit

struct HomeDashboardView: View {
    var onExplore: () -> Void
    @Environment(AppModel.self) private var model

    private var movies: [Item] {
        model.results.filter { $0.type == .movie }
    }

    private var series: [Item] {
        model.results.filter { $0.type == .series }
    }

    private var live: [Item] {
        model.results.filter { $0.type == .live }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                hero

                if !model.recentlyAdded.isEmpty {
                    posterSection(L("recent.title"), items: model.recentlyAdded)
                }

                if !movies.isEmpty {
                    posterSection("أفلام من مكتبتك", items: movies)
                }

                if !series.isEmpty {
                    posterSection("مسلسلات", items: series)
                }

                if !live.isEmpty {
                    posterSection("قنوات مباشرة", items: live)
                }

                if model.results.isEmpty {
                    ContentUnavailableView(
                        "مكتبتك جاهزة للاستكشاف",
                        systemImage: "sparkles.tv",
                        description: Text(
                            model.syncing
                            ? "جارٍ تجهيز المحتوى..."
                            : "اختر تصنيفًا من القائمة أو حدّث مكتبتك."
                        )
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                }
            }
            .padding(28)
            .frame(maxWidth: 1400)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(CinemaTheme.background)
    }

    private var hero: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: [
                            CinemaTheme.selectedSurface,
                            CinemaTheme.surface,
                            CinemaTheme.background
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    Label("SANDOKELDONIA", systemImage: "sparkles")
                        .font(.caption.weight(.bold))
                        .tracking(2)
                        .foregroundStyle(CinemaTheme.accent)

                    Text("مسا مسا عالناس الكويسه")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(CinemaTheme.primaryText)

                    Text("أفلامك ومسلسلاتك وقنواتك في مكان واحد.")
                        .font(.title3)
                        .foregroundStyle(CinemaTheme.secondaryText)

                    HStack(spacing: 12) {
                        Button {
                            model.selectedCategory = "__all"
                            model.searchText = ""
                            model.scope = .category
                            model.tab = .movie
                            onExplore()
                        } label: {
                            Label("اكتشف الأفلام", systemImage: "play.fill")
                                .font(.headline)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 11)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(CinemaTheme.accent)

                        // Pulls the movie and series lists again from the playlist link, so new titles show up.
                        Button {
                            Task { await model.sync() }
                        } label: {
                            Label(model.syncing ? syncStatusText(model.syncProgress) : L("settings.refresh"),
                                  systemImage: "arrow.clockwise")
                                .font(.headline)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 11)
                        }
                        .buttonStyle(.bordered)
                        .tint(CinemaTheme.accent)
                        .disabled(model.syncing)
                        .help(L("settings.refresh"))
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "film.stack.fill")
                    .font(.system(size: 76, weight: .ultraLight))
                    .foregroundStyle(CinemaTheme.accent.opacity(0.7))
                    .padding(.trailing, 16)
                    .accessibilityHidden(true)
            }
            .padding(30)
        }
        .frame(minHeight: 230)
    }

    private func posterSection(_ title: String, items: [Item]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(CinemaTheme.primaryText)

                Spacer()

                Text("\(items.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(CinemaTheme.secondaryText)
            }

            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 145, maximum: 190), spacing: 16)
                ],
                alignment: .leading,
                spacing: 18
            ) {
                ForEach(items.prefix(12)) { item in
                    Button {
                        if model.hasInfo(item) {
                            model.openInfo = item
                        } else {
                            model.play(item)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            ZStack(alignment: .topTrailing) {
                                Artwork(
                                    url: item.iconURL,
                                    symbol: item.type == .live ? "tv" : "film",
                                    fill: true
                                )
                                .frame(height: 210)
                                .frame(maxWidth: .infinity)
                                .clipped()
                                .background(CinemaTheme.surface)

                                if model.isFavorite(item) {
                                    Image(systemName: "star.fill")
                                        .font(.caption)
                                        .foregroundStyle(CinemaTheme.accent)
                                        .padding(8)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                            Text(item.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(CinemaTheme.primaryText)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("تشغيل \(item.name)")
                }
            }
        }
    }
}
