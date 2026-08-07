import Foundation

/// XPC 服务委托，接受新连接并导出 DropNestXPCHelper 实例。
class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: (any DropNestXPCHelperProtocol).self)
        let exportedObject = DropNestXPCHelper()
        newConnection.exportedObject = exportedObject
        newConnection.resume()
        return true
    }
}

let delegate = ServiceDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
