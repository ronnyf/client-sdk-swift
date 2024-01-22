/*
 * Copyright 2024 LiveKit
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import AVFoundation
import Foundation

@objc
public class CameraCaptureOptions: NSObject, VideoCaptureOptions {
    @objc
    public let position: AVCaptureDevice.Position

    @objc
    public let preferredFormat: AVCaptureDevice.Format?

    /// preferred dimensions for capturing, the SDK may override with a recommended value.
    @objc
    public let dimensions: Dimensions

    /// preferred fps to use for capturing, the SDK may override with a recommended value.
    @objc
    public let fps: Int

    @objc
    override public init() {
        position = .front
        preferredFormat = nil
        dimensions = .h720_169
        fps = 30
    }

    @objc
    public init(position: AVCaptureDevice.Position = .front,
                preferredFormat: AVCaptureDevice.Format? = nil,
                dimensions: Dimensions = .h720_169,
                fps: Int = 30)
    {
        self.position = position
        self.preferredFormat = preferredFormat
        self.dimensions = dimensions
        self.fps = fps
    }

    public func copyWith(position: AVCaptureDevice.Position? = nil,
                         preferredFormat: AVCaptureDevice.Format? = nil,
                         dimensions: Dimensions? = nil,
                         fps: Int? = nil) -> CameraCaptureOptions
    {
        CameraCaptureOptions(position: position ?? self.position,
                             preferredFormat: preferredFormat ?? self.preferredFormat,
                             dimensions: dimensions ?? self.dimensions,
                             fps: fps ?? self.fps)
    }

    // MARK: - Equal

    override public func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? Self else { return false }
        return position == other.position &&
            preferredFormat == other.preferredFormat &&
            dimensions == other.dimensions &&
            fps == other.fps
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(position)
        hasher.combine(preferredFormat)
        hasher.combine(dimensions)
        hasher.combine(fps)
        return hasher.finalize()
    }
}
