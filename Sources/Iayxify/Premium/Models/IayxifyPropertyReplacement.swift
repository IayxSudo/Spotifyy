enum IayxifyPropertyModification {
    case remove
    case setBool(Bool)
    case setEnum(String)
    // Flip if present, append if missing (needs name + scope).
    case forceBool(Bool)
}

struct IayxifyPropertyReplacement {
    let scope: String?
    let name: String?
    let modification: IayxifyPropertyModification
    
    init(name: String? = nil, scope: String? = nil, modification: IayxifyPropertyModification) {
        self.name = name
        self.scope = scope
        self.modification = modification
    }
}
