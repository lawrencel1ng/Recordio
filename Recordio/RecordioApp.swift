//
//  RecordioApp.swift
//  Recordio
//
//  Created by Lawrence Ling on 5/1/26.
//

import SwiftUI
import CoreData

@main
struct RecordioApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
