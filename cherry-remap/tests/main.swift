import Foundation
let cherryVendorID = 0x046A
let l = Lighting()
l.describeInterfaces(); print(l.status)
l.mode = UInt8(CommandLine.arguments.count > 1 ? Int(CommandLine.arguments[1], radix: 16) ?? 0 : 0)
l.speed = 2
l.apply(); print(l.status)
