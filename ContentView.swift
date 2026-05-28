import SwiftUI
import SwiftData
import AVFoundation
import UIKit
import UserNotifications
internal import Combine

// MARK: - Safe screen bounds (visionOS‑compatible)
struct Screen {
    static var bounds: CGRect {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
            ?? scenes.first as? UIWindowScene
        return windowScene?.screen.bounds ?? CGRect(x: 0, y: 0, width: 390, height: 844)
    }
    static var width: CGFloat { bounds.width }
    static var height: CGFloat { bounds.height }
}

// MARK: - SwiftData Models
@Model
final class EffectivenessScore {
    var score: Int
    var lastUpdated: Date
    init(score: Int = 0, lastUpdated: Date = .now) {
        self.score = score
        self.lastUpdated = lastUpdated
    }
}

@Model
final class TaskItem: Identifiable, Hashable {
    @Attribute(.unique) var id: UUID
    var title: String
    var icon: String
    var createdAt: Date
    var isCompleted: Bool
    init(id: UUID = UUID(), title: String, icon: String = "📝", createdAt: Date = .now, isCompleted: Bool = false) {
        self.id = id
        self.title = title
        self.icon = icon
        self.createdAt = createdAt
        self.isCompleted = isCompleted
    }
}

@Model
final class Achievement: Identifiable {
    @Attribute(.unique) var id: String
    var name: String
    var achievementDescription: String
    var iconName: String
    var isUnlocked: Bool
    var unlockedDate: Date?
    var threshold: Int

    init(id: String, name: String, description: String, iconName: String, threshold: Int, isUnlocked: Bool = false, unlockedDate: Date? = nil) {
        self.id = id
        self.name = name
        self.achievementDescription = description
        self.iconName = iconName
        self.threshold = threshold
        self.isUnlocked = isUnlocked
        self.unlockedDate = unlockedDate
    }
}

// MARK: - Haptic Manager
class HapticManager {
    static let shared = HapticManager()
    private init() {}
    func impact(style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
    func notification(type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}

// MARK: - Effectiveness Tracker
@MainActor
final class EffectivenessTracker: ObservableObject {
    @Published var score: Int = 0
    @Published var showCompletionCelebration = false
    private var context: ModelContext
    private var scoreEntity: EffectivenessScore?
    private var hasShownCompletion = false

    init(context: ModelContext) {
        self.context = context
        loadScore()
        checkAllAchievements()
    }

    func increment(for category: String) {
        let newScore = min(score + 1, 200)
        if newScore != score {
            score = newScore
            saveScore()
            checkAchievementsForCurrentScore()

            if score == 200 && !hasShownCompletion {
                showCompletionCelebration = true
                hasShownCompletion = true
            }
        }
    }

    func reloadScore() {
        loadScore()
    }

    private func saveScore() {
        if let entity = scoreEntity {
            entity.score = score
            entity.lastUpdated = .now
        } else {
            let newEntity = EffectivenessScore(score: score)
            context.insert(newEntity)
            scoreEntity = newEntity
        }
        try? context.save()
    }

    private func loadScore() {
        let descriptor = FetchDescriptor<EffectivenessScore>()
        if let existing = try? context.fetch(descriptor).first {
            scoreEntity = existing
            score = existing.score
        } else {
            let newEntity = EffectivenessScore()
            context.insert(newEntity)
            scoreEntity = newEntity
            score = 0
        }
    }

    private func checkAchievementsForCurrentScore() {
        let descriptor = FetchDescriptor<Achievement>(
            predicate: #Predicate { !$0.isUnlocked && $0.threshold <= score }
        )
        guard let toUnlock = try? context.fetch(descriptor) else { return }
        for achievement in toUnlock {
            achievement.isUnlocked = true
            achievement.unlockedDate = .now
            HapticManager.shared.notification(type: .success)
        }
        try? context.save()
    }

    private func checkAllAchievements() {
        checkAchievementsForCurrentScore()
    }
}

// MARK: - Main App Entry
@main
struct MindfulMomentsApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: EffectivenessScore.self, TaskItem.self, Achievement.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(EffectivenessTracker(context: container.mainContext))
                .modelContainer(container)
        }
    }
}

// MARK: - ContentView
struct ContentView: View {
    @State private var showFeatures = false
    @State private var cloudOffset: CGFloat = -Screen.width
    @State private var showOnboarding = false
    @State private var showingEffectivenessDetail = false
    @State private var showingSettings = false
    @State private var showingAchievements = false
    @State private var showWelcomePopup = false
    @State private var pendingPopupAfterOnboarding = false
    @EnvironmentObject var tracker: EffectivenessTracker
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) var systemReduceMotion
    @AppStorage("reduceAnimations") private var reduceAnimations = false
    @AppStorage("hasLaunchedBefore") private var hasLaunchedBefore = false

    let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationView {
            ZStack {
                BackgroundView(cloudOffset: $cloudOffset)

                VStack {
                    VStack(spacing: 5) {
                        Text("Mindful")
                            .font(.custom("Arial Rounded MT Bold", size: 42, relativeTo: .largeTitle))
                            .foregroundColor(.white)
                            .shadow(color: Color(red: 0.6, green: 0.9, blue: 0.8).opacity(0.5), radius: 10, x: 0, y: 5)
                        Text("Moments")
                            .font(.custom("Arial Rounded MT Bold", size: 42, relativeTo: .largeTitle))
                            .foregroundColor(Color(red: 0.6, green: 0.9, blue: 0.8))
                    }
                    .padding(.top, 30)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Mindful Moments")

                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    gradient: Gradient(colors: [
                                        Color(red: 0.6, green: 0.9, blue: 0.8).opacity(0.3),
                                        Color(red: 0.4, green: 0.7, blue: 0.6).opacity(0.1),
                                        .clear
                                    ]),
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 140
                                )
                            )
                            .frame(width: 240, height: 240)

                        Image("mindfulm-removebg-preview")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 180, height: 180)
                            .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
                            .accessibilityHidden(true)
                    }

                    Text("Find your peace in every moment")
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.top, 5)

                    if showFeatures {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(0..<featureTitles.count, id: \.self) { index in
                                FeatureCard(
                                    title: featureTitles[index],
                                    icon: featureIcons[index],
                                    color: featureColors[index],
                                    destination: featureDestinations[index]
                                )
                                .transition(.scale.combined(with: .opacity))
                                .accessibilityHint("Opens this feature")
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                    }

                    Spacer()

                    VStack(spacing: 8) {
                        HStack(spacing: 4) {
                            ForEach(0..<5) { _ in
                                Circle()
                                    .fill(Color.white.opacity(0.4))
                                    .frame(width: 4, height: 4)
                            }
                        }
                        Text("Begin your mindfulness journey today")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.bottom, 20)
                    .opacity(showFeatures ? 1 : 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack {
                    HStack {
                        Button(action: { showingAchievements = true }) {
                            Image(systemName: "trophy.fill")
                                .font(.title2)
                                .foregroundColor(.yellow)
                                .padding(8)
                                .background(Color.white.opacity(0.2))
                                .clipShape(Circle())
                        }
                        .accessibilityLabel("Achievements")

                        Spacer()

                        EffectivenessBadge(score: tracker.score)
                            .onTapGesture { showingEffectivenessDetail = true }

                        Button(action: { showingSettings = true }) {
                            Image(systemName: "gearshape.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.white.opacity(0.2))
                                .clipShape(Circle())
                        }
                        .accessibilityLabel("Settings")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 40)

                    Spacer()
                }

                if showWelcomePopup {
                    welcomePopup
                }

                if tracker.showCompletionCelebration {
                    completionCelebration
                }
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .sheet(isPresented: $showingEffectivenessDetail) { EffectivenessDetailView() }
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .sheet(isPresented: $showingAchievements) { AchievementsView() }
        .onAppear {
            let effectiveReduceMotion = systemReduceMotion || reduceAnimations
            if !effectiveReduceMotion {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) { showFeatures = true }
                }
                withAnimation(.linear(duration: 30).repeatForever(autoreverses: false)) {
                    cloudOffset = Screen.width
                }
            } else {
                showFeatures = true
            }

            if !hasLaunchedBefore {
                showOnboarding = true
                hasLaunchedBefore = true
            }

            let descriptor = FetchDescriptor<Achievement>()
            if let count = try? modelContext.fetchCount(descriptor), count == 0 {
                createDefaultAchievements(in: modelContext)
            }

            if showOnboarding {
                pendingPopupAfterOnboarding = true
            } else {
                withAnimation(.easeIn(duration: 0.5)) {
                    showWelcomePopup = true
                }
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView()
                .onDisappear {
                    if pendingPopupAfterOnboarding {
                        withAnimation(.easeIn(duration: 0.5)) {
                            showWelcomePopup = true
                        }
                        pendingPopupAfterOnboarding = false
                    }
                }
        }
    }

    private var welcomePopup: some View {
        Color.black.opacity(0.4)
            .ignoresSafeArea()
            .overlay(
                VStack(spacing: 20) {
                    Image(systemName: "hand.wave.fill")
                        .font(.system(size: 70))
                        .foregroundColor(.yellow)
                        .shadow(color: .yellow, radius: 15)
                        .scaleEffect(showWelcomePopup ? 1 : 0.8)
                        .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: showWelcomePopup)

                    Text("Welcome to Mindful Moments!")
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white)

                    Text("Let's get started on your journey to peace and mindfulness.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal)

                    Text("Tap anywhere to continue")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.top, 8)
                }
                .padding(30)
                .background(
                    RoundedRectangle(cornerRadius: 25)
                        .fill(.ultraThinMaterial)
                        .background(
                            RoundedRectangle(cornerRadius: 25)
                                .stroke(
                                    LinearGradient(
                                        colors: [.yellow, .orange, .white],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 4
                                )
                                .shadow(color: .yellow, radius: 15)
                        )
                )
                .padding(40)
                .transition(.scale.combined(with: .opacity))
            )
            .zIndex(1)
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.5)) {
                    showWelcomePopup = false
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    withAnimation(.easeOut(duration: 0.5)) {
                        showWelcomePopup = false
                    }
                }
            }
    }

    private var completionCelebration: some View {
        Color.black.opacity(0.6)
            .ignoresSafeArea()
            .overlay(
                VStack(spacing: 25) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.yellow)
                        .shadow(color: .yellow, radius: 20)
                        .scaleEffect(1.2)
                        .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: tracker.showCompletionCelebration)

                    Text("Congratulations!")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    Text("You've reached an effectiveness score of 200 and unlocked all achievements!")
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal)

                    Text("You've completed your mindfulness journey. Well done!")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal)

                    Button("Continue") {
                        withAnimation(.easeOut(duration: 0.5)) {
                            tracker.showCompletionCelebration = false
                        }
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: 200)
                    .background(Color.green)
                    .cornerRadius(12)
                    .padding(.top, 20)
                }
                .padding(40)
                .background(
                    RoundedRectangle(cornerRadius: 30)
                        .fill(.ultraThinMaterial)
                        .background(
                            RoundedRectangle(cornerRadius: 30)
                                .stroke(
                                    LinearGradient(
                                        colors: [.yellow, .green, .white],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 5
                                )
                                .shadow(color: .yellow, radius: 20)
                        )
                )
                .padding(30)
                .transition(.scale.combined(with: .opacity))
            )
            .zIndex(2)
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.5)) {
                    tracker.showCompletionCelebration = false
                }
            }
    }

    private func createDefaultAchievements(in context: ModelContext) {
        let thresholds = Array(stride(from: 5, through: 200, by: 5))
        for thresh in thresholds {
            let id = "score_\(thresh)"
            let name = "Score \(thresh)"
            let description = "Reach an effectiveness score of \(thresh)"
            let achievement = Achievement(
                id: id,
                name: name,
                description: description,
                iconName: "leaf.fill",
                threshold: thresh
            )
            context.insert(achievement)
        }
        try? context.save()
    }

    private let featureTitles = ["Memory Game", "Riddles", "Checklist", "Meditation"]
    private let featureIcons = ["gamecontroller", "questionmark.circle", "checkmark.square", "leaf"]
    private let featureColors: [Color] = [
        Color(red: 0.4, green: 0.8, blue: 0.7),
        Color(red: 0.8, green: 0.7, blue: 0.4),
        Color(red: 0.7, green: 0.6, blue: 0.9),
        Color(red: 0.9, green: 0.5, blue: 0.7)
    ]

    private var featureDestinations: [AnyView] {
        [
            AnyView(MemoryMatchingView()),
            AnyView(RiddlesView()),
            AnyView(DailyChecklistView()),
            AnyView(MeditationYogaView())
        ]
    }
}

// MARK: - Effectiveness Badge
struct EffectivenessBadge: View {
    let score: Int
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.blue.opacity(0.3))
                .frame(width: 44, height: 44)
                .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 2))
                .background(Circle().fill(.ultraThinMaterial).shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2))
            Text("\(score)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        }
        .accessibilityLabel("Effectiveness score: \(score)")
    }
}

// MARK: - Effectiveness Detail View
struct EffectivenessDetailView: View {
    @EnvironmentObject var tracker: EffectivenessTracker
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var context
    @Query private var achievements: [Achievement]
    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(colors: [Color(red: 0.05, green: 0.15, blue: 0.25), Color(red: 0.02, green: 0.1, blue: 0.2)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
                VStack(spacing: 30) {
                    Text("Effectiveness Score").font(.largeTitle).fontWeight(.bold).foregroundColor(.white)
                    ZStack {
                        Circle().fill(Color.blue.opacity(0.3)).frame(width: 120, height: 120).overlay(Circle().stroke(Color.white, lineWidth: 3))
                        Text("\(tracker.score)").font(.system(size: 48, weight: .bold)).foregroundColor(.white)
                    }
                    Text("You earn 1 point each time you:").font(.title2).foregroundColor(.white)
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Complete the memory game", systemImage: "gamecontroller")
                        Label("Reveal a riddle answer", systemImage: "questionmark")
                        Label("Finish all checklist tasks", systemImage: "checklist")
                        Label("Complete a meditation session", systemImage: "leaf")
                    }.font(.headline).foregroundColor(.white.opacity(0.9)).padding().background(Color.white.opacity(0.2)).cornerRadius(16)

                    if tracker.score == 200 {
                        Text("🏆 You've reached the maximum score! 🏆")
                            .font(.headline)
                            .foregroundColor(.yellow)
                            .padding()
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(16)
                    }

                    if !achievements.filter({ $0.isUnlocked }).isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Recent Achievements").font(.headline).foregroundColor(.white)
                            ForEach(achievements.filter { $0.isUnlocked }.sorted(by: { $0.threshold > $1.threshold }).prefix(3)) { achievement in
                                HStack {
                                    Image(systemName: achievement.iconName).foregroundColor(.yellow)
                                    Text(achievement.name).foregroundColor(.white)
                                }
                            }
                        }.padding().background(Color.white.opacity(0.15)).cornerRadius(16)
                    }
                    Spacer()
                    Button("Done") { dismiss() }.font(.headline).foregroundColor(.white).padding().frame(maxWidth: 200).background(Color.blue).cornerRadius(12)
                }.padding()
            }.navigationBarHidden(true)
        }
    }
}

// MARK: - Feature Card
struct FeatureCard: View {
    let title: String; let icon: String; let color: Color; let destination: AnyView
    @State private var isPressed = false
    @State private var animateGradient = false
    @State private var glowAmount: CGFloat = 0.5
    @Environment(\.accessibilityReduceMotion) var systemReduceMotion
    @AppStorage("reduceAnimations") private var reduceAnimations = false
    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    var effectiveReduceMotion: Bool { systemReduceMotion || reduceAnimations }

    var body: some View {
        NavigationLink(destination: destination) {
            VStack(spacing: dynamicTypeSize > .xxLarge ? 8 : 16) {
                Image(systemName: icon)
                    .font(.system(size: dynamicTypeSize > .xxLarge ? 48 : 36))
                    .symbolEffect(.bounce, value: isPressed)
                    .frame(height: 40)
                    .shadow(color: color.opacity(0.8), radius: glowAmount * 10, x: 0, y: 0)
                    .animation(effectiveReduceMotion ? nil : Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: glowAmount)
                Text(title).font(.title3).fontWeight(.semibold).multilineTextAlignment(.center).shadow(color: .white.opacity(0.3), radius: 2, x: 0, y: 1)
            }
            .frame(maxWidth: .infinity, minHeight: dynamicTypeSize > .xxLarge ? 150 : 120)
            .padding(.vertical, dynamicTypeSize > .xxLarge ? 32 : 24)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 28).fill(color.opacity(0.5)).blur(radius: 12).scaleEffect(1.05).opacity(glowAmount)
                    RoundedRectangle(cornerRadius: 28).fill(
                        LinearGradient(colors: [color.opacity(0.8), color, color.opacity(0.9)], startPoint: animateGradient ? .topLeading : .bottomLeading, endPoint: animateGradient ? .bottomTrailing : .topTrailing)
                    )
                    .shadow(color: color.opacity(0.5), radius: isPressed ? 4 : 10, x: 0, y: isPressed ? 2 : 8)
                    .overlay(RoundedRectangle(cornerRadius: 28).stroke(LinearGradient(colors: [.white.opacity(0.6), .clear], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2))
                }
            )
            .foregroundColor(.white)
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .rotation3DEffect(.degrees(isPressed ? 2 : 0), axis: (x: 1, y: 1, z: 0))
            .animation(effectiveReduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true; HapticManager.shared.impact(style: .light); if !effectiveReduceMotion { withAnimation(.linear(duration: 2).repeatForever(autoreverses: true)) { animateGradient.toggle() } } }
                .onEnded { _ in isPressed = false; animateGradient = false }
        )
        .onAppear { if !effectiveReduceMotion { withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) { glowAmount = 0.8 } } }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(title)
        .accessibilityHint("Opens \(title)")
    }
}

// MARK: - Background Views
struct BackgroundView: View {
    @Binding var cloudOffset: CGFloat
    @Environment(\.accessibilityReduceMotion) var systemReduceMotion
    @AppStorage("reduceAnimations") private var reduceAnimations = false
    var effectiveReduceMotion: Bool { systemReduceMotion || reduceAnimations }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.05, green: 0.15, blue: 0.25), Color(red: 0.02, green: 0.1, blue: 0.2), Color(red: 0.08, green: 0.2, blue: 0.3)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            if !effectiveReduceMotion {
                MovingStarsView()
                ForEach(0..<10) { index in CloudElement(index: index, offset: $cloudOffset) }
                SparkleOverlay().allowsHitTesting(false)
            }
        }
    }
}

struct MovingStarsView: View {
    let starCount = 100
    @State private var initialPositions: [CGPoint] = []
    @State private var speeds: [CGSize] = []
    @Environment(\.accessibilityReduceMotion) var systemReduceMotion
    @AppStorage("reduceAnimations") private var reduceAnimations = false
    var effectiveReduceMotion: Bool { systemReduceMotion || reduceAnimations }

    var body: some View {
        GeometryReader { geometry in
            if !effectiveReduceMotion {
                TimelineView(.animation(minimumInterval: 0.05, paused: false)) { timeline in
                    Canvas { context, size in
                        guard initialPositions.count == starCount, speeds.count == starCount else { return }
                        let time = timeline.date.timeIntervalSinceReferenceDate
                        for i in 0..<starCount {
                            let start = initialPositions[i]
                            let speed = speeds[i]
                            var x = start.x + speed.width * CGFloat(time)
                            var y = start.y + speed.height * CGFloat(time)
                            x = x.truncatingRemainder(dividingBy: size.width)
                            if x < 0 { x += size.width }
                            y = y.truncatingRemainder(dividingBy: size.height)
                            if y < 0 { y += size.height }
                            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2, height: 2)), with: .color(.white.opacity(Double.random(in: 0.3...0.9))))
                        }
                    }
                }
                .onAppear { updatePositions(for: geometry.size) }
                .onChange(of: geometry.size) { _, newSize in
                    updatePositions(for: newSize)
                }
            }
        }.ignoresSafeArea()
    }
    private func updatePositions(for size: CGSize) {
        initialPositions = (0..<starCount).map { _ in CGPoint(x: .random(in: 0...size.width), y: .random(in: 0...size.height)) }
        speeds = (0..<starCount).map { _ in CGSize(width: .random(in: 10...30), height: .random(in: 5...20)) }
    }
}

struct CloudElement: View {
    let index: Int; @Binding var offset: CGFloat
    @Environment(\.accessibilityReduceMotion) var systemReduceMotion
    @AppStorage("reduceAnimations") private var reduceAnimations = false
    var effectiveReduceMotion: Bool { systemReduceMotion || reduceAnimations }

    var body: some View {
        let size = CGFloat(40 + index * 8)
        let opacity = Double(0.05 + Double(index) * 0.015)
        let yPosition = CGFloat(100 + index * 60)
        let speed = Double(25 + index * 3)
        Image(systemName: "cloud.fill")
            .font(.system(size: size))
            .foregroundColor(.white.opacity(opacity))
            .offset(x: effectiveReduceMotion ? 0 : offset + CGFloat(index) * 100, y: yPosition)
            .animation(effectiveReduceMotion ? nil : .linear(duration: speed).repeatForever(autoreverses: false), value: offset)
    }
}

struct SparkleOverlay: View {
    let sparkleCount = 40
    @State private var sparkles: [Sparkle] = []
    let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
    @Environment(\.accessibilityReduceMotion) var systemReduceMotion
    @AppStorage("reduceAnimations") private var reduceAnimations = false
    var effectiveReduceMotion: Bool { systemReduceMotion || reduceAnimations }

    struct Sparkle: Identifiable { let id = UUID(); var x: CGFloat; var y: CGFloat; var size: CGFloat; var color: Color; var speedX: CGFloat; var speedY: CGFloat }
    var body: some View {
        if !effectiveReduceMotion {
            GeometryReader { geometry in
                ZStack {
                    ForEach(sparkles) { sparkle in
                        Circle().fill(sparkle.color).frame(width: sparkle.size, height: sparkle.size).position(x: sparkle.x, y: sparkle.y).opacity(0.5)
                    }
                }
                .onAppear { initializeSparkles(in: geometry.size) }
                .onChange(of: geometry.size) { _, newSize in
                    initializeSparkles(in: newSize)
                }
                .onReceive(timer) { _ in
                    withAnimation(.linear(duration: 0.05)) {
                        for i in 0..<sparkles.count {
                            sparkles[i].x += sparkles[i].speedX * 0.01
                            sparkles[i].y += sparkles[i].speedY * 0.01
                            if sparkles[i].x < 0 { sparkles[i].x = geometry.size.width }
                            if sparkles[i].x > geometry.size.width { sparkles[i].x = 0 }
                            if sparkles[i].y < 0 { sparkles[i].y = geometry.size.height }
                            if sparkles[i].y > geometry.size.height { sparkles[i].y = 0 }
                        }
                    }
                }
            }.ignoresSafeArea()
        }
    }
    private func initializeSparkles(in size: CGSize) {
        sparkles = (0..<sparkleCount).map { _ in
            Sparkle(x: .random(in: 0...size.width), y: .random(in: 0...size.height), size: .random(in: 2...5), color: [Color.yellow, Color.white, Color(red: 0.8, green: 0.9, blue: 1.0)].randomElement()!, speedX: .random(in: -15...15), speedY: .random(in: -15...15))
        }
    }
}

// MARK: - Memory Matching Game
struct MemoryMatchingView: View {
    @State private var cloudOffset: CGFloat = -Screen.width
    @State private var emojis = ["🌙", "⭐", "🌠", "✨", "🌌", "🌃", "🌉", "🏙️", "🌙", "⭐", "🌠", "✨", "🌌", "🌃", "🌉", "🏙️"]
    @State private var flippedCards = Array(repeating: false, count: 16)
    @State private var flippedIndices = [Int]()
    @State private var matchedPairs = 0
    @State private var gameCompleted = false
    @State private var showConfetti = false
    @State private var cardScale: [CGFloat] = Array(repeating: 1.0, count: 16)
    @State private var floatingParticles: [Particle] = []
    @State private var cardRotation: [Double] = Array(repeating: 0, count: 16)
    @State private var cardGlow: [Bool] = Array(repeating: false, count: 16)
    @State private var matchPulse: [Bool] = Array(repeating: false, count: 16)
    @State private var boardShake = false
    @State private var showInstructions = true
    @State private var movesCount = 0
    @EnvironmentObject var tracker: EffectivenessTracker
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) var systemReduceMotion
    @AppStorage("reduceAnimations") private var reduceAnimations = false
    var effectiveReduceMotion: Bool { systemReduceMotion || reduceAnimations }

    struct Particle: Identifiable { let id = UUID(); var x: CGFloat; var y: CGFloat; var size: CGFloat; var opacity: Double; var speed: Double; var color: Color }

    var body: some View {
        ZStack {
            BackgroundView(cloudOffset: $cloudOffset)
            VStack {
                HStack {
                    VStack { Text("Pairs").font(.caption).foregroundColor(.white.opacity(0.7)); Text("\(matchedPairs)/8").font(.title2).fontWeight(.bold).foregroundColor(.white) }
                    Spacer()
                    Text("Memory Game").font(.title2).fontWeight(.bold).foregroundColor(.white).shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1).scaleEffect(gameCompleted ? 1.1 : 1.0).animation(gameCompleted && !effectiveReduceMotion ? .easeInOut(duration: 1).repeatForever(autoreverses: true) : nil, value: gameCompleted)
                    Spacer()
                    VStack { Text("Moves").font(.caption).foregroundColor(.white.opacity(0.7)); Text("\(movesCount)").font(.title2).fontWeight(.bold).foregroundColor(.white) }
                }.padding(.horizontal).padding(.top, 20)

                if gameCompleted {
                    VStack(spacing: 10) {
                        Text("🎉 Congratulations! 🎉").font(.title3).fontWeight(.bold).foregroundColor(.white).scaleEffect(showConfetti ? 1.2 : 1.0)
                        Text("You've matched all the cards!").font(.headline).foregroundColor(.white)
                        Text("in \(movesCount) moves").font(.subheadline).foregroundColor(.white.opacity(0.8))
                    }.padding().frame(maxWidth: .infinity).background(Color.white.opacity(0.2)).cornerRadius(12).padding(.horizontal).shadow(radius: 5).transition(.scale.combined(with: .opacity))
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                    ForEach(emojis.indices, id: \.self) { index in
                        CardView(emoji: emojis[index], isFlipped: flippedCards[index], isMatched: matchedPairs > 0 && flippedCards[index], glow: cardGlow[index], pulse: matchPulse[index])
                            .scaleEffect(cardScale[index])
                            .rotation3DEffect(.degrees(cardRotation[index]), axis: (x: 0, y: 1, z: 0))
                            .onTapGesture { flipCard(at: index) }
                            .accessibilityLabel(flippedCards[index] ? "card with \(emojis[index])" : "face down card")
                            .accessibilityHint(flippedCards[index] ? "" : "Double tap to flip")
                            .accessibilityAddTraits(.isButton)
                    }
                }.padding().modifier(ShakeEffect(shake: boardShake))

                Spacer()

                if gameCompleted || movesCount > 0 {
                    Button(action: resetGame) { HStack { Image(systemName: "arrow.clockwise"); Text("Play Again") } }
                        .font(.headline).foregroundColor(.white).padding().frame(maxWidth: .infinity).background(Color.blue.opacity(0.7)).cornerRadius(12).padding(.horizontal).shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 2).padding(.bottom).transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !effectiveReduceMotion { createFloatingParticles() }
            if showInstructions { DispatchQueue.main.asyncAfter(deadline: .now() + 3) { withAnimation(.easeOut(duration: 0.5)) { showInstructions = false } } }
        }
        .overlay(Group { if showInstructions { InstructionsOverlay().transition(.opacity) } })
    }

    func flipCard(at index: Int) {
        guard !flippedCards[index] && flippedIndices.count < 2 && !gameCompleted else { return }
        movesCount += 1
        HapticManager.shared.impact(style: .light)
        withAnimation(.easeOut(duration: 0.1)) { cardScale[index] = 0.95 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                cardScale[index] = 1.0
                flippedCards[index] = true
                cardRotation[index] = 180
            }
        }
        flippedIndices.append(index)
        if flippedIndices.count == 2 {
            let first = flippedIndices[0], second = flippedIndices[1]
            if emojis[first] == emojis[second] {
                HapticManager.shared.notification(type: .success)
                withAnimation(.easeInOut(duration: 0.3)) { matchPulse[first] = true; matchPulse[second] = true }
                withAnimation(.spring(response: 0.6, dampingFraction: 0.4)) { cardScale[first] = 1.1; cardScale[second] = 1.1 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.4)) { cardScale[first] = 1.0; cardScale[second] = 1.0; matchPulse[first] = false; matchPulse[second] = false }
                    withAnimation(.easeInOut(duration: 0.5)) { cardGlow[first] = true; cardGlow[second] = true }
                }
                matchedPairs += 1
                if matchedPairs == emojis.count / 2 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        withAnimation(.easeInOut(duration: 0.5)) { gameCompleted = true; showConfetti = true }
                        tracker.increment(for: "memory_game")
                        if !effectiveReduceMotion { createConfetti() }
                        HapticManager.shared.notification(type: .success)
                    }
                }
                flippedIndices.removeAll()
            } else {
                HapticManager.shared.notification(type: .error)
                withAnimation(.default) { boardShake = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { flippedCards[first] = false; flippedCards[second] = false; cardRotation[first] = 0; cardRotation[second] = 0 }
                    withAnimation(.default) { boardShake = false }
                    flippedIndices.removeAll()
                }
            }
        }
    }

    func resetGame() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            flippedCards = Array(repeating: false, count: 16)
            flippedIndices = []; matchedPairs = 0; gameCompleted = false; showConfetti = false
            cardScale = Array(repeating: 1.0, count: 16)
            cardRotation = Array(repeating: 0, count: 16)
            cardGlow = Array(repeating: false, count: 16)
            matchPulse = Array(repeating: false, count: 16)
            movesCount = 0; showInstructions = true
            emojis.shuffle()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { withAnimation(.easeOut(duration: 0.5)) { showInstructions = false } }
    }

    func createFloatingParticles() {
        floatingParticles = (0..<20).map { _ in
            Particle(
                x: .random(in: 0...Screen.width),
                y: .random(in: 0...Screen.height),
                size: .random(in: 2...6),
                opacity: .random(in: 0.1...0.3),
                speed: .random(in: 2...5),
                color: [Color.blue, Color.purple, Color.white].randomElement()!
            )
        }
        withAnimation(.linear(duration: 15).repeatForever(autoreverses: false)) {
            for i in 0..<floatingParticles.count {
                floatingParticles[i].y += CGFloat.random(in: 100...300)
                if floatingParticles[i].y > Screen.height {
                    floatingParticles[i].y = -20
                    floatingParticles[i].x = .random(in: 0...Screen.width)
                }
            }
        }
    }

    func createConfetti() {
        floatingParticles = (0..<50).map { _ in
            Particle(
                x: Screen.width/2,
                y: Screen.height/2,
                size: .random(in: 4...8),
                opacity: .random(in: 0.5...1.0),
                speed: .random(in: 1...3),
                color: [Color.blue, Color.purple, Color.white, Color.cyan].randomElement()!
            )
        }
        withAnimation(.spring(response: 0.8, dampingFraction: 0.3)) {
            for i in 0..<floatingParticles.count {
                let angle = Double.random(in: 0...(2 * .pi))
                let distance = CGFloat.random(in: 100...200)
                floatingParticles[i].x += cos(angle) * distance
                floatingParticles[i].y += sin(angle) * distance
            }
        }
    }
}

// MARK: - Card View
struct CardView: View {
    let emoji: String; let isFlipped: Bool; let isMatched: Bool; let glow: Bool; let pulse: Bool
    @Environment(\.accessibilityReduceMotion) var systemReduceMotion
    @AppStorage("reduceAnimations") private var reduceAnimations = false
    var effectiveReduceMotion: Bool { systemReduceMotion || reduceAnimations }

    var body: some View {
        ZStack {
            if !isFlipped {
                RoundedRectangle(cornerRadius: 10).fill(LinearGradient(colors: [Color(red: 0.1, green: 0.2, blue: 0.4), Color(red: 0.05, green: 0.1, blue: 0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 70, height: 70).overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.3), lineWidth: 2)).shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 4).overlay(ZStack { Circle().fill(Color.white.opacity(0.1)).frame(width: 8, height: 8).offset(x: -10, y: -10); Circle().fill(Color.white.opacity(0.1)).frame(width: 6, height: 6).offset(x: 15, y: 15); Circle().fill(Color.white.opacity(0.1)).frame(width: 4, height: 4).offset(x: -5, y: 12) })
            }
            if isFlipped {
                RoundedRectangle(cornerRadius: 10).fill(Color.white).frame(width: 70, height: 70).overlay(Text(emoji).font(.system(size: 30))).shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2).overlay(RoundedRectangle(cornerRadius: 10).stroke(LinearGradient(colors: [.white.opacity(0.8), .gray.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2)).overlay(glow ? RoundedRectangle(cornerRadius: 10).stroke(Color.blue, lineWidth: 3).scaleEffect(1.1) : nil).scaleEffect(pulse ? 1.05 : 1.0)
            }
        }
        .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.3)
        .opacity(isMatched ? 0.8 : 1.0).scaleEffect(isMatched ? 0.9 : 1.0)
        .animation(effectiveReduceMotion ? nil : .easeInOut(duration: 0.3), value: glow)
        .animation(effectiveReduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.5), value: pulse)
    }
}

// MARK: - Shake Effect
struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 2;
    var shakesPerUnit: CGFloat = 2;
    var animatableData: CGFloat
    init(shake: Bool) { animatableData = shake ? 1 : 0 }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: amount * sin(animatableData * .pi * shakesPerUnit), y: 0))
    }
}

// MARK: - Instructions Overlay
struct InstructionsOverlay: View {
    @State private var opacity: Double = 0
    @Environment(\.accessibilityReduceMotion) var systemReduceMotion
    @AppStorage("reduceAnimations") private var reduceAnimations = false
    var effectiveReduceMotion: Bool { systemReduceMotion || reduceAnimations }

    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            VStack(spacing: 20) {
                Text("How to Play").font(.title2).fontWeight(.bold).foregroundColor(.white)
                VStack(alignment: .leading, spacing: 15) {
                    HStack { Text("•"); Text("Tap cards to flip them over") }
                    HStack { Text("•"); Text("Find matching pairs of emojis") }
                    HStack { Text("•"); Text("Complete the game with the fewest moves possible") }
                }.foregroundColor(.white).padding().background(Color.black.opacity(0.5)).cornerRadius(12)
                Text("Tap anywhere to begin").font(.caption).foregroundColor(.white.opacity(0.8)).padding(.top)
            }.padding()
        }.opacity(opacity)
        .onAppear { withAnimation(effectiveReduceMotion ? nil : .easeIn(duration: 0.5)) { opacity = 1 } }
        .onTapGesture { withAnimation(effectiveReduceMotion ? nil : .easeOut(duration: 0.5)) { opacity = 0 } }
    }
}

// MARK: - Riddles View
struct RiddlesView: View {
    struct Riddle: Identifiable { let id = UUID(); let question: String; let answer: String }
    @State private var riddles: [Riddle] = [
        Riddle(question: "What has to be broken before you can use it?", answer: "An egg"),
        Riddle(question: "I'm tall when I'm young, and I'm short when I'm old. What am I?", answer: "A candle"),
        Riddle(question: "The more of me you take, the more you leave behind. What am I?", answer: "Footsteps"),
        Riddle(question: "What goes up but never comes down?", answer: "Your age"),
        Riddle(question: "I have keys but open no locks. What am I?", answer: "A piano"),
        Riddle(question: "What has hands but can't clap?", answer: "A clock"),
        Riddle(question: "The more you remove from me, the bigger I get. What am I?", answer: "A hole"),
        Riddle(question: "I speak without a mouth and hear without ears. What am I?", answer: "An echo"),
        Riddle(question: "The more you share me, the less you have. What am I?", answer: "A secret"),
        Riddle(question: "I have a heart that doesn't beat. What am I?", answer: "An artichoke"),
        Riddle(question: "What gets wetter the more it dries?", answer: "A towel"),
        Riddle(question: "What belongs to you but others use it more than you do?", answer: "Your name"),
        Riddle(question: "What is full of holes but still holds water?", answer: "A sponge"),
        Riddle(question: "I have cities, but no houses. What am I?", answer: "A map"),
        Riddle(question: "What can travel around the world while staying in the same place?", answer: "A stamp"),
        Riddle(question: "I have legs but do not walk. What am I?", answer: "A table"),
        Riddle(question: "I fly without wings, I cry without eyes. What am I?", answer: "A cloud"),
        Riddle(question: "I have an endless supply but am never enough. What am I?", answer: "Time"),
        Riddle(question: "I have a face, but no eyes, mouth, or nose. What am I?", answer: "A clock"),
        Riddle(question: "What can you catch but not throw?", answer: "A cold"),
        Riddle(question: "The more you use me, the duller I become. What am I?", answer: "A pencil"),
        Riddle(question: "What runs but never walks, has a bed but never sleeps?", answer: "A river"),
        Riddle(question: "What has a thumb and four fingers but isn't alive?", answer: "A glove"),
        Riddle(question: "What is always in front of you but can't be seen?", answer: "The future"),
        Riddle(question: "What has an eye but cannot see?", answer: "A needle"),
        Riddle(question: "What has words but never speaks?", answer: "A book"),
        Riddle(question: "What can fill a room but takes up no space?", answer: "Light"),
        Riddle(question: "The more you have of me, the less you see. What am I?", answer: "Darkness")
    ]
    @State private var currentRiddleIndex = 0
    @State private var showAnswer = false
    @State private var showHint = false
    @State private var cloudOffset: CGFloat = -Screen.width
    @EnvironmentObject var tracker: EffectivenessTracker
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) var systemReduceMotion
    @AppStorage("reduceAnimations") private var reduceAnimations = false
    @AppStorage("speechRate") private var speechRate = 0.42
    @AppStorage("autoReadRiddles") private var autoReadRiddles = false
    let speaker = AVSpeechSynthesizer()

    var effectiveReduceMotion: Bool { systemReduceMotion || reduceAnimations }

    var body: some View {
        ZStack {
            BackgroundView(cloudOffset: $cloudOffset)
            VStack(spacing: 22) {
                Text("Tap the card or press 'Reveal Answer'")
                    .foregroundColor(.white)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)

                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(showAnswer ? Color.white : Color(red: 0.1, green: 0.2, blue: 0.3))
                        .frame(height: 180)
                        .shadow(radius: 5)

                    Text(riddles[currentRiddleIndex].question)
                        .font(.title3)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding()
                        .opacity(showAnswer ? 0 : 1)

                    Text(riddles[currentRiddleIndex].answer)
                        .font(.title2)
                        .bold()
                        .foregroundColor(.black)
                        .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                        .opacity(showAnswer ? 1 : 0)
                }
                .rotation3DEffect(.degrees(showAnswer ? 180 : 0), axis: (x: 0, y: 1, z: 0))
                .animation(effectiveReduceMotion ? nil : .easeInOut(duration: 0.45), value: showAnswer)
                .padding(.horizontal)
                .onTapGesture {
                    if !showAnswer {
                        revealAnswer()
                    }
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(showAnswer ? "Answer: \(riddles[currentRiddleIndex].answer)" : "Question: \(riddles[currentRiddleIndex].question)")

                if showHint && !showAnswer {
                    Text("Hint: First letter: '\(String(riddles[currentRiddleIndex].answer.prefix(1)))'")
                        .foregroundColor(.yellow)
                        .font(.subheadline)
                }

                VStack(spacing: 15) {
                    Button("Reveal Answer") {
                        if !showAnswer {
                            revealAnswer()
                        }
                    }
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.orange.opacity(0.8))
                    .cornerRadius(12)
                    .disabled(showAnswer)

                    Button(showHint ? "Hide Hint" : "Show Hint") {
                        HapticManager.shared.impact(style: .light)
                        showHint.toggle()
                    }
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.opacity(0.7))
                    .cornerRadius(12)

                    Button("Next Riddle") {
                        HapticManager.shared.impact(style: .light)
                        withAnimation(effectiveReduceMotion ? nil : .easeInOut(duration: 0.3)) {
                            showAnswer = false
                            showHint = false
                            currentRiddleIndex = (currentRiddleIndex + 1) % riddles.count
                        }
                    }
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.purple.opacity(0.7))
                    .cornerRadius(12)
                }
                .padding(.horizontal)

                Spacer()
            }
        }
    }

    private func revealAnswer() {
        HapticManager.shared.impact(style: .light)
        tracker.increment(for: "riddle")

        if autoReadRiddles {
            let utterance = AVSpeechUtterance(string: riddles[currentRiddleIndex].answer)
            utterance.rate = Float(speechRate)
            utterance.pitchMultiplier = 1.1
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            speaker.speak(utterance)
        }

        withAnimation(effectiveReduceMotion ? nil : .easeInOut(duration: 0.45)) {
            showAnswer = true
        }
    }
}

// MARK: - Daily Checklist View
struct DailyChecklistView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TaskItem.createdAt) private var tasks: [TaskItem]
    @State private var newTask = ""
    @State private var selectedIcon = "📝"
    @State private var caregiverMode = false
    @State private var showCompletionMessage = false
    @State private var stars: [Particle] = []
    @State private var starships: [Particle] = []
    @AppStorage("lastChecklistDate") private var lastChecklistDate = ""
    @AppStorage("speechRate") private var speechRate = 0.42
    let icons = ["📝", "💊", "🥤", "🍽️", "🚶", "🛏️", "📞", "🧘"]
    let speaker = AVSpeechSynthesizer()
    @State private var cloudOffset: CGFloat = -Screen.width
    @EnvironmentObject var tracker: EffectivenessTracker
    @Environment(\.accessibilityReduceMotion) var systemReduceMotion
    @AppStorage("reduceAnimations") private var reduceAnimations = false
    var effectiveReduceMotion: Bool { systemReduceMotion || reduceAnimations }

    struct Particle: Identifiable { let id = UUID(); var x: CGFloat; var y: CGFloat; var size: CGFloat; var opacity: Double; var speed: Double; var color: Color }
    var completedCount: Int { tasks.filter { $0.isCompleted }.count }

    var body: some View {
        ZStack {
            BackgroundView(cloudOffset: $cloudOffset)
            if !effectiveReduceMotion {
                ForEach(starships) { ship in
                    Image(systemName: "rocket.fill").resizable().frame(width: ship.size * 2.2, height: ship.size * 2.2).foregroundColor(ship.color).rotationEffect(.degrees(45)).opacity(ship.opacity).position(x: ship.x, y: ship.y).shadow(color: ship.color.opacity(0.6), radius: 10)
                }
            }
            VStack(spacing: 14) {
                Text("Daily Checklist").font(.title2).fontWeight(.bold).foregroundColor(.white)

                MoodCheckInCard().padding(.horizontal)
                Toggle("Caregiver Mode", isOn: $caregiverMode).toggleStyle(SwitchToggleStyle(tint: .green)).padding(.horizontal).foregroundColor(.white).accessibilityHint("Enable to add or delete tasks")
                if caregiverMode {
                    HStack {
                        Picker("", selection: $selectedIcon) { ForEach(icons, id: \.self) { Text($0) } }.pickerStyle(MenuPickerStyle())
                        TextField("New task", text: $newTask).textFieldStyle(RoundedBorderTextFieldStyle()).accessibilityLabel("Enter new task")
                        Button { guard !newTask.isEmpty else { return }; HapticManager.shared.impact(style: .medium); let task = TaskItem(title: newTask, icon: selectedIcon); context.insert(task); newTask = "" } label: { Image(systemName: "plus.circle.fill").font(.title2).foregroundColor(.white) }.accessibilityLabel("Add task")
                    }.padding(.horizontal)
                }
                Button("🔊 Read My Tasks") { speakTasks() }.foregroundColor(.white.opacity(0.9)).accessibilityHint("Listen to your tasks")
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(tasks) { task in
                            HStack {
                                Text(task.icon).font(.title2)
                                Text(task.title).foregroundColor(.white).strikethrough(task.isCompleted).opacity(task.isCompleted ? 0.6 : 1)
                                Spacer()
                                Circle().stroke(Color.white, lineWidth: 2).frame(width: 26, height: 26)
                                    .overlay(task.isCompleted ? Image(systemName: "checkmark").foregroundColor(.white) : nil)
                                    .onTapGesture { toggleTask(task) }
                                    .accessibilityLabel(task.isCompleted ? "Completed" : "Not completed")
                                    .accessibilityHint("Tap to toggle completion")
                                if caregiverMode {
                                    Button { context.delete(task); HapticManager.shared.impact(style: .medium) } label: { Image(systemName: "trash").foregroundColor(.red.opacity(0.8)) }.accessibilityLabel("Delete task")
                                }
                            }.padding().background(Color.white.opacity(0.15)).cornerRadius(12).padding(.horizontal)
                        }
                    }
                }
                if showCompletionMessage {
                    VStack(spacing: 8) {
                        Text("🌟 Good Job! 🌟").font(.title).fontWeight(.bold)
                        Text("All tasks completed").font(.headline)
                    }.foregroundColor(.white).padding().frame(maxWidth: .infinity).background(Color.green.opacity(0.85)).cornerRadius(18).padding(.horizontal).transition(.scale.combined(with: .opacity))
                }
                Spacer()
            }
        }
        .onAppear {
            resetIfNewDay()
            if !effectiveReduceMotion { createStars(); createStarships() }
        }
    }

    func toggleTask(_ task: TaskItem) {
        task.isCompleted.toggle()
        HapticManager.shared.impact(style: .light)
        if task.isCompleted { HapticManager.shared.notification(type: .success) }
        try? context.save()
        let allCompleted = tasks.allSatisfy { $0.isCompleted }
        if allCompleted && !tasks.isEmpty {
            withAnimation(.spring()) { showCompletionMessage = true }
            tracker.increment(for: "checklist_complete")
            speakCompletion()
        } else { showCompletionMessage = false }
    }

    func speakTasks() {
        let text = tasks.isEmpty ? "You don't have any tasks right now. You're doing okay." : "Here are your tasks for today. " + tasks.map { $0.title }.joined(separator: ". ")
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = Float(speechRate); utterance.pitchMultiplier = 1.15; utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        speaker.speak(utterance)
    }

    func speakCompletion() {
        let utterance = AVSpeechUtterance(string: "Good job. You completed everything today. I'm proud of you.")
        utterance.rate = Float(speechRate); utterance.pitchMultiplier = 1.1; utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        speaker.speak(utterance)
    }

    func resetIfNewDay() {
        let today = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
        if today != lastChecklistDate {
            for task in tasks { task.isCompleted = false }
            try? context.save()
            showCompletionMessage = false
            lastChecklistDate = today
        }
    }

    func createStars() {
        stars = (0..<60).map { _ in
            Particle(
                x: .random(in: 0...Screen.width),
                y: .random(in: 0...Screen.height),
                size: .random(in: 1.5...3.5),
                opacity: .random(in: 0.2...0.6),
                speed: .random(in: 1...3),
                color: .white
            )
        }
        withAnimation(.linear(duration: 40).repeatForever(autoreverses: false)) {
            for i in stars.indices {
                stars[i].y += 600
                if stars[i].y > Screen.height {
                    stars[i].y = -20
                }
            }
        }
    }

    func createStarships() {
        let colors: [Color] = [.cyan, .purple, .pink, .orange, .green, .blue]
        starships = (0..<6).map { i in
            Particle(
                x: .random(in: -300...Screen.width),
                y: .random(in: 0...Screen.height * 0.6),
                size: .random(in: 18...26),
                opacity: 0.9,
                speed: .random(in: 6...10),
                color: colors[i % colors.count]
            )
        }
        withAnimation(.linear(duration: 16).repeatForever(autoreverses: false)) {
            for i in starships.indices {
                starships[i].x += 900
                starships[i].y += 300
                if starships[i].x > Screen.width + 300 {
                    starships[i].x = -300
                    starships[i].y = .random(in: 0...Screen.height * 0.6)
                }
            }
        }
    }
}

// MARK: - Meditation & Yoga View
struct MeditationYogaView: View {
    struct Pose: Identifiable {
        let id = UUID()
        let name: String
        let icon: String
        let description: String
        let detailedInstructions: String
        let benefits: String
        let duration: Int
        let breathingPattern: String
    }

    let poses: [Pose] = [
        Pose(
            name: "Lotus Pose",
            icon: "person.fill",
            description: "A classic seated pose for meditation that promotes stability and calm.",
            detailedInstructions: "Sit on the floor with your legs extended. Bend your right knee and place your right foot on your left thigh. Bend your left knee and place your left foot on your right thigh. Rest your hands on your knees with palms up. Keep your spine long and shoulders relaxed.",
            benefits: "Opens hips, improves posture, calms the mind, reduces muscle tension",
            duration: 180,
            breathingPattern: "Inhale for 4 counts, hold for 4, exhale for 6"
        ),
        Pose(
            name: "Child's Pose",
            icon: "figure.child",
            description: "A gentle resting pose that helps you feel safe and grounded.",
            detailedInstructions: "Kneel on the floor, touch your big toes together, and sit on your heels. Separate your knees about hip-width apart. Exhale and lay your torso down between your thighs. Rest your forehead on the floor. Extend your arms forward or rest them alongside your body.",
            benefits: "Gently stretches hips, thighs, and ankles; calms the brain; relieves stress",
            duration: 120,
            breathingPattern: "Slow, gentle breaths. Focus on the rise and fall of your back."
        ),
        Pose(
            name: "Cat-Cow Pose",
            icon: "figure.walk",
            description: "A gentle flow between two poses that warms up the spine.",
            detailedInstructions: "Start on hands and knees in a tabletop position. Inhale, drop your belly, lift your chest and tailbone (Cow). Exhale, round your spine, tuck your chin to chest (Cat). Flow smoothly between these poses with your breath.",
            benefits: "Improves spinal flexibility, massages abdominal organs, relieves back pain",
            duration: 150,
            breathingPattern: "Inhale for Cow, Exhale for Cat. Move with your breath."
        ),
        Pose(
            name: "Corpse Pose",
            icon: "bed.double.fill",
            description: "The ultimate relaxation pose. Lie down and let go completely.",
            detailedInstructions: "Lie on your back with legs extended and arms at your sides, palms up. Close your eyes. Let your feet fall open. Consciously relax every part of your body from head to toe. Stay still and breathe naturally.",
            benefits: "Calms the nervous system, reduces fatigue, integrates the benefits of your practice",
            duration: 300,
            breathingPattern: "Natural breath. Observe without changing it."
        ),
        Pose(
            name: "Seated Forward Fold",
            icon: "figure.seated.side",
            description: "A calming forward bend that stretches the entire back body.",
            detailedInstructions: "Sit with legs extended straight in front. Inhale and lengthen your spine. Exhale and hinge at your hips to fold forward. Reach for your feet or shins. Keep your spine long and relax into the stretch.",
            benefits: "Stretches spine, shoulders, hamstrings; calms the brain; relieves stress",
            duration: 120,
            breathingPattern: "Inhale to lengthen, exhale to fold deeper"
        ),
        Pose(
            name: "Mountain Pose",
            icon: "figure.stand",
            description: "The foundation of all standing poses. Find stillness and strength.",
            detailedInstructions: "Stand with feet together, weight evenly distributed. Engage your thighs, lift your kneecaps. Lengthen your tailbone toward the floor. Lift through the top of your head. Let your arms hang naturally at your sides.",
            benefits: "Improves posture, strengthens thighs, knees, and ankles; increases awareness",
            duration: 60,
            breathingPattern: "Stand tall, breathe deeply. Feel grounded like a mountain."
        ),
        Pose(
            name: "Tree Pose",
            icon: "figure.wave",
            description: "A balancing pose that promotes focus and stability.",
            detailedInstructions: "Start in Mountain Pose. Shift weight to your left foot. Place right foot on left inner thigh (or calf, avoiding knee). Bring hands to heart center or overhead. Focus on a steady point. Switch sides.",
            benefits: "Improves balance, strengthens legs, opens hips, increases focus",
            duration: 60,
            breathingPattern: "Breathe steadily. Find your balance point with each inhale."
        ),
        Pose(
            name: "Easy Pose",
            icon: "person.crop.circle",
            description: "A simple cross-legged seated position for meditation.",
            detailedInstructions: "Sit on a cushion if needed. Cross your shins, placing each foot under the opposite knee. Rest hands on knees. Lengthen spine, relax shoulders. Close eyes and focus on breath.",
            benefits: "Opens hips, calms the mind, promotes inner peace",
            duration: 180,
            breathingPattern: "Deep belly breathing. Inhale 4, exhale 6."
        )
    ]

    @State private var selectedPose: Pose? = nil
    @State private var sessionStarted = false
    @State private var isBreathingIn = true
    @State private var timeRemaining = 0
    @State private var showEndMessage = false
    @State private var showDetailedInstructions = false
    private let speaker = AVSpeechSynthesizer()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var cloudOffset: CGFloat = -Screen.width
    @EnvironmentObject var tracker: EffectivenessTracker
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) var systemReduceMotion
    @AppStorage("reduceAnimations") private var reduceAnimations = false
    @AppStorage("speechRate") private var speechRate = 0.42
    @AppStorage("meditationVoice") private var meditationVoice = true

    var effectiveReduceMotion: Bool { systemReduceMotion || reduceAnimations }

    var body: some View {
        ZStack {
            BackgroundView(cloudOffset: $cloudOffset)
            if selectedPose == nil {
                poseSelectionView
            } else {
                meditationView
            }
        }
        .onReceive(timer) { _ in
            if sessionStarted && timeRemaining > 0 {
                timeRemaining -= 1
                updateBreathingPattern()
                if timeRemaining == 0 { endMeditation() }
            }
        }
    }

    var poseSelectionView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Choose Your Practice")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.top, 30)

                Text("Listen to your body. Every pose is an invitation, not a demand.")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                ForEach(poses) { pose in
                    Button {
                        HapticManager.shared.impact(style: .light)
                        selectedPose = pose
                        timeRemaining = pose.duration
                    } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 16) {
                                Image(systemName: pose.icon)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 50, height: 50)
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(Color.white.opacity(0.2))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))

                                VStack(alignment: .leading) {
                                    Text(pose.name)
                                        .font(.title3)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)

                                    Text("\(pose.duration / 60):\(String(format: "%02d", pose.duration % 60)) min")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                }

                                Spacer()

                                Image(systemName: "info.circle")
                                    .foregroundColor(.white.opacity(0.6))
                            }

                            Text(pose.description)
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.9))
                                .lineLimit(2)
                        }
                        .padding()
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(16)
                        .padding(.horizontal)
                    }
                    .accessibilityLabel(pose.name)
                    .accessibilityHint(pose.description)
                }
            }
            .padding(.vertical)
        }
    }

    var meditationView: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text(selectedPose?.name ?? "")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.top, 20)

                Image(systemName: selectedPose?.icon ?? "person.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 100)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.white.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(radius: 8)

                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 200, height: 200)

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue.opacity(0.6), .purple.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 140, height: 140)
                        .scaleEffect(isBreathingIn ? 1.3 : 0.8)
                        .animation(effectiveReduceMotion ? nil : .easeInOut(duration: 4).repeatForever(autoreverses: true), value: isBreathingIn)

                    VStack {
                        Text(isBreathingIn ? "🌬️ Breathe In" : "💨 Breathe Out")
                            .font(.headline)
                            .foregroundColor(.white)

                        if sessionStarted {
                            Text("\(timeRemaining / 60):\(String(format: "%02d", timeRemaining % 60))")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.top, 4)
                        }
                    }
                }

                if let pose = selectedPose {
                    Text("Breathing Pattern")
                        .font(.headline)
                        .foregroundColor(.white)

                    Text(pose.breathingPattern)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }

                if let pose = selectedPose, !sessionStarted {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("✨ Benefits")
                            .font(.headline)
                            .foregroundColor(.white)

                        Text(pose.benefits)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                            .multilineTextAlignment(.leading)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.15))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }

                Button(showDetailedInstructions ? "Hide Instructions" : "Show Detailed Instructions") {
                    withAnimation {
                        showDetailedInstructions.toggle()
                    }
                }
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal)

                if showDetailedInstructions, let pose = selectedPose {
                    Text(pose.detailedInstructions)
                        .font(.body)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                        .padding()
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(12)
                        .padding(.horizontal)
                        .transition(.opacity)
                }

                if !sessionStarted && !showEndMessage {
                    Button(action: startMeditation) {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Begin Practice")
                        }
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.green.opacity(0.8))
                        .cornerRadius(14)
                        .padding(.horizontal)
                    }
                }

                if sessionStarted {
                    Button(action: endMeditation) {
                        Text("End Session Early")
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.8))
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.red.opacity(0.6))
                            .cornerRadius(14)
                            .padding(.horizontal)
                    }
                }

                if showEndMessage {
                    VStack(spacing: 16) {
                        Text("🧘‍♀️ Practice Complete 🧘‍♂️")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("You took time for yourself today. That's beautiful.")
                            .multilineTextAlignment(.center)
                            .font(.headline)

                        Text("Notice how you feel now compared to when you started.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)

                        Button("Choose Another Pose") {
                            withAnimation {
                                selectedPose = nil
                                sessionStarted = false
                                showEndMessage = false
                                showDetailedInstructions = false
                            }
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue.opacity(0.7))
                        .cornerRadius(14)
                        .padding(.top, 8)
                    }
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(16)
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }

    func startMeditation() {
        sessionStarted = true
        isBreathingIn = true
        showEndMessage = false
        if meditationVoice {
            speakInstructions()
        }
    }

    func endMeditation() {
        sessionStarted = false
        isBreathingIn = false
        showEndMessage = true
        tracker.increment(for: "meditation")
        if meditationVoice {
            speakEndMessage()
        }
        HapticManager.shared.notification(type: .success)
    }

    func updateBreathingPattern() {
        if timeRemaining % 4 == 0 {
            isBreathingIn.toggle()
        }
    }

    func speakInstructions() {
        guard let pose = selectedPose else { return }
        let instructions = """
        Let's begin \(pose.name). 
        \(pose.detailedInstructions)
        We'll practice for \(pose.duration / 60) minutes.
        Remember: \(pose.breathingPattern)
        """
        let utterance = AVSpeechUtterance(string: instructions)
        utterance.rate = Float(speechRate)
        utterance.pitchMultiplier = 1.1
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        speaker.speak(utterance)
    }

    func speakEndMessage() {
        let message = "Thank you for practicing with us today. Notice how your body feels. Carry this peace with you."
        let utterance = AVSpeechUtterance(string: message)
        utterance.rate = Float(speechRate)
        utterance.pitchMultiplier = 1.15
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        speaker.speak(utterance)
    }
}

// MARK: - Onboarding
struct OnboardingView: View {
    @Environment(\.dismiss) var dismiss
    @State private var currentPage = 0
    @State private var cloudOffset: CGFloat = -Screen.width
    @Environment(\.accessibilityReduceMotion) var systemReduceMotion
    @AppStorage("reduceAnimations") private var reduceAnimations = false
    var effectiveReduceMotion: Bool { systemReduceMotion || reduceAnimations }

    var body: some View {
        ZStack {
            BackgroundView(cloudOffset: $cloudOffset)
            TabView(selection: $currentPage) {
                OnboardingPage(title: "Welcome to Mindful Moments", description: "This app was born from my own journey. I created it to help others find small moments of peace in their day.", imageName: "heart.fill", color: .pink).tag(0)
                OnboardingPage(title: "Why Mindfulness?", description: "Through meditation, puzzles, and reflection, I learned to be kinder to myself. Now I want to share that with you.", imageName: "leaf.fill", color: .green).tag(1)
                OnboardingPage(title: "What You'll Find", description: "Games to sharpen your mind, riddles to spark curiosity, checklists to stay grounded, and meditations to breathe.", imageName: "sparkles", color: .orange).tag(2)
                OnboardingPage(title: "Let's Begin", description: "Take a deep breath. You're exactly where you need to be.", imageName: "hand.raised.fill", color: .purple, isLast: true, onDismiss: { dismiss() }).tag(3)
            }
            .tabViewStyle(PageTabViewStyle())
            .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .always))
        }
        .interactiveDismissDisabled()
    }
}

struct OnboardingPage: View {
    let title: String; let description: String; let imageName: String; let color: Color; var isLast = false; var onDismiss: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) var systemReduceMotion
    @AppStorage("reduceAnimations") private var reduceAnimations = false
    var effectiveReduceMotion: Bool { systemReduceMotion || reduceAnimations }

    var body: some View {
        VStack(spacing: 25) {
            Spacer()
            Image(systemName: imageName).font(.system(size: 80)).foregroundColor(color).symbolEffect(.bounce, options: .repeating, value: true).accessibilityHidden(true).shadow(color: color.opacity(0.6), radius: 10, x: 0, y: 5)
            Text(title).font(.largeTitle).fontWeight(.bold).foregroundColor(.white).multilineTextAlignment(.center).shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 2)
            Text(description).font(.title3).foregroundColor(.white.opacity(0.9)).multilineTextAlignment(.center).padding(.horizontal, 30)
            Spacer()
            if isLast {
                Button("Get Started") { onDismiss?() }
                    .font(.headline).foregroundColor(.white).padding().frame(maxWidth: 200).background(color).cornerRadius(12).shadow(color: color.opacity(0.5), radius: 10, x: 0, y: 5).padding(.bottom, 50)
            }
        }.padding().accessibilityElement(children: .combine)
    }
}

// MARK: - Mood Check‑In Card
struct MoodCheckInCard: View {
    @State private var mood: Double = 0.5
    @State private var showSuggestion = false
    @State private var suggestionText = ""
    @Environment(\.accessibilityReduceMotion) var systemReduceMotion
    @AppStorage("reduceAnimations") private var reduceAnimations = false
    var effectiveReduceMotion: Bool { systemReduceMotion || reduceAnimations }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How are you feeling right now?").font(.headline).foregroundColor(.white)
            Slider(value: $mood, in: 0...1, step: 0.01).accentColor(moodColor)
                .onChange(of: mood) { _, _ in
                    if !effectiveReduceMotion { withAnimation { updateSuggestion() } } else { updateSuggestion() }
                }
                .accessibilityLabel("Mood slider").accessibilityValue(String(format: "%.0f percent", mood * 100))
            if showSuggestion { Text(suggestionText).font(.subheadline).foregroundColor(.white.opacity(0.9)).padding(.top, 4).transition(effectiveReduceMotion ? .identity : .slide) }
        }.padding().background(Color.white.opacity(0.15)).cornerRadius(16).onAppear(perform: updateSuggestion)
    }
    var moodColor: Color { mood < 0.3 ? .red : mood < 0.6 ? .orange : .green }
    private func updateSuggestion() {
        if mood < 0.3 { suggestionText = "It's okay to feel low. Try a short meditation or talk to someone." }
        else if mood < 0.6 { suggestionText = "A gentle walk or a riddle might lift your spirits." }
        else { suggestionText = "You're in a good space! Why not play a memory game?" }
        showSuggestion = true
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject var tracker: EffectivenessTracker
    @State private var showingResetConfirmation = false
    @State private var showingResetAchievementsConfirmation = false

    @AppStorage("speechRate") private var speechRate = 0.42
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("dailyReminder") private var dailyReminder = false
    @AppStorage("autoReadRiddles") private var autoReadRiddles = false
    @AppStorage("meditationVoice") private var meditationVoice = true
    @AppStorage("reduceAnimations") private var reduceAnimations = false

    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(colors: [Color(red: 0.05, green: 0.15, blue: 0.25), Color(red: 0.02, green: 0.1, blue: 0.2)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
                Form {
                    Section(header: Text("Speech").foregroundColor(.white)) {
                        VStack {
                            Text("Speech rate: \(speechRate, specifier: "%.2f")")
                                .foregroundColor(.white)
                            Slider(value: $speechRate, in: 0.2...0.6, step: 0.02)
                                .accentColor(.blue)
                        }
                        Toggle("Auto‑read riddles", isOn: $autoReadRiddles)
                            .foregroundColor(.white)
                            .toggleStyle(SwitchToggleStyle(tint: .green))
                        Toggle("Meditation Voice Guidance", isOn: $meditationVoice)
                            .foregroundColor(.white)
                            .toggleStyle(SwitchToggleStyle(tint: .green))
                    }
                    .listRowBackground(Color.white.opacity(0.2))

                    Section(header: Text("Accessibility").foregroundColor(.white)) {
                        Toggle("Enable Haptics", isOn: $hapticsEnabled)
                            .foregroundColor(.white)
                            .toggleStyle(SwitchToggleStyle(tint: .green))
                        Toggle("Reduce Animations", isOn: $reduceAnimations)
                            .foregroundColor(.white)
                            .toggleStyle(SwitchToggleStyle(tint: .green))
                    }
                    .listRowBackground(Color.white.opacity(0.2))

                    Section(header: Text("Notifications").foregroundColor(.white)) {
                        Toggle("Daily Reminder", isOn: $dailyReminder)
                            .foregroundColor(.white)
                            .toggleStyle(SwitchToggleStyle(tint: .green))
                            .onChange(of: dailyReminder) { _, newValue in
                                if newValue {
                                    requestNotificationPermission()
                                    scheduleDailyReminder()
                                } else {
                                    cancelDailyReminder()
                                }
                            }
                    }
                    .listRowBackground(Color.white.opacity(0.2))

                    Section(header: Text("Data Management").foregroundColor(.white)) {
                        Button("Reset Achievements") {
                            showingResetAchievementsConfirmation = true
                        }
                        .foregroundColor(.orange)

                        Button("Reset All Data") {
                            showingResetConfirmation = true
                        }
                        .foregroundColor(.red)
                    }
                    .listRowBackground(Color.white.opacity(0.2))

                    Section(header: Text("About").foregroundColor(.white)) {
                        HStack {
                            Text("Version")
                                .foregroundColor(.white)
                            Spacer()
                            Text("1.0.4")
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.2))
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.white)
                }
            }
            .alert("Reset All Data?", isPresented: $showingResetConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) { resetAllData() }
            } message: {
                Text("This will delete all your progress and achievements. This cannot be undone.")
            }
            .alert("Reset Achievements?", isPresented: $showingResetAchievementsConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) { resetAchievements() }
            } message: {
                Text("This will reset all achievements. Your game scores will remain.")
            }
        }
    }

    private func resetAllData() {
        try? context.delete(model: EffectivenessScore.self)
        try? context.delete(model: TaskItem.self)
        try? context.delete(model: Achievement.self)
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        let newScore = EffectivenessScore()
        context.insert(newScore)
        createDefaultAchievements(in: context)
        try? context.save()
        tracker.reloadScore()
        tracker.showCompletionCelebration = false
    }

    private func resetAchievements() {
        try? context.delete(model: Achievement.self)
        createDefaultAchievements(in: context)
        try? context.save()
    }

    private func createDefaultAchievements(in context: ModelContext) {
        let thresholds = Array(stride(from: 5, through: 200, by: 5))
        for thresh in thresholds {
            let id = "score_\(thresh)"
            let name = "Score \(thresh)"
            let description = "Reach an effectiveness score of \(thresh)"
            let achievement = Achievement(
                id: id,
                name: name,
                description: description,
                iconName: "leaf.fill",
                threshold: thresh
            )
            context.insert(achievement)
        }
        try? context.save()
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func scheduleDailyReminder() {
        let content = UNMutableNotificationContent()
        content.title = "Mindful Moments"
        content.body = "Take a moment for yourself today."
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = 10
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        let request = UNNotificationRequest(identifier: "dailyReminder", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private func cancelDailyReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["dailyReminder"])
    }
}

// MARK: - Achievements View
struct AchievementsView: View {
    @Query(sort: \Achievement.threshold) private var achievements: [Achievement]
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(colors: [Color(red: 0.05, green: 0.15, blue: 0.25), Color(red: 0.02, green: 0.1, blue: 0.2)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(achievements) { achievement in
                            HStack {
                                Image(systemName: achievement.iconName)
                                    .font(.largeTitle)
                                    .foregroundColor(achievement.isUnlocked ? .yellow : .gray)
                                    .frame(width: 60)
                                    .shadow(color: achievement.isUnlocked ? .yellow : .clear, radius: 10)

                                VStack(alignment: .leading) {
                                    Text(achievement.name)
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    Text(achievement.achievementDescription)
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                    if let date = achievement.unlockedDate {
                                        Text("Unlocked \(date, formatter: dateFormatter)")
                                            .font(.caption2)
                                            .foregroundColor(.green)
                                    }
                                }
                                Spacer()
                                if achievement.isUnlocked {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundColor(.green)
                                }
                            }
                            .padding()
                            .background(Color.white.opacity(0.15))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Achievements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.white)
                }
            }
        }
    }
}

private let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    return f
}()
