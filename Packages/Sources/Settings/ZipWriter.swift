import Foundation

/// Writes a zip of stored entries: no compression, CRC32 per entry, UTF-8 names.
enum ZipWriter {
  struct Entry {
    var name: String
    var data: Data
  }

  static func archive(_ entries: [Entry], modified: Date, timeZone: TimeZone) -> Data {
    let (time, date) = dosTimestamp(modified, timeZone: timeZone)
    var body = Data()
    var directory = Data()
    for entry in entries {
      let name = Data(entry.name.utf8)
      let crc = crc32(entry.data)
      let size = UInt32(entry.data.count)
      let offset = UInt32(body.count)

      body.append(le: UInt32(0x0403_4b50))
      body.append(le: UInt16(20))
      body.append(le: UInt16(0x0800))
      body.append(le: UInt16(0))
      body.append(le: time)
      body.append(le: date)
      body.append(le: crc)
      body.append(le: size)
      body.append(le: size)
      body.append(le: UInt16(name.count))
      body.append(le: UInt16(0))
      body.append(name)
      body.append(entry.data)

      directory.append(le: UInt32(0x0201_4b50))
      directory.append(le: UInt16(20))
      directory.append(le: UInt16(20))
      directory.append(le: UInt16(0x0800))
      directory.append(le: UInt16(0))
      directory.append(le: time)
      directory.append(le: date)
      directory.append(le: crc)
      directory.append(le: size)
      directory.append(le: size)
      directory.append(le: UInt16(name.count))
      directory.append(le: UInt16(0))
      directory.append(le: UInt16(0))
      directory.append(le: UInt16(0))
      directory.append(le: UInt16(0))
      directory.append(le: UInt32(0))
      directory.append(le: offset)
      directory.append(name)
    }
    var out = body
    out.append(directory)
    out.append(le: UInt32(0x0605_4b50))
    out.append(le: UInt16(0))
    out.append(le: UInt16(0))
    out.append(le: UInt16(entries.count))
    out.append(le: UInt16(entries.count))
    out.append(le: UInt32(directory.count))
    out.append(le: UInt32(body.count))
    out.append(le: UInt16(0))
    return out
  }

  static func crc32(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xFFFF_FFFF
    for byte in data {
      crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
    }
    return crc ^ 0xFFFF_FFFF
  }

  private static let table: [UInt32] = (0..<256).map { n in
    (0..<8).reduce(UInt32(n)) { c, _ in c & 1 == 1 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
  }

  /// MS-DOS time and date fields; seconds are kept to the even one.
  static func dosTimestamp(_ date: Date, timeZone: TimeZone) -> (time: UInt16, date: UInt16) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    let year = max(1980, min(2107, parts.year ?? 1980))
    let time = UInt16((parts.hour ?? 0) << 11 | (parts.minute ?? 0) << 5 | (parts.second ?? 0) / 2)
    let day = UInt16((year - 1980) << 9 | (parts.month ?? 1) << 5 | (parts.day ?? 1))
    return (time, day)
  }
}

extension Data {
  fileprivate mutating func append(le value: UInt16) {
    append(contentsOf: [UInt8(value & 0xFF), UInt8(value >> 8)])
  }

  fileprivate mutating func append(le value: UInt32) {
    append(contentsOf: (0..<4).map { UInt8((value >> (8 * $0)) & 0xFF) })
  }
}
