import Foundation

/// A save as it is written to the iCloud backup: the save's bytes and an HMAC-SHA256 of them
/// under a key built into the app, named by its number, so a hand-edited backup doesn't restore.
private struct SealedSave: Codable {
  var key: Int
  var save: Data
  var seal: String
}

/// The seal keys by number. New saves are sealed with `CURRENT_SEAL_KEY`; older keys stay so
/// saves sealed with them still open, and are resealed with the current key on their next write.
private let SEAL_KEYS: [Int: [UInt8]] = [
  1: [
    0x2e, 0xec, 0x42, 0x66, 0x5d, 0x55, 0x62, 0xdc, 0xa1, 0x59, 0xa8, 0xb5, 0x18, 0x6a, 0x97, 0x0f,
    0x0f, 0x65, 0x0f, 0xb3, 0x23, 0xf9, 0x8f, 0x0a, 0xd6, 0xe9, 0xff, 0x53, 0x6b, 0xf3, 0xdf, 0x88,
  ]
]
private let CURRENT_SEAL_KEY = 1

/// A save wrapped with its seal, for the backup.
public func sealSave(_ save: Data) -> Data { sealSave(save, keyNumber: CURRENT_SEAL_KEY, key: SEAL_KEYS[CURRENT_SEAL_KEY]!) }

/// A save sealed with a given key, under its number.
func sealSave(_ save: Data, keyNumber: Int, key: [UInt8]) -> Data {
  let sealed = SealedSave(key: keyNumber, save: save, seal: hex(hmacSHA256(key: key, message: Array(save))))
  return (try? JSONEncoder().encode(sealed)) ?? Data()
}

/// The save inside a sealed backup file, when its key is one the app has, its seal matches,
/// and it is a current save (`isCurrentSave`). Nil for an edited, unsealed or older save.
public func openSealedSave(_ data: Data) -> Data? {
  guard let sealed = try? JSONDecoder().decode(SealedSave.self, from: data),
    let key = SEAL_KEYS[sealed.key],
    sealed.seal == hex(hmacSHA256(key: key, message: Array(sealed.save))),
    isCurrentSave(sealed.save)
  else { return nil }
  return sealed.save
}

private func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }

/// HMAC-SHA256 (RFC 2104).
public func hmacSHA256(key: [UInt8], message: [UInt8]) -> [UInt8] {
  var block = key.count > 64 ? sha256(key) : key
  block += [UInt8](repeating: 0, count: 64 - block.count)
  let inner = sha256(block.map { $0 ^ 0x36 } + message)
  return sha256(block.map { $0 ^ 0x5c } + inner)
}

private let K: [UInt32] = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
]

/// SHA-256 (FIPS 180-4).
public func sha256(_ message: [UInt8]) -> [UInt8] {
  var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
  var data = message
  let bits = UInt64(message.count) * 8
  data.append(0x80)
  while data.count % 64 != 56 { data.append(0) }
  for i in (0..<8).reversed() { data.append(UInt8(truncatingIfNeeded: bits >> (UInt64(i) * 8))) }
  func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }
  var w = [UInt32](repeating: 0, count: 64)
  for chunk in stride(from: 0, to: data.count, by: 64) {
    for t in 0..<16 {
      let i = chunk + t * 4
      w[t] = UInt32(data[i]) << 24 | UInt32(data[i + 1]) << 16 | UInt32(data[i + 2]) << 8 | UInt32(data[i + 3])
    }
    for t in 16..<64 {
      let s0 = rotr(w[t - 15], 7) ^ rotr(w[t - 15], 18) ^ (w[t - 15] >> 3)
      let s1 = rotr(w[t - 2], 17) ^ rotr(w[t - 2], 19) ^ (w[t - 2] >> 10)
      w[t] = w[t - 16] &+ s0 &+ w[t - 7] &+ s1
    }
    var (a, b, c, d, e, f, g, hh) = (h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7])
    for t in 0..<64 {
      let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
      let ch = (e & f) ^ (~e & g)
      let t1 = hh &+ s1 &+ ch &+ K[t] &+ w[t]
      let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
      let maj = (a & b) ^ (a & c) ^ (b & c)
      let t2 = s0 &+ maj
      (hh, g, f, e, d, c, b, a) = (g, f, e, d &+ t1, c, b, a, t1 &+ t2)
    }
    h = zip(h, [a, b, c, d, e, f, g, hh]).map { $0 &+ $1 }
  }
  return h.flatMap { v in (0..<4).map { UInt8(truncatingIfNeeded: v >> (24 - UInt32($0) * 8)) } }
}
