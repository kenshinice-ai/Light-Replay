// Synthetic-only audit probe. Compile with current PropertyModel/MediaStore.swift into an external scratch directory.
// It creates and cleans only its own temporary folder; never targets the app Documents directory.
import Foundation
let parent=FileManager.default.temporaryDirectory.appending(path:"PR-delete-probe-\(UUID().uuidString)",directoryHint:.isDirectory)
try FileManager.default.createDirectory(at:parent,withIntermediateDirectories:true)
let target=parent.appending(path:"synthetic-photo.jpg")
try Data("synthetic only".utf8).write(to:target)
try FileManager.default.setAttributes([.posixPermissions:0o555],ofItemAtPath:parent.path)
defer {try? FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:parent.path);try? FileManager.default.removeItem(at:parent)}
do{try MediaStore.removeThrowingUnlessMissing(target);print("Expected permission error was not triggered")}
catch{print("throwing remove correctly reports:",error.localizedDescription)}
MediaStore.removeIgnoringMissing(target)
print("silent remove returns normally; file remains:",FileManager.default.fileExists(atPath:target.path))
