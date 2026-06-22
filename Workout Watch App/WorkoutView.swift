//
//  WorkoutView.swift
//  Workout Watch App
//
//  Created by 山中雄樹 on 2026/03/04.
//

import SwiftUI
import MapKit

struct WorkoutView: View {
    @EnvironmentObject var workoutManager: WorkoutManager
    @ObservedObject var locationManager: LocationManager
    @State private var currentPage = 1
    @State private var isTogglingPause = false
    @State private var isEndingWorkout = false
    @State private var verticalPage = 1

    // タイマーベースの点滅制御
    @State private var blinkTimer: Timer?
    @State private var isButtonVisible = true
    @State private var clockTriggerActive = false
    @State private var clockShakeOffset: CGFloat = 0

    @Environment(\.scenePhase) private var scenePhase
    
    // 画面サイズに応じたスケール係数
    private var sizeScale: CGFloat {
        let screenWidth = WKInterfaceDevice.current().screenBounds.width
        // 40mm (162pt) を基準 (1.0)、45mm (184pt) で約1.14、Ultra (205pt) で約1.26
        return screenWidth / 162.0
    }
    
    var body: some View {
        TabView(selection: $currentPage) {
            // コントロールページ（0番目・左側）
            controlView
                .tag(0)
            
            // メインページ（1番目・中央）: 縦TabViewでスプリット(上)、ワークアウト(中)、マップ(下)を配置
            TabView(selection: $verticalPage) {
                splitTimesView
                    .tag(0)
                mainWorkoutView
                    .tag(1)
                WatchWorkoutMapView(verticalPage: $verticalPage, locationManager: locationManager)
                    .tag(2)
            }
            .tabViewStyle(.verticalPage)
            .tag(1)
            
            // ミュージックコントロールページ（2番目・右側）
            MusicControlView()
                .tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .offset(x: clockShakeOffset)
        .onChange(of: workoutManager.isPaused) { oldValue, newValue in
            print("🔄 isPaused changed from \(oldValue) to \(newValue)")
            // 点滅状態を確実に同期
            if newValue {
                // 一時停止になったら点滅開始
                print("🔄 Starting blink animation...")
                startBlinking()
            } else {
                // 再開したら点滅停止
                print("🔄 Stopping blink animation...")
                stopBlinking()
            }
        }
        .onChange(of: currentPage) { oldValue, newValue in
            if workoutManager.isPaused {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    startBlinking()
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // 手首を上げて画面が点灯した時、必ずメインワークアウト画面に戻る
            if newPhase == .active && workoutManager.isWorkoutActive {
                currentPage = 1
                verticalPage = 1
            }
        }
        .onAppear {
            currentPage = 1
            verticalPage = 1
            clockTriggerActive = false
            isTogglingPause = false
            isEndingWorkout = false
            isButtonVisible = true
            // ルート追跡開始（GPS は ContentView で起動済み）
            locationManager.startRouteTracking()
            if workoutManager.isPaused {
                startBlinking()
            }
            // watchOSはレイアウトに変化がある時のみ時計位置を右上へ更新する。
            // 遷移完了後にTabView全体を±12ptで左右に微小振りして変化を検知させる。
            // offsetが小さいためページ切り替えは起きず、視覚的にもほぼ気にならない。
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                guard workoutManager.isWorkoutActive else { return }
                clockTriggerActive = true
                withAnimation(.easeInOut(duration: 0.08)) { clockShakeOffset = -12 }
                try? await Task.sleep(for: .milliseconds(100))
                withAnimation(.easeInOut(duration: 0.08)) { clockShakeOffset = 12 }
                try? await Task.sleep(for: .milliseconds(100))
                withAnimation(.easeInOut(duration: 0.08)) { clockShakeOffset = 0 }
            }
        }
        .onDisappear {
            stopBlinking()
            isTogglingPause = false
            isEndingWorkout = false
        }
    }
    
    // スプリット記録画面（下スワイプで表示）
    private var splitTimesView: some View {
        GeometryReader { geometry in
            // ヘッダー・ギャップ・フッターを明示的に分離
            let topSpaceH: CGFloat = 30  // 画面最上部からの余白
            let textH: CGFloat = 24      // 「スプリット」20ptフォントの高さ
            let gapH: CGFloat = 8        // タイトルと記録グリッドの間隔
            let footerH: CGFloat = 26
            let rowH = (geometry.size.height - topSpaceH - textH - gapH - footerH) / 5.0
            let splits = workoutManager.lapTimes
            let fastest: Int? = splits.count > 1
                ? splits.indices.min(by: { splits[$0] < splits[$1] })
                : nil
            let slowest: Int? = splits.count > 1
                ? splits.indices.max(by: { splits[$0] < splits[$1] })
                : nil

            VStack(spacing: 0) {
                // 画面最上部からの余白 40pt
                Color.clear.frame(height: topSpaceH)

                // タイトル（最大フォント）
                Text("スプリット")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: textH)

                // タイトルと記録の間の余白 8pt
                Color.clear.frame(height: gapH)

                // スプリットグリッド（ScrollViewReader で最新行へ自動スクロール）
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            if splits.isEmpty {
                                Text("記録なし")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: rowH * 3)
                            } else {
                                let totalRows = (splits.count + 4) / 5
                                ForEach(0..<totalRows, id: \.self) { row in
                                    HStack(spacing: 0) {
                                        ForEach(0..<5, id: \.self) { col in
                                            let i = row * 5 + col
                                            if i < splits.count {
                                                VStack(spacing: 0) {
                                                    Text("\(i + 1)km")
                                                        .font(.system(size: 14, weight: .medium))
                                                        .foregroundStyle(.secondary)
                                                        .lineLimit(1)
                                                    Text(formatSplitTime(splits[i]))
                                                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                                                        .foregroundStyle(splitColor(i, fastest: fastest, slowest: slowest))
                                                        .minimumScaleFactor(0.6)
                                                        .lineLimit(1)
                                                }
                                                .frame(maxWidth: .infinity, minHeight: rowH, maxHeight: rowH)
                                            } else {
                                                Color.clear
                                                    .frame(maxWidth: .infinity, minHeight: rowH, maxHeight: rowH)
                                            }
                                        }
                                    }
                                    .id("row_\(row)")
                                }
                            }
                        }
                    }
                    .onChange(of: workoutManager.lapTimes.count) { _, newCount in
                        guard newCount > 0 else { return }
                        let lastRow = (newCount - 1) / 5
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo("row_\(lastRow)", anchor: .bottom)
                        }
                    }
                }

                // フッター（大きめの余白）
                Color.clear.frame(height: footerH)
            }
        }
        .ignoresSafeArea(edges: [.top, .bottom])
    }

    private func splitColor(_ index: Int, fastest: Int?, slowest: Int?) -> Color {
        if fastest == index { return .red }
        if slowest == index { return .blue }
        return .green
    }

    private func formatSplitTime(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }

    private func calculateMarathonPrediction() -> String {
        let marathonDistance = 42195.0
        let currentDistance = workoutManager.distance
        let elapsedTime = workoutManager.elapsedTime

        guard currentDistance > 0 && elapsedTime > 0 else { return "--:--:--" }

        let estimatedTotal = marathonDistance * (elapsedTime / currentDistance)
        let hours = Int(estimatedTotal / 3600)
        let minutes = Int(estimatedTotal.truncatingRemainder(dividingBy: 3600) / 60)
        let seconds = Int(estimatedTotal.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }

    // メイン画面
    private var mainWorkoutView: some View {
        GeometryReader { geometry in
            let cellSpacing: CGFloat = 2
            let horizontalPadding: CGFloat = 4
            let footerHeight: CGFloat = 8
            let availableWidth = geometry.size.width - horizontalPadding * 2
            let cellWidth = (availableWidth - cellSpacing) / 2

            VStack(spacing: 0) {
                // ワークアウトタイトル
                Text(workoutManager.workoutName)
                    .font(.system(size: 12 * sizeScale, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                // 経過時間
                Text(workoutManager.elapsedTimeString)
                    .font(.system(size: 21 * sizeScale, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.bottom, 2)

                // 2x3 メトリクスグリッド（残り領域を3行に均等分配）
                VStack(spacing: cellSpacing) {
                    // Row 1: 距離 | カロリー
                    HStack(spacing: cellSpacing) {
                        WatchMetricCell(
                            icon: "figure.run",
                            label: "距離",
                            value: String(format: "%.2f", workoutManager.distance / 1000),
                            unit: "km",
                            color: .blue,
                            sizeScale: sizeScale
                        )
                        .frame(width: cellWidth)

                        WatchMetricCell(
                            icon: "flame.fill",
                            label: "カロリー",
                            value: String(format: "%.0f", workoutManager.activeCalories),
                            unit: "kcal",
                            color: .orange,
                            sizeScale: sizeScale
                        )
                        .frame(width: cellWidth)
                    }
                    .frame(maxHeight: .infinity)

                    // Row 2: 平均心拍数 | ペース
                    HStack(spacing: cellSpacing) {
                        WatchMetricCell(
                            icon: "heart.fill",
                            label: "平均心拍数",
                            value: workoutManager.averageHeartRate > 0 ? String(format: "%.0f", workoutManager.averageHeartRate) : "--",
                            unit: "bpm",
                            color: .red,
                            sizeScale: sizeScale
                        )
                        .frame(width: cellWidth)

                        WatchMetricCell(
                            icon: "speedometer",
                            label: "ペース",
                            value: workoutManager.currentPaceString,
                            unit: "/km",
                            color: .green,
                            sizeScale: sizeScale
                        )
                        .frame(width: cellWidth)
                    }
                    .frame(maxHeight: .infinity)

                    // Row 3: 歩数 | フルマラソン予想
                    HStack(spacing: cellSpacing) {
                        WatchMetricCell(
                            icon: "figure.walk.motion",
                            label: "歩数",
                            value: String(format: "%.0f", workoutManager.stepCount),
                            unit: "歩",
                            color: .purple,
                            sizeScale: sizeScale
                        )
                        .frame(width: cellWidth)

                        WatchMarathonCell(
                            prediction: calculateMarathonPrediction(),
                            sizeScale: sizeScale
                        )
                        .frame(width: cellWidth)
                    }
                    .frame(maxHeight: .infinity)
                }
                .padding(.horizontal, horizontalPadding)
                .frame(maxHeight: .infinity)

                // フッター（画面下の空白）
                Color.clear
                    .frame(height: footerHeight)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea(edges: clockTriggerActive ? [.top, .bottom] : [.bottom])
    }
    
    // コントロール専用画面
    private var controlView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            // 一時停止/再開ボタン
            Button {
                guard !isTogglingPause && !isEndingWorkout else {
                    print("⚠️ Already toggling pause, ignoring tap")
                    return
                }

                let wasPaused = workoutManager.isPaused
                togglePause()

                if wasPaused == true {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation {
                            currentPage = 1
                        }
                    }
                }
                // 一時停止時：その画面に留まる（何もしない）
            } label: {
                HStack {
                    Image(systemName: workoutManager.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 22 * sizeScale))
                    Text(workoutManager.isPaused ? "再開" : "一時停止")
                        .font(.system(size: 20 * sizeScale, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(workoutManager.isPaused ? .green : .orange)
            .disabled(isTogglingPause || isEndingWorkout)
            .opacity(isTogglingPause ? 0.5 : (workoutManager.isPaused && !isButtonVisible ? 0.4 : 1.0))
            .animation(.easeInOut(duration: 0.2), value: isButtonVisible)

            // ワークアウト終了ボタン
            Button {
                endWorkout()
            } label: {
                Text("ワークアウトを終了")
                    .font(.system(size: 28 * sizeScale, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(isEndingWorkout)
            .opacity(isEndingWorkout ? 0.5 : 1.0)
            
            Spacer()
        }
        .padding()
    }
    
    private func togglePause() {
        guard !isTogglingPause else { return }

        isTogglingPause = true

        if workoutManager.isPaused {
            workoutManager.resumeWorkout()
        } else {
            workoutManager.pauseWorkout()
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            isTogglingPause = false
        }
    }
    
    private func startBlinking() {
        stopBlinking()
        isButtonVisible = true

        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { _ in
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.4)) {
                    self.isButtonVisible.toggle()
                }
            }
        }

        if let timer = blinkTimer {
            RunLoop.current.add(timer, forMode: .common)
        }
    }

    private func stopBlinking() {
        blinkTimer?.invalidate()
        blinkTimer = nil

        Task { @MainActor in
            withAnimation(.easeOut(duration: 0.2)) {
                isButtonVisible = true
            }
        }
    }
    
    private func endWorkout() {
        // 連続タップを防止（履歴の重複保存を防ぐ）
        guard !isEndingWorkout else {
            print("⚠️ endWorkout: Already ending, ignoring tap")
            return
        }
        isEndingWorkout = true

        // ワークアウト履歴のスナップショットを即座に取得（後続のリセットに備える）
        let shouldSaveRecord = workoutManager.elapsedTime >= 10
        let capturedRoute = locationManager.routeCoordinates.map {
            RouteCoordinate(latitude: $0.latitude, longitude: $0.longitude)
        }
        locationManager.stopRouteTracking()
        let record: WorkoutHistoryRecord? = shouldSaveRecord ? WorkoutHistoryRecord(
            workoutName: workoutManager.workoutName,
            elapsedTime: workoutManager.elapsedTime,
            distance: workoutManager.distance,
            activeCalories: workoutManager.activeCalories,
            averageHeartRate: workoutManager.averageHeartRate,
            stepCount: workoutManager.stepCount,
            lapTimes: workoutManager.lapTimes,
            routeCoordinates: capturedRoute,
            deviceSource: "watch"
        ) : nil

        stopBlinking()

        // 一時停止関連の状態をリセット
        isTogglingPause = false
        isButtonVisible = true

        Task { @MainActor in
            defer { isEndingWorkout = false }

            print("🔴 WorkoutView: Starting workout end sequence")

            // ボタンの視覚フィードバックを優先するため一度yieldしてから保存
            if let record {
                await Task.yield()
                WorkoutHistoryStore.shared.save(record: record)
            }

            // ワークアウトを終了
            await workoutManager.endWorkout()

            print("🔴 WorkoutView: isWorkoutActive = \(workoutManager.isWorkoutActive)")
            print("🔴 WorkoutView: session = \(workoutManager.session != nil)")

            // ページを初期状態に戻す
            currentPage = 1

            // フォールバック: 万が一 isWorkoutActive が残っていれば強制リセット
            try? await Task.sleep(for: .milliseconds(100))
            if workoutManager.isWorkoutActive {
                print("⚠️ WorkoutView: isWorkoutActive is still true after endWorkout!")
                workoutManager.isWorkoutActive = false
            }
        }
    }
}

// Apple Watch用メトリクスセル
struct WatchMetricCell: View {
    let icon: String
    let label: String
    let value: String
    let unit: String
    let color: Color
    let sizeScale: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 1) {
                Image(systemName: icon)
                    .font(.system(size: 11 * sizeScale))
                Text(label)
                    .font(.system(size: 11 * sizeScale, weight: .medium))
            }
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.5)

            Spacer(minLength: 0)

            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value)
                    .font(.system(size: 22 * sizeScale, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.3)
                Text(unit)
                    .font(.system(size: 11 * sizeScale))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.3)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 1)
        .padding(.horizontal, 2)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// Apple Watch用フルマラソン予想セル
struct WatchMarathonCell: View {
    let prediction: String
    let sizeScale: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 1) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 11 * sizeScale))
                    Text("フルマラソン")
                        .font(.system(size: 11 * sizeScale, weight: .medium))
                }
                Text("予想")
                    .font(.system(size: 11 * sizeScale, weight: .medium))
            }
            .foregroundStyle(.cyan)
            .lineLimit(1)
            .minimumScaleFactor(0.5)

            Spacer(minLength: 0)

            Text(prediction)
                .font(.system(size: 19 * sizeScale, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.3)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 1)
        .padding(.horizontal, 2)
        .background(Color.cyan.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// ワークアウト中マップビュー（Apple Watch用）
struct WatchWorkoutMapView: View {
    @Binding var verticalPage: Int
    @ObservedObject var locationManager: LocationManager
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var zoomSpan = MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004)
    @State private var crownValue: Double = 0.0
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            if locationManager.authorizationStatus == .denied ||
               locationManager.authorizationStatus == .restricted {
                VStack(spacing: 8) {
                    Image(systemName: "location.slash.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("位置情報が\n無効です")
                        .font(.system(size: 13))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // マップ本体（リアルタイム軌跡付き）
                Map(position: $cameraPosition) {
                    // 走行軌跡を青色で表示
                    if locationManager.routeCoordinates.count > 1 {
                        MapPolyline(coordinates: locationManager.routeCoordinates)
                            .stroke(.blue, lineWidth: 4)
                    }
                    // スタート地点マーカー（小さい赤丸）
                    if let startCoord = locationManager.startCoordinate {
                        Annotation("", coordinate: startCoord) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 10, height: 10)
                                .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                                .shadow(color: .black.opacity(0.4), radius: 2)
                        }
                        .annotationTitles(.hidden)
                    }
                    // 現在地アイコン
                    if let location = locationManager.currentLocation {
                        Annotation("", coordinate: location.coordinate) {
                            ZStack {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 30, height: 30)
                                    .shadow(color: .black.opacity(0.3), radius: 3)
                                Image(systemName: "figure.run")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .annotationTitles(.hidden)
                    }
                }
                .mapStyle(.standard)
                .ignoresSafeArea()
                .onMapCameraChange(frequency: .onEnd) { context in
                    zoomSpan = context.region.span
                }

                // ▲ボタン（画面絶対最上端・システムクロック位置まで）
                // Mapのジェスチャー横取りを防ぐため highPriorityGesture を使用
                VStack(spacing: 0) {
                    ZStack {
                        // タッチ受信用の不透明極薄レイヤー（Color.clearはhit-testが通らないため）
                        Color.black.opacity(0.001)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .contentShape(Rectangle())
                        // ▲ボタン外観
                        Image(systemName: "chevron.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 90, height: 28)
                            .background(.black.opacity(0.55))
                            .clipShape(Capsule())
                    }
                    .highPriorityGesture(
                        TapGesture().onEnded {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                verticalPage = 1
                            }
                        }
                    )
                    Spacer()
                }
                .ignoresSafeArea(edges: .top)

                // 縮尺テキスト（右下固定）
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(watchScaleLabel(for: zoomSpan))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .padding(.trailing, 4)
                            .padding(.bottom, 6)
                    }
                }

                // 位置取得中インジケーター
                if locationManager.currentLocation == nil {
                    VStack(spacing: 8) {
                        ProgressView()
                            .tint(.white)
                        Text("位置情報を\n取得中...")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                }
            }
        }
        .onChange(of: locationManager.currentLocation) { _, location in
            guard let loc = location else { return }
            withAnimation(.linear(duration: 0.5)) {
                cameraPosition = .region(MKCoordinateRegion(
                    center: loc.coordinate,
                    span: zoomSpan
                ))
            }
        }
        .onAppear {
            isFocused = true
            // 画面表示・再表示のたびに100m縮尺・現在地へリセット
            let span100m = MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004)
            zoomSpan = span100m
            if let loc = locationManager.currentLocation {
                cameraPosition = .region(MKCoordinateRegion(
                    center: loc.coordinate,
                    span: span100m
                ))
            } else {
                cameraPosition = .automatic
            }
        }
        .focusable()
        .focused($isFocused)
        .digitalCrownRotation($crownValue, from: -1000.0, through: 1000.0, sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: false)
        .onChange(of: crownValue) { oldValue, newValue in
            let delta = newValue - oldValue
            let zoomFactor = pow(2.0, -delta * 0.05)
            let newLat = max(0.0005, min(0.5, zoomSpan.latitudeDelta * zoomFactor))
            let newLon = max(0.0005, min(0.5, zoomSpan.longitudeDelta * zoomFactor))
            zoomSpan = MKCoordinateSpan(latitudeDelta: newLat, longitudeDelta: newLon)
            if let loc = locationManager.currentLocation {
                cameraPosition = .region(MKCoordinateRegion(center: loc.coordinate, span: zoomSpan))
            }
        }
    }

    // 現在のズームスパンから縮尺テキストを生成
    private func watchScaleLabel(for span: MKCoordinateSpan) -> String {
        let metersPerDegree = 111_000.0
        let widthMeters = span.latitudeDelta * metersPerDegree * 0.25
        let steps = [1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000, 10000]
        let nice = steps.min(by: { abs(Double($0) - widthMeters) < abs(Double($1) - widthMeters) }) ?? 1
        return nice >= 1000 ? "\(nice / 1000) km" : "\(nice) m"
    }
}

#Preview {
    WorkoutView(locationManager: LocationManager())
        .environmentObject(WorkoutManager())
}
