import Foundation
import Darwin

/// All traversal is relative to open directory descriptors. Links and shared
/// inodes are rejected before overwriting any content in the selected item.
enum SecureFileShredder {
    static func shred(at url: URL) throws {
        let parent = url.deletingLastPathComponent().resolvingSymlinksInPath()
        let descriptor = open(parent.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else { throw posixError() }
        defer { close(descriptor) }
        let name = url.lastPathComponent
        guard !name.isEmpty, name != ".", name != "..", url.standardizedFileURL.path != "/" else {
            throw POSIXError(.EPERM)
        }
        try visit(parent: descriptor, name: name, overwrite: false)
        try visit(parent: descriptor, name: name, overwrite: true)
    }

    private static func visit(parent: Int32, name: String, overwrite: Bool) throws {
        var expected = stat()
        guard fstatat(parent, name, &expected, AT_SYMLINK_NOFOLLOW) == 0 else { throw posixError() }
        let type = expected.st_mode & mode_t(S_IFMT)
        guard type == mode_t(S_IFDIR) || (type == mode_t(S_IFREG) && expected.st_nlink == 1) else {
            throw POSIXError(.ELOOP)
        }
        let flags = type == mode_t(S_IFDIR)
            ? O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            : (overwrite ? O_WRONLY : O_RDONLY) | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
        let descriptor = openat(parent, name, flags)
        guard descriptor >= 0 else { throw posixError() }
        defer { close(descriptor) }
        var actual = stat()
        guard fstat(descriptor, &actual) == 0,
              actual.st_dev == expected.st_dev, actual.st_ino == expected.st_ino,
              actual.st_mode & mode_t(S_IFMT) == type,
              type == mode_t(S_IFDIR) || actual.st_nlink == 1 else { throw POSIXError(.ESTALE) }

        if type == mode_t(S_IFDIR) {
            for child in try names(in: descriptor) {
                try visit(parent: descriptor, name: child, overwrite: overwrite)
            }
        } else if overwrite {
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
            let zeros = Data(count: 1024 * 1024)
            var remaining = actual.st_size
            while remaining > 0 {
                let count = Int(min(remaining, off_t(zeros.count)))
                try handle.write(contentsOf: zeros.prefix(count))
                remaining -= off_t(count)
            }
            try handle.synchronize()
        }

        if overwrite {
            var current = stat()
            guard fstatat(parent, name, &current, AT_SYMLINK_NOFOLLOW) == 0,
                  current.st_dev == actual.st_dev, current.st_ino == actual.st_ino else {
                throw POSIXError(.ESTALE)
            }
            guard unlinkat(parent, name, type == mode_t(S_IFDIR) ? AT_REMOVEDIR : 0) == 0 else {
                throw posixError()
            }
        }
    }

    private static func names(in descriptor: Int32) throws -> [String] {
        let copy = dup(descriptor)
        guard copy >= 0 else { throw posixError() }
        guard let directory = fdopendir(copy) else {
            let error = posixError()
            close(copy)
            throw error
        }
        defer { closedir(directory) }
        var result: [String] = []
        while true {
            errno = 0
            guard let entry = readdir(directory) else {
                if errno != 0 { throw posixError() }
                break
            }
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) {
                    String(validatingUTF8: $0)
                }
            }
            guard let name else { throw POSIXError(.EILSEQ) }
            if name != "." && name != ".." { result.append(name) }
        }
        return result
    }

    private static func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
