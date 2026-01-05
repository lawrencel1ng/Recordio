import SwiftUI

struct FolderSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recordingManager = RecordingManager.shared
    
    let recording: Recording
    
    @State private var searchText = ""
    @State private var showingNewFolderAlert = false
    @State private var newFolderName = ""
    
    var filteredFolders: [Folder] {
        if searchText.isEmpty {
            return recordingManager.folders
        } else {
            return recordingManager.folders.filter { ($0.name ?? "").localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var body: some View {
        NavigationView {
            List {
                if !searchText.isEmpty && filteredFolders.isEmpty {
                    Text("No folders found")
                        .foregroundColor(.secondary)
                }
                
                Section {
                    Button(action: {
                        moveRecording(to: nil)
                    }) {
                        HStack {
                            Image(systemName: "tray")
                                .foregroundColor(.secondary)
                            Text("No Folder")
                                .foregroundColor(.primary)
                            Spacer()
                            if recording.folder == nil {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
                
                Section {
                    ForEach(filteredFolders) { folder in
                        Button(action: {
                            moveRecording(to: folder)
                        }) {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundColor(.blue)
                                Text(folder.name ?? "Untitled")
                                    .foregroundColor(.primary)
                                Spacer()
                                if recording.folder == folder {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Move to Folder")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search folders")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        newFolderName = ""
                        showingNewFolderAlert = true
                    }) {
                        Image(systemName: "folder.badge.plus")
                    }
                }
            }
            .alert("New Folder", isPresented: $showingNewFolderAlert) {
                TextField("Folder Name", text: $newFolderName)
                Button("Cancel", role: .cancel) { }
                Button("Create") {
                    if !newFolderName.isEmpty {
                        let folder = recordingManager.createFolder(name: newFolderName)
                        moveRecording(to: folder)
                    }
                }
            }
        }
    }
    
    private func moveRecording(to folder: Folder?) {
        recordingManager.moveRecording(recording, to: folder)
        dismiss()
    }
}
