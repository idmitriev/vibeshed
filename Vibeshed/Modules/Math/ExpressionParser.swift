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
            case .op, .function, .factorial: true
            default: false
            }
        }
    }

    // MARK: - Tokenizer

    /// Supported unary functions. An implementation returns nil when the argument
    /// is outside the function's domain.
    private static let functions: [String: @Sendable (Double) -> Double?] = [
        "sqrt": { $0 >= 0 ? sqrt($0) : nil },
        "sin": { sin($0) },
        "cos": { cos($0) },
        "tan": { tan($0) },
        "asin": { $0 >= -1 && $0 <= 1 ? asin($0) : nil },
        "acos": { $0 >= -1 && $0 <= 1 ? acos($0) : nil },
        "atan": { atan($0) },
        "log": { $0 > 0 ? log10($0) : nil },
        "ln": { $0 > 0 ? log($0) : nil },
        "abs": { abs($0) },
        "ceil": { ceil($0) },
        "floor": { floor($0) },
        "round": { $0.rounded() },
        "exp": { exp($0) },
    ]

    private static let constants: [String: Double] = [
        "pi": .pi,
        "e": Darwin.M_E,
    ]

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

            guard let nextIdx = scanSymbol(input, at: idx, into: &tokens) else { return nil }
            idx = nextIdx
        }
        return tokens
    }

    /// Appends the token(s) for the operator or parenthesis at `idx` and returns the
    /// index after what it consumed, or nil for an unexpected character.
    private static func scanSymbol(
        _ input: String, at idx: String.Index, into tokens: inout [Token]
    ) -> String.Index? {
        let ch = input[idx]
        let next = input.index(after: idx)
        switch ch {
        case "(":
            tokens.append(.leftParen)
        case ")":
            tokens.append(.rightParen)
            if next < input.endIndex, input[next] == "!" {
                tokens.append(.factorial)
                return input.index(after: next)
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
        return next
    }

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
        } else if functions[word] != nil {
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
        case "+", "-": 1
        case "*", "/", "%": 2
        case "^": 3
        default: 0
        }
    }

    private static func isRightAssociative(_ op: Character) -> Bool {
        op == "^"
    }

    private static func applyOp(
        _ op: Character, _ lhs: Double, _ rhs: Double
    ) -> Double? {
        switch op {
        case "+": lhs + rhs
        case "-": lhs - rhs
        case "*": lhs * rhs
        case "/": rhs == 0 ? nil : lhs / rhs
        case "^": pow(lhs, rhs)
        case "%": rhs == 0 ? nil : lhs.truncatingRemainder(dividingBy: rhs)
        default: nil
        }
    }

    private static func applyFunction(
        _ name: String, _ val: Double
    ) -> Double? {
        functions[name].flatMap { $0(val) }
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
            guard processToken(token, output: &output, opStack: &opStack) else { return nil }
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
