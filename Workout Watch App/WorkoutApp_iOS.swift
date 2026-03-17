//
//  WorkoutApp_iOS.swift
//  Workout - iOS
//
//  Created by 山中雄樹 on 2026/03/04.
//

import SwiftUI
import Combine
import MediaPlayer
import AVFoundation
import WatchConnectivity
import HealthKit

// 🔥 アプリ終了時にワークアウトを確実に終了させるためのAppDelegate
class WorkoutAppDelegate: NSObject, UIApplicationDelegate {
    // WorkoutManagerの参照を保持（Appから設定される）
    weak var workoutManager: WorkoutManager?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        print("🚀 App launched")
        return true
    }
    
    // 🔥 アプリ終了時に呼ばれる（スワイプで終了した時も含む）
    func applicationWillTerminate(_ application: UIApplication) {
        print("🔴 ========================================")
        print("🔴 APPLICATION WILL TERMINATE")
        print("🔴 ========================================")
        
        guard let workoutManager = workoutManager else {
            print("⚠️ WorkoutManager reference is nil")
            return
        }
        
        if workoutManager.isWorkoutActive {
            print("🔴 ⚠️ Active workout detected during app termination!")
            print("🔴 Forcing workout to end to clean up Dynamic Island...")
            
            // 🔥 RunLoopを使って確実に処理を実行
            let runLoop = RunLoop.current
            var finished = false
            
            Task.detached { @MainActor in
                await workoutManager.endWorkout()
                print("🔴 ✅ Workout ended during app termination")
                finished = true
            }
            
            // 🔥 最大5秒間RunLoopを回す（より長い時間を確保）
            let deadline = Date().addingTimeInterval(5.0)
            while !finished && Date() < deadline {
                runLoop.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
            }
            
            if finished {
                print("🔴 ✅ Workout termination completed successfully")
                // 🔥 追加の待機（HealthKitのクリーンアップ）
                Thread.sleep(forTimeInterval: 1.0)
                print("🔴 ✅ Additional cleanup delay completed")
            } else {
                print("🔴 ⚠️ Workout termination did not complete in time")
            }
        } else {
            print("ℹ️ No active workout during termination")
        }
        
        print("🔴 ========================================")
    }
}

@main
struct WorkoutPhoneApp: App {
    @StateObject private var workoutManager = WorkoutManager()
    @UIApplicationDelegateAdaptor(WorkoutAppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    
    // 🔥 バックグラウンド移行の時刻を記録
    @State private var backgroundEntryTime: Date? = nil
    
    // 🔥 Watch Connectivity Managerの参照を保持（解放されないように）
    private let workoutConnectivityManager = PhoneWorkoutConnectivityManager.shared
    
    init() {
        // AVAudioSessionを設定して、他のアプリの音楽と共存できるようにする
        do {
            let audioSession = AVAudioSession.sharedInstance()
            // .ambient を使用して、他の音楽アプリと完全に共存
            // .mixWithOthers で同時再生を許可
            // .duckOthers は使用しない（他の音楽の音量を下げない）
            try audioSession.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try audioSession.setActive(true, options: [.notifyOthersOnDeactivation])
            print("🔊 AVAudioSession configured: .ambient with .mixWithOthers")
        } catch {
            print("⚠️ Failed to configure AVAudioSession: \(error.localizedDescription)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            PhoneContentView()
                .environmentObject(workoutManager)
                .onAppear {
                    // 🔥 AppDelegateにWorkoutManagerの参照を渡す
                    appDelegate.workoutManager = workoutManager
                    
                    // 起動時にWatch Connectivity Managerを初期化
                    if WCSession.isSupported() {
                        // 音楽用のConnectivity Manager
                        _ = PhoneMusicConnectivityManager.shared
                        
                        // ワークアウトデータ用のConnectivity Manager（参照を保持済み）
                        workoutConnectivityManager.workoutManager = workoutManager
                        print("⌚️ PhoneWorkoutConnectivityManager initialized and linked to WorkoutManager")
                    }
                }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(from: oldPhase, to: newPhase)
        }
    }
    
    // 🔥 Scene Phase変更の処理
    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        print("🔄 ========================================")
        print("🔄 Scene phase: \(oldPhase) → \(newPhase)")
        print("🔄 Workout active: \(workoutManager.isWorkoutActive)")
        print("🔄 ========================================")
        
        switch newPhase {
        case .background:
            // バックグラウンドに入った時刻を記録
            backgroundEntryTime = Date()
            print("📱 App entered BACKGROUND at \(backgroundEntryTime!)")
            
            // 🔥 バックグラウンドに入っても何もしない
            // （applicationWillTerminate で処理する）
            if workoutManager.isWorkoutActive {
                print("ℹ️ Workout is active in background - will be handled by applicationWillTerminate if app is terminated")
            }
            
        case .active:
            print("📱 App became ACTIVE")
            
            // バックグラウンドからの復帰時間を確認
            if let bgTime = backgroundEntryTime {
                let timeInBackground = Date().timeIntervalSince(bgTime)
                print("📱 Was in background for \(timeInBackground) seconds")
                backgroundEntryTime = nil
            }
            
        case .inactive:
            print("📱 App became INACTIVE")
            // inactiveは通知センターを開いたり、コントロールセンターを表示した時も発火するため
            // ここでは何もしない
            
        @unknown default:
            print("📱 Unknown scene phase: \(newPhase)")
        }
    }
}

struct PhoneContentView: View {
    @EnvironmentObject private var workoutManager: WorkoutManager
    
    var body: some View {
        Group {
            if workoutManager.isWorkoutActive {
                PhoneWorkoutView()
                    .id("workout-view")
                    .transition(.opacity)
            } else {
                PhoneWorkoutTypeSelectionView()
                    .id("selection-view")
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: workoutManager.isWorkoutActive)
    }
}

struct PhoneWorkoutTypeSelectionView: View {
    @EnvironmentObject private var workoutManager: WorkoutManager
    @State private var isStarting = false
    @State private var showError = false
    @State private var hasRequestedPermission = false
    
    let workoutTypes: [(name: String, type: HKWorkoutActivityType, icon: String, color: Color)] = [
        ("ウォーキング", .walking, "walking", .green),
        ("ジョギング", .running, "jogging", .blue),
        ("ランニング", .running, "running", .red)
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 24) {
                    ForEach(workoutTypes, id: \.name) { workout in
                        Button {
                            startWorkout(type: workout.type, name: workout.name)
                        } label: {
                            HStack(spacing: 32) {
                                Image(workout.icon)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 50, height: 50)
                                
                                Text(workout.name)
                                    .font(.system(size: 30.75, weight: .semibold))
                                    .foregroundColor(workout.color)
                                
                                Spacer()
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 20)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        .disabled(isStarting)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .opacity(isStarting ? 0.3 : 1.0)
                .disabled(isStarting)
                
                if isStarting {
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                        Text("ワークアウトを準備中...")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                    .padding(32)
                    .background(Color.black.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
            .navigationTitle("ワークアウト")
            .alert("エラー", isPresented: $showError) {
                Button("OK") {
                    workoutManager.errorMessage = nil
                    isStarting = false
                }
            } message: {
                if let errorMessage = workoutManager.errorMessage {
                    Text(errorMessage)
                }
            }
            .onChange(of: workoutManager.errorMessage) { oldValue, newValue in
                if newValue != nil {
                    showError = true
                    isStarting = false
                }
            }
            .onChange(of: workoutManager.isWorkoutActive) { oldValue, newValue in
                if newValue {
                    isStarting = false
                }
            }
            .onAppear {
                // 初回のみ権限をリクエスト（アプリ起動時にダイアログ表示）
                if !hasRequestedPermission {
                    hasRequestedPermission = true
                    Task {
                        await workoutManager.requestAuthorization()
                    }
                }
            }
        }
    }
    
    private func startWorkout(type: HKWorkoutActivityType, name: String) {
        guard !isStarting else { return }
        guard !workoutManager.isWorkoutActive else { return }
        
        isStarting = true
        
        // タイムアウトタイマーを設定（30秒 - 実機での権限ダイアログ＋セッション開始を考慮）
        let timeoutTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(30))
            
            if isStarting {
                print("⚠️ Workout start timeout after 30 seconds")
                isStarting = false
                
                // タイムアウト後もワークアウトがアクティブでない場合はエラー表示
                if !workoutManager.isWorkoutActive {
                    workoutManager.errorMessage = "ワークアウトの開始がタイムアウトしました。\nHealthKitの権限を確認してください。"
                }
            }
        }
        
        Task { @MainActor in
            await workoutManager.startWorkout(activityType: type, workoutName: name)
            
            // ワークアウト開始処理が完了したらタイムアウトタスクをキャンセル
            timeoutTask.cancel()
            isStarting = false
        }
    }
}

enum MetricCardType: String, Identifiable, CaseIterable {
    case distance, calories, heartRate, pace, steps, marathon
    
    var id: String { rawValue }
}

struct PhoneWorkoutView: View {
    @EnvironmentObject var workoutManager: WorkoutManager
    @State private var selectedTab = 1
    @State private var isButtonVisible = true
    @State private var blinkTimer: Timer?
    @State private var shouldScrollToTop = false
    @State private var cachedBestLapText: String? = nil
    @State private var lastLapCount: Int = 0
    @State private var isEditMode = false
    @State private var visibleCards: [MetricCardType] = [.distance, .calories, .heartRate, .pace, .steps, .marathon]
    @State private var draggingCard: MetricCardType?
    @State private var longPressTriggered: MetricCardType? = nil
    @State private var showAddCardMenu = false
    
    var body: some View {
        VStack(spacing: 0) {
            // ページスタイルのTabView（スワイプアニメーション対応）
            TabView(selection: $selectedTab) {
                lapTimesView
                    .tag(0)
                
                mainWorkoutView
                    .tag(1)
                
                PhoneMusicControlView()
                    .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            
            // カスタムタブバー
            customTabBar
        }
        .sheet(isPresented: $showAddCardMenu) {
            AddCardMenuView(
                visibleCards: $visibleCards,
                isPresented: $showAddCardMenu
            )
        }
        .onChange(of: workoutManager.isPaused) { oldValue, newValue in
            if newValue {
                startBlinking()
            } else {
                stopBlinking()
            }
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            if newValue == 0 && (oldValue == 1 || oldValue == 2) {
                if !workoutManager.isPaused {
                    shouldScrollToTop = true
                }
            }
        }
        .onAppear {
            if workoutManager.isPaused {
                startBlinking()
            }
            updateBestLapTextIfNeeded()
            loadCardConfiguration()
        }
        .onDisappear {
            stopBlinking()
        }
        .onChange(of: workoutManager.lapTimes.count) { oldValue, newValue in
            if newValue != lastLapCount {
                updateBestLapTextIfNeeded()
            }
        }
    }
    
    // シンプルなタブバー（Liquid Glass付き）
    private var customTabBar: some View {
        VStack(spacing: 0) {
            // 上部の区切り線
            Divider()
            
            GlassEffectContainer(spacing: 20) {
                HStack(spacing: 12) {
                    // ラップタブ
                    tabButton(
                        index: 0,
                        icon: "list.bullet",
                        label: "ラップ",
                        isSelected: selectedTab == 0
                    )
                    
                    // ワークアウトタブ
                    tabButton(
                        index: 1,
                        icon: "figure.run",
                        label: "ワークアウト",
                        isSelected: selectedTab == 1
                    )
                    
                    // 音楽タブ
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTab = 2
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "music.note")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundStyle(selectedTab == 2 ? .white : .secondary)
                                .frame(height: 28)
                            
                            Text("ミュージック")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(selectedTab == 2 ? .white : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .contentShape(Rectangle())
                    }
                    .glassEffect(
                        selectedTab == 2 ? 
                            .regular.tint(.pink).interactive() : 
                            .regular.interactive(),
                        in: .rect(cornerRadius: 16)
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(.regularMaterial)
        }
        .ignoresSafeArea(edges: .bottom)
    }
    
    private func tabButton(index: Int, icon: String, label: String, isSelected: Bool) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = index
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .frame(height: 28)
                
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? .white : .secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .contentShape(Rectangle())
        }
        .glassEffect(
            isSelected ? 
                .regular.tint(tabColor(for: index)).interactive() : 
                .regular.interactive(),
            in: .rect(cornerRadius: 16)
        )
    }
    
    private func tabColor(for index: Int) -> Color {
        switch index {
        case 0: return .blue
        case 1: return .green
        case 2: return .pink
        default: return .blue
        }
    }
    
    private var mainWorkoutView: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 6) {
                            Text(workoutManager.workoutName)
                                .font(.system(size: 32, weight: .bold))
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 0)
                            
                            VStack(spacing: 1) {
                                Text("経過時間")
                                    .font(.system(size: 21))
                                    .foregroundStyle(.secondary)
                                Text(workoutManager.elapsedTimeString)
                                    .font(.system(size: 60, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                            }
                            .padding(.top, 0)
                            .padding(.bottom, 4)
                            
                            // ＋ボタン（編集モード時のみ表示、全てのカードが表示されていない場合）
                            // 右上に配置、少し小さめに
                            HStack {
                                Spacer()
                                
                                if isEditMode && visibleCards.count < MetricCardType.allCases.count {
                                    Button {
                                        showAddCardMenu = true
                                    } label: {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 38))
                                            .foregroundStyle(.blue)
                                            .symbolEffect(.bounce, value: showAddCardMenu)
                                            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                                    }
                                    .padding(.trailing, 36)
                                    .padding(.top, 8)
                                    .padding(.bottom, 8)
                                    .transition(.scale.combined(with: .opacity))
                                }
                            }
                            .frame(height: isEditMode && visibleCards.count < MetricCardType.allCases.count ? 54 : 0)
                            .opacity(isEditMode && visibleCards.count < MetricCardType.allCases.count ? 1 : 0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isEditMode)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: visibleCards.count)
                            
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                ForEach(visibleCards) { cardType in
                                    DraggableCardView(
                                        cardType: cardType,
                                        isEditMode: $isEditMode,
                                        draggingCard: $draggingCard,
                                        cardOrder: $visibleCards,
                                        canDelete: cardType != .distance,
                                        onEnterEditMode: {
                                            if !isEditMode {
                                                print("👆 長押し検出: \(cardType.rawValue)")
                                                enterEditMode()
                                                // 編集モード後にドラッグ開始
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                                    self.draggingCard = cardType
                                                }
                                            }
                                        },
                                        onDelete: {
                                            removeCard(cardType)
                                        },
                                        cardContent: {
                                            cardView(for: cardType)
                                        }
                                    )
                                    .id(cardType)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 0)
                            .padding(.bottom, 0)
                        }
                    }
                    .blur(radius: isEditMode ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: isEditMode)
                    
                    // ボタンを下部に固定
                    controlButtons()
                        .padding(.horizontal, 12)
                        .padding(.top, 16)
                        .padding(.bottom, 18)
                        .background(Color(UIColor.systemBackground))
                }
                
                // 編集モード時のヘッダー（上にオーバーレイ）
                if isEditMode {
                    VStack {
                        editModeHeader
                            .transition(.move(edge: .top).combined(with: .opacity))
                        Spacer()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    // 編集モードのヘッダー
    private var editModeHeader: some View {
        HStack {
            Text("カードを並び替え")
                .font(.headline)
                .foregroundStyle(.primary)
            
            Spacer()
            
            Button {
                exitEditMode()
            } label: {
                Text("完了")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
    }
    
    private var lapTimesView: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    if workoutManager.lapTimes.isEmpty {
                        Text("ラップタイムはまだありません")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    } else {
                        ForEach(Array(workoutManager.lapTimes.enumerated()), id: \.offset) { index, time in
                            HStack {
                                Text("\(index + 1)km")
                                    .font(.title)
                                    .fontWeight(.bold)
                                Spacer()
                                Text(formatLapTime(time))
                                    .font(.system(size: 36))
                                    .fontWeight(.semibold)
                                    .monospacedDigit()
                                    .foregroundStyle(lapColor(for: time, at: index))
                            }
                            .padding(.vertical, 8)
                            .id(index)  // 各行にIDを付与
                        }
                    }
                }
                .navigationTitle("ラップタイム")
                .onChange(of: selectedTab) { oldValue, newValue in
                    // ラップタイム画面に切り替わった時
                    if newValue == 0 && !workoutManager.lapTimes.isEmpty {
                        // 最新のラップタイム（最後の要素）にスクロール
                        let lastIndex = workoutManager.lapTimes.count - 1
                        withAnimation {
                            proxy.scrollTo(lastIndex, anchor: .bottom)
                        }
                    }
                }
                .onAppear {
                    // 画面が表示された時も最新のラップタイムを表示
                    if !workoutManager.lapTimes.isEmpty {
                        let lastIndex = workoutManager.lapTimes.count - 1
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation {
                                proxy.scrollTo(lastIndex, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func lapColor(for time: TimeInterval, at index: Int) -> Color {
        guard !workoutManager.lapTimes.isEmpty else { return .green }
        guard workoutManager.lapTimes.count > 1 else { return .green }
        
        let fastest = workoutManager.lapTimes.min() ?? 0
        let slowest = workoutManager.lapTimes.max() ?? 0
        
        // 最速記録は常に赤（抜かれない限り赤文字）
        if time == fastest {
            return .red
        }
        // 最遅記録は青
        else if time == slowest && fastest != slowest {
            return .blue
        }
        // その他は緑
        else {
            return .green
        }
    }
    
    private func controlButtons() -> some View {
        HStack(spacing: 12) {
            Button {
                if workoutManager.isPaused {
                    workoutManager.resumeWorkout()
                } else {
                    workoutManager.pauseWorkout()
                }
            } label: {
                Label(
                    workoutManager.isPaused ? "再開" : "一時停止",
                    systemImage: workoutManager.isPaused ? "play.fill" : "pause.fill"
                )
                .font(.system(size: 20, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .opacity(isButtonVisible ? 1.0 : 0.3)
            
            Button {
                Task {
                    await workoutManager.endWorkout()
                }
            } label: {
                Label("終了", systemImage: "xmark")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.red)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }
    
    private func formatLapTime(_ time: TimeInterval) -> String {
        let hours = Int(time / 3600)
        let minutes = Int(time.truncatingRemainder(dividingBy: 3600) / 60)
        let seconds = Int(time.truncatingRemainder(dividingBy: 60))
        
        // 1時間未満の場合は mm:ss 形式
        if hours == 0 {
            return String(format: "%02d:%02d", minutes, seconds)
        } else {
            // 1時間以上の場合は h:mm:ss 形式
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
    }
    
    private func startBlinking() {
        stopBlinking()
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                isButtonVisible.toggle()
            }
        }
    }
    
    private func stopBlinking() {
        blinkTimer?.invalidate()
        blinkTimer = nil
        isButtonVisible = true
    }
    
    private func updateBestLapTextIfNeeded() {
        let currentLapCount = workoutManager.lapTimes.count
        
        // ラップ数が変わった場合のみ更新
        if currentLapCount != lastLapCount {
            lastLapCount = currentLapCount
            cachedBestLapText = calculateBestLapText()
        }
    }
    
    private func calculateBestLapText() -> String? {
        guard !workoutManager.lapTimes.isEmpty else { return nil }
        
        // 全ラップの中で最速のタイムを取得
        guard let fastest = workoutManager.lapTimes.min() else { return nil }
        
        // 最速ラップのインデックスを取得（1-based）
        guard let fastestIndex = workoutManager.lapTimes.firstIndex(of: fastest) else { return nil }
        let kmNumber = fastestIndex + 1
        
        // 最速記録を formatLapTime と同じ形式で表示
        let hours = Int(fastest / 3600)
        let minutes = Int(fastest.truncatingRemainder(dividingBy: 3600) / 60)
        let seconds = Int(fastest.truncatingRemainder(dividingBy: 60))
        
        // 1時間未満の場合は mm:ss 形式
        let timeString: String
        if hours == 0 {
            timeString = String(format: "%02d:%02d", minutes, seconds)
        } else {
            // 1時間以上の場合は h:mm:ss 形式
            timeString = String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        
        return "\(kmNumber)km/\(timeString)"
    }
    
    private func calculateMarathonRemainingTime() -> TimeInterval? {
        let marathonDistance = 42195.0 // メートル
        let currentDistance = workoutManager.distance // メートル
        let elapsedTime = workoutManager.elapsedTime // 秒
        
        // 走行距離が0の場合は計算できない
        guard currentDistance > 0 && elapsedTime > 0 else { return nil }
        
        // 現在のペース（秒/メートル）
        let currentPace = elapsedTime / currentDistance
        
        // フルマラソン完走までの予想時間
        let estimatedTotalTime = marathonDistance * currentPace
        
        // 残り時間
        let remainingTime = estimatedTotalTime - elapsedTime
        
        return max(0, remainingTime)
    }
    
    @ViewBuilder
    private func cardView(for cardType: MetricCardType) -> some View {
        switch cardType {
        case .distance:
            MetricCard(
                title: "距離",
                value: String(format: "%.2f", max(0, workoutManager.distance / 1000.0)),
                unit: "km",
                icon: "figure.walk",
                color: .blue
            )
            .onChange(of: workoutManager.distance) { oldValue, newValue in
                print("📱 iOS UI - Distance changed: \(String(format: "%.2f", oldValue))m -> \(String(format: "%.2f", newValue))m (displayed: \(String(format: "%.3f", newValue/1000.0))km)")
            }
            
        case .calories:
            MetricCard(
                title: "カロリー",
                value: String(format: "%.0f", max(0, workoutManager.activeCalories)),
                unit: "kcal",
                icon: "flame.fill",
                color: .orange
            )
            
        case .heartRate:
            MetricCard(
                title: "平均心拍数",
                value: workoutManager.averageHeartRate > 0 ? String(format: "%.0f", workoutManager.averageHeartRate) : "--",
                unit: "bpm",
                icon: "heart.fill",
                color: .red
            )
            
        case .pace:
            MetricCardWithRecord(
                title: "ペース",
                value: workoutManager.currentPaceString,
                unit: "/km",
                icon: "timer",
                color: .green,
                recordText: cachedBestLapText
            )
            .id("pace-card-\(workoutManager.lapTimes.count)")
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: cachedBestLapText)
            
        case .steps:
            MetricCard(
                title: "歩数",
                value: String(format: "%.0f", max(0, workoutManager.stepCount)),
                unit: "歩",
                icon: "figure.walk.motion",
                color: .purple
            )
            
        case .marathon:
            MarathonTimeCard(
                title: "フルマラソン予想",
                remainingTime: calculateMarathonRemainingTime(),
                icon: "flag.checkered",
                color: .cyan
            )
        }
    }
    
    private func enterEditMode() {
        guard !isEditMode else { return }
        
        print("🎯 編集モード開始")
        
        // バイブレーション（より強い）
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.prepare() // 事前準備で遅延を減らす
        impactFeedback.impactOccurred()
        
        // 確実にメインスレッドで実行
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                self.isEditMode = true
            }
        }
    }
    
    private func exitEditMode() {
        print("🎯 編集モード終了")
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isEditMode = false
        }
        draggingCard = nil
        
        // 設定を保存
        saveCardConfiguration()
    }
    
    private func saveCardConfiguration() {
        let orderStrings = visibleCards.map { $0.rawValue }
        UserDefaults.standard.set(orderStrings, forKey: "visibleCards")
        print("💾 カード設定を保存: \(orderStrings)")
    }
    
    private func loadCardConfiguration() {
        guard let orderStrings = UserDefaults.standard.array(forKey: "visibleCards") as? [String] else {
            print("📂 保存された設定が見つかりません。デフォルト設定を使用します。")
            return
        }
        
        let loadedCards = orderStrings.compactMap { MetricCardType(rawValue: $0) }
        
        // 少なくとも距離カードが含まれている場合のみ適用
        if loadedCards.contains(.distance) && !loadedCards.isEmpty {
            visibleCards = loadedCards
            print("✅ カード設定を読み込み: \(orderStrings)")
        } else {
            print("⚠️ 保存された設定が不正です。デフォルト設定を使用します。")
            print("   保存されていた設定: \(orderStrings)")
        }
    }
    
    private func availableCardsToAdd() -> [MetricCardType] {
        MetricCardType.allCases.filter { !visibleCards.contains($0) }
    }
    
    private func cardTypeDisplayName(_ cardType: MetricCardType) -> String {
        switch cardType {
        case .distance: return "距離"
        case .calories: return "カロリー"
        case .heartRate: return "平均心拍数"
        case .pace: return "ペース"
        case .steps: return "歩数"
        case .marathon: return "フルマラソン予想"
        }
    }
    
    private func addCard(_ cardType: MetricCardType) {
        guard !visibleCards.contains(cardType) else { return }
        
        print("➕ カード追加: \(cardType.rawValue)")
        
        let feedback = UINotificationFeedbackGenerator()
        feedback.notificationOccurred(.success)
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            visibleCards.append(cardType)
        }
    }
    
    private func removeCard(_ cardType: MetricCardType) {
        // 距離カードは削除できない
        guard cardType != .distance else {
            print("⚠️ 距離カードは削除できません")
            return
        }
        
        guard visibleCards.contains(cardType) else { return }
        
        print("🗑️ カード削除: \(cardType.rawValue)")
        
        let feedback = UINotificationFeedbackGenerator()
        feedback.notificationOccurred(.warning)
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            visibleCards.removeAll { $0 == cardType }
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 0) {
            // アイコンエリア（固定）
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.system(size: 22))
                Spacer()
            }
            .padding(.top, 10)
            .padding(.horizontal, 10)
            
            Spacer()
            
            // 新記録スペース（ペースカードと高さを揃えるため）
            VStack(spacing: 0) {
                Text(" ")
                    .font(.system(size: 16, weight: .bold))
                    .lineLimit(1)
            }
            .frame(height: 20) // 固定高さ
            .padding(.bottom, 2)
            .padding(.horizontal, 10)
            
            // タイトルと値エリア（固定）
            VStack(spacing: 2) {
                HStack {
                    Text(title)
                        .font(.system(size: 19))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.system(size: 66, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                    Text(unit)
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
            
            Spacer()
        }
        .frame(minHeight: 150, maxHeight: 150)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct MetricCardWithRecord: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    let recordText: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // アイコンエリア（固定）
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.system(size: 22))
                Spacer()
            }
            .padding(.top, 10)
            .padding(.horizontal, 10)
            
            Spacer()
            
            // 新記録表示エリア（固定高さ）
            VStack(spacing: 0) {
                if let recordText = recordText {
                    Text("新記録 \(recordText)")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(.red)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                } else {
                    // 空のスペースを確保して高さを固定
                    Text(" ")
                        .font(.system(size: 19, weight: .bold))
                        .lineLimit(1)
                }
            }
            .frame(height: 20) // 固定高さ
            .padding(.bottom, 2)
            .padding(.horizontal, 10)
            
            // タイトルと値エリア（固定）
            VStack(spacing: 2) {
                HStack {
                    Text(title)
                        .font(.system(size: 19))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.system(size: 66, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                    Text(unit)
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
            
            Spacer()
        }
        .frame(minHeight: 150, maxHeight: 150)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct MarathonTimeCard: View {
    let title: String
    let remainingTime: TimeInterval?
    let icon: String
    let color: Color
    
    @EnvironmentObject private var workoutManager: WorkoutManager
    
    // 完走予想タイムと残り時間を計算
    private var marathonTimes: (total: TimeInterval, remaining: TimeInterval)? {
        guard let remaining = remainingTime, remaining > 0 else { return nil }
        let total = remaining + workoutManager.elapsedTime
        return (total: total, remaining: remaining)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // 「今のペースなら」とアイコン表示エリア（他のカードと高さを揃えるため）
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.system(size: 20))
                Text("今のペースなら")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.cyan)
                    .lineLimit(1)
                Spacer()
            }
            .frame(height: 20)
            .padding(.top, 10)
            .padding(.bottom, 2)
            .padding(.horizontal, 10)
            
            // タイトルと値エリア
            VStack(spacing: 0) {
                HStack {
                    Text(title)
                        .font(.system(size: 19))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                
                if let times = marathonTimes {
                    // 完走予想タイム
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(formatMarathonTime(times.total))
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                    }
                    .frame(height: 38)
                    
                    // 残り時間表示（大きく、2行）
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            Text("残り")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                            Text(formatMarathonTime(times.remaining))
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Spacer()
                            Text("でゴール")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 38)
                } else {
                    // データがない場合
                    VStack(spacing: 2) {
                        Text("--:--:--")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(height: 38)
                        
                        Text("計測中...")
                            .font(.system(size: 14))
                            .foregroundStyle(.tertiary)
                            .frame(height: 38)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
            
            Spacer()
        }
        .frame(minHeight: 150, maxHeight: 150)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func formatMarathonTime(_ time: TimeInterval) -> String {
        let hours = Int(time / 3600)
        let minutes = Int(time.truncatingRemainder(dividingBy: 3600) / 60)
        let seconds = Int(time.truncatingRemainder(dividingBy: 60))
        
        // h:mm:ss 形式で表示
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
}

struct PhoneMusicControlView: View {
    @StateObject private var musicController = PhoneMusicController()
    @State private var showPermissionAlert = false
    @State private var showMusicPicker = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                artworkView()
                    .padding(.top, 20)
                    .onTapGesture {
                        // アートワークタップで曲選択
                        showMusicPicker = true
                    }
                nowPlayingInfo()
                playbackControls()
                    .padding(.vertical, 8)
                Spacer()
            }
            .navigationTitle("Apple Music")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Apple Music")
                        .font(.system(size: 17 * 1.5, weight: .semibold)) // 1.5倍のサイズ（25.5pt）
                        .foregroundStyle(.pink) // ピンク色に設定
                }
            }
            .onAppear {
                print("🎵 PhoneMusicControlView appeared")
                
                // 音楽ライブラリへのアクセスを要求
                musicController.requestMusicLibraryAccess { granted in
                    if granted {
                        musicController.startMonitoring()
                    } else {
                        showPermissionAlert = true
                    }
                }
            }
            .onDisappear {
                print("🎵 PhoneMusicControlView disappeared")
                musicController.stopMonitoring()
            }
            .alert("音楽ライブラリへのアクセス", isPresented: $showPermissionAlert) {
                Button("設定を開く") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("ミュージックを制御するには、設定で音楽ライブラリへのアクセスを許可してください。")
            }
            .sheet(isPresented: $showMusicPicker) {
                MusicPickerView(musicController: musicController)
            }
        }
    }
    
    // アートワーク表示
    @ViewBuilder
    private func artworkView() -> some View {
        Group {
            // アートワークがある場合は表示し続ける（停止してもアートワークを保持）
            if let artwork = musicController.displayArtwork {
                Image(uiImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 280, height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                    .transition(.scale.combined(with: .opacity))
            } else {
                // アートワークがない場合はタップで曲選択を促す
                Button {
                    showMusicPicker = true
                } label: {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(
                            colors: [Color.pink.opacity(0.6), Color.pink.opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 280, height: 280)
                        .overlay {
                            VStack(spacing: 16) {
                                Image(systemName: "music.note")
                                    .font(.system(size: 80))
                                    .foregroundStyle(.white.opacity(0.8))
                                Text("タップして曲を選択")
                                    .font(.headline)
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                        }
                        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: musicController.displayArtwork)
    }
    
    @ViewBuilder
    private func nowPlayingInfo() -> some View {
        VStack(spacing: 8) {
            if let title = musicController.currentTrackTitle {
                Text(title)
                    .font(.title)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal)
                if let artistName = musicController.currentArtist {
                    Text(artistName)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                }
                if let albumName = musicController.currentAlbum {
                    Text(albumName)
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                }
            } else {
                Text("再生していません")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private func playbackControls() -> some View {
        HStack(spacing: 60) {
            Button {
                // 現在再生中の曲情報がある場合のみ有効
                if musicController.currentArtwork != nil {
                    musicController.skipToPrevious()
                }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(musicController.currentArtwork != nil ? .pink : .gray)
            }
            .disabled(musicController.currentArtwork == nil)
            
            Button {
                // currentArtwork（現在再生中）がない場合は曲選択画面を表示
                // displayArtwork（停止後も保持）ではなくcurrentArtworkで判定
                if musicController.currentArtwork == nil {
                    showMusicPicker = true
                } else {
                    // 曲情報がある場合は再生/一時停止
                    musicController.togglePlayPause()
                }
            } label: {
                Image(systemName: musicController.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.pink)
            }
            
            Button {
                // 現在再生中の曲情報がある場合のみ有効
                if musicController.currentArtwork != nil {
                    musicController.skipToNext()
                }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(musicController.currentArtwork != nil ? .pink : .gray)
            }
            .disabled(musicController.currentArtwork == nil)
        }
    }
}

@MainActor
class PhoneMusicController: NSObject, ObservableObject {
    // Apple Music用
    @Published var isPlaying: Bool = false
    @Published var currentTrackTitle: String? = nil
    @Published var currentArtist: String? = nil
    @Published var currentAlbum: String? = nil
    @Published var currentArtwork: UIImage? = nil
    @Published var displayArtwork: UIImage? = nil // 停止してもアートワークを保持
    
    private let musicPlayer = MPMusicPlayerController.systemMusicPlayer
    private var hasLibraryAccess = false
    
    override init() {
        super.init()
        print("🎵 PhoneMusicController initialized")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    
    func requestMusicLibraryAccess(completion: @escaping (Bool) -> Void) {
        MPMediaLibrary.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.hasLibraryAccess = (status == .authorized)
                print("🎵 Music Library Access: \(status == .authorized ? "Granted" : "Denied")")
                completion(status == .authorized)
            }
        }
    }
    
    
    func startMonitoring() {
        print("🎵 Starting music monitoring...")
        
        // Now Playing Info Centerからの通知を監視
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNowPlayingItemChanged),
            name: .MPMusicPlayerControllerNowPlayingItemDidChange,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePlaybackStateChanged),
            name: .MPMusicPlayerControllerPlaybackStateDidChange,
            object: nil
        )
        
        // Now Playing Info Centerの通知も監視（Spotify等のサードパーティアプリ用）
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNowPlayingInfoChanged),
            name: NSNotification.Name("MPNowPlayingInfoDidChange"),
            object: nil
        )
        
        // 音楽プレイヤーの通知を有効化
        musicPlayer.beginGeneratingPlaybackNotifications()
        
        // Now Playing Infoを取得
        updateNowPlayingInfo()
        
        print("🎵 Music monitoring started successfully")
    }
    
    @objc private func handleNowPlayingInfoChanged() {
        print("🎵 Now Playing Info changed (notification)")
        updateNowPlayingInfo()
    }
    
    @objc private func handleNowPlayingItemChanged() {
        print("🎵 Now playing item changed (notification)")
        updateNowPlayingInfo()
    }
    
    @objc private func handlePlaybackStateChanged() {
        print("🎵 Playback state changed (notification)")
        updateNowPlayingInfo()
    }
    
    func stopMonitoring() {
        musicPlayer.endGeneratingPlaybackNotifications()
        NotificationCenter.default.removeObserver(self, name: .MPMusicPlayerControllerNowPlayingItemDidChange, object: nil)
        NotificationCenter.default.removeObserver(self, name: .MPMusicPlayerControllerPlaybackStateDidChange, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("MPNowPlayingInfoDidChange"), object: nil)
        
        print("🎵 Music monitoring stopped")
    }
    
    
    private var lastNowPlayingTitle: String? = nil
    
    private func updateNowPlayingInfo() {
        // Now Playing Info Centerから情報を取得（全てのアプリ対応）
        let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()
        
        // デバッグ：Now Playing Info辞書の全キーを表示
        if let nowPlayingInfo = nowPlayingInfoCenter.nowPlayingInfo {
            if !nowPlayingInfo.isEmpty {
                // 再生状態を判定（再生レートから推測）
                let playbackRate = nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] as? Double ?? 0.0
                let isNowPlayingActive = playbackRate > 0.0
                
                let newTitle = nowPlayingInfo[MPMediaItemPropertyTitle] as? String
                let newArtist = nowPlayingInfo[MPMediaItemPropertyArtist] as? String
                let newAlbum = nowPlayingInfo[MPMediaItemPropertyAlbumTitle] as? String
                
                // 曲が変わった時だけログ出力
                if newTitle != lastNowPlayingTitle {
                    print("🎵 ========== Now Playing Info Changed ==========")
                    print("🎵 Dictionary keys: \(nowPlayingInfo.keys)")
                    print("🎵 Dictionary count: \(nowPlayingInfo.count)")
                    print("🎵 Title: \(newTitle ?? "nil")")
                    print("🎵 Artist: \(newArtist ?? "nil")")
                    print("🎵 Album: \(newAlbum ?? "nil")")
                    print("🎵 Playback Rate: \(playbackRate)")
                    print("🎵 Is Playing: \(isNowPlayingActive)")
                    print("🎵 =============================================")
                    lastNowPlayingTitle = newTitle
                }
                
                // Now Playing Info Centerに情報がある場合は、その情報を表示
                currentTrackTitle = newTitle
                currentArtist = newArtist
                currentAlbum = newAlbum
                isPlaying = isNowPlayingActive
                
                // アートワークを取得して保持
                if let artwork = nowPlayingInfo[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork {
                    let artworkImage = artwork.image(at: CGSize(width: 280, height: 280))
                    if artworkImage != currentArtwork {
                        currentArtwork = artworkImage
                        displayArtwork = artworkImage // 表示用にも保存
                        print("🎵 Artwork loaded from Now Playing Info")
                    }
                } else if currentArtwork != nil {
                    currentArtwork = nil
                    // displayArtworkは保持（停止してもアートワークを表示し続ける）
                }
            } else {
                if lastNowPlayingTitle != nil {
                    print("🎵 Now Playing Info dictionary is empty")
                    lastNowPlayingTitle = nil
                }
                handleNoNowPlayingInfo()
            }
        } else {
            if lastNowPlayingTitle != nil {
                print("🎵 Now Playing Info is nil")
                lastNowPlayingTitle = nil
            }
            handleNoNowPlayingInfo()
        }
    }
    
    private func handleNoNowPlayingInfo() {
        // Now Playing Info Centerに情報がない場合
        print("🎵 No Now Playing Info available")
        
        // Apple Musicライブラリアクセスがある場合は常にチェック
        if hasLibraryAccess {
            print("🎵 Checking Apple Music (player state: \(musicPlayer.playbackState.rawValue))")
            updateAppleMusicFromLibrary()
        } else {
            print("🎵 No library access - clearing all info")
            // 何も再生していない
            clearAllMusicInfo()
        }
    }
    
    private func clearAllMusicInfo() {
        if currentTrackTitle != nil {
            print("🎵 No track playing - clearing all info")
            currentTrackTitle = nil
            currentArtist = nil
            currentAlbum = nil
            currentArtwork = nil
            isPlaying = false
        }
    }
    
    private func updateAppleMusicFromLibrary() {
        guard hasLibraryAccess else { return }
        
        if let nowPlayingItem = musicPlayer.nowPlayingItem {
            let newTitle = nowPlayingItem.title
            let newArtist = nowPlayingItem.artist
            let newAlbum = nowPlayingItem.albumTitle
            
            if currentTrackTitle != newTitle {
                currentTrackTitle = newTitle
                print("🎵 Apple Music Track: \(newTitle ?? "Unknown")")
            }
            if currentArtist != newArtist {
                currentArtist = newArtist
            }
            if currentAlbum != newAlbum {
                currentAlbum = newAlbum
            }
            
            // アートワークを取得して保持
            if let artworkProperty = nowPlayingItem.artwork {
                let artwork = artworkProperty.image(at: CGSize(width: 280, height: 280))
                if artwork != currentArtwork {
                    currentArtwork = artwork
                    displayArtwork = artwork // 表示用にも保存
                    print("🎵 Apple Music Artwork loaded")
                }
            } else if currentArtwork != nil {
                currentArtwork = nil
                // displayArtworkは保持（停止してもアートワークを表示し続ける）
            }
            
            // 再生状態を取得
            let newIsPlaying = musicPlayer.playbackState == .playing
            if isPlaying != newIsPlaying {
                isPlaying = newIsPlaying
                print("🎵 Apple Music Playing: \(newIsPlaying)")
            }
        } else {
            // Apple Musicで何も再生していない
            if currentTrackTitle != nil {
                print("🎵 Apple Music - No track playing")
                currentTrackTitle = nil
                currentArtist = nil
                currentAlbum = nil
                currentArtwork = nil
                isPlaying = false
                // displayArtworkは保持（停止してもアートワークを表示し続ける）
            }
        }
    }
    
    func togglePlayPause() {
        // システムミュージックプレイヤーを使用して再生/一時停止を制御（Apple Music）
        if isPlaying {
            musicPlayer.pause()
            print("🎵 Apple Music paused")
        } else {
            musicPlayer.play()
            print("🎵 Apple Music playing")
        }
        
        // すぐにUIを更新
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.updateNowPlayingInfo()
        }
    }
    
    func skipToNext() {
        // システムミュージックプレイヤーで次の曲へ（Apple Music）
        musicPlayer.skipToNextItem()
        print("🎵 Apple Music - Skipped to next track")
        
        // 少し遅延してから情報を更新
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.updateNowPlayingInfo()
        }
    }
    
    func skipToPrevious() {
        // システムミュージックプレイヤーで前の曲へ（Apple Music）
        musicPlayer.skipToPreviousItem()
        print("🎵 Apple Music - Skipped to previous track")
        
        // 少し遅延してから情報を更新
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.updateNowPlayingInfo()
        }
    }
    
    
    // 曲を再生する
    func playItem(_ item: MPMediaItem) {
        print("🎵 Playing item: \(item.title ?? "Unknown")")
        
        // コレクションを作成して設定
        let collection = MPMediaItemCollection(items: [item])
        musicPlayer.setQueue(with: collection)
        musicPlayer.play()
        
        // 少し遅延してから情報を更新
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.updateNowPlayingInfo()
        }
    }
    
    // アルバムを再生する
    func playAlbum(_ album: MPMediaItemCollection) {
        print("🎵 Playing album: \(album.representativeItem?.albumTitle ?? "Unknown")")
        
        musicPlayer.setQueue(with: album)
        musicPlayer.play()
        
        // 少し遅延してから情報を更新
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.updateNowPlayingInfo()
        }
    }
}

// 音楽選択画面
struct MusicPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var musicController: PhoneMusicController
    @State private var selectedTab = 0  // 0: アルバム, 1: 曲
    @State private var searchText = ""
    
    // ライブラリから曲とアルバムを取得
    private var allSongs: [MPMediaItem] {
        let query = MPMediaQuery.songs()
        return query.items ?? []
    }
    
    private var allAlbums: [MPMediaItemCollection] {
        let query = MPMediaQuery.albums()
        return query.collections ?? []
    }
    
    // 検索でフィルタリング
    private var filteredSongs: [MPMediaItem] {
        if searchText.isEmpty {
            return allSongs
        }
        return allSongs.filter { item in
            let title = item.title?.lowercased() ?? ""
            let artist = item.artist?.lowercased() ?? ""
            let search = searchText.lowercased()
            return title.contains(search) || artist.contains(search)
        }
    }
    
    private var filteredAlbums: [MPMediaItemCollection] {
        if searchText.isEmpty {
            return allAlbums
        }
        return allAlbums.filter { collection in
            let albumTitle = collection.representativeItem?.albumTitle?.lowercased() ?? ""
            let artist = collection.representativeItem?.artist?.lowercased() ?? ""
            let search = searchText.lowercased()
            return albumTitle.contains(search) || artist.contains(search)
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // タブ選択（アルバムを最初に）
                Picker("選択", selection: $selectedTab) {
                    Text("アルバム").tag(0)
                    Text("曲").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()
                
                // 検索バー
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("検索", text: $searchText)
                        .textFieldStyle(.plain)
                    
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)
                .padding(.bottom, 8)
                
                // リスト表示（アルバムが0、曲が1）
                if selectedTab == 0 {
                    albumsList
                } else {
                    songsList
                }
            }
            .navigationTitle("ミュージックを選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // 曲のリスト
    private var songsList: some View {
        List {
            if filteredSongs.isEmpty {
                Text("曲が見つかりません")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(filteredSongs, id: \.persistentID) { item in
                    Button {
                        musicController.playItem(item)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            // アートワーク
                            if let artwork = item.artwork {
                                Image(uiImage: artwork.image(at: CGSize(width: 50, height: 50)) ?? UIImage())
                                    .resizable()
                                    .frame(width: 50, height: 50)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            } else {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(.systemGray5))
                                    .frame(width: 50, height: 50)
                                    .overlay {
                                        Image(systemName: "music.note")
                                            .foregroundStyle(.secondary)
                                    }
                            }
                            
                            // タイトルとアーティスト
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title ?? "不明な曲")
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                
                                Text(item.artist ?? "不明なアーティスト")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.plain)
    }
    
    // アルバムのリスト
    private var albumsList: some View {
        List {
            if filteredAlbums.isEmpty {
                Text("アルバムが見つかりません")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(filteredAlbums, id: \.persistentID) { collection in
                    Button {
                        musicController.playAlbum(collection)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            // アルバムアートワーク
                            if let artwork = collection.representativeItem?.artwork {
                                Image(uiImage: artwork.image(at: CGSize(width: 60, height: 60)) ?? UIImage())
                                    .resizable()
                                    .frame(width: 60, height: 60)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            } else {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(.systemGray5))
                                    .frame(width: 60, height: 60)
                                    .overlay {
                                        Image(systemName: "music.note.list")
                                            .foregroundStyle(.secondary)
                                    }
                            }
                            
                            // アルバムタイトルとアーティスト
                            VStack(alignment: .leading, spacing: 4) {
                                Text(collection.representativeItem?.albumTitle ?? "不明なアルバム")
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                
                                Text(collection.representativeItem?.artist ?? "不明なアーティスト")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                
                                Text("\(collection.count)曲")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.plain)
    }
}

// 条件付きでViewモディファイアを適用するヘルパー
extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
// カードのブルブル揺れアニメーション（iPhoneホーム画面スタイル）
struct WiggleModifier: ViewModifier {
    let isWiggling: Bool
    @State private var isAnimating = false
    
    // 各カードごとに異なるランダムな揺れの角度を生成
    private let randomAngle = Double.random(in: -2.0...2.0)
    
    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(isWiggling && isAnimating ? randomAngle : isWiggling && !isAnimating ? -randomAngle : 0))
            .animation(
                isWiggling ?
                    Animation.easeInOut(duration: 0.12)
                        .repeatForever(autoreverses: true) : 
                    .spring(response: 0.3, dampingFraction: 0.6),
                value: isWiggling
            )
            .animation(
                Animation.easeInOut(duration: 0.12)
                    .repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear {
                if isWiggling {
                    isAnimating = true
                }
            }
            .onChange(of: isWiggling) { oldValue, newValue in
                if newValue {
                    // 揺れ開始
                    isAnimating = true
                    // わずかな遅延を入れてアニメーションを確実に開始
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                        withAnimation(
                            Animation.easeInOut(duration: 0.12)
                                .repeatForever(autoreverses: true)
                        ) {
                            isAnimating.toggle()
                        }
                    }
                } else {
                    // 揺れ停止
                    isAnimating = false
                }
            }
    }
}

// ドラッグ可能なカードビュー（長押しでそのままドラッグ開始）
struct DraggableCardView<Content: View>: View {
    let cardType: MetricCardType
    @Binding var isEditMode: Bool
    @Binding var draggingCard: MetricCardType?
    @Binding var cardOrder: [MetricCardType]
    let canDelete: Bool
    let onEnterEditMode: () -> Void
    let onDelete: () -> Void
    @ViewBuilder let cardContent: () -> Content
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            cardContent()
                .modifier(WiggleModifier(isWiggling: isEditMode))
                .scaleEffect(draggingCard == cardType ? 1.05 : 1.0)
                .opacity(draggingCard == cardType ? 0.7 : 1.0)
                .zIndex(draggingCard == cardType ? 1 : 0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: draggingCard)
                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: cardOrder)
                // 編集モードでない時は長押しで編集モードに入る
                .if(!isEditMode) { view in
                    view.onLongPressGesture(minimumDuration: 0.3) {
                        print("👆 長押し完了（編集モード開始）: \(cardType.rawValue)")
                        onEnterEditMode()
                    }
                }
                // 常にドラッグ可能（編集モード時のみ実際に動作）
                .onDrag {
                    guard isEditMode else {
                        print("⚠️ 編集モードではないためドラッグ不可")
                        return NSItemProvider()
                    }
                    
                    print("🎯 onDrag呼び出し: \(cardType.rawValue)")
                    let feedback = UIImpactFeedbackGenerator(style: .light)
                    feedback.impactOccurred()
                    draggingCard = cardType
                    return NSItemProvider(object: cardType.rawValue as NSString)
                }
                .onDrop(of: [.text], delegate: ImprovedCardDropDelegate(
                    currentCard: cardType,
                    cardOrder: $cardOrder,
                    draggingCard: $draggingCard,
                    isEditMode: isEditMode
                ))
            
            // ❌バッジ（編集モード時のみ表示、削除可能なカードのみ）
            if isEditMode && canDelete {
                Button {
                    onDelete()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 28, height: 28)
                        
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .offset(x: 8, y: -8)
                .transition(.scale.combined(with: .opacity))
                .zIndex(2)
            }
        }
    }
}

// カードの並び替えデリゲート（iPhoneホーム画面スタイル・改善版）
struct ImprovedCardDropDelegate: DropDelegate {
    let currentCard: MetricCardType
    @Binding var cardOrder: [MetricCardType]
    @Binding var draggingCard: MetricCardType?
    let isEditMode: Bool
    
    func dropEntered(info: DropInfo) {
        guard isEditMode else {
            print("❌ 編集モードではありません")
            return
        }
        guard let draggingCard = draggingCard else {
            print("❌ ドラッグ中のカードがありません")
            return
        }
        
        // 同じカードの場合は何もしない
        if draggingCard == currentCard {
            return
        }
        
        // 現在の位置を取得
        guard let fromIndex = cardOrder.firstIndex(of: draggingCard),
              let toIndex = cardOrder.firstIndex(of: currentCard) else {
            print("❌ インデックスが見つかりません")
            return
        }
        
        // デバッグ出力
        print("🔄 カード入れ替え: \(draggingCard.rawValue) [\(fromIndex)] ⇄ \(currentCard.rawValue) [\(toIndex)]")
        print("   入れ替え前の順番: \(cardOrder.map { $0.rawValue })")
        
        // ハプティックフィードバック（入れ替え時）
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.impactOccurred()
        
        // 2つのカードを入れ替え
        var newOrder = cardOrder
        newOrder.swapAt(fromIndex, toIndex)
        
        print("   入れ替え後の順番: \(newOrder.map { $0.rawValue })")
        
        // アニメーション付きで更新
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            cardOrder = newOrder
        }
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard isEditMode else {
            return DropProposal(operation: .forbidden)
        }
        return DropProposal(operation: .move)
    }
    
    func performDrop(info: DropInfo) -> Bool {
        guard isEditMode else { return false }
        print("✅ ドロップ完了 - draggingCardをnilに")
        
        // 成功のハプティックフィードバック
        let feedback = UINotificationFeedbackGenerator()
        feedback.notificationOccurred(.success)
        
        // ドラッグ終了時にdraggingCardをクリア
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                draggingCard = nil
            }
        }
        
        return true
    }
    
    func dropExited(info: DropInfo) {
        print("👋 ドロップエリアを出ました: \(currentCard.rawValue)")
    }
}

// カード追加メニュー（複数選択可能、全て追加されたら自動で閉じる）
struct AddCardMenuView: View {
    @Binding var visibleCards: [MetricCardType]
    @Binding var isPresented: Bool
    
    // 追加可能なカードリスト（現在表示されていないもの）
    private var availableCards: [MetricCardType] {
        MetricCardType.allCases.filter { !visibleCards.contains($0) }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if availableCards.isEmpty {
                    // 全てのカードが追加済みの場合
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.green)
                        
                        Text("全てのカードが追加されています")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section {
                            ForEach(availableCards) { cardType in
                                Button {
                                    addCard(cardType)
                                } label: {
                                    HStack(spacing: 16) {
                                        Image(systemName: cardIcon(for: cardType))
                                            .font(.system(size: 28))
                                            .foregroundStyle(cardColor(for: cardType))
                                            .frame(width: 40)
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(cardTypeDisplayName(cardType))
                                                .font(.headline)
                                                .foregroundStyle(.primary)
                                            
                                            Text(cardDescription(for: cardType))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 24))
                                            .foregroundStyle(.blue)
                                    }
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            Text("追加可能なカード (\(availableCards.count))")
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("カードを追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        isPresented = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    
    private func addCard(_ cardType: MetricCardType) {
        guard !visibleCards.contains(cardType) else { return }
        
        print("➕ カード追加: \(cardType.rawValue)")
        
        // 成功のハプティックフィードバック
        let feedback = UINotificationFeedbackGenerator()
        feedback.notificationOccurred(.success)
        
        // カードを追加
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            visibleCards.append(cardType)
        }
        
        // 全てのカードが追加されたらログ出力（自動で閉じない）
        if visibleCards.count == MetricCardType.allCases.count {
            print("✅ 全てのカードが追加されました。完了ボタンで閉じてください。")
        }
    }
    
    private func cardTypeDisplayName(_ cardType: MetricCardType) -> String {
        switch cardType {
        case .distance: return "距離"
        case .calories: return "カロリー"
        case .heartRate: return "平均心拍数"
        case .pace: return "ペース"
        case .steps: return "歩数"
        case .marathon: return "フルマラソン予想"
        }
    }
    
    private func cardDescription(for cardType: MetricCardType) -> String {
        switch cardType {
        case .distance: return "走行距離をkmで表示"
        case .calories: return "消費カロリーをkcalで表示"
        case .heartRate: return "平均心拍数をbpmで表示"
        case .pace: return "1kmあたりのペースを表示"
        case .steps: return "歩数をカウント"
        case .marathon: return "現在のペースでの完走予想時間"
        }
    }
    
    private func cardIcon(for cardType: MetricCardType) -> String {
        switch cardType {
        case .distance: return "figure.walk"
        case .calories: return "flame.fill"
        case .heartRate: return "heart.fill"
        case .pace: return "timer"
        case .steps: return "figure.walk.motion"
        case .marathon: return "flag.checkered"
        }
    }
    
    private func cardColor(for cardType: MetricCardType) -> Color {
        switch cardType {
        case .distance: return .blue
        case .calories: return .orange
        case .heartRate: return .red
        case .pace: return .green
        case .steps: return .purple
        case .marathon: return .cyan
        }
    }
}

