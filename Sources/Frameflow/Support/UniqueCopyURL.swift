import Foundation

func uniqueCopyURL(fileName sourceFileName: String, in destinationURL: URL, reservedNames: inout Set<String>) -> URL {
    let fileManager = FileManager.default
    let sourceURL = URL(fileURLWithPath: sourceFileName)
    let baseName = sourceURL.deletingPathExtension().lastPathComponent
    let pathExtension = sourceURL.pathExtension
    var index = 1

    while true {
        let fileName: String
        if index == 1 {
            fileName = sourceFileName
        } else if pathExtension.isEmpty {
            fileName = "\(baseName) \(index)"
        } else {
            fileName = "\(baseName) \(index).\(pathExtension)"
        }

        let candidateURL = destinationURL.appendingPathComponent(fileName)
        if !reservedNames.contains(fileName),
           !fileManager.fileExists(atPath: candidateURL.path) {
            reservedNames.insert(fileName)
            return candidateURL
        }

        index += 1
    }
}
