//
//  Logging.swift
//  LiveKitCore
//
//  Created by Falk, Ronny on 9/6/23.
//

import Foundation
import OSLog

//MARK: - simple logging

public enum Logger {
	
	public static func log(
		level: OSLogType = .info,
		oslog: OSLog,
		line: UInt = #line,
		file: StaticString = #file,
		message: @autoclosure () -> String
	) {
		os_log(level, log: oslog, "%s [%s:%s]", message(), file.description, line.description)
	}	
	
	public static func plog(
		level: OSLogType = .info,
		oslog: OSLog,
		line: UInt = #line,
		publicMessage: String
	) {
		os_log(level, log: oslog, "\(publicMessage, privacy: .public) [\(line.description, privacy: .public)]")
	}
}

//MARK: - some overrides so Swift.Log can be removed, not sure why this was imported to begin with ... 

extension Utils {
	enum logger {
		static func log<T>(_ message: String, type: T.Type, oslog: OSLog = OSLog(subsystem: "Utils", category: "LiveKit")) {
			Logger.log(oslog: oslog, message: message)
		}
	}
}

extension ConnectivityListener {
	static let oslog = OSLog(subsystem: "ConnectivityListener", category: "LiveKit")
	func log(_ message: String) {
		Logger.log(oslog: Self.oslog, message: message)
	}
}

extension Engine {
	enum logger {
		static func log<T>(_ message: String, _ level: OSLogType = .info, type: T.Type, oslog: OSLog = OSLog(subsystem: "Engine", category: "LiveKit")) {
			Logger.log(level: level, oslog: oslog, message: message)
		}
	}
}
