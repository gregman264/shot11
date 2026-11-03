import Foundation

/// ZIP sans compression (les JPEG ne se compressent pas) : instantané.
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
        for b in data {
            c = table[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8)
        }
        return c ^ 0xFFFFFFFF
    }

    static func make(_ entries: [(String, Data)]) -> Data {
        var out = Data()
        var central = Data()
        let cal = Calendar.current
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date())
        let time = UInt16(((c.hour ?? 0) << 11) | ((c.minute ?? 0) << 5) | ((c.second ?? 0) / 2))
        let date = UInt16((((c.year ?? 2026) - 1980) << 9) | ((c.month ?? 1) << 5) | (c.day ?? 1))

        for (name, data) in entries {
            let nameData = Data(name.utf8)
            let crc = crc32(data)
            let size = UInt32(data.count)
            let offset = UInt32(out.count)

            out.le32(0x04034b50); out.le16(20); out.le16(0x0800); out.le16(0)
            out.le16(time); out.le16(date); out.le32(crc); out.le32(size); out.le32(size)
            out.le16(UInt16(nameData.count)); out.le16(0)
            out.append(nameData)
            out.append(data)

            central.le32(0x02014b50); central.le16(20); central.le16(20); central.le16(0x0800); central.le16(0)
            central.le16(time); central.le16(date); central.le32(crc); central.le32(size); central.le32(size)
            central.le16(UInt16(nameData.count)); central.le16(0); central.le16(0)
            central.le16(0); central.le16(0); central.le32(0); central.le32(offset)
            central.append(nameData)
        }

        let centralOffset = UInt32(out.count)
        out.append(central)
        out.le32(0x06054b50); out.le16(0); out.le16(0)
        out.le16(UInt16(entries.count)); out.le16(UInt16(entries.count))
        out.le32(UInt32(central.count)); out.le32(centralOffset); out.le16(0)
        return out
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
