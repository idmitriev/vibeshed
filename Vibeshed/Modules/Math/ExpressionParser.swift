import Foundation

enum ExpressionParser {
    // MARK: - Token Types

    private enum Token: Sendable {
        case number(Double)
        case op(Character)
        case unaryMinus
        case factorial
        case function(String)
        case leftParen
        case rightParen
    }

    // MARK: - Public API

    static func evaluate(_ expression: String) -> Double? {
        let cleaned = expression
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: ",", with: "")
        guard !cleaned.isEmpty else { return nil }

        guard let tokens = tokenize(cleaned) else { return nil }
        guard !tokens.isEmpty else { return nil }

        return evaluateTokens(tokens)
    }

    /// Returns true if the expression contains operators/functions (not just a bare number)
    static func isNonTrivial(_ expression: String) -> Bool {
        let cleaned = expression
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: ",", with: "")
        guard let tokens = tokenize(cleaned) else { return false }
        return tokens.contains { token in
            switch token {
            case .op, .function, .factorial: return true
            default: return false
            }
        }
    }

    // MARK: - Tokenizer

    private static let functions = Set([
        "sqrt", "sin", "cos", "tan",
        "asin", "acos", "atan",
        "log", "ln", "abs",
        "ceil", "floor", "round", "exp",
    ])

    private static let constants: [String: Double] = [
        "pi": .pi,
        "e": Darwin.M_E,
    ]

    // swiftlint:disable cyclomatic_complexity
    private static func tokenize(_ input: String) -> [Token]? {
        var tokens: [Token] = []
        var idx = input.startIndex

        while idx < input.endIndex {
            let ch = input[idx]

            if ch.isWhitespace {
                idx = input.index(after: idx)
                continue
            }

            if ch.isNumber || ch == "." {
                let numResult = scanNumber(input, from: idx)
                guard let (val, nextIdx) = numResult else { return nil }
                tokens.append(.number(val))
                idx = nextIdx
                continue
            }

            if ch.isLetter {
                let wordResult = scanWord(input, from: idx)
                guard let (token, nextIdx) = wordResult else { return nil }
                tokens.append(token)
                idx = nextIdx
                continue
            }

            switch ch {
            case "(":
                tokens.append(.leftParen)
            case ")":
                tokens.append(.rightParen)
                let next = input.index(after: idx)
                if next < input.endIndex, input[next] == "!" {
                    tokens.append(.factorial)
                    idx = input.index(after: next)
                    continue
                }
            case "+", "*", "/", "^", "%":
                tokens.append(.op(ch))
            case "-":
                let isUnary = tokens.isEmpty || isUnaryContext(tokens.last)
                tokens.append(isUnary ? .unaryMinus : .op(ch))
            case "!":
                tokens.append(.factorial)
            default:
                return nil
            }
            idx = input.index(after: idx)
        }
        return tokens
    }
    // swiftlint:enable cyclomatic_complexity

    private static func scanNumber(
        _ input: String, from start: String.Index
    ) -> (Double, String.Index)? {
        var idx = start
        var numStr = ""
        while idx < input.endIndex,
              input[idx].isNumber || input[idx] == "."
        {
            numStr.append(input[idx])
            idx = input.index(after: idx)
        }
        guard let val = Double(numStr) else { return nil }
        return (val, idx)
    }

    private static func scanWord(
        _ input: String, from start: String.Index
    ) -> (Token, String.Index)? {
        var idx = start
        var word = ""
        while idx < input.endIndex, input[idx].isLetter {
            word.append(input[idx])
            idx = input.index(after: idx)
        }
        if let val = constants[word] {
            return (.number(val), idx)
        } else if functions.contains(word) {
            return (.function(word), idx)
        }
        return nil
    }

    private static func isUnaryContext(_ lastToken: Token?) -> Bool {
        guard let last = lastToken else { return true }
        switch last {
        case .op, .unaryMinus, .leftParen: return true
        default: return false
        }
    }

    // MARK: - Shunting-Yard Evaluation

    private static func precedence(_ op: Character) -> Int {
        switch op {
        case "+", "-": return 1
        case "*", "/", "%": return 2
        case "^": return 3
        default: return 0
        }
    }

    private static func isRightAssociative(_ op: Character) -> Bool {
        op == "^"
    }

    private static func applyOp(
        _ op: Character, _ lhs: Double, _ rhs: Double
    ) -> Double? {
        switch op {
        case "+": return lhs + rhs
        case "-": return lhs - rhs
        case "*": return lhs * rhs
        case "/": return rhs == 0 ? nil : lhs / rhs
        case "^": return pow(lhs, rhs)
        case "%": return rhs == 0 ? nil : lhs.truncatingRemainder(dividingBy: rhs)
        default: return nil
        }
    }

    private static func applyFunction(
        _ name: String, _ val: Double
    ) -> Double? {
        switch name {
        case "sqrt": return val >= 0 ? sqrt(val) : nil
        case "sin": return sin(val)
        case "cos": return cos(val)
        case "tan": return tan(val)
        case "asin": return val >= -1 && val <= 1 ? asin(val) : nil
        case "acos": return val >= -1 && val <= 1 ? acos(val) : nil
        case "atan": return atan(val)
        case "log": return val > 0 ? log10(val) : nil
        case "ln": return val > 0 ? log(val) : nil
        case "abs": return abs(val)
        case "ceil": return ceil(val)
        case "floor": return floor(val)
        case "round": return (val).rounded()
        case "exp": return exp(val)
        default: return nil
        }
    }

    private static func factorial(_ num: Double) -> Double? {
        guard num >= 0, num == num.rounded(), num <= 170 else { return nil }
        let intN = Int(num)
        if intN == 0 { return 1 }
        var result: Double = 1
        for idx in 1 ... intN {
            result *= Double(idx)
        }
        return result
    }

    private static func evaluateTokens(_ tokens: [Token]) -> Double? {
        var output: [Double] = []
        var opStack: [Token] = []

        for token in tokens {
            if !processToken(token, output: &output, opStack: &opStack) {
                return nil
            }
        }

        // Drain remaining operators
        while !opStack.isEmpty {
            if case .leftParen = opStack.last { return nil }
            if !popAndApply(&output, &opStack) { return nil }
        }

        guard output.count == 1 else { return nil }
        let result = output[0]
        if result.isNaN || result.isInfinite { return nil }
        return result
    }

    // swiftlint:disable cyclomatic_complexity
    private static func processToken(
        _ token: Token,
        output: inout [Double],
        opStack: inout [Token]
    ) -> Bool {
        switch token {
        case let .number(val):
            output.append(val)

        case let .function(name):
            opStack.append(.function(name))

        case .leftParen:
            opStack.append(.leftParen)

        case .rightParen:
            if !handleRightParen(&output, &opStack) { return false }

        case let .op(op):
            handleOperator(op, output: &output, opStack: &opStack)

        case .unaryMinus:
            opStack.append(.unaryMinus)

        case .factorial:
            guard let val = output.popLast(),
                  let result = factorial(val)
            else { return false }
            output.append(result)
        }
        return true
    }
    // swiftlint:enable cyclomatic_complexity

    private static func handleRightParen(
        _ output: inout [Double], _ opStack: inout [Token]
    ) -> Bool {
        while let top = opStack.last {
            if case .leftParen = top { break }
            if !popAndApply(&output, &opStack) { return false }
        }
        guard case .leftParen? = opStack.last else { return false }
        opStack.removeLast()
        if let top = opStack.last, case .function = top {
            if !popAndApply(&output, &opStack) { return false }
        }
        return true
    }

    private static func handleOperator(
        _ op: Character,
        output: inout [Double],
        opStack: inout [Token]
    ) {
        let prec = precedence(op)
        let rightAssoc = isRightAssociative(op)
        while let top = opStack.last {
            if case let .op(topOp) = top {
                let topPrec = precedence(topOp)
                if topPrec > prec || (topPrec == prec && !rightAssoc) {
                    _ = popAndApply(&output, &opStack)
                    continue
                }
            } else if case .unaryMinus = top {
                _ = popAndApply(&output, &opStack)
                continue
            }
            break
        }
        opStack.append(.op(op))
    }

    private static func popAndApply(
        _ output: inout [Double], _ opStack: inout [Token]
    ) -> Bool {
        guard let top = opStack.popLast() else { return false }
        switch top {
        case let .op(op):
            guard output.count >= 2 else { return false }
            let rhs = output.removeLast()
            let lhs = output.removeLast()
            guard let result = applyOp(op, lhs, rhs) else { return false }
            output.append(result)
            return true
        case let .function(name):
            guard let val = output.popLast() else { return false }
            guard let result = applyFunction(name, val) else { return false }
            output.append(result)
            return true
        case .unaryMinus:
            guard let val = output.popLast() else { return false }
            output.append(-val)
            return true
        default:
            return false
        }
    }
}
