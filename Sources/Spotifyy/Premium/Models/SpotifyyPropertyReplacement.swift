enum SpotifyyPropertyModification {
    case remove
    case setBool(Bool)
    case setEnum(String)
    // Flip if present, append if missing (needs name + scope).
    case forceBool(Bool)
}

struct SpotifyyPropertyReplacement {
    let scope: String?
    let name: String?
    let modification: SpotifyyPropertyModification
    
    init(name: String? = nil, scope: String? = nil, modification: SpotifyyPropertyModification) {
        self.name = name
        self.scope = scope
        self.modification = modification
    }
}
