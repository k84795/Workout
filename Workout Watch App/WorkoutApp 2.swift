//
//  WorkoutApp.swift
//  Workout (iPhone App)
//
//  Created on 2026/03/09.
//

#if os(iOS)
import SwiftUI

@main
struct WorkoutPhoneApp: App {
    
    init() {
        // Watch Connectivityマネージャーを初期化
        _ = PhoneMusicConnectivityManager.shared
    }
    
    var body: some Scene {
        WindowGroup {
            PhoneContentView()
        }
    }
}

struct PhoneContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "applewatch")
                .font(.system(size: 80))
                .foregroundStyle(.pink)
                .padding()
            
            Text("Workout アプリ")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Apple Watchでワークアウトを開始してください")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
        }
        .padding()
    }
}

#Preview {
    PhoneContentView()
}
#endif // os(iOS)

