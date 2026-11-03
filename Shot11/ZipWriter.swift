import Foundation

/// ZIP sans compression, écrit fichier par fichier (peu de mémoire, même avec beaucoup d'articles).
enum ZipWriter {
    private static let table: [UInt32] = {
        var t = [UInt32](repeating: 0, count: 256)
        for n in 0..<256 {
            var c = UInt32(n)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            t[n] = c
        }
        return t
    }()

    static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            for b in buf {
                c = table[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8)
            }
        }
        return c ^ 0xFFFFFFFF
    }

    static func write(entries: [(name: String, url: URL)], to dest: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        fm.createFile(atPath: dest.path, contents: nil)
        let fh = try FileHandle(forWritingTo: dest)
        defer { try? fh.close() }

        let cal = Calendar.current
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date())
        let time = UInt16(((c.hour ?? 0) << 11) | ((c.minute ?? 0) << 5) | ((c.second ?? 0) / 2))
        let date = UInt16((((c.year ?? 2026) - 1980) << 9) | ((c.month ?? 1) << 5) | (c.day ?? 1))

        var central = Data()
        var offset: UInt32 = 0
        var count = 0

        for e in entries {
            guard let data = try? Data(contentsOf: e.url, options: .mappedIfSafe) else { continue }
            let nameData = Data(e.name.utf8)
            let crc = crc32(data)
            let size = UInt32(data.count)

            var head = Data()
            head.le32(0x04034b50); head.le16(20); head.le16(0x0800); head.le16(0)
            head.le16(time); head.le16(date); head.le32(crc); head.le32(size); head.le32(size)
            head.le16(UInt16(nameData.count)); head.le16(0)
            head.append(nameData)
            try fh.write(contentsOf: head)
            try fh.write(contentsOf: data)

            central.le32(0x02014b50); central.le16(20); central.le16(20); central.le16(0x0800); central.le16(0)
            central.le16(time); central.le16(date); central.le32(crc); central.le32(size); central.le32(size)
            central.le16(UInt16(nameData.count)); central.le16(0); central.le16(0)
            central.le16(0); central.le16(0); central.le32(0); central.le32(offset)
            central.append(nameData)

            offset += UInt32(head.count) + size
            count += 1
        }

        var tail = central
        tail.le32(0x06054b50); tail.le16(0); tail.le16(0)
        tail.le16(UInt16(count)); tail.le16(UInt16(count))
        tail.le32(UInt32(central.count)); tail.le32(offset); tail.le16(0)
        try fh.write(contentsOf: tail)
    }
}

private extension Data {
    mutating func le16(_ v: UInt16) {
        append(UInt8(v & 0xFF))
        append(UInt8((v >> 8) & 0xFF))
    }

    mutating func le32(_ v: UInt32) {
        append(UInt8(v & 0xFF))
        append(UInt8((v >> 8) & 0xFF))
        append(UInt8((v >> 16) & 0xFF))
        append(UInt8((v >> 24) & 0xFF))
    }
}
