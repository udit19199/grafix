import Foundation

/// Fractional indexing (z-order keys), ported from Excalidraw's vendored
/// `packages/fractional-indexing` (CC0). Keys compare lexicographically (ASCII).
public enum FractionalIndex {
  static let digits = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz".utf8)
  static let zero = digits[0]

  /// A key strictly between `a` and `b` (either may be nil for open ends).
  /// Returns nil only if the inputs are invalid or out of order.
  public static func between(_ a: String?, _ b: String?) -> String? {
    let ka = a.map { Array($0.utf8) }
    let kb = b.map { Array($0.utf8) }
    if let ka, !isValid(ka) { return nil }
    if let kb, !isValid(kb) { return nil }
    if let ka, let kb, !(ka.lexicographicallyPrecedes(kb)) { return nil }
    guard let key = keyBetween(ka, kb) else { return nil }
    return String(decoding: key, as: UTF8.self)
  }

  /// `n` sorted keys strictly between `a` and `b`.
  public static func between(_ a: String?, _ b: String?, count n: Int) -> [String]? {
    if n <= 0 { return [] }
    if n == 1 { return between(a, b).map { [$0] } }
    if b == nil {
      var result: [String] = []
      var c = a
      for _ in 0..<n {
        guard let next = between(c, nil) else { return nil }
        result.append(next)
        c = next
      }
      return result
    }
    if a == nil {
      var result: [String] = []
      var c = b
      for _ in 0..<n {
        guard let next = between(nil, c) else { return nil }
        result.append(next)
        c = next
      }
      return result.reversed()
    }
    let mid = n / 2
    guard let c = between(a, b),
      let left = between(a, c, count: mid),
      let right = between(c, b, count: n - mid - 1)
    else { return nil }
    return left + [c] + right
  }

  public static func isValid(_ key: String) -> Bool { isValid(Array(key.utf8)) }

  static func isValid(_ key: [UInt8]) -> Bool {
    guard !key.isEmpty, key.allSatisfy({ digits.contains($0) }) else { return false }
    if key == [UInt8(ascii: "A")] + Array(repeating: zero, count: 26) { return false }
    guard let len = integerLength(key[0]), len <= key.count else { return false }
    return key.count == len || key.last != zero
  }

  static func integerLength(_ head: UInt8) -> Int? {
    if head >= UInt8(ascii: "a") && head <= UInt8(ascii: "z") {
      return Int(head - UInt8(ascii: "a")) + 2
    }
    if head >= UInt8(ascii: "A") && head <= UInt8(ascii: "Z") {
      return Int(UInt8(ascii: "Z") - head) + 2
    }
    return nil
  }

  static func integerPart(_ key: [UInt8]) -> [UInt8] {
    Array(key.prefix(integerLength(key[0]) ?? key.count))
  }

  static func midpoint(_ a: [UInt8], _ b: [UInt8]?) -> [UInt8] {
    if let b {
      var n = 0
      while n < b.count, (n < a.count ? a[n] : zero) == b[n] { n += 1 }
      if n > 0 {
        return Array(b.prefix(n))
          + midpoint(Array(a.dropFirst(min(n, a.count))), Array(b.dropFirst(n)))
      }
    }
    let digitA = a.isEmpty ? 0 : digits.firstIndex(of: a[0])!
    let digitB = b.map { $0.isEmpty ? digits.count : digits.firstIndex(of: $0[0])! } ?? digits.count
    if digitB - digitA > 1 {
      let mid = Int((0.5 * Double(digitA + digitB)).rounded())
      return [digits[mid]]
    }
    if let b, b.count > 1 { return [b[0]] }
    return [digits[digitA]] + midpoint(Array(a.dropFirst()), nil)
  }

  static func increment(_ x: [UInt8]) -> [UInt8]? {
    let head = x[0]
    var digs = Array(x.dropFirst())
    var carry = true
    var i = digs.count - 1
    while carry && i >= 0 {
      let d = digits.firstIndex(of: digs[i])! + 1
      if d == digits.count {
        digs[i] = zero
      } else {
        digs[i] = digits[d]
        carry = false
      }
      i -= 1
    }
    if carry {
      if head == UInt8(ascii: "Z") { return [UInt8(ascii: "a"), zero] }
      if head == UInt8(ascii: "z") { return nil }
      let h = head + 1
      if h > UInt8(ascii: "a") { digs.append(zero) } else { digs.removeLast() }
      return [h] + digs
    }
    return [head] + digs
  }

  static func decrement(_ x: [UInt8]) -> [UInt8]? {
    let head = x[0]
    var digs = Array(x.dropFirst())
    var borrow = true
    var i = digs.count - 1
    while borrow && i >= 0 {
      let d = digits.firstIndex(of: digs[i])! - 1
      if d == -1 {
        digs[i] = digits.last!
      } else {
        digs[i] = digits[d]
        borrow = false
      }
      i -= 1
    }
    if borrow {
      if head == UInt8(ascii: "a") { return [UInt8(ascii: "Z"), digits.last!] }
      if head == UInt8(ascii: "A") { return nil }
      let h = head - 1
      if h < UInt8(ascii: "Z") { digs.append(digits.last!) } else { digs.removeLast() }
      return [h] + digs
    }
    return [head] + digs
  }

  static func keyBetween(_ a: [UInt8]?, _ b: [UInt8]?) -> [UInt8]? {
    guard let a else {
      guard let b else { return [UInt8(ascii: "a"), zero] }
      let ib = integerPart(b)
      let fb = Array(b.dropFirst(ib.count))
      if ib == [UInt8(ascii: "A")] + Array(repeating: zero, count: 26) {
        return ib + midpoint([], fb)
      }
      if ib.lexicographicallyPrecedes(b) { return ib }
      return decrement(ib)
    }
    let ia = integerPart(a)
    let fa = Array(a.dropFirst(ia.count))
    guard let b else {
      return increment(ia) ?? (ia + midpoint(fa, nil))
    }
    let ib = integerPart(b)
    let fb = Array(b.dropFirst(ib.count))
    if ia == ib { return ia + midpoint(fa, fb) }
    guard let i = increment(ia) else { return nil }
    if i.lexicographicallyPrecedes(b) { return i }
    return ia + midpoint(fa, nil)
  }

  /// Repairs indices so they strictly increase along `elements` order,
  /// reusing every index that is already in order (like Excalidraw's
  /// syncInvalidIndices). Changed elements are bumped.
  public static func sync(_ elements: inout [Element]) {
    var previous: String? = nil
    var i = 0
    while i < elements.count {
      if let idx = elements[i].index, isValid(idx), previous.map({ $0 < idx }) ?? true {
        previous = idx
        i += 1
        continue
      }
      // Find the run of invalid elements and the next valid upper bound.
      var j = i
      var upper: String? = nil
      while j < elements.count {
        if let idx = elements[j].index, isValid(idx), previous.map({ $0 < idx }) ?? true {
          upper = idx
          break
        }
        j += 1
      }
      let keys =
        between(previous, upper, count: j - i)
        ?? between(previous, nil, count: j - i) ?? []
      for (offset, key) in keys.enumerated() {
        elements[i + offset].index = key
      }
      previous = keys.last ?? previous
      i = j
    }
  }
}
