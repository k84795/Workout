//
//  WorkoutTypeSelectionView.swift
//  Workout Watch App
//
//  Created by 山中雄樹 on 2026/03/04.
//

import SwiftUI
import HealthKit

struct WorkoutTypeSelectionView: View {
    @EnvironmentObject private var workoutManager: WorkoutManager
    @State private var showError = false
    @State private var showHistory = false

    var onWorkoutSelected: ((HKWorkoutActivityType, String) -> Void)?
    
    let workoutTypes: [(name: String, type: HKWorkoutActivityType, icon: String, color: Color)] = [
        ("ウォーキング", .walking, "walking", .green),
        ("ジョギング", .running, "jogging", .blue),
        ("ランニング", .running, "running", .red)
    ]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ForEach(Array(workoutTypes.enumerated()), id: \.offset) { index, workout in
                    Button {
                        guard !workoutManager.isWorkoutActive else { return }
                        onWorkoutSelected?(workout.type, workout.name)
                    } label: {
                        HStack(spacing: 8) {
                            Image(workout.icon)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 28, height: 28)

                            Text(workout.name)
                                .font(.system(size: 24, weight: .semibold))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .foregroundStyle(workout.color)

                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, minHeight: 56, maxHeight: .infinity)
                    }
                    .buttonStyle(.plain)
                    .disabled(workoutManager.isWorkoutActive)

                    if index < workoutTypes.count - 1 {
                        Divider()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }
            }
            .sheet(isPresented: $showHistory) {
                WatchWorkoutHistoryView()
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {
                workoutManager.errorMessage = nil
            }
        } message: {
            if let errorMessage = workoutManager.errorMessage {
                Text(errorMessage)
            }
        }
        .onChange(of: workoutManager.errorMessage) { _, newValue in
            if newValue != nil {
                showError = true
            }
        }
    }
    
}

struct WatchWorkoutHistoryView: View {
    @State private var records: [WorkoutHistoryRecord] = []
    @State private var recordToDelete: WorkoutHistoryRecord?
    @State private var showDeleteAlert = false
    @State private var showDeleteAllAlert = false

    private var sizeScale: CGFloat {
        let screenWidth = WKInterfaceDevice.current().screenBounds.width
        return screenWidth / 162.0
    }

    var body: some View {
        NavigationStack {
        Group {
            if records.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                    Text("履歴はありません")
                        .font(.system(size: 14 * sizeScale))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    Spacer()
                }
            } else {
                List {
                    ForEach(records) { record in
                    NavigationLink {
                        WatchWorkoutLapDetailView(record: record)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(formatDate(record.date))
                                .font(.system(size: 12 * sizeScale, weight: .semibold))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 3) {
                                Image(workoutIcon(for: record.workoutName))
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 20 * sizeScale, height: 20 * sizeScale)
                                Text(record.workoutName)
                                    .font(.system(size: 20 * sizeScale, weight: .bold))
                                    .foregroundStyle(workoutColor(for: record.workoutName))
                                    .fixedSize(horizontal: true, vertical: false)
                                Text(record.deviceEmoji)
                                    .font(.system(size: 20 * sizeScale))
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            .lineLimit(1)
                            HStack {
                                HStack(spacing: 2) {
                                    Image(systemName: "figure.run")
                                        .font(.system(size: 9 * sizeScale))
                                    Text(String(format: "%.2fkm", record.distance / 1000))
                                        .font(.system(size: 12 * sizeScale, design: .rounded))
                                }
                                .foregroundStyle(.blue)
                                Spacer()
                                HStack(spacing: 2) {
                                    Image(systemName: "timer")
                                        .font(.system(size: 9 * sizeScale))
                                    Text(formatTime(record.elapsedTime))
                                        .font(.system(size: 12 * sizeScale, design: .rounded))
                                }
                                .foregroundStyle(.green)
                            }
                            HStack {
                                HStack(spacing: 2) {
                                    Image(systemName: "flame.fill")
                                        .font(.system(size: 9 * sizeScale))
                                    Text(String(format: "%.0fkcal", record.activeCalories))
                                        .font(.system(size: 11 * sizeScale))
                                }
                                .foregroundStyle(.orange)
                                Spacer()
                                if record.averageHeartRate > 0 {
                                    HStack(spacing: 2) {
                                        Image(systemName: "heart.fill")
                                            .font(.system(size: 9 * sizeScale))
                                        Text(String(format: "%.0fbpm", record.averageHeartRate))
                                            .font(.system(size: 11 * sizeScale))
                                    }
                                    .foregroundStyle(.red)
                                }
                            }
                            HStack {
                                if record.distance > 0 {
                                    HStack(spacing: 2) {
                                        Image(systemName: "speedometer")
                                            .font(.system(size: 9 * sizeScale))
                                        Text(formatPace(elapsedTime: record.elapsedTime, distance: record.distance))
                                            .font(.system(size: 11 * sizeScale))
                                    }
                                    .foregroundStyle(.cyan)
                                }
                                Spacer()
                                if record.stepCount > 0 {
                                    HStack(spacing: 2) {
                                        Image(systemName: "figure.walk")
                                            .font(.system(size: 9 * sizeScale))
                                        Text(String(format: "%.0f歩", record.stepCount))
                                            .font(.system(size: 11 * sizeScale))
                                    }
                                    .foregroundStyle(.purple)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                recordToDelete = record
                                showDeleteAlert = true
                            } label: {
                                Image(systemName: "xmark")
                            }
                        }
                    }

                    Button(role: .destructive) {
                        showDeleteAllAlert = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("全ての履歴を削除")
                                .font(.system(size: 13 * sizeScale, weight: .semibold))
                            Spacer()
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("履歴")
        .onAppear {
            records = WorkoutHistoryStore.shared.loadRecords()
        }
        .alert("この履歴を消しますか？", isPresented: $showDeleteAlert) {
            Button("OK", role: .destructive) {
                if let record = recordToDelete {
                    WorkoutHistoryStore.shared.delete(recordID: record.id)
                    records = WorkoutHistoryStore.shared.loadRecords()
                    recordToDelete = nil
                }
            }
            Button("キャンセル", role: .cancel) {
                recordToDelete = nil
            }
        }
        .alert("全ての履歴を消しますか？", isPresented: $showDeleteAllAlert) {
            Button("OK", role: .destructive) {
                WorkoutHistoryStore.shared.deleteAll()
                records = []
            }
            Button("キャンセル", role: .cancel) {}
        }
        }
    }

    private func workoutColor(for name: String) -> Color {
        switch name {
        case "ウォーキング": return .green
        case "ジョギング": return .blue
        case "ランニング": return .red
        default: return .primary
        }
    }

    private func workoutIcon(for name: String) -> String {
        switch name {
        case "ウォーキング": return "walking"
        case "ジョギング": return "jogging"
        case "ランニング": return "running"
        default: return "running"
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d HH:mm"
        return formatter.string(from: date)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func formatPace(elapsedTime: TimeInterval, distance: Double) -> String {
        guard distance > 0 else { return "--:--" }
        let pacePerKm = elapsedTime / (distance / 1000)
        let minutes = Int(pacePerKm) / 60
        let seconds = Int(pacePerKm) % 60
        return String(format: "%d:%02d/km", minutes, seconds)
    }
}

struct WatchWorkoutLapDetailView: View {
    let record: WorkoutHistoryRecord

    private var sizeScale: CGFloat {
        let screenWidth = WKInterfaceDevice.current().screenBounds.width
        return screenWidth / 162.0
    }

    var body: some View {
        List {
            if record.lapTimes.isEmpty {
                Text("スプリット記録はありません")
                    .font(.system(size: 14 * sizeScale))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(record.lapTimes.enumerated()), id: \.offset) { index, time in
                    HStack {
                        Text("\(index + 1)km")
                            .font(.system(size: 16 * sizeScale, weight: .bold))
                        Spacer()
                        Text(formatLapTime(time))
                            .font(.system(size: 16 * sizeScale, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(lapColor(for: time))
                    }
                }
            }
        }
        .navigationTitle("スプリット")
    }

    private func formatLapTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let hundredths = Int((time.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%d:%02d.%02d", minutes, seconds, hundredths)
    }

    private func lapColor(for time: TimeInterval) -> Color {
        guard record.lapTimes.count > 1 else { return .green }
        let fastest = record.lapTimes.min() ?? 0
        let slowest = record.lapTimes.max() ?? 0
        if time == fastest { return .red }
        if time == slowest && fastest != slowest { return .blue }
        return .green
    }
}

struct WatchCountdownView: View {
    let onCancel: () -> Void
    let onFinish: () -> Void

    @State private var count = 3
    @State private var ringProgress: CGFloat = 1.0
    @State private var isDismissed = false

    private var sizeScale: CGFloat {
        let screenWidth = WKInterfaceDevice.current().screenBounds.width
        return screenWidth / 162.0
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ZStack {
                // 背景リング
                Circle()
                    .stroke(Color.green.opacity(0.25), lineWidth: 10 * sizeScale)
                    .frame(width: 120 * sizeScale, height: 120 * sizeScale)

                // カウントダウンリング
                Circle()
                    .trim(from: 0, to: ringProgress)
                    .stroke(
                        Color.green,
                        style: StrokeStyle(lineWidth: 10 * sizeScale, lineCap: .round)
                    )
                    .frame(width: 120 * sizeScale, height: 120 * sizeScale)
                    .rotationEffect(.degrees(-90))
                    .id(count)

                // カウントダウン数字（タップでスキップ）
                Text("\(count)")
                    .font(.system(size: 64 * sizeScale, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            // キャンセルボタン（右上）
            VStack {
                HStack {
                    Spacer()
                    Button {
                        isDismissed = true
                        onCancel()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14 * sizeScale, weight: .bold))
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(10 * sizeScale)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.trailing, 6 * sizeScale)
                Spacer()
            }
        }
        .onTapGesture {
            isDismissed = true
            onFinish()
        }
        .onAppear {
            startCountdown()
        }
    }

    private func startCountdown() {
        Task { @MainActor in
            for i in [3, 2, 1] {
                if isDismissed { return }
                count = i
                ringProgress = 1.0
                withAnimation(.linear(duration: 1.0)) {
                    ringProgress = 0.0
                }
                try? await Task.sleep(for: .seconds(1))
            }
            if isDismissed { return }
            onFinish()
        }
    }
}

#Preview {
    WorkoutTypeSelectionView()
        .environmentObject(WorkoutManager())
}
