// swift-tools-version:5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
	name: "LiveKit",
	platforms: [
		.iOS(.v15),
		.macOS(.v12)
	],
	products: [
		.library(
			name: "LiveKit",
			type: .static,
			targets: ["LiveKit"]
		),
		.library(
			name: "LiveKitCore",
			type: .static,
			targets: ["LiveKitCore"]
		)
	],
	dependencies: [
		.package(url: "https://github.com/apple/swift-protobuf.git", .upToNextMajor(from: "1.22.1")),
		.package(url: "https://github.com/google/promises.git", .upToNextMajor(from: "2.0.0")),
		.package(url: "https://github.com/apple/swift-log.git", .upToNextMajor(from: "1.5.3")),
		.package(url: "https://github.com/apple/swift-async-algorithms.git", .upToNextMajor(from: "0.1.0")),
		.package(url: "git@github.corp.ebay.com:eBayMobile/webrtc-ios-xcframework.git", branch: "alternative"),
	],
	targets: [
		.systemLibrary(name: "CHeaders"),
//		.binaryTarget(
//			name: "WebRTC",
//			url: "https://github.com/stasel/WebRTC/releases/download/119.0.0/WebRTC-M119.xcframework.zip",
//			checksum: "60737020738e76f2200f3f2c12a32f260d116f858a2e1ff33c48973ddd3e1c97"
//		),
		.target(
			name: "LiveKit",
			dependencies: [
				.target(name: "CHeaders"),
				.target(name: "WebRTC"),
				.product(name: "SwiftProtobuf", package: "swift-protobuf"),
				.product(name: "Promises", package: "Promises"),
				.product(name: "FBLPromises", package: "Promises"),
				.product(name: "Logging", package: "swift-log"),
			],
			path: "Sources",
			sources: [
				"LiveKit",
			]
		),
		.testTarget(
			name: "LiveKitTests",
			dependencies: ["LiveKit"]
		),
		.systemLibrary(name: "FakePromises", path: "Sources/FakePromises"),
		.systemLibrary(name: "FakeFBLPromises", path: "Sources/FakeFBLPromises"),
		.target(
			name: "LiveKitCore",
			dependencies: [
				.target(name: "FakePromises"),
				.target(name: "FakeFBLPromises"),
				.target(name: "WebRTC"),
				.product(name: "SwiftProtobuf", package: "swift-protobuf"),
				.product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
			],
			path: "Sources/LiveKitCore",
			sources: [
				"Core/Convenience.swift",
				"Core/LiveKit+Signals.swift",
				"Core/Logging.swift",
				"Core/MessageChannel.swift",
				"Core/MessageChannel+Connect.swift",
				"Core/Models.swift",
				"Core/PeerConnection.swift",
				"Core/PeerConnection+Coordinator.swift",
				"Core/PeerConnection+Negotiation.swift",
				"Core/PeerConnection+RTC.swift",
				"Core/PeerConnection+RTCdelegate.swift",
				"Core/PeerConnectionFactory.swift",
				"Core/Publishing.swift",
				"Core/Session.swift",
				"Core/Session+Connect.swift",
				"Core/Session+Publish.swift",
				"Core/SignalHub.swift",
				"Core/SignalHub+LiveKit.swift",
				"Core/SignalHub+RTC.swift",
				"Core/SignalHub+VideoPublishing.swift",
				"Core/VideoView.swift",
				"Core/AudioDevice.swift",
				// the following sources are symlinks:
				"Shared/ConnectivityListener-Core.swift",
				"Shared/DimensionsProvider.swift",
				"Shared/Engine-Core.swift",
				"Shared/Extensions/Engine+WebRTC.swift",
				"Shared/Extensions/Primitives.swift",
				"Shared/Extensions/RTCConfiguration.swift",
				"Shared/Extensions/RTCMediaConstraints.swift",
				"Shared/Extensions/TimeInterval.swift",
				"Shared/LiveKit-Core.swift",
				"Shared/Protocols/MediaEncoding.swift",
				"Shared/Protos/livekit_ipc.pb.swift",
				"Shared/Protos/livekit_models.pb.swift",
				"Shared/Protos/livekit_rtc.pb.swift",
				"Shared/SharedModels.swift",
				"Shared/Support/ConnectivityListener.swift",
				"Shared/Support/Utils.swift",
				"Shared/Types/AudioCaptureOptions.swift",
				"Shared/Types/AudioEncoding.swift",
				"Shared/Types/AudioPublishOptions.swift",
				"Shared/Types/CaptureOptions.swift",
				"Shared/Types/ConnectOptions.swift",
				"Shared/Types/ConnectionState.swift",
				"Shared/Types/Dimensions.swift",
				"Shared/Types/DisconnectReason.swift",
				"Shared/Types/Errors.swift",
				"Shared/Types/IceCandidate.swift",
				"Shared/Types/Other.swift",
				"Shared/Types/ProtocolVersion.swift",
				"Shared/Types/PublishOptions.swift",
				"Shared/Types/SessionDescription.swift",
				"Shared/Types/VideoEncoding+Comparable.swift",
				"Shared/Types/VideoEncoding.swift",
				"Shared/Types/VideoParameters+Comparable.swift",
				"Shared/Types/VideoParameters.swift",
				"Shared/Types/VideoPublishOptions.swift",
				"Shared/Types/VideoQuality.swift",
			],
			swiftSettings: [
				.define("LKCORE"),
				.define("LK_USE_ALTERNATIVE_WEBRTC_BUILD"),
			]
		),
		.testTarget(
			name: "LiveKitCoreTests",
			dependencies: ["LiveKitCore"],
			path: "Sources/LiveKitCoreTests"
		)
	]
)
