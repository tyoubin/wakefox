import Darwin
import Foundation

enum WakeOnLanError: Error, LocalizedError {
    case invalidMacAddress
    case sendFailure(Error)

    var errorDescription: String? {
        switch self {
        case .invalidMacAddress:
            return "Invalid MAC address."
        case .sendFailure(let error):
            return "Failed to send packet: \(error.localizedDescription)"
        }
    }
}

protocol WakeOnLanSending {
    func sendWakePacket(to macAddress: String, completion: @escaping @Sendable (Result<Void, WakeOnLanError>) -> Void)
}

enum WakeOnLanPacketBuilder {
    static func buildPacket(macAddress: String) throws -> Data {
        let cleanMac = macAddress
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")

        guard cleanMac.count == 12 else {
            throw WakeOnLanError.invalidMacAddress
        }

        var macBytes = [UInt8]()
        macBytes.reserveCapacity(6)
        for i in stride(from: 0, to: cleanMac.count, by: 2) {
            let start = cleanMac.index(cleanMac.startIndex, offsetBy: i)
            let end = cleanMac.index(start, offsetBy: 2)
            let hex = String(cleanMac[start..<end])
            guard let byte = UInt8(hex, radix: 16) else {
                throw WakeOnLanError.invalidMacAddress
            }
            macBytes.append(byte)
        }

        guard macBytes.count == 6 else {
            throw WakeOnLanError.invalidMacAddress
        }

        var packet = Data()
        packet.append(contentsOf: [UInt8](repeating: 0xFF, count: 6))
        for _ in 0..<16 {
            packet.append(contentsOf: macBytes)
        }
        return packet
    }
}

final class WakeOnLanSender: WakeOnLanSending {
    func sendWakePacket(to macAddress: String, completion: @escaping @Sendable (Result<Void, WakeOnLanError>) -> Void) {
        do {
            let packet = try WakeOnLanPacketBuilder.buildPacket(macAddress: macAddress)
            let ports: [UInt16] = [9, 7]

            var sentCount = 0
            var lastError: Error?

            try sendOnInterfaceBroadcasts(packet: packet, ports: ports, sentCount: &sentCount, lastError: &lastError)

            if sentCount == 0 {
                try sendOnGlobalBroadcast(packet: packet, ports: ports, sentCount: &sentCount, lastError: &lastError)
            }

            if sentCount > 0 {
                completion(.success(()))
            } else if let error = lastError {
                throw WakeOnLanError.sendFailure(error)
            } else {
                throw WakeOnLanError.sendFailure(POSIXError(.ENETDOWN))
            }
        } catch let wolError as WakeOnLanError {
            completion(.failure(wolError))
        } catch {
            completion(.failure(.sendFailure(error)))
        }
    }

    private func sendOnInterfaceBroadcasts(packet: Data, ports: [UInt16], sentCount: inout Int, lastError: inout Error?) throws {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let start = ifaddr else {
            throw WakeOnLanError.sendFailure(POSIXError(.ENETDOWN))
        }
        defer { freeifaddrs(start) }

        var cursor = start
        while true {
            let ifa = cursor.pointee
            let name = String(cString: ifa.ifa_name)
            let flags = Int32(ifa.ifa_flags)

            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            let isTunnel = name.hasPrefix("utun") || name.hasPrefix("p2p") || name.hasPrefix("awdl") || name.hasPrefix("gif") || name.hasPrefix("stf")

            if isUp && !isLoopback && !isTunnel,
               let addrPtr = ifa.ifa_addr,
               let netmaskPtr = ifa.ifa_netmask,
               addrPtr.pointee.sa_family == sa_family_t(AF_INET)
            {
                let addr_in = addrPtr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                let netmask_in = netmaskPtr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }

                let sock = socket(AF_INET, SOCK_DGRAM, 0)
                guard sock >= 0 else {
                    guard let next = ifa.ifa_next else { break }
                    cursor = next
                    continue
                }

                var broadcast: Int32 = 1
                guard setsockopt(sock, SOL_SOCKET, SO_BROADCAST, &broadcast, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
                    close(sock)
                    guard let next = ifa.ifa_next else { break }
                    cursor = next
                    continue
                }

                var ifIndex = UInt32(if_nametoindex(name))
                if ifIndex > 0 {
                    setsockopt(sock, IPPROTO_IP, IP_BOUND_IF, &ifIndex, socklen_t(MemoryLayout<UInt32>.size))
                }

                var broadAddr = addr_in
                broadAddr.sin_addr.s_addr = addr_in.sin_addr.s_addr | ~netmask_in.sin_addr.s_addr

                for port in ports {
                    broadAddr.sin_port = CFSwapInt16HostToBig(port)
                    let sent = sendto_wrapper(sock, packet, &broadAddr)
                    if sent == packet.count {
                        sentCount += 1
                    } else {
                        lastError = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                    }
                }

                close(sock)
            }

            guard let next = ifa.ifa_next else { break }
            cursor = next
        }
    }

    private func sendOnGlobalBroadcast(packet: Data, ports: [UInt16], sentCount: inout Int, lastError: inout Error?) throws {
        let sock = socket(AF_INET, SOCK_DGRAM, 0)
        guard sock >= 0 else { return }

        var broadcast: Int32 = 1
        guard setsockopt(sock, SOL_SOCKET, SO_BROADCAST, &broadcast, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            close(sock)
            return
        }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = INADDR_BROADCAST

        for port in ports {
            addr.sin_port = CFSwapInt16HostToBig(port)
            let sent = sendto_wrapper(sock, packet, &addr)
            if sent == packet.count {
                sentCount += 1
            } else {
                lastError = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }

        close(sock)
    }
}

private func sendto_wrapper(_ sock: Int32, _ packet: Data, _ addr: inout sockaddr_in) -> Int {
    packet.withUnsafeBytes { buf in
        withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                sendto(sock, buf.baseAddress, packet.count, 0, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
    }
}
