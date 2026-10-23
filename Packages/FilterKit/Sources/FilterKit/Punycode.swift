import Foundation

/// Converts internationalised domain names to ASCII ("żółw.pl" -> "xn--w-uga1v8h.pl"),
/// which Safari's rules require. Matches Python's "idna" codec closely enough for filter lists.
enum IDNA {
    static func toASCII(_ domain: String) -> String? {
        let labels = domain.split(separator: ".", omittingEmptySubsequences: false)
        var result: [String] = []
        for label in labels {
            guard let ascii = labelToASCII(String(label)), (1...63).contains(ascii.utf8.count) else {
                return nil
            }
            result.append(ascii)
        }
        return result.joined(separator: ".")
    }

    private static func labelToASCII(_ label: String) -> String? {
        if label.unicodeScalars.allSatisfy(\.isASCII) {
            return label
        }
        let prepared = label.precomposedStringWithCompatibilityMapping.lowercased()
        if prepared.unicodeScalars.allSatisfy(\.isASCII) {
            return prepared
        }
        guard let encoded = Punycode.encode(prepared) else { return nil }
        return "xn--" + encoded
    }
}

/// RFC 3492 Punycode encoder.
enum Punycode {
    private static let base = 36, tMin = 1, tMax = 26, skew = 38, damp = 700
    private static let initialBias = 72, initialN = 128

    static func encode(_ input: String) -> String? {
        let scalars = input.unicodeScalars.map { Int($0.value) }
        var output = scalars.filter { $0 < 0x80 }.map { Character(Unicode.Scalar(UInt8($0))) }
        let basicCount = output.count
        var handled = basicCount
        if basicCount > 0 { output.append("-") }

        var n = initialN, delta = 0, bias = initialBias
        while handled < scalars.count {
            guard let m = scalars.filter({ $0 >= n }).min() else { return nil }
            delta += (m - n) * (handled + 1)
            n = m
            for c in scalars {
                if c < n { delta += 1 }
                if c == n {
                    var q = delta
                    var k = base
                    while true {
                        let t = k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias)
                        if q < t { break }
                        output.append(digit(t + (q - t) % (base - t)))
                        q = (q - t) / (base - t)
                        k += base
                    }
                    output.append(digit(q))
                    bias = adapt(delta, handled + 1, handled == basicCount)
                    delta = 0
                    handled += 1
                }
            }
            delta += 1
            n += 1
        }
        return String(output)
    }

    private static func digit(_ d: Int) -> Character {
        Character(Unicode.Scalar(UInt8(d < 26 ? d + 97 : d + 22)))
    }

    private static func adapt(_ delta: Int, _ numPoints: Int, _ firstTime: Bool) -> Int {
        var delta = firstTime ? delta / damp : delta / 2
        delta += delta / numPoints
        var k = 0
        while delta > ((base - tMin) * tMax) / 2 {
            delta /= base - tMin
            k += base
        }
        return k + (base - tMin + 1) * delta / (delta + skew)
    }
}
