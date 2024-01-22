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
		.package(url: "https://github.com/apple/swift-protobuf.git", .upToNextMajor(from: "1.25.2")),
		.package(url: "https://github.com/apple/swift-log.git", .upToNextMajor(from: "1.5.3")),
		.package(url: "https://github.com/apple/swift-async-algorithms.git", .upToNextMajor(from: "0.1.0")),
		.package(url: "git@github.corp.ebay.com:eBayMobile/webrtc-ios-xcframework.git", .upToNextMinor(from: "1.0.0")),
	],
	targets: [
		.systemLibrary(name: "CHeaders"),
		.target(
			name: "LiveKit",
			dependencies: [
				.target(name: "CHeaders"),
				.product(name: "LKWebRTC", package: "webrtc-ios-xcframework"),
				.product(name: "SwiftProtobuf", package: "swift-protobuf"),
				.product(name: "Logging", package: "swift-log"),
			],
			path: "Sources",
			exclude: [
				"LiveKitCore",
			]
		),
		.testTarget(
			name: "LiveKitTests",
			dependencies: ["LiveKit"]
		),
		.target(
			name: "LiveKitCore",
			dependencies: [
				.product(name: "EWebRTC", package: "webrtc-ios-xcframework"),
				.product(name: "SwiftProtobuf", package: "swift-protobuf"),
				.product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
			],
			path: "Sources/LiveKitCore",
			sources: [
				"Core/AudioDevice.swift",
				"Core/Convenience.swift",
				"Core/LiveKit+Signals.swift",
				"Core/LiveKitCompatibility.swift",
				"Core/Logging.swift",
				"Core/MediaTransmitters.swift",
				"Core/MessageChannel.swift",
				"Core/MessageChannel+Connect.swift",
				"Core/Models.swift",
				"Core/Nalu.swift",
				"Core/Nalu+Sequence.swift",
				"Core/PassthroughVideoDecoder.swift",
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
				// the following sources are symlinks:
				"Shared/ConnectivityListener-Core.swift",
				"Shared/DimensionsProvider.swift",
				"Shared/Engine-Core.swift",
				"Shared/VideoCoding-Core.swift",
				"Shared/Extensions/Primitives.swift",
				"Shared/Extensions/RTCConfiguration.swift",
				"Shared/Extensions/RTCMediaConstraints.swift",
				"Shared/Extensions/TimeInterval.swift",
				"Shared/LiveKit-Core.swift",
				"Shared/Protocols/MediaEncoding.swift",
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
				"Shared/Types/Errors.swift",
				"Shared/Types/IceCandidate.swift",
				"Shared/Types/IceServer.swift",
				"Shared/Types/Other.swift",
				"Shared/Types/ProtocolVersion.swift",
				"Shared/Types/PublishOptions.swift",
				"Shared/Types/ScalabilityMode.swift",
				"Shared/Types/SessionDescription.swift",
				"Shared/Types/VideoCodec.swift",
				"Shared/Types/VideoEncoding+Comparable.swift",
				"Shared/Types/VideoEncoding.swift",
				"Shared/Types/VideoParameters+Comparable.swift",
				"Shared/Types/VideoParameters.swift",
				"Shared/Types/VideoPublishOptions.swift",
				"Shared/Types/VideoQuality.swift",
			],
			swiftSettings: [
				.define("LKCORE_USE_EBAY_WEBRTC"),
			]
		),
		.testTarget(
			name: "LiveKitCoreTests",
			dependencies: ["LiveKitCore"]
		)
	]
)
