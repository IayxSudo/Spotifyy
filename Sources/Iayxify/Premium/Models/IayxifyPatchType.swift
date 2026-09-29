import Foundation

enum IayxifyPatchType: Int {
    case notSet
    case disabled
    case requests
    
    var isPatching: Bool { self == .requests }
}
