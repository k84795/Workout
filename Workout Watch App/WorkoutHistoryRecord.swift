
//
//  WorkoutHistoryRecord.swift
//  RUX
//
//  Created by 山中雄樹 on 2026/05/30.
//

import Foundation
import WatchConnectivity

struct WorkoutHistoryRecord: Codable, Identifiable {
    let id: UUID
    let workoutName: String
    let date: Date
    let elapsedTime: TimeInterval
    let distance: Double
    let activeCalories: Double
    let averageHeartRate: Double
    let stepCount: Double
    let lapTimes: [TimeInterval]

    init(workoutName: String, elapsedTime: TimeInterval, distance: Double, activeCalories: Double, averageHeartRate: Double, stepCount: Double, lapTimes: [TimeInterval]) {
        self.id = UUID()
        self.workoutName = workoutName
        self.date = Date()
        self.elapsedTime = elapsedTime
        self.distance = distance
        self.activeCalories = activeCalories
        self.averageHeartRate = averageHeartRate
        self.stepCount = stepCount
        self.lapTimes = lapTimes
    }
}

class WorkoutHistoryStore {
    static let shared = WorkoutHistoryStore()

    private let key = "workoutHistory"
    private let deletedIDsKey = "deletedWorkoutHistoryIDs"
    private let maxRecords = 30

    // MARK: - Local Operations

    func save(record: WorkoutHistoryRecord) {
        var records = loadRecords()
        records.insert(record, at: 0)
        if records.count > maxRecords {
            records = Array(records.prefix(maxRecords))
        }
        persist(records)
        syncFullState()
    }

    func delete(recordID: UUID) {
        var records = loadRecords()
        records.removeAll { $0.id == recordID }
        persist(records)
        addDeletedID(recordID)
        syncFullState()
    }

    func deleteAll() {
        let records = loadRecords()
        for record in records {
            addDeletedID(record.id)
        }
        UserDefaults.standard.removeObject(forKey: key)
        syncFullState()
    }

    func loadRecords() -> [WorkoutHistoryRecord] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let records = try? JSONDecoder().decode([WorkoutHistoryRecord].self, from: data) else {
            return []
        }
        return records
    }

    // MARK: - Deleted IDs

    private func addDeletedID(_ id: UUID) {
        var ids = loadDeletedIDs()
        ids.insert(id.uuidString)
        if ids.count > 100 {
            ids = Set(Array(ids).suffix(100))
        }
        UserDefaults.standard.set(Array(ids), forKey: deletedIDsKey)
    }

    private func loadDeletedIDs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: deletedIDsKey) ?? [])
    }

    // MARK: - Remote Sync

    func handleRemoteFullState(_ context: [String: Any]) {
        guard let recordsData = context["historyRecords"] as? Data,
              let remoteRecords = try? JSONDecoder().decode([WorkoutHistoryRecord].self, from: recordsData) else {
            return
        }

        let remoteDeletedIDs = Set(context["historyDeletedIDs"] as? [String] ?? [])

        var localDeletedIDs = loadDeletedIDs()
        localDeletedIDs.formUnion(remoteDeletedIDs)
        UserDefaults.standard.set(Array(localDeletedIDs), forKey: deletedIDsKey)

        var local = loadRecords()
        let localIDs = Set(local.map { $0.id })

        local.removeAll { remoteDeletedIDs.contains($0.id.uuidString) }

        for record in remoteRecords {
            if !localIDs.contains(record.id) && !localDeletedIDs.contains(record.id.uuidString) {
                local.append(record)
            }
        }

        local.sort { $0.date > $1.date }
        if local.count > maxRecords {
            local = Array(local.prefix(maxRecords))
        }

        persist(local)
    }

    // MARK: - Private

    private func persist(_ records: [WorkoutHistoryRecord]) {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func syncFullState() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        let records = loadRecords()
        guard let recordsData = try? JSONEncoder().encode(records) else { return }
        let deletedIDs = Array(loadDeletedIDs())

        let context: [String: Any] = [
            "historyRecords": recordsData,
            "historyDeletedIDs": deletedIDs
        ]

        try? session.updateApplicationContext(context)
    }
}
