import Foundation

enum SpotifyyPatchType: Int {
    case notSet
    case disabled
    case requests
    
    var isPatching: Bool { self == .requests }
}
